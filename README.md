# GL-MT6000 Custom OpenWrt Configuration

> **Warning: Heavily Customized — Read Before Flashing**
>
> This repository contains my personal OpenWrt configuration for the Flint 2 (GL-MT6000) router, based on [pesa1234](https://github.com/pesa1234)'s work. See the [OpenWrt forum thread](https://forum.openwrt.org/t/mt6000-custom-build-with-luci-and-some-optimization-kernel-6-12-x/185241) for details on pesa1234's customizations.
>
> **Do not use this configuration unless your setup exactly matches mine. Fork and adapt instead.**

## Repository Structure

- [`mt6000.config`](mt6000.config) — OpenWrt build configuration (`.config`)
- [`download_qosmate.sh`](download_qosmate.sh) — Build-host helper that fetches [QoSmate](https://github.com/hudra0/qosmate) (SQM/CAKE) and, optionally, its LuCI app into `files/` so they are baked into the image
- [`files/`](files/) — Custom files overlaid on the root filesystem at build time
  - [`files/etc/uci-defaults/`](files/etc/uci-defaults/) — First-boot scripts that configure the router via UCI (see note below)
  - [`files/etc/config/qosmate`](files/etc/config/qosmate) — QoSmate config (CAKE on `eth1`, 240/25 Mbit down/up)
  - [`files/etc/scripts/`](files/etc/scripts/) — Runtime tuning and WiFi automation scripts (see [Scripts](#scripts))
  - [`files/etc/crontabs/root`](files/etc/crontabs/root) — Scheduled jobs (see [Cron jobs](#cron-jobs))
  - [`files/etc/hotplug.d/iface/30-unbound-cache`](files/etc/hotplug.d/iface/30-unbound-cache) — Dumps/restores the unbound DNS cache across WAN up/down events
  - [`files/etc/board.d/`](files/etc/board.d/) — Board setup: hostname, root password, timezone (loaded from U-Boot env via `fw_loadenv`)
  - [`files/etc/rc.local`](files/etc/rc.local) — Boot hook; the CPU-tuning scripts are present but commented out by default
  - [`files/etc/sysupgrade.conf`](files/etc/sysupgrade.conf) — Preserves `/etc/scripts/` across sysupgrades
  - [`files/etc/fw_env.config`](files/etc/fw_env.config) — Points `fw_printenv`/`fw_setenv` at the U-Boot env partition
  - [`files/etc/dropbear/`](files/etc/dropbear/) — SSH `authorized_keys` and host keys

> **Note:** Most `uci-defaults` scripts currently start with an early `exit 0`, so they are effectively disabled — `90_my_ddns` is the only one that runs. Remove the early `exit 0` to re-enable a script before building.

## Differences from pesa1234's Build

**Added:**
- WiFi UCODE scripts for faster boot
- WireGuard VPN server (port 51545) with up to 6 peers
- Cloudflare DDNS
- **unbound** recursive DNS resolver (`unbound-daemon`, `luci-app-unbound`) with cache persistence across WAN drops
- **QoSmate** (CAKE-based SQM) — pulled into the image via [`download_qosmate.sh`](download_qosmate.sh)
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

Secrets and device-specific values are stored in U-Boot environment — a region of flash that survives firmware upgrades. The first-boot scripts read these variables and fall back to safe defaults if missing.

Set variables over SSH with `fw_setenv`:

```sh
fw_setenv <variable> "<value>"
```

### WiFi

| Variable | Description |
|---|---|
| `wifi_ssid` | WiFi network name |
| `wifi_key` | WiFi password |
| `wifi_country` | Country code (e.g. `NL`) |

### DDNS (Cloudflare)

| Variable | Description |
|---|---|
| `ddns_cf_lookup_host` | Hostname to resolve for IP check |
| `ddns_cf_domain` | Domain in `subdomain@example.com` format |
| `ddns_cf_password` | Cloudflare API token |

### WireGuard

| Variable | Description |
|---|---|
| `wg0_priv_key` | Server private key |
| `wg0_peer1_priv_key` / `wg0_peer1_pub_key` | Peer 1 (Pixel) keys |
| `wg0_peer2_priv_key` / `wg0_peer2_pub_key` | Peer 2 (Lenovo) keys |
| `wg0_peer3_priv_key` / `wg0_peer3_pub_key` | Peer 3 (OP) keys |
| `wg0_peer4_priv_key` / `wg0_peer4_pub_key` | Peer 4 (ROG) keys |
| `wg0_peer5_priv_key` / `wg0_peer5_pub_key` | Peer 5 (MF286D) keys |
| `wg0_peer6_priv_key` / `wg0_peer6_pub_key` | Peer 6 (WD3600) keys |

### Network

| Variable | Description |
|---|---|
| `dhcp_default_duid` | DHCP DUID for WAN |

## Recovery

If you flash without the required U-Boot variables set, the router may not boot correctly. Recovery instructions are in the [GL.iNet debrick documentation](https://docs.gl-inet.com/router/en/4/faq/debrick/).

## Acknowledgements

- [OpenWrt project](https://openwrt.org) and the [GL-MT6000 wiki page](https://openwrt.org/toh/gl.inet/gl-mt6000)
- [pesa1234](https://github.com/pesa1234) for the [MT6000 custom builds](https://github.com/pesa1234/MT6000_cust_build) and the [forum thread](https://forum.openwrt.org/t/mt6000-custom-build-with-luci-and-some-optimization-kernel-6-12-x/185241)
