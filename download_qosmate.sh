#!/bin/bash
# =============================================================================
# setup_qosmate_files.sh
#
# Populates the OpenWrt custom image `files/` directory with qosmate and
# (optionally) luci-app-qosmate so they are baked directly into the firmware.
#
# Run this script from the ROOT of your repo (the folder that contains `files/`).
#
# Usage:
#   bash setup_qosmate_files.sh                        # backend only, auto tag
#   bash setup_qosmate_files.sh --with-luci            # backend + LuCI UI
#   bash setup_qosmate_files.sh --tag v1.8.0           # pin a specific version
#   bash setup_qosmate_files.sh --with-luci --tag v1.8.0
#
# Requirements (on the build host): curl or wget, and basic coreutils.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
BACKEND_REPO="hudra0/qosmate"
LUCI_REPO="hudra0/luci-app-qosmate"
FILES_DIR="$(pwd)/files"
WITH_LUCI=false
FORCED_TAG=""

# Fallback tags used when GitHub API/scrape both fail
FALLBACK_BACKEND_TAG="v1.8.0"
FALLBACK_LUCI_TAG="v1.8.0"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-luci) WITH_LUCI=true; shift ;;
    --tag)       FORCED_TAG="$2"; shift 2 ;;
    --tag=*)     FORCED_TAG="${1#--tag=}"; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# Portable HTTP GET → stdout
http_get() {
  local url="$1"
  if command -v curl &>/dev/null; then
    curl -fsSL --user-agent "setup_qosmate_files/1.0" "$url"
  elif command -v wget &>/dev/null; then
    wget -qO- --user-agent "setup_qosmate_files/1.0" "$url"
  else
    return 1
  fi
}

# Portable download to file
download() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v curl &>/dev/null; then
    curl -fsSL --user-agent "setup_qosmate_files/1.0" "$url" -o "$dest"
  elif command -v wget &>/dev/null; then
    wget -qO "$dest" --user-agent "setup_qosmate_files/1.0" "$url"
  else
    error "Neither curl nor wget found. Please install one of them."
  fi
}

# Resolve the latest release tag for a GitHub repo.
# Strategy 1: GitHub API (JSON)  — may be rate-limited
# Strategy 2: Scrape /releases/latest redirect URL
# Strategy 3: Use the provided hardcoded fallback
latest_tag() {
  local repo="$1" fallback="$2"
  local tag=""

  # -- Strategy 1: GitHub REST API ------------------------------------------
  tag=$(http_get "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep -o '"tag_name":"[^"]*' | sed 's/"tag_name":"//' || true)

  if [[ -n "$tag" ]]; then
    echo "$tag"
    return
  fi

  warn "GitHub API rate-limited or unavailable for ${repo}. Trying HTML scrape..."

  # -- Strategy 2: Scrape the releases page for the tag in the URL -----------
  # GitHub redirects /releases/latest to /releases/tag/vX.Y.Z
  tag=$(http_get "https://github.com/${repo}/releases/latest" 2>/dev/null \
        | grep -o 'releases/tag/[^"]*' | head -1 | sed 's|releases/tag/||' || true)

  if [[ -n "$tag" ]]; then
    warn "Resolved tag via HTML scrape: ${tag}"
    echo "$tag"
    return
  fi

  warn "HTML scrape also failed. Using hardcoded fallback tag: ${fallback}"
  echo "$fallback"
}

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
  error "Neither curl nor wget found. Please install one of them and re-run."
fi

[[ -d "$FILES_DIR" ]] || {
  warn "'files/' directory not found at: $FILES_DIR"
  warn "Creating it now. Make sure you are running this from your repo root."
  mkdir -p "$FILES_DIR"
}

# ---------------------------------------------------------------------------
# Resolve tags
# ---------------------------------------------------------------------------
if [[ -n "$FORCED_TAG" ]]; then
  BACKEND_TAG="$FORCED_TAG"
  LUCI_TAG="$FORCED_TAG"
  info "Using forced tag: ${FORCED_TAG}"
else
  info "Resolving latest qosmate backend tag..."
  BACKEND_TAG=$(latest_tag "$BACKEND_REPO" "$FALLBACK_BACKEND_TAG")
  info "Backend tag: ${BACKEND_TAG}"

  if [[ "$WITH_LUCI" == true ]]; then
    info "Resolving latest luci-app-qosmate tag..."
    LUCI_TAG=$(latest_tag "$LUCI_REPO" "$FALLBACK_LUCI_TAG")
    info "LuCI tag: ${LUCI_TAG}"
  fi
fi

BASE_RAW="https://raw.githubusercontent.com/${BACKEND_REPO}/${BACKEND_TAG}"

# ---------------------------------------------------------------------------
# Backend files
# ---------------------------------------------------------------------------
info "Downloading /etc/qosmate.sh ..."
download "${BASE_RAW}/etc/qosmate.sh" "${FILES_DIR}/etc/qosmate.sh"
chmod +x "${FILES_DIR}/etc/qosmate.sh"

info "Downloading /etc/init.d/qosmate ..."
download "${BASE_RAW}/etc/init.d/qosmate" "${FILES_DIR}/etc/init.d/qosmate"
chmod +x "${FILES_DIR}/etc/init.d/qosmate"

info "Downloading /etc/hotplug.d/iface/13-qosmateHotplug ..."
download "${BASE_RAW}/etc/hotplug.d/iface/13-qosmateHotplug" \
         "${FILES_DIR}/etc/hotplug.d/iface/13-qosmateHotplug"

if [[ ! -f "${FILES_DIR}/etc/config/qosmate" ]]; then
  info "Downloading /etc/config/qosmate (default config) ..."
  download "${BASE_RAW}/etc/config/qosmate" "${FILES_DIR}/etc/config/qosmate"
else
  warn "/etc/config/qosmate already exists in files/ — skipping to preserve your custom config."
fi

mkdir -p "${FILES_DIR}/etc/qosmate.d"
info "Created /etc/qosmate.d/ directory placeholder."

# ---------------------------------------------------------------------------
# LuCI frontend (optional)
# ---------------------------------------------------------------------------
if [[ "$WITH_LUCI" == true ]]; then
  LUCI_RAW="https://raw.githubusercontent.com/${LUCI_REPO}/${LUCI_TAG}"

  LUCI_VIEW_DIR="${FILES_DIR}/www/luci-static/resources/view/qosmate"
  mkdir -p "$LUCI_VIEW_DIR" \
           "${FILES_DIR}/usr/share/luci/menu.d" \
           "${FILES_DIR}/usr/share/rpcd/acl.d" \
           "${FILES_DIR}/usr/libexec/rpcd"

  for js_file in settings hfsc cake advanced rules connections custom_rules ipsets statistics; do
    info "Downloading LuCI view: ${js_file}.js ..."
    download "${LUCI_RAW}/htdocs/luci-static/resources/view/${js_file}.js" \
             "${LUCI_VIEW_DIR}/${js_file}.js" 2>/dev/null \
    || warn "  ${js_file}.js not found in ${LUCI_TAG} — skipping."
  done

  # menu.d JSON
  info "Downloading luci-app-qosmate.json (menu) ..."
  download "${LUCI_RAW}/root/usr/share/luci/menu.d/luci-app-qosmate.json" \
           "${FILES_DIR}/usr/share/luci/menu.d/luci-app-qosmate.json"

  # ACL JSON
  info "Downloading luci-app-qosmate.json (ACL) ..."
  download "${LUCI_RAW}/root/usr/share/rpcd/acl.d/luci-app-qosmate.json" \
           "${FILES_DIR}/usr/share/rpcd/acl.d/luci-app-qosmate.json"

  # rpcd handlers
  info "Downloading luci.qosmate rpcd handler ..."
  download "${LUCI_RAW}/root/usr/libexec/rpcd/luci.qosmate" \
           "${FILES_DIR}/usr/libexec/rpcd/luci.qosmate"

  info "Downloading luci.qosmate_stats rpcd handler ..."
  download "${LUCI_RAW}/root/usr/libexec/rpcd/luci.qosmate_stats" \
           "${FILES_DIR}/usr/libexec/rpcd/luci.qosmate_stats"

  chmod +x "${FILES_DIR}/usr/libexec/rpcd/luci.qosmate" \
            "${FILES_DIR}/usr/libexec/rpcd/luci.qosmate_stats"
fi

# ---------------------------------------------------------------------------
# uci-defaults: enable service on first boot
# ---------------------------------------------------------------------------
UCI_DEFAULTS_SCRIPT="${FILES_DIR}/etc/uci-defaults/99-qosmate-enable"
if [[ ! -f "$UCI_DEFAULTS_SCRIPT" ]]; then
  info "Creating uci-defaults script to enable qosmate at first boot..."
  mkdir -p "$(dirname "$UCI_DEFAULTS_SCRIPT")"
  cat > "$UCI_DEFAULTS_SCRIPT" << 'EOF'
#!/bin/sh
# Enable qosmate service at first boot.
# Runs once after flashing; deleted automatically by the init system afterwards.
/etc/init.d/qosmate enable
exit 0
EOF
  chmod +x "$UCI_DEFAULTS_SCRIPT"
else
  warn "uci-defaults script already exists — skipping."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
info "Done! QoSmate ${BACKEND_TAG} files placed under files/:"
find "${FILES_DIR}/etc" \( -name "*qosmate*" -o -name "13-qosmateHotplug" \) 2>/dev/null \
  | sed "s|${FILES_DIR}||" | sort
if [[ "$WITH_LUCI" == true ]]; then
  find "${FILES_DIR}/www" "${FILES_DIR}/usr" -name "*qosmate*" 2>/dev/null \
    | sed "s|${FILES_DIR}||" | sort
fi

echo ""
warn "IMPORTANT — add these to your image packages list:"
echo "   kmod-sched kmod-sched-cake kmod-sched-ctinfo kmod-sched-red"
echo "   kmod-ifb kmod-veth kmod-netem ip-full tc-full"
if [[ "$WITH_LUCI" == true ]]; then
  echo "   luci-base rpcd rpcd-mod-file  (LuCI dependencies)"
fi
echo ""
warn "Set your WAN interface and speeds in files/etc/config/qosmate before building."
