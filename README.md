# GL-MT6000 Custom OpenWrt Configuration

> **Warning: Heavily Customized — Read Before Flashing**
>
> This repository contains my personal OpenWrt configuration for the Flint 2 (GL-MT6000) router, based on [pesa1234](https://github.com/pesa1234)'s work. See the [OpenWrt forum thread](https://forum.openwrt.org/t/mt6000-custom-build-with-luci-and-some-optimization-kernel-6-12-x/185241) for details on pesa1234's customizations.
>
> **Do not use this configuration unless your setup exactly matches mine. Fork and adapt instead.**

## Repository Structure

- [`mt6000.config`](mt6000.config) — OpenWrt build configuration (`.config`)
- [`build.sh`](build.sh) — Local build script (feeds → defconfig → download → make); runs inside the container from `shell.nix`
- [`shell.nix`](shell.nix) — `nix-shell` environment that provides `podman` and helper functions to build inside a Debian container (see [Building](#building))
- [`.github/workflows/build-openwrt.yaml`](.github/workflows/build-openwrt.yaml) — GitHub Actions CI that reproduces the local build on `ubuntu-24.04-arm` and publishes to Releases + Pages
- [`files/`](files/) — Custom files overlaid on the root filesystem at build time
  - [`files/etc/uci-defaults/`](files/etc/uci-defaults/) — First-boot scripts that configure the router via UCI (see note below)
  - [`files/etc/scripts/`](files/etc/scripts/) — Runtime tuning and WiFi automation scripts (see [Scripts](#scripts))
  - [`files/etc/crontabs/root`](files/etc/crontabs/root) — Scheduled jobs (see [Cron jobs](#cron-jobs))
  - [`files/etc/hotplug.d/iface/30-unbound-cache`](files/etc/hotplug.d/iface/30-unbound-cache) — Dumps/restores the unbound DNS cache across WAN up/down events
  - [`files/etc/board.d/`](files/etc/board.d/) — Board setup: hostname, root password, timezone, WiFi SSID/key/country (loaded from U-Boot env, see [U-Boot Environment Variables](#u-boot-environment-variables))
  - [`files/etc/rc.local`](files/etc/rc.local) — Boot hook; the CPU-tuning scripts are present but commented out by default
  - [`files/etc/sysupgrade.conf`](files/etc/sysupgrade.conf) — Preserves `/etc/scripts/` across sysupgrades
  - [`files/etc/fw_env.config`](files/etc/fw_env.config) — Points `fw_printenv`/`fw_setenv` at the U-Boot env partition
  - [`files/etc/dropbear/`](files/etc/dropbear/) — SSH `authorized_keys` and host keys

> **Note:** Each `uci-defaults` script starts with an idempotence guard: it checks whether the configuration it manages is already present and exits early if so. Settings are applied on genuine first boot only and never clobber an existing (possibly hand-tuned) config — including when the scripts re-run after a sysupgrade that restored the config backup.

## Differences from pesa1234's Build

**Added:**
- WiFi UCODE scripts for faster boot
- WireGuard VPN server (port 51545) with up to 7 peers
- Cloudflare DDNS
- **unbound** recursive DNS resolver (`unbound-daemon`, `luci-app-unbound`) with cache persistence across WAN drops
- ACME / Let's Encrypt (`acme`, `acme-acmesh`, `acme-acmesh-dnsapi`)
- Avahi (mDNS)
- `collectd` + `luci-app-statistics` for monitoring (CPU, RAM, network, thermals, etc.)
- `iperf3` for network performance testing
- `htop`, `watch`, `wget`, `drill`, `jq`, `blkid`, `bridger`, and other CLI tools
- WiFi/CPU tuning scripts and WiFi day/night automation (see [Scripts](#scripts))
- Shell history enabled
- IPv6 configured on WAN (`reqaddress='try'`, `reqprefix='auto'`)
- DNS set to Cloudflare for Families (`1.1.1.2`, `1.0.0.2`)

**Removed:**
- adblock, samba, USB storage support, ZeroTier, Tailscale
- `attendedsysupgrade` (built as module only)

**Compiler options:** `cortex-a53+crc+crypto`, LTO, MOLD linker, OpenSSL speed optimizations.

## Building

This repo holds only the config and overlay (`mt6000.config` + `files/`). The build itself runs against a checkout of [pesa1234/openwrt](https://github.com/pesa1234/openwrt), with this repo's files overlaid on top.

### CI (GitHub Actions)

[`build-openwrt.yaml`](.github/workflows/build-openwrt.yaml) runs on push, on a schedule, and manually. It detects the newest `next-*` branch upstream, checks out both repos, overlays `files/` and `mt6000.config` → `.config`, then builds on `ubuntu-24.04-arm` and publishes the firmware to GitHub Releases + Pages.

### Local (nix-shell + podman)

The host is NixOS, so the build can't run natively (non-FHS userland, and OpenWrt refuses to build as root). [`shell.nix`](shell.nix) works around this by giving `nix-shell` `podman`, which runs the build inside a `debian:bookworm-slim` container as the host user — the same non-root, FHS environment the CI uses.

Setup is fully automated by [`build.sh`](build.sh) — no manual cloning or copying. From this repo:

```sh
nix-shell           # enters env with podman + openwrt-* helpers
openwrt-start       # first run only: create the Debian container + install build deps
openwrt-build       # runs build.sh in the container
```

`build.sh` (running in the container) mirrors the CI: it detects the newest upstream `next-*` branch, clones/updates the OpenWrt tree, overlays `files/` and `mt6000.config` → `.config`, then runs feeds → `defconfig` → `download` → `make`.

The container mounts **this repo at `/builder`** and the **OpenWrt tree at `/openwrt`**. The tree lives *outside* this repo — by default a sibling `../openwrt` — so build artifacts (10 GB+) never land in the repo. Firmware ends up in `../openwrt/bin/targets/mediatek/filogic/`. Because the tree persists, rebuilds are incremental: just `nix-shell` → `openwrt-build`.

Overrides (env vars, read by both `shell.nix` and `build.sh`):

| Variable | Default | Purpose |
|---|---|---|
| `OPENWRT_DIR` | `../openwrt` | Where to check out / build the OpenWrt tree |
| `OPENWRT_BRANCH` | newest `next-*` | Pin a specific upstream branch |
| `APKSIGN_PRIVATE_KEY_FILE` | _(auto-generated)_ | Use a specific EC key to sign the package feed (e.g. the CI's key) instead of generating a persistent local one |

Other helpers: `openwrt-shell` (interactive container shell), `openwrt-menuconfig`, `openwrt-status`, `openwrt-stop`, `openwrt-clean` (remove container).

## Scripts

Located in [`files/etc/scripts/`](files/etc/scripts/) and preserved across sysupgrades:

| Script | Purpose |
|---|---|
| `wifi_off.sh` | Night mode: lowers 2.4 GHz TX power and disables the 5 GHz radio |
| `wifi_on.sh` | Restores 2.4 GHz TX power and re-enables the 5 GHz radio |
| `best_wifi_channels.sh` | Auto-selects the least-congested 2.4 GHz channel (1/6/11) |
| `aql_tuning.sh` | Tunes 802.11 AQL queue limits (latency vs. bandwidth) |
| `airtime_fairness.sh` | Forces airtime-fairness + deficit mode on both radios |
| `manual_interrupts.sh` | Pins NIC/WiFi IRQs and RPS/XPS to specific CPU cores |

The CPU/WiFi tuning scripts (`aql_tuning.sh`, `manual_interrupts.sh`, `airtime_fairness.sh`) are wired into [`rc.local`](files/etc/rc.local) but commented out — uncomment to enable at boot.

## Cron jobs

Defined in [`files/etc/crontabs/root`](files/etc/crontabs/root):

| Schedule | Job |
|---|---|
| `23:00` daily | `wifi_off.sh` — night mode |
| `07:00` daily | `wifi_on.sh` — day mode |
| `08:00` daily | `best_wifi_channels.sh` — re-pick 2.4 GHz channel |
| `00:00` daily | `acme renew` — renew Let's Encrypt certs |

## U-Boot Environment Variables

Secrets and device-specific values are stored in the U-Boot environment — a region of flash that survives firmware upgrades. The board-setup and first-boot scripts read these variables and fall back to safe defaults if missing. [`files/etc/fw_env.config`](files/etc/fw_env.config) points `fw_printenv`/`fw_setenv` at the env partition (`/dev/mmcblk0p1`, offset `0x0`, size `0x80000`).

Set variables over SSH with `fw_setenv`:

```sh
fw_setenv <variable> "<value>"
```

### System

Read by [`files/etc/board.d/90_system`](files/etc/board.d/90_system) (via `fw_loadenv` → `/var/run/uboot-env/`):

| Variable | Description | Fallback if unset |
|---|---|---|
| `root_password_hash` | Root password hash, crypt format as in `/etc/shadow` | no root password set |
| `timezone` | System timezone (e.g. `CET-1CEST,M3.5.0,M10.5.0/3`) | OpenWrt default (`UTC`) |

### WiFi

Read by [`files/etc/board.d/90_wireless`](files/etc/board.d/90_wireless):

| Variable | Description | Fallback if unset |
|---|---|---|
| `wifi_ssid` | WiFi network name | `GL-MT6000` |
| `wifi_key` | WiFi password (WPA2/WPA3 mixed, `sae-mixed`) | `changeme123` |
| `wifi_country` | Country code | `NL` |

### DDNS (Cloudflare)

Read by [`files/etc/uci-defaults/90_my_ddns`](files/etc/uci-defaults/90_my_ddns):

| Variable | Description |
|---|---|
| `ddns_cf_lookup_host` | Hostname to resolve for IP check |
| `ddns_cf_domain` | Domain in `subdomain@example.com` format |
| `ddns_cf_password` | Cloudflare API token |

### WireGuard

Read by [`files/etc/uci-defaults/90_my_wireguard`](files/etc/uci-defaults/90_my_wireguard) (skipped if `network.wg0` already exists):

| Variable | Description |
|---|---|
| `wg0_priv_key` | Server private key |
| `wg0_peer1_priv_key` / `wg0_peer1_pub_key` / `wg0_peer1_desc` | Peer 1 keys and description (fallback `Peer1`) |
| `wg0_peer2_priv_key` / `wg0_peer2_pub_key` / `wg0_peer2_desc` | Peer 2 keys and description (fallback `Peer2`) |
| `wg0_peer3_priv_key` / `wg0_peer3_pub_key` / `wg0_peer3_desc` | Peer 3 keys and description (fallback `Peer3`) |
| `wg0_peer4_priv_key` / `wg0_peer4_pub_key` / `wg0_peer4_desc` | Peer 4 keys and description (fallback `Peer4`) |
| `wg0_peer5_priv_key` / `wg0_peer5_pub_key` / `wg0_peer5_desc` | Peer 5 keys and description (fallback `Peer5`) |
| `wg0_peer6_priv_key` / `wg0_peer6_pub_key` / `wg0_peer6_desc` | Peer 6 keys and description (fallback `Peer6`) |
| `wg0_peer7_priv_key` / `wg0_peer7_pub_key` / `wg0_peer7_desc` | Peer 7 keys and description (fallback `Peer7`) |

### Network

Read by [`files/etc/uci-defaults/90_my_network`](files/etc/uci-defaults/90_my_network):

| Variable | Description |
|---|---|
| `dhcp_default_duid` | Default DHCPv6 DUID (`network.globals.dhcp_default_duid`) |

### Static DHCP hosts

Read by [`files/etc/uci-defaults/90_my_dhcp`](files/etc/uci-defaults/90_my_dhcp). Up to 7 static leases (`N` = 0…6), each defined by:

| Variable | Description |
|---|---|
| `dhcp_hostN_name` | Hostname (required) |
| `dhcp_hostN_mac` | MAC address (required) |
| `dhcp_hostN_ip` | Static IPv4 address (required; the IPv6 `hostid` is derived from its last octet) |
| `dhcp_hostN_duid` | DHCPv6 DUID (optional) |

A host slot is skipped entirely if `name`, `mac`, or `ip` is missing. All static leases are created with `leasetime='infinite'`.

## Recovery

If you flash without the required U-Boot variables set, the router may not boot correctly. Recovery instructions are in the [GL.iNet debrick documentation](https://docs.gl-inet.com/router/en/4/faq/debrick/).

## Acknowledgements

- [OpenWrt project](https://openwrt.org) and the [GL-MT6000 wiki page](https://openwrt.org/toh/gl.inet/gl-mt6000)
- [pesa1234](https://github.com/pesa1234) for the [MT6000 custom builds](https://github.com/pesa1234/MT6000_cust_build) and the [forum thread](https://forum.openwrt.org/t/mt6000-custom-build-with-luci-and-some-optimization-kernel-6-12-x/185241)
