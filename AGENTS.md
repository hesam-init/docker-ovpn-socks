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

1.  **Entrypoint (`scripts/vpn-bootstrap.sh`)**:
    *   Runs initial safety checks on paths, configuration files, and credentials.
    *   Generates a runtime-specific config `/tmp/config-runtime.ovpn` based on the environment options.
    *   Appends reconnect properties (`ping-restart`, `persist-tun`, etc.) and registers the `up` hook to `/usr/local/bin/setup-nat.sh` (`scripts/vpn-nat.sh`).
    *   Starts OpenVPN.
2.  **NAT & Proxy Hook (`scripts/vpn-nat.sh`)**:
    *   Triggers *after* OpenVPN establishes the `tun0` interface.
    *   Applies `iptables` NAT masquerade rules on `tun0` and enables IP forwarding.
    *   Sets up **Policy-Based Routing (Table 128)** to handle asymmetric routing for port-forwarded replies or secondary interfaces.
    *   Applies RFC-1918 private network bypasses (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) to exit through the default host bridge instead of the VPN tunnel.
    *   Generates `/tmp/sockd.conf` and starts the Dante SOCKS5 daemon (`sockd -D -f /tmp/sockd.conf`) in the background.

---

## 3. Environment Variable Quirk Matrix

| Env Variable | Default / Expected | Behavior / Constraints |
| :--- | :--- | :--- |
| `CREDENTIALS` | `true` | Set to `false` to disable the `auth.txt` presence and format validations (e.g., for key/cert-based VPNs or tests). |
| `PROXY_PORT` | `""` | The SOCKS5 proxy port. SOCKS5 daemon (`sockd`) will **not** start if this is unset/empty. |
| `PROXY_USER` / `PROXY_PASS` | `""` | If setting authentication, both variables must be set. Leaving them empty runs SOCKS5 in open/anonymous mode. |

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
    docker exec <container> pgrep -a sockd
    ```
