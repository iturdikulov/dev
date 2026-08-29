# ob_nm — OpenWrt-style router on Debian

Turns a Debian machine with multiple NICs into a LAN gateway: bridge + DHCP/DNS,
nftables NAT/firewall, dual WAN (Wi‑Fi + wired backup), and **Mihomo** (Clash Meta)
for selective proxy routing. Optional **ss-zapret2** (Docker) adds DPI bypass via
local SOCKS5.

Config lives in this repo under `system/` and is hard-linked into `/etc` by the
stage scripts.

## Defaults

| Setting | Value |
|---------|--------|
| LAN bridge | `br-lan` @ `192.168.1.1/24` |
| DHCP pool | `192.168.1.100` – `192.168.1.200` |
| Wi‑Fi WAN | `wlp6s0` (primary) |
| Wired WAN backup | `enp2s0` |
| LAN ports | `enp3s0 enp4s0 enp5s0` |
| Mihomo mixed proxy | `:7890` |
| Mihomo DNS | `:7874` |
| Mihomo web UI | `http://192.168.1.1:9090/ui/metacubexd/` |
| Mihomo API secret | see `secret:` in `system/etc/mihomo/config.yaml` |

Override interface names and LAN subnet in `ob_nm.conf` — also update
`system/etc/nftables.conf` and `system/etc/dnsmasq.d/br-lan.conf` if you change them.

## Prerequisites

- Debian (or derivative) with NetworkManager
- Internet on at least one interface for stages 01–03
- `sudo` access
- For ss-zapret2: [Docker](https://get.docker.com) (install separately)

## Fresh install

Run from this directory. Stages are numbered; **01–03 need internet**,
**04–09 change networking** (use local console for WAN steps), **10 enables Mihomo**.

Interactive wrapper:

```bash
cd ~/.config/yadm/ob_nm
bash install.sh
```

Or run stages manually:

| Stage | Script | What it does |
|-------|--------|--------------|
| 01 | `01_packages.sh` | Install `network-manager`, `dnsmasq`, `nftables`, … |
| 02 | `02_mihomo_install.sh` | Download Mihomo binary, install units (**service left stopped**) |
| 03 | `03_mihomo_update.sh` | Register daily Mihomo update cron job |
| 04 | `04_forwarding.sh` | Enable IP forwarding (sysctl) |
| 05 | `05_lan_bridge.sh` | Create `br-lan`, attach LAN ports |
| 06 | `06_wan_backup.sh` | Wired WAN as DHCP backup |
| 07 | `07_dhcp_dns.sh` | dnsmasq DHCP + DNS on LAN |
| 08 | `08_firewall_nat.sh` | nftables firewall + NAT (**disruptive**) |
| 09 | `09_wifi_select.sh` | Interactive Wi‑Fi WAN setup |
| 10 | `10_mihomo_enable.sh` | Deploy config, UI, **enable Mihomo + docker-route** |

Recommended order: **01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10**.

> **Warning:** `08_firewall_nat.sh` drops inbound WAN traffic (SSH over WAN stops).
> Manage the router from the LAN after that. It also restarts Docker if running.

## Mihomo

### Install only (stage 02)

Installs `/usr/local/bin/mihomo`, links `/etc/mihomo/config.yaml`, registers
`mihomo.service` and `ob-nm-docker-route.service`. Service stays **disabled**.

### Enable routing (stage 10)

```bash
bash 10_mihomo_enable.sh
```

- Validates config
- Fetches Metacubexd dashboard (once)
- Enables and starts `mihomo` + `ob-nm-docker-route`

### Edit config

Edit `system/etc/mihomo/config.yaml`, then redeploy:

```bash
bash 10_mihomo_enable.sh
```

Or link and reload manually:

```bash
sudo ln -f "$(pwd)/system/etc/mihomo/config.yaml" /etc/mihomo/config.yaml
sudo mihomo -t -d /etc/mihomo
sudo systemctl restart mihomo
sudo /usr/local/sbin/ob-nm-docker-route.sh
```

### LAN clients

Point clients at `192.168.1.1:7890` (HTTP/SOCKS) or configure the router as
default gateway — Mihomo TUN captures traffic from LAN automatically when enabled.

## ss-zapret2 (optional, DPI bypass)

Runs in Docker on the router. Mihomo connects via **SOCKS5** on `127.0.0.1:1080`
(proxy name `ss-zapret2` in config; YouTube rule-set routes there directly,
also available in the `FALLBACK` group).

### First-time setup

```bash
git clone https://github.com/vernette/ss-zapret2 /opt/ss-zapret2
cd /opt/ss-zapret2
cp config.default config
cp .env.example .env
nano .env          # set SS_PASSWORD, ports if needed
docker compose up -d
```

Ensure `.env` matches Mihomo (`SOCKS_PORT=1080`). Mihomo expects SOCKS5, not
Shadowsocks — do not point Mihomo at port 8388 directly.

### Verify

```bash
docker exec zapret2-proxy curl -s -o /dev/null -w '%{http_code}\n' \
  https://www.gstatic.com/generate_204
curl -x socks5h://127.0.0.1:1080 -s -o /dev/null -w '%{http_code}\n' \
  https://www.gstatic.com/generate_204
```

YouTube (site + CDN) is routed to **ss-zapret2**. Zapret uses fake TLS + `sni=www.google.com` for hosts in `hosts-user.txt` (see `/opt/ss-zapret2/config`). Run `blockcheck2.sh` per ss-zapret2 README to re-tune if DPI changes.

### Docker + Mihomo TUN

Mihomo `auto-redirect` hijacks TCP from Docker subnets. This repo ships
`ob-nm-docker-route.service` and `/usr/local/sbin/ob-nm-docker-route.sh` to
fix that (ip rules + nft bypass). It runs:

- on boot (`ob-nm-docker-route.service`)
- after each Mihomo start (`mihomo.service.d/docker-route.conf`)

If SOCKS breaks after a Mihomo restart:

```bash
sudo /usr/local/sbin/ob-nm-docker-route.sh
```

## LAN app runners

Several services in `~/.config/yadm/runs/` are exposed on `*.lan` hostnames.
ob_nm serves DNS for those names via `system/etc/ob-nm-hosts.txt` (deployed by
stage **07**).

| Hostname | Service | Runner | Install first |
|----------|---------|--------|---------------|
| `ob.lan` | Router / Mihomo UI | ob_nm stages 01–10 | — |
| `zdash.lan` | Mihomo MetaCubeXD (Proxies view) | ob_nm stages 01–10 | — |
| `bt.lan` | qBittorrent-nox | `runs/qbittorrent-nox` | `nginx` (optional — runner installs `nginx-light` if missing) |
| `news.lan` | Miniflux RSS reader | `runs/miniflux` | **`DB`** (PostgreSQL 18), `nginx` (optional) |

### Router (ob_nm)

Run stages through **07** before LAN clients can resolve `*.lan`. After editing
`system/etc/ob-nm-hosts.txt`, redeploy DNS:

```bash
cd ~/.config/yadm/ob_nm
bash 07_dhcp_dns.sh
```

Stage **10** deploys the `zdash.lan` nginx vhost. Opening
`http://zdash.lan/` redirects to the MetaCubeXD Proxies view.

### App host

On the machine that runs the apps (often the same box as the router):

```bash
cd ~/.config/yadm
runs/DB                 # required for miniflux
runs/nginx              # optional; miniflux & qbittorrent install nginx-light themselves
runs/qbittorrent-nox
runs/miniflux
```

Or use the interactive runner: `bash run_runner.sh` from `~/.config/yadm`.

Both app runners reverse-proxy through nginx and expect DNS for `bt.lan` /
`news.lan` to point at the app host. If that host has `br-lan`, the runners also
patch local `/etc/hosts`; other LAN clients rely on ob_nm DNS.

After adding or changing hostnames, redeploy ob_nm DNS on the router (see above).

## After reboot

Nothing manual should be required if stages 08 and 10 were completed:

- `nftables`, `docker`, `mihomo`, `ob-nm-docker-route` are enabled at boot
- ss-zapret2 container uses `restart: unless-stopped`

Quick check:

```bash
curl -x socks5h://127.0.0.1:1080 -s -o /dev/null -w '%{http_code}\n' \
  https://www.gstatic.com/generate_204
```

If the ss-zapret2 container was removed (`docker compose down`), recreate it:

```bash
cd /opt/ss-zapret2 && docker compose up -d
```

## Operations cheat sheet

| Task | Command |
|------|---------|
| Update Mihomo binary | `bash 03_mihomo_update.sh` |
| Reload firewall rules | `bash 08_firewall_nat.sh` ⚠️ disruptive |
| Enable / redeploy Mihomo | `bash 10_mihomo_enable.sh` |
| Fix Docker SOCKS after Mihomo restart | `sudo /usr/local/sbin/ob-nm-docker-route.sh` |
| Restart ss-zapret2 only | `cd /opt/ss-zapret2 && docker compose restart` |
| Mihomo logs | `journalctl -u mihomo -f` |
| ss-zapret2 logs | `docker logs -f zapret2-proxy` |

### Avoid (brief connectivity loss)

- `sudo nft -f /etc/nftables.conf` — flushes entire ruleset
- `systemctl restart docker` — prefer `docker compose restart` in ss-zapret2
- `systemctl restart mihomo` — only when needed; run `ob-nm-docker-route.sh` after

## File layout

```
ob_nm/
├── install.sh              # interactive stage runner
├── ob_nm.conf              # optional overrides
├── 01_packages.sh … 10_mihomo_enable.sh
└── system/                 # hard-linked into /
    ├── etc/mihomo/config.yaml
    ├── etc/nftables.conf
    ├── etc/dnsmasq.d/br-lan.conf
    ├── etc/systemd/system/mihomo.service
    ├── etc/systemd/system/ob-nm-docker-route.service
    ├── etc/systemd/system/mihomo.service.d/docker-route.conf
    └── usr/local/sbin/ob-nm-docker-route.sh
```
