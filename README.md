# Docker VPN SOCKS Router

A lightweight, containerized solution for running **OpenVPN** and **OpenConnect / Cisco AnyConnect** VPN clients with embedded **[gost](https://gost.run) HTTP + SOCKS5** proxies. Each VPN container runs its own gost proxy, which serves HTTP and SOCKS4/5 on a single port and sends all traffic out through the VPN tunnel interface (`tun0`), allowing applications and local network devices to route traffic through specific VPNs simply by selecting a port or dedicated LAN IP.

---

## Architecture

Each container is self-contained: one VPN client process (OpenVPN or OpenConnect) + one gost HTTP/SOCKS5 proxy. No separate proxy container or complex inter-container proxy chaining is required.

```mermaid
flowchart TD
    subgraph Clients["Clients & Applications"]
        App1["Application / Browser<br>(Port 1080)"]
        App2["Application / Browser<br>(Port 9090)"]
        LAN["LAN Devices<br>(Smart TVs, PCs)"]
    end

    subgraph DockerHost["Docker Host"]
        subgraph OVPN["OpenVPN Container (ovpn-template)"]
            Gost1["gost HTTP + SOCKS5<br>(0.0.0.0:1080)"]
            NAT1["iptables MASQUERADE"]
            TUN1["tun0 Interface"]
            Table1["Routing Table 128<br>(Reply Path Fix)"]
        end

        subgraph OC["OpenConnect Container (openconnect-template)"]
            Gost2["gost HTTP + SOCKS5<br>(0.0.0.0:1080 -> Host 9090)"]
            NAT2["iptables MASQUERADE"]
            TUN2["tun0 Interface"]
            Table2["Routing Table 128<br>(Reply Path Fix)"]
        end
    end

    subgraph Remote["Remote Endpoints"]
        RemoteOVPN["OpenVPN Server"]
        RemoteOC["OpenConnect / AnyConnect Server"]
        Internet["Internet<br>(Masked with VPN IP)"]
    end

    App1 -->|"socks5h:// or http://127.0.0.1:1080"| Gost1
    App2 -->|"socks5h:// or http://127.0.0.1:9090"| Gost2
    LAN -->|"socks5:// or http://192.168.0.120:1080 (macvlan)"| Gost1

    Gost1 --> TUN1
    TUN1 --> NAT1
    NAT1 --> RemoteOVPN
    RemoteOVPN --> Internet

    Gost2 --> TUN2
    TUN2 --> NAT2
    NAT2 --> RemoteOC
    RemoteOC --> Internet
```

### Network & Routing Flow

```text
Application Request (HTTP or SOCKS4/5)
      │
      ▼
Container gost Proxy (auto://:PROXY_PORT)
      │
      ▼
Tunnel Interface (gost ?interface=tun0)
      │
      ▼
iptables NAT MASQUERADE on tun0
      │
      ▼
Encrypted VPN Tunnel (OpenVPN or OpenConnect)
      │
      ▼
Internet (Egress with Remote VPN Gateway IP)
```

- **Policy-Based Routing (Table 128)**: Routes return traffic for incoming connections (host port-forwards and macvlan interfaces) back through their original gateway, eliminating asymmetric routing drops.
- **LAN Bypass**: RFC-1918 private subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) are routed through the local bridge/host gateway so local network resources remain directly accessible.

---

## Features

- **Multi-Protocol Support**: Seamlessly run **OpenVPN** and **OpenConnect / Cisco AnyConnect** containers.
- **HTTP + SOCKS5 on One Port**: Each container runs an embedded [gost](https://gost.run) proxy (`auto://`) that accepts HTTP and SOCKS4/5 clients on the same port, with egress bound to `tun0` so traffic can't leak if the tunnel drops.
- **Multi-VPN Concurrent Routing**: Run multiple VPN containers simultaneously on different host ports or dedicated LAN IPs.
- **Flexible Authentication**: Provide credentials via environment variables (`VPN_USER`/`VPN_PASSWORD`) or mounted credential files (`auth.txt`).
- **Untrusted Certificate Auto-Acceptance**: Automatic handling of untrusted, self-signed, or legacy OpenConnect SSL certificates (`VPN_AUTO_ACCEPT_CERT=true`).
- **Optional Proxy Authentication**: Set `PROXY_USER` and `PROXY_PASS` for authenticated access (HTTP and SOCKS5), or leave unset for open LAN proxying. Special characters are URL-encoded automatically.
- **Policy-Based Routing (Table 128)**: Dedicated routing tables solve asymmetric routing issues when port forwarding or using multi-homed interfaces.
- **RFC-1918 LAN Bypass**: Local subnets (`10/8`, `172.16/12`, `192.168/16`) automatically bypass the VPN tunnel.
- **Macvlan Support**: Assign real, dedicated LAN IPs to containers for direct access from any device on your network without host port forwarding (see [wiki/bridge.md](wiki/bridge.md)).
- **Integrated Docker Healthchecks**: Continual verification of `tun0` interface status and outbound reachability with automated failover and restart support.
- **Alpine 3.24 Base**: Small (~117 MB) multi-stage Alpine image with support for custom mirrors in restricted network environments.

---

## Prerequisites

- Docker Engine (v20.10+), Docker Compose (v2.0+) and Docker Buildx (used by `make`). See the host setup guides for [Arch Linux](wiki/install-arch.md) and [Debian-based distros](wiki/install-debian.md)
- Host Linux kernel with `/dev/net/tun` support (standard on most distributions)
- OpenVPN configuration files (`.ovpn`) OR OpenConnect/AnyConnect server address
- VPN credentials (username and password)

---

## Directory Structure

```text
docker-ovpn-socks/
├── Dockerfile                  # Multi-stage build: Alpine 3.24 base + gost, ovpn & openconnect targets
├── Makefile                    # `make` / `make raw` image builds
├── docker-compose.base.yml     # Base service templates: ovpn-template & openconnect-template
├── docker-compose.yml          # Standard multi-protocol deployment (port mapping)
├── docker-compose.bridge.yml   # Multi-VPN deployment with Macvlan LAN IPs
├── docker-compose.test.yml     # Testing compose file for auth-free VPN configs
├── scripts/
│   ├── openvpn-entrypoint.sh     # OpenVPN entrypoint & config builder
│   ├── openconnect-entrypoint.sh # OpenConnect entrypoint & credential loader
│   ├── openconnect-hook.sh       # OpenConnect vpnc-script hook (wraps stock vpnc-script)
│   ├── tunnel-up.sh              # Tunnel hook: NAT masquerade, Table 128 routing, & gost proxy
│   └── lib/common.sh             # Shared helpers sourced by all scripts
├── configs/                    # Directory for provider configs & credentials (gitignored)
│   ├── ovpn-vpnbaz/            # Sample provider directory
│   ├── ovpn-kart/              # Sample provider directory
│   └── ovpn-eliteping/         # Sample provider directory
├── wiki/
│   ├── README.md               # Wiki index
│   ├── install-arch.md         # Docker host setup on Arch Linux
│   ├── install-debian.md       # Docker host setup on Debian/Ubuntu
│   └── bridge.md               # Macvlan networking and host-shim guide
└── CLAUDE.md                   # Claude Code guidance: architecture & runtime quirks
```

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/hesam-init/docker-ovpn-socks.git
cd docker-ovpn-socks
```

---

### Option A: OpenVPN Setup

1. Create a config directory and copy your `.ovpn` configuration:

   ```bash
   mkdir -p configs/my-ovpn
   cp /path/to/my-vpn.ovpn configs/my-ovpn/config.ovpn
   ```

2. Create `configs/my-ovpn/auth.txt` with your username on line 1 and password on line 2:

   ```text
   your_vpn_username
   your_vpn_password
   ```

   ```bash
   chmod 600 configs/my-ovpn/auth.txt
   ```

3. Add or update the service in `docker-compose.yml`:

   ```yaml
   services:
     my-ovpn-socks:
       extends:
         file: docker-compose.base.yml
         service: ovpn-template
       container_name: my-ovpn-socks
       environment:
         - PROXY_PORT=1080
         - VPN_CONFIG=/etc/openvpn/config.ovpn
       ports:
         - "1080:1080"
       volumes:
         - ./configs/my-ovpn:/etc/openvpn:ro,z
   ```

---

### Option B: OpenConnect / AnyConnect Setup

#### Method 1: Credentials via Environment Variables

```yaml
services:
  my-oc-socks:
    extends:
      file: docker-compose.base.yml
      service: openconnect-template
    container_name: my-oc-socks
    environment:
      - PROXY_PORT=1080
      - VPN_SERVER=vpn.example.com
      - VPN_USER=your_username
      - VPN_PASSWORD=your_password
      - VPN_AUTO_ACCEPT_CERT=true
    ports:
      - "9090:1080"
```

#### Method 2: Credentials via Mounted `auth.txt` File

1. Create `configs/my-oc/auth.txt`:
   - Line 1: `your_username`
   - Line 2: `your_password`

   ```bash
   mkdir -p configs/my-oc
   chmod 600 configs/my-oc/auth.txt
   ```

2. Configure `docker-compose.yml`:

   ```yaml
   services:
     my-oc-socks:
       extends:
         file: docker-compose.base.yml
         service: openconnect-template
       container_name: my-oc-socks
       environment:
         - PROXY_PORT=1080
         - VPN_SERVER=vpn.example.com
         - VPN_AUTO_ACCEPT_CERT=true
       ports:
         - "9090:1080"
       volumes:
         - ./configs/my-oc/auth.txt:/etc/openconnect/auth.txt:ro,z
   ```

---

### 3. Build Base Images and Start Services

```bash
# Build the images (uses host networking for reliable mirror access)
make               # or `make raw` for plain `docker build`

# Start services in the background
docker compose up -d

# View live container logs
docker compose logs -f
```

---

### 4. Test the Proxy

Verify that external traffic is exiting through the VPN. Every proxy port accepts both HTTP and SOCKS clients:

```bash
# Direct host connection (your real IP)
curl ifconfig.me

# Through the OpenVPN proxy (port 1080), as SOCKS5 or HTTP
curl --proxy socks5h://127.0.0.1:1080 ifconfig.me
curl --proxy http://127.0.0.1:1080 ifconfig.me

# Through the OpenConnect proxy (port 9090)
curl --proxy socks5h://127.0.0.1:9090 ifconfig.me
```

> [!NOTE]
> `docker compose build` does not work for these templates: Compose builds through bake, which rejects `build.network: host` unless `--allow=network.host` is passed, and Compose has no way to pass it. The Makefile runs `docker buildx bake --allow=network.host -f docker-compose.base.yml --load <targets>` instead.

> [!TIP]
> Always use `socks5h://` instead of `socks5://` in `curl` so that DNS resolution happens remotely inside the container rather than leaking through your local DNS resolver.

---

## Environment Variables Reference

### Common & Proxy Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PROXY_PORT` | _(empty)_ | Port gost listens on for HTTP and SOCKS (e.g. `1080`). If unset, no proxy is started. |
| `PROXY_USER` | _(empty)_ | Proxy username (requires `PROXY_PASS`). |
| `PROXY_PASS` | _(empty)_ | Proxy password (requires `PROXY_USER`). |
| `QUIET_GOST` | `true` | gost logs only errors (no per-connection log lines). Set to `false` for full gost logging when debugging. |
| `CREDENTIALS` | `true` | Set to `false` to disable credential validations (e.g. for key/cert-based VPNs or tests). |
| `TZ` | `Asia/Tehran` | Timezone inside the container. |
| `LOG_FILE` | `/logs/<hostname>.log` | Log file location for container operations. |

### OpenVPN Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `VPN_CONFIG` | `/etc/openvpn/config.ovpn` | Path to the `.ovpn` configuration file inside the container. |
| `AUTH_FILE` | `/etc/openvpn/auth.txt` | Path to the credentials file (Line 1: username, Line 2: password). |

### OpenConnect / AnyConnect Variables

| Variable | Default / Fallback | Description |
| :--- | :--- | :--- |
| `VPN_SERVER` | `${OPENCONNECT_SERVER}` / `${SERVER}` | Target OpenConnect VPN server hostname or IP (required). |
| `VPN_USER` | `${VPN_USERNAME}` / `${USER}` / `${USERNAME}` | VPN username (used if auth file is not mounted). |
| `VPN_PASSWORD` | `${VPN_PASS}` / `${PASSWORD}` / `${PASS}` | VPN password (used if auth file is not mounted). |
| `VPN_AUTH_FILE` | `${AUTH_FILE}` / `/etc/openconnect/auth.txt` | Path to credentials file (Line 1: user, Line 2: pass). |
| `VPN_AUTO_ACCEPT_CERT`| `true` | Automatically confirm untrusted/self-signed SSL certificates with `"yes"`. |
| `VPN_EXTRA_ARGS` | `--no-dtls` | Additional command-line flags passed directly to `openconnect`. |
| `VPN_AUTHGROUP` | _(empty)_ | Optional authgroup dropdown selection name. |

---

## Compose Files Reference

### 1. `docker-compose.yml` — Multi-Protocol Deployment
Contains standard port-forwarded VPN services:
- `vpnbaz-socks`: OpenVPN client (container: `vpnbaz`, port mapped to host `1080:1080`)
- `eliteping-socks`: OpenVPN client (container: `eliteping`, port mapped to host `1081:1080`)
- `tci-socks`: OpenConnect client (container: `tci-socks`, port mapped to host `9090:1080`)

```bash
docker compose up -d
docker compose logs -f
```

### 2. `docker-compose.base.yml` — Service Templates
Defines the base service definitions inherited by other compose files via `extends`:
- `ovpn-template`: Image `ovpn-client:latest`, `NET_ADMIN`, `/dev/net/tun`, sysctls for IP forwarding and source valid mark, ulimits, fast-stop signal (`SIGKILL`), and automated healthchecks.
- `openconnect-template`: Image `openconnect-client:latest`, shares identical network capabilities, sysctls, and healthcheck configurations.

Build base images:
```bash
make                  # ovpn-client:latest, openconnect-client:latest (via buildx bake)
make no-cache         # same, ignoring the build cache
make raw              # same images with plain `docker build --network host -f Dockerfile --target ovpn|openconnect`
make raw-no-cache     # raw build, ignoring the build cache
make ARGS=...         # extra flags are passed through
```

### 3. `docker-compose.bridge.yml` — Multi-VPN with Macvlan LAN IPs
Deploys VPN containers directly onto your physical local network using Docker's macvlan driver. Each container receives a dedicated LAN IP:
- `vpnbaz-bridge`: OpenVPN on LAN IP `192.168.0.120:1080`
- `eliteping-bridge`: OpenVPN on LAN IP `192.168.0.121:1080`
- `tci-bridge`: OpenConnect on LAN IP `192.168.0.110:1080` (also maps port `9090`)

> [!IMPORTANT]
> The `docker-ovpn-vlan` external network must be created before starting this compose file. For complete instructions and host communication setup, see [wiki/bridge.md](wiki/bridge.md).

```bash
docker compose -f docker-compose.bridge.yml up -d
```

### 4. `docker-compose.test.yml` — Authentication-Free Testing
A lightweight test environment with `CREDENTIALS=false` for testing `.ovpn` configurations that use embedded keys/certificates or public endpoints without authentication:

```bash
docker compose -f docker-compose.test.yml up -d
```

---

## Adding More VPN Connections

To add another VPN service, simply define a new block in your compose file extending the appropriate base template:

### Adding an OpenVPN Service:

```yaml
vpn-nl-socks:
  extends:
    file: docker-compose.base.yml
    service: ovpn-template
  container_name: vpn-nl-socks
  environment:
    - PROXY_PORT=1080
    - VPN_CONFIG=/etc/openvpn/nl-server.ovpn
  ports:
    - "1083:1080"
  volumes:
    - ./configs/my-nl-vpn:/etc/openvpn:ro,z
```

### Adding an OpenConnect Service:

```yaml
vpn-cisco-socks:
  extends:
    file: docker-compose.base.yml
    service: openconnect-template
  container_name: vpn-cisco-socks
  environment:
    - PROXY_PORT=1080
    - VPN_SERVER=cisco.gateway.com
    - VPN_USER=myuser
    - VPN_PASSWORD=mypassword
  ports:
    - "1084:1080"
```

Start the new service:
```bash
docker compose up -d vpn-nl-socks vpn-cisco-socks
```

---

## Usage Examples

### Command Line Tools

```bash
# curl (remote DNS resolution)
curl --proxy socks5h://127.0.0.1:1080 https://ipinfo.io

# wget
wget -e use_proxy=yes -e https_proxy=socks5h://127.0.0.1:1080 https://ipinfo.io

# Git over SOCKS5
git config --global http.proxy socks5h://127.0.0.1:1080

# Tools that only speak HTTP proxies can use the same port
export ALL_PROXY="socks5h://127.0.0.1:1080"
export http_proxy="http://127.0.0.1:1080"
export https_proxy="http://127.0.0.1:1080"
```

### Authenticated Proxy Usage

When `PROXY_USER` and `PROXY_PASS` are configured:

```bash
curl --proxy socks5h://proxyuser:secretpass@127.0.0.1:1080 https://ipinfo.io
curl --proxy http://proxyuser:secretpass@127.0.0.1:1080 https://ipinfo.io
```

### Web Browsers (Firefox)

1. Open **Settings** → **General** → **Network Settings**.
2. Select **Manual proxy configuration**.
3. Set **SOCKS Host** to `127.0.0.1` and Port to `1080` (or `9090`).
4. Select **SOCKS v5**.
5. Check **Proxy DNS when using SOCKS v5** to prevent DNS leaks.

Alternatively, set **HTTP Proxy** to the same host and port and check **Also use this proxy for HTTPS**.

### Direct LAN Access (Macvlan)

From any computer, console, or phone connected to the same physical network:

```bash
# Connect directly to container's dedicated LAN IP
curl --proxy socks5://192.168.0.110:1080 https://ipinfo.io
```

---

## Healthchecks & Container Monitoring

Each container inherits automated health monitoring from `docker-compose.base.yml`:

```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "ip link show tun0 && (curl -sf --max-time 5 https://1.1.1.1 > /dev/null || curl -sf --max-time 5 https://cloudflare.com/cdn-cgi/trace > /dev/null)"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 20s
```

### Monitor Container Health

```bash
# View container health status
docker compose ps

# Detailed health check status and logs
docker inspect --format='{{json .State.Health}}' vpnbaz | jq .
```

---

## Management Commands

```bash
# View live logs for all running services
docker compose logs -f

# View logs of a specific container
docker logs -f vpnbaz
docker logs -f tci-socks

# Restart a specific service
docker compose restart vpnbaz

# Stop all containers
docker compose down

# Rebuild containers after Dockerfile or script changes
make no-cache
docker compose up -d

# Shell access into a container
docker exec -it vpnbaz bash
docker exec -it tci-socks bash
```

---

## Troubleshooting Playbook

### Diagnostic Commands

Run these commands inside the target container to inspect network state:

```bash
# 1. Verify VPN tunnel interface is up and has an IP
docker exec -it vpnbaz ip addr show tun0

# 2. Test outbound connectivity through VPN
docker exec -it vpnbaz curl -sf --max-time 5 https://1.1.1.1

# 3. Verify iptables NAT MASQUERADE rule
docker exec -it vpnbaz iptables -t nat -L -n -v

# 4. Check policy routing rules and Table 128
docker exec -it vpnbaz ip rule show
docker exec -it vpnbaz ip route show table 128

# 5. Check if the gost proxy is running
docker exec -it vpnbaz pgrep -a gost
```

---

### Common Issues & Solutions

#### 1. Proxy connects but traffic has no internet
- **Cause**: Tunnel interface `tun0` is not up, or iptables masquerading failed.
- **Solution**: Check container logs (`docker logs -f <container>`) to see if the VPN handshake succeeded. Verify NAT rules:
  ```bash
  docker exec -it <container> iptables -t nat -L POSTROUTING -n -v
  ```

#### 2. OpenConnect certificate prompt rejected
- **Cause**: The VPN server uses a self-signed, invalid, or expired certificate.
- **Solution**: Ensure `VPN_AUTO_ACCEPT_CERT=true` is set in the container environment. The entrypoint script automatically passes `"yes"` to the certificate trust prompt.

#### 3. Connections from LAN drop, reset, or hang
- **Cause**: Asymmetric routing on multi-homed or macvlan interfaces.
- **Solution**: Verify that Table 128 policy routing was created:
  ```bash
  docker exec -it <container> ip route show table 128
  docker exec -it <container> ip rule show
  ```
  Ensure the container has `sysctls: [net.ipv4.conf.all.src_valid_mark=1]` enabled in compose.

#### 4. Local network addresses routed through VPN
- **Cause**: Missing RFC-1918 bypass routes.
- **Solution**: Verify that bypass routes exist in the container routing table:
  ```bash
  docker exec -it <container> ip route show | grep -E '10\.|172\.|192\.168'
  ```

#### 5. OpenVPN `auth.txt not found` or authentication failure
- **Cause**: File missing, bad volume mount path, or incorrect newline formatting (e.g. Windows CRLF line endings).
- **Solution**: Ensure `auth.txt` has line 1 username and line 2 password with Linux LF line endings:
  ```bash
  dos2unix configs/myvpn/auth.txt
  chmod 600 configs/myvpn/auth.txt
  ```

#### 6. gost proxy not running
- **Cause**: `PROXY_PORT` was not provided in the environment, or conflicting `PROXY_USER`/`PROXY_PASS` settings.
- **Solution**: Verify `PROXY_PORT=1080` is present. If using authentication, ensure both `PROXY_USER` and `PROXY_PASS` are defined. gost logs to the container output, and its command line shows the listener:
  ```bash
  docker logs <container> | grep -i gost
  docker exec -it <container> pgrep -a gost
  ```
  By default (`QUIET_GOST=true`) gost logs only errors, so a quiet log is expected while it works normally. Set `QUIET_GOST=false` to see every connection.

---

## Technical Details

### Startup & Lifecycle Flow

#### OpenVPN Lifecycle:
1. **Entrypoint (`scripts/openvpn-entrypoint.sh`)**:
   - Validates configuration files, paths, and credentials.
   - Captures original default route and gateway (`ORIG_GW`, `ORIG_DEV`, `ORIG_IP`) into `/tmp/proxy-env.sh`.
   - Generates `/tmp/config-runtime.ovpn` with auto-reconnect directives and registers `up /usr/local/bin/tunnel-up.sh`.
   - Launches `openvpn`.
2. **Tunnel Hook (`scripts/tunnel-up.sh`)**:
   - Invoked once `tun0` is established.
   - Applies `iptables` NAT masquerade on `tun0` and enables IP forwarding.
   - Applies Policy-Based Routing (Table 128) for `$ORIG_IP` via `$ORIG_GW`.
   - Adds RFC-1918 bypass routes (`10/8`, `172.16/12`, `192.168/16`).
   - Launches gost in the background: `gost -L "auto://[user:pass@]:PORT?interface=tun0"`.

#### OpenConnect Lifecycle:
1. **Entrypoint (`scripts/openconnect-entrypoint.sh`)**:
   - Validates target server and resolves credentials (from env vars or `auth.txt`).
   - Pre-captures original default gateway (`ORIG_GW`, `ORIG_DEV`, `ORIG_IP`) into `/tmp/proxy-env.sh`.
   - Launches `openconnect` with `--script=/usr/local/bin/openconnect-hook.sh`.
   - Automatically answers `"yes"` to untrusted certificate prompts when `VPN_AUTO_ACCEPT_CERT=true`.
2. **Hook (`scripts/openconnect-hook.sh` -> `scripts/tunnel-up.sh`)**:
   - Runs standard `vpnc-script` to configure routes and DNS.
   - On `connect` and `reconnect` events, triggers `/usr/local/bin/tunnel-up.sh` to apply NAT, Table 128 routing, and launch gost.

---

## Security & Performance

- **File Permissions**: Always set `chmod 600` on credentials files (`auth.txt`). Mount configuration directories read-only (`:ro,z`).
- **Required Capabilities**: Containers require `NET_ADMIN` capability and access to `/dev/net/tun` to configure routes and create interfaces.
- **Resource Footprint**:
  - Memory: ~45–60 MB per container.
  - CPU: Negligible at idle (< 0.1%), scales linearly with cryptographic throughput.
  - Latency: Minimal overhead (~1–3 ms internal routing overhead + remote VPN tunnel latency).

---

## Acknowledgments

- [gost](https://gost.run) - GO Simple Tunnel, HTTP/SOCKS proxy
- [OpenVPN](https://openvpn.net/) - Open-source SSL/TLS VPN solution
- [OpenConnect](https://www.infradead.org/openconnect/) - Multi-protocol VPN client for Cisco AnyConnect, Pulse, and GlobalProtect
- [Alpine Linux](https://alpinelinux.org/) - Small, security-oriented container base OS

---

## License

This project is licensed under the [MIT License](LICENSE) or project default terms.
