{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "openwrt-build-env";

  buildInputs = with pkgs; [
    podman
    bash
    coreutils
  ];

  CONTAINER_NAME = "openwrt-builder";
  DEBIAN_IMAGE   = "docker.io/library/debian:bookworm-slim";

  shellHook = ''
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║    OpenWrt Build Environment — Podman + Debian       ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    # ── Paths ───────────────────────────────────────────────────────
    # BUILDER_DIR = questo repo (config + overlay). OPENWRT_DIR = albero
    # OpenWrt esterno (default: cartella sorella ../openwrt), sovrascrivibile.
    export BUILDER_DIR="$PWD"
    export OPENWRT_DIR="''${OPENWRT_DIR:-$(dirname "$PWD")/openwrt}"
    mkdir -p "$OPENWRT_DIR"
    OPENWRT_DIR="$(cd "$OPENWRT_DIR" && pwd)"   # normalizza a path assoluto

    echo "  Repo (builder):  $BUILDER_DIR   → /builder"
    echo "  Albero OpenWrt:  $OPENWRT_DIR   → /openwrt"
    echo ""

    # ── Helper functions ────────────────────────────────────────────

    openwrt-start() {
      if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "[*] Container '$CONTAINER_NAME' già esistente, lo avvio..."
        podman start "$CONTAINER_NAME"
      else
        echo "[*] Creo il container '$CONTAINER_NAME' da $DEBIAN_IMAGE ..."
        podman run -dit \
          --name "$CONTAINER_NAME" \
          --hostname openwrt-builder \
          --userns=keep-id \
          -v "$BUILDER_DIR:/builder:z" \
          -v "$OPENWRT_DIR:/openwrt:z" \
          -w /builder \
          "$DEBIAN_IMAGE" \
          bash

        echo "[*] Installo le dipendenze di build OpenWrt nel container..."
        # apt richiede root: usiamo --user root esplicitamente solo qui
        podman exec --user root "$CONTAINER_NAME" bash -c '
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -qq
          apt-get install -y --no-install-recommends \
            build-essential clang flex bison g++ gawk \
            gcc-multilib gettext git libncurses5-dev \
            libssl-dev openssl python3-distutils rsync unzip \
            zlib1g-dev file wget curl ca-certificates \
            libelf-dev swig time patch python3-setuptools \
            llvm linux-libc-dev
          echo "[✓] Dipendenze installate."
        '

        echo "[*] Configuro git safe.directory nel container..."
        podman exec "$CONTAINER_NAME" bash -c \
          'git config --global --add safe.directory /builder && \
           git config --global --add safe.directory /openwrt'
        echo "[✓] Configurazione completata."
      fi
      echo "[✓] Container pronto. Usa  openwrt-build  per compilare o  openwrt-shell  per entrare."
    }

    # Apre una shell interattiva nel container come utente host
    openwrt-shell() {
      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "[!] Container non trovato. Esegui prima  openwrt-start"
        return 1
      fi
      podman start "$CONTAINER_NAME" 2>/dev/null
      echo "[*] Entro nel container (repo → /builder, albero → /openwrt)"
      podman exec -it "$CONTAINER_NAME" bash
    }

    # Esegue un comando nel container come utente host
    openwrt-run() {
      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "[!] Container non trovato. Esegui prima  openwrt-start"
        return 1
      fi
      podman start "$CONTAINER_NAME" 2>/dev/null
      podman exec -it "$CONTAINER_NAME" bash -c "$*"
    }

    # Esegue un comando nel container come root (es. per installare pacchetti)
    openwrt-run-root() {
      if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "[!] Container non trovato. Esegui prima  openwrt-start"
        return 1
      fi
      podman start "$CONTAINER_NAME" 2>/dev/null
      podman exec -it --user root "$CONTAINER_NAME" bash -c "$*"
    }

    openwrt-menuconfig() {
      openwrt-run "cd /openwrt && make menuconfig"
    }

    # Setup completo + build: build.sh clona/aggiorna l'albero OpenWrt in /openwrt,
    # applica files/ e mt6000.config, poi compila.
    openwrt-build() {
      if [ ! -f "$BUILDER_DIR/build.sh" ]; then
        echo "[!] build.sh non trovato in $BUILDER_DIR"
        return 1
      fi
      echo "[*] Avvio build.sh nel container..."
      openwrt-run "cd /builder && BUILDER_DIR=/builder OPENWRT_DIR=/openwrt bash build.sh"
    }

    openwrt-stop() {
      podman stop "$CONTAINER_NAME" && echo "[✓] Container fermato."
    }

    openwrt-clean() {
      podman rm -f "$CONTAINER_NAME" 2>/dev/null && echo "[✓] Container rimosso."
    }

    openwrt-status() {
      echo "── Percorsi ────────────────────────────────────────────"
      echo "  /builder → $BUILDER_DIR"
      echo "  /openwrt → $OPENWRT_DIR"
      echo "── Container ──────────────────────────────────────────"
      podman ps -a --filter "name=^$CONTAINER_NAME$" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
      echo "── Immagine ────────────────────────────────────────────"
      podman images "$DEBIAN_IMAGE" --format \
        "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null \
        || echo "(immagine non ancora scaricata)"
    }

    export -f openwrt-start
    export -f openwrt-shell
    export -f openwrt-run
    export -f openwrt-run-root
    export -f openwrt-menuconfig
    export -f openwrt-build
    export -f openwrt-stop
    export -f openwrt-clean
    export -f openwrt-status

    echo "  Comandi disponibili:"
    echo ""
    echo "  openwrt-start             — crea/avvia il container Debian e installa le dipendenze"
    echo "  openwrt-build             — setup (clone/overlay) + build completa nel container"
    echo "  openwrt-shell             — apre una shell interattiva nel container"
    echo "  openwrt-run <cmd>         — esegue un comando nel container (utente host)"
    echo "  openwrt-run-root <cmd>    — esegue un comando nel container come root (es. apt)"
    echo "  openwrt-menuconfig        — avvia make menuconfig sull'albero /openwrt"
    echo "  openwrt-stop              — ferma il container (senza eliminarlo)"
    echo "  openwrt-clean             — rimuove il container"
    echo "  openwrt-status            — mostra percorsi, stato container e immagine"
    echo ""
    echo "  Nota: questo repo → /builder,  l'albero OpenWrt esterno → /openwrt."
    echo ""
  '';
}
