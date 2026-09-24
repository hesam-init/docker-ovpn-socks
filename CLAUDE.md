# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Docker images that run a VPN client (OpenVPN or OpenConnect/AnyConnect) plus an embedded Dante SOCKS5 server bound to `tun0`. There is one VPN and one proxy per container. There is no application code, only POSIX `sh` scripts in `scripts/`, a multi-stage `Dockerfile`, and compose files. There are no tests or linters. User docs are in `README.md` and macvlan/LAN-IP setup is in `BRIDGE.md`.

## Commands

```bash
# Build both images (ovpn-client:latest, openconnect-client:latest); uses build network=host for mirror access
docker compose -f docker-compose.base.yml build

# Validate compose files after editing. Use `config` to check changes; do not `up` containers
docker compose config
docker compose -f docker-compose.bridge.yml config
docker compose -f docker-compose.test.yml config

# Debugging a running container
docker exec <c> ip addr show tun0
docker exec <c> curl -sf --max-time 5 https://1.1.1.1
docker exec <c> iptables -t nat -L -n -v
docker exec <c> ip rule show; docker exec <c> ip route show table 128
docker exec <c> pgrep -a danted
curl --proxy socks5h://127.0.0.1:<port> ifconfig.me   # socks5h = remote DNS, no leak
```

## Architecture (spans several files)

**Image layout**: `Dockerfile` has a `base` stage and two targets, `ovpn` and `openconnect`. Scripts are renamed when copied into the image, so the in-container paths differ from the repo paths:
- `scripts/_vpn-nat.sh` → `/usr/local/bin/setup-nat.sh` (shared by both targets)
- `scripts/ovpn-bootstrap.sh` or `scripts/openconnect-bootstrap.sh` → `/usr/local/bin/startup.sh` (CMD)
- `scripts/vpnc-wrapper.sh` → `/usr/local/bin/vpnc-wrapper.sh` (openconnect only)

**Compose layout**: `docker-compose.base.yml` defines `ovpn-template` and `openconnect-template`. These set caps, devices, sysctls, the healthcheck, SIGKILL stop, and the `TZ`, `VPN_AUTO_ACCEPT_CERT` and `VPN_EXTRA_ARGS` defaults. Every real service `extends:` one of them. `docker-compose.yml` uses host port mappings. `docker-compose.bridge.yml` adds macvlan LAN IPs through the external network `docker-ovpn-vlan`, which must be created first (see `BRIDGE.md`). Keep the bridge and main compose files in sync on server/config choices. `docker-compose.test.yml` uses `CREDENTIALS=false`.

**Runtime flow**: the bootstrap and the hook run in separate processes, so they share state through `/tmp/proxy-env.sh`.
1. `startup.sh` validates the env (config file, credentials, `PROXY_PORT` range, PROXY_USER/PASS both-or-neither). It then captures the pre-VPN default route as `ORIG_GW`, `ORIG_DEV` and `ORIG_IP`, and writes them with the proxy vars to `/tmp/proxy-env.sh`. The capture has to happen before the VPN rewrites routes.
2. For OpenVPN, it writes `/tmp/config-runtime.ovpn` (user config + reconnect directives + `script-security 2` / `up /usr/local/bin/setup-nat.sh`) and then `exec`s openvpn. For OpenConnect, it loops forever and respawns `openconnect --interface=tun0 --script=vpnc-wrapper.sh`. When `VPN_AUTO_ACCEPT_CERT=true` it pipes `yes\n<password>` to stdin, which answers the cert prompt and then the password prompt.
3. `vpnc-wrapper.sh` runs the stock `vpnc-script` and then calls `setup-nat.sh` on `reason=connect|reconnect`.
4. `setup-nat.sh` sources `/tmp/proxy-env.sh` and falls back to re-detecting the route. It then sets up:
   - MASQUERADE and FORWARD rules on `tun0`
   - policy routing (`from $ORIG_IP` → table 128 via the original gateway), so replies to port-forwarded or macvlan-inbound connections don't go out through the tunnel
   - RFC-1918 bypass routes via the original gateway
   - `/tmp/sockd.conf`, then `danted -D` (skipped if `PROXY_PORT` is empty)

**Invariants when editing scripts**:
- `setup-nat.sh` runs again on every reconnect, so every step must stay idempotent. Use the `ipt_add` and `ip_rule_add` helpers, `ip route replace`, and the `pgrep danted` guard.
- Scripts are `#!/bin/sh` with `set -e` (dash on Debian), so avoid bashisms.
- The `ORIG_*` capture logic is duplicated across both bootstrap scripts and `_vpn-nat.sh`. Keep the copies consistent.

**Env var fallbacks (openconnect)**: `VPN_SERVER` falls back to `OPENCONNECT_SERVER`, then `SERVER`. `VPN_USER` and `VPN_PASSWORD` have similar alias chains. The auth file (`VPN_AUTH_FILE`, then `AUTH_FILE`, then `/etc/openconnect/auth.txt`) takes precedence over the env vars when it exists. Auth files are line 1 user, line 2 password. `CREDENTIALS=false` skips credential checks.

## Constraints

- **Keep the Iranian mirrors**: the base image `docker.arvancloud.ir/debian:bookworm` and the apt source `http://repo.iut.ac.ir/debian/` (with `mirror.arvancloud.ir` as the commented alternative). The target deployment has restricted network access.
- Containers need `cap_add: NET_ADMIN`, `/dev/net/tun`, and the sysctls `net.ipv4.ip_forward=1` and `net.ipv4.conf.all.src_valid_mark=1`. These are inherited from the base templates, so don't remove them.
- `configs/<provider>/*.ovpn` are committed. `auth.txt` and `*.auth` files are gitignored and must stay out of git.
