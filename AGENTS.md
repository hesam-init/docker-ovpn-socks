# Agent Guide (AGENTS.md)

This guide highlights non-obvious configurations, networking constraints, and runtime execution quirks of the `docker-ovpn-socks` project.

---

## 1. Build & Dependency Quirks

*   **Alpine Package Mirror**: The `Dockerfile` overrides the Alpine repository to use Arvan Cloud Iran mirrors (`http://mirror.0-1.ir/alpine/...`). Keep this mirror configuration intact when updating packages or changing bases, particularly when deploying in restricted network environments.
*   **Docker Capabilities & Sysctls**: Every container inherits network capabilities from `docker-compose.base.yml`. They **must** run with:
    *   `cap_add: [NET_ADMIN]`
    *   `devices: [/dev/net/tun:/dev/net/tun]`
    *   `sysctls`: `net.ipv4.ip_forward=1` and `net.ipv4.conf.all.src_valid_mark=1` (required for policy routing).

---

## 2. Bootstrapping & Runtime Flow

### OpenVPN Flow:
1.  **Entrypoint (`scripts/ovpn-bootstrap.sh`)**:
    *   Runs safety checks on paths, configuration files, and credentials.
    *   Pre-captures original default gateway (`ORIG_GW`, `ORIG_DEV`, `ORIG_IP`) into `/tmp/proxy-env.sh`.
    *   Generates `/tmp/config-runtime.ovpn` with reconnect options and registers `up /usr/local/bin/setup-nat.sh`.
    *   Starts OpenVPN.
2.  **NAT & Proxy Hook (`scripts/_vpn-nat.sh`)**:
    *   Triggers *after* OpenVPN establishes the `tun0` interface.
    *   Applies `iptables` NAT masquerade rules on `tun0` and enables IP forwarding.
    *   Sets up **Policy-Based Routing (Table 128)** to handle asymmetric routing for port-forwarded replies or secondary interfaces.
    *   Applies RFC-1918 private network bypasses (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) to exit through the default host bridge instead of the VPN tunnel.
    *   Generates `/tmp/sockd.conf` and starts the Dante SOCKS5 daemon (`danted -D -f /tmp/sockd.conf`) in the background.

### OpenConnect Flow:
1.  **Entrypoint (`scripts/openconnect-bootstrap.sh`)**:
    *   Validates target VPN server (`VPN_SERVER` / `OPENCONNECT_SERVER`).
    *   Resolves credentials from `AUTH_FILE` or environment variables (`VPN_USER`/`VPN_PASSWORD`).
    *   Pre-captures original default gateway (`ORIG_GW`, `ORIG_DEV`, `ORIG_IP`) into `/tmp/proxy-env.sh`.
    *   Starts OpenConnect targeting `tun0` with `--script=/usr/local/bin/vpnc-wrapper.sh`.
    *   Auto-confirms untrusted SSL certificate prompts with `"yes"` when `VPN_AUTO_ACCEPT_CERT=true`.
2.  **Hook (`scripts/vpnc-wrapper.sh` -> `scripts/_vpn-nat.sh`)**:
    *   Executes default `vpnc-script` to configure VPN routes and DNS.
    *   On `connect` and `reconnect` reasons, calls `/usr/local/bin/setup-nat.sh` (`scripts/_vpn-nat.sh`).

---

## 3. Environment Variable Quirk Matrix

| Env Variable | Default / Expected | Behavior / Constraints |
| :--- | :--- | :--- |
| `VPN_SERVER` | `""` | Target OpenConnect VPN server (e.g. `TCI.apibaz.org`). Required for OpenConnect containers. |
| `VPN_USER` / `VPN_PASSWORD` | `""` | OpenConnect credentials. Used if `AUTH_FILE` is not mounted. |
| `VPN_AUTO_ACCEPT_CERT` | `true` | When `true`, automatically answers `"yes"` to untrusted certificate prompts. |
| `VPN_EXTRA_ARGS` | `--no-dtls` | Additional command-line flags passed directly to `openconnect`. |
| `CREDENTIALS` | `true` | Set to `false` to disable credential validations (e.g., for key/cert-based VPNs or tests). |
| `PROXY_PORT` | `""` | The SOCKS5 proxy port. SOCKS5 daemon (`danted`) will **not** start if this is unset/empty. |
| `PROXY_USER` / `PROXY_PASS` | `""` | If setting proxy authentication, both variables must be set. Leaving them empty runs SOCKS5 in open/anonymous mode. |

---

## 4. Troubleshooting & Verification Commands

Use these exact commands when debugging a container's routing and SOCKS5 status:

*   **Verify Tunnel Health**:
    ```bash
    docker exec <container> ip addr show tun0
    docker exec <container> curl -sf --max-time 5 https://1.1.1.1
    ```
*   **Verify iptables NAT/Forward Rules**:
    ```bash
    docker exec <container> iptables -t nat -L -n -v
    ```
*   **Inspect Routing Policy Table 128 (Asymmetric Flow)**:
    ```bash
    docker exec <container> ip rule show
    docker exec <container> ip route show table 128
    ```
*   **Check SOCKS5 Daemon**:
    ```bash
    docker exec <container> pgrep -a danted
    ```
