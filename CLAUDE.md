# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Docker images that run a VPN client (OpenVPN or OpenConnect/AnyConnect) plus an embedded gost proxy (HTTP + SOCKS on one port) whose egress is bound to `tun0`. There is one VPN and one proxy per container. There is no application code, only bash scripts in `scripts/`, a multi-stage Alpine `Dockerfile`, a `Makefile`, and compose files. There are no tests or linters. User docs are in `README.md` and macvlan/LAN-IP setup is in `BRIDGE.md`.

## Commands

```bash
# Build ovpn-client:latest and openconnect-client:latest via the Makefile
make                   # docker buildx bake --allow=network.host -f docker-compose.base.yml --load ovpn-template openconnect-template
make no-cache          # same, with --no-cache
make raw               # same images via plain `docker build --network host -f Dockerfile --target <ovpn|openconnect>`
make raw-no-cache
# `docker compose build` fails: Compose always builds through bake, which rejects the templates'
# `build.network: host` without --allow=network.host, and Compose cannot pass that flag

# Validate compose files after editing. Use `config` to check changes; do not `up` containers
docker compose config
docker compose -f docker-compose.bridge.yml config
docker compose -f docker-compose.test.yml config

# Debugging a running container
docker exec <c> ip addr show tun0
docker exec <c> curl -sf --max-time 5 https://1.1.1.1
docker exec <c> iptables -t nat -L -n -v
docker exec <c> ip rule show; docker exec <c> ip route show table 128
docker exec <c> pgrep -a gost
curl --proxy socks5h://127.0.0.1:<port> ifconfig.me   # socks5h = remote DNS, no leak
curl --proxy http://127.0.0.1:<port> ifconfig.me      # same port also speaks HTTP
```

## Architecture (spans several files)

**Image layout**: `Dockerfile` has an Alpine 3.24 `base` stage (bash, curl, iptables, iproute2, gost v3, openvpn, openconnect, vpnc for `/etc/vpnc/vpnc-script`) and two targets, `ovpn` and `openconnect`. Each script keeps its repo basename in the image:
- `scripts/lib/common.sh` → `/usr/local/lib/vpn-socks/common.sh` (sourced by every script: logging, `validate_proxy_env`, `capture_orig_route`, `save_proxy_env`/`load_proxy_env`)
- `scripts/tunnel-up.sh` → `/usr/local/bin/tunnel-up.sh` (shared by both targets)
- `scripts/openvpn-entrypoint.sh` or `scripts/openconnect-entrypoint.sh` → `/usr/local/bin/` under the same name (CMD of the `ovpn` or `openconnect` target)
- `scripts/openconnect-hook.sh` → `/usr/local/bin/openconnect-hook.sh` (openconnect only)

**Compose layout**: `docker-compose.base.yml` defines `ovpn-template` and `openconnect-template`. These set caps, devices, sysctls, the healthcheck, SIGKILL stop, and the `TZ`, `VPN_AUTO_ACCEPT_CERT` and `VPN_EXTRA_ARGS` defaults. Every real service `extends:` one of them. `docker-compose.yml` uses host port mappings. `docker-compose.bridge.yml` adds macvlan LAN IPs through the external network `docker-ovpn-vlan`, which must be created first (see `BRIDGE.md`). Keep the bridge and main compose files in sync on server/config choices. `docker-compose.test.yml` uses `CREDENTIALS=false`. Images are built with the `Makefile`, not `docker compose build`.

**Runtime flow**: the entrypoint and the hook run in separate processes, so they share state through `/tmp/proxy-env.sh`.
1. The entrypoint (`openvpn-entrypoint.sh` or `openconnect-entrypoint.sh`) validates the env (config file, credentials, `PROXY_PORT` range, PROXY_USER/PASS both-or-neither). It then captures the pre-VPN default route as `ORIG_GW`, `ORIG_DEV` and `ORIG_IP`, and writes them with the proxy vars to `/tmp/proxy-env.sh`. The capture has to happen before the VPN rewrites routes.
2. For OpenVPN, it writes `/tmp/config-runtime.ovpn` (user config + reconnect directives + `script-security 2` / `up /usr/local/bin/tunnel-up.sh`) and then `exec`s openvpn. For OpenConnect, it loops forever and respawns `openconnect --interface=tun0 --script=openconnect-hook.sh`. When `VPN_AUTO_ACCEPT_CERT=true` it pipes `yes\n<password>` to stdin, which answers the cert prompt and then the password prompt.
3. `openconnect-hook.sh` runs the stock `vpnc-script` and then calls `tunnel-up.sh` on `reason=connect|reconnect`.
4. `tunnel-up.sh` sources `/tmp/proxy-env.sh` and falls back to re-detecting the route. It then sets up:
   - MASQUERADE and FORWARD rules on `tun0`
   - policy routing (`from $ORIG_IP` → table 128 via the original gateway), so replies to port-forwarded or macvlan-inbound connections don't go out through the tunnel
   - RFC-1918 bypass routes via the original gateway
   - `setup_gost` (skipped if `PROXY_PORT` is empty): `gost -L "auto://[user:pass@]:PORT?interface=tun0" &`. It is backgrounded because gost has no daemon mode, and outlives the hook. Credentials are URL-encoded with `urlencode`. `interface=tun0` binds egress to the tunnel, so traffic can't leak through eth0 if the tunnel drops

**Invariants when editing scripts**:
- `tunnel-up.sh` runs again on every reconnect, so every step must stay idempotent. Use the `ipt_add` and `ip_rule_add` helpers, `ip route replace`, and the `pgrep -x gost` guard.
- Scripts are `#!/usr/bin/env bash` with `set -Eeuo pipefail` (except `openconnect-hook.sh`, which omits `-e` so a vpnc-script failure can't block NAT setup). Read optional env vars as `${VAR:-}` because of `-u`, and guard pipelines that may legitimately match nothing with `|| true`.
- Shared logic lives in `lib/common.sh`; put new helpers there rather than copying them between scripts. `/tmp/proxy-env.sh` is written with `printf %q`, so keep using `save_proxy_env` instead of a hand-written heredoc.

**Env var fallbacks (openconnect)**: `VPN_SERVER` falls back to `OPENCONNECT_SERVER`, then `SERVER`. `VPN_USER` and `VPN_PASSWORD` have similar alias chains. The auth file (`VPN_AUTH_FILE`, then `AUTH_FILE`, then `/etc/openconnect/auth.txt`) takes precedence over the env vars when it exists. Auth files are line 1 user, line 2 password. `CREDENTIALS=false` skips credential checks.

## Constraints

- **Keep the Iranian mirrors**: the base image `docker.arvancloud.ir/alpine:3.24` and the apk repos `http://repo.iut.ac.ir/repo/alpine/v3.24/{main,community}`. The target deployment has restricted network access.
- Containers need `cap_add: NET_ADMIN`, `/dev/net/tun`, and the sysctls `net.ipv4.ip_forward=1` and `net.ipv4.conf.all.src_valid_mark=1`. These are inherited from the base templates, so don't remove them.
- `configs/<provider>/*.ovpn` are committed. `auth.txt` and `*.auth` files are gitignored and must stay out of git.
