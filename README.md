# Docker VPN SOCKS Router

A lightweight, containerized solution for running **OpenVPN** and **OpenConnect / AnyConnect** VPN clients with embedded SOCKS5 proxies. Each VPN container runs its own Dante SOCKS5 server bound directly to the VPN tunnel interface (`tun0`), so clients route traffic through a specific VPN by choosing its port.

## Architecture

```
Client → SOCKS5 Port 1080 → OpenVPN Container (Dante on tun0) → OpenVPN Tunnel → Internet
Client → SOCKS5 Port 1082 → OpenConnect Container (Dante on tun0) → OpenConnect Tunnel → Internet
```

Each container is self-contained: one VPN client process (OpenVPN or OpenConnect) + one Dante daemon, no separate proxy container.

### Network Flow

```
Application
    ↓ (SOCKS5 request to port 1080 / 1082)
VPN Container (Dante)
    ↓ (bound to tun0, exits via VPN tunnel)
iptables MASQUERADE on tun0
    ↓
Internet (with VPN IP)
```

## Features

- **Multi-Protocol Support**: Run **OpenVPN** or **OpenConnect / AnyConnect** containers
- **Self-contained containers**: Each VPN container runs its own embedded Dante SOCKS5 server
- **Multiple VPN support**: Run multiple VPN containers on different ports simultaneously
- **Flexible Auth**: Supply credentials via environment variables (`VPN_USER`/`VPN_PASSWORD`) or files (`auth.txt`)
- **Untrusted Cert Auto-Acceptance**: Automatic handling of untrusted/self-signed OpenConnect certificates (`VPN_AUTO_ACCEPT_CERT=true`)
- **Optional SOCKS5 auth**: Set `PROXY_USER`/`PROXY_PASS` for username auth, or leave unset for open proxy
- **Policy-based routing**: Asymmetric routing fix via a dedicated routing table (table 128)
- **LAN bypass**: Local subnets (`10/8`, `172.16/12`, `192.168/16`) never go through the VPN tunnel
- **Macvlan support**: Assign real LAN IPs to containers for direct LAN access without port-forwarding
- **Easy to scale**: Add more VPN connections by duplicating service blocks

## Prerequisites

- Docker and Docker Compose
- OpenVPN configuration files (`.ovpn`) OR OpenConnect server address (e.g., `TCI.apibaz.org`)
- VPN credentials (via environment variables or `auth.txt`)

## Directory Structure

```
docker-ovpn-socks/
├── Dockerfile                     # Multi-stage: base (Debian) + ovpn + openconnect
├── docker-compose.yml             # Simple multi-protocol deployment
├── docker-compose.base.yml        # Reusable ovpn-template & openconnect-template
├── docker-compose.bridge.yml      # Multi-VPN with macvlan LAN IPs
├── docker-compose.test.yml        # Test environment
├── scripts/
│   ├── ovpn-bootstrap.sh          # OpenVPN entrypoint
│   ├── openconnect-bootstrap.sh   # OpenConnect entrypoint
│   ├── vpnc-wrapper.sh            # OpenConnect vpnc event hook wrapper
│   └── _vpn-nat.sh                # Tunnel hook: configures NAT, routing, and Dante
├── configs/
│   ├── ovpn-vpnbaz/               # OpenVPN provider configs + auth.txt
│   ├── ovpn-eliteping/            # OpenVPN provider configs + auth.txt
│   └── shared/
└── BRIDGE.md                      # Macvlan networking setup guide
```

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/hesam-init/docker-ovpn-socks.git
cd docker-ovpn-socks
```

### 2. Add VPN Configurations

Place your `.ovpn` file and `auth.txt` inside a config directory:

```bash
mkdir -p configs/myvpn
cp my-server.ovpn configs/myvpn/config.ovpn
```

**`configs/myvpn/auth.txt`** format:

```
your_vpn_username
your_vpn_password
```

```bash
chmod 600 configs/myvpn/auth.txt
```

### 3. Configure Compose

Edit `docker-compose.yml` to point at your config:

```yaml
services:
  myvpn-socks:
    extends:
      file: docker-compose.base.yml
      service: vpn-template
    container_name: myvpn-socks
    environment:
      - PROXY_PORT=1080
      - VPN_CONFIG=/etc/openvpn/config.ovpn
    ports:
      - "1080:1080"
    volumes:
      - ./configs/myvpn:/etc/openvpn:ro,z
```

### 4. Build and Start

```bash
docker compose -f docker-compose.base.yml build
docker compose up -d
```

### 5. Test Proxy

```bash
# Check your real IP
curl ifconfig.me

# Check VPN IP through proxy
curl --proxy socks5h://127.0.0.1:1080 ifconfig.me
```

## Environment Variables

### Common / Proxy Variables
| Variable | Default | Description |
|---|---|---|
| `PROXY_PORT` | _(empty)_ | Port for Dante SOCKS5 server; leave unset to disable proxy |
| `PROXY_USER` | _(empty)_ | SOCKS5 username (requires `PROXY_PASS`) |
| `PROXY_PASS` | _(empty)_ | SOCKS5 password (requires `PROXY_USER`) |
| `CREDENTIALS` | `true` | Set to `false` to skip credential requirements (e.g. for certs or tests) |

### OpenVPN Variables
| Variable | Default | Description |
|---|---|---|
| `VPN_CONFIG` | `/etc/openvpn/config.ovpn` | Path to the `.ovpn` file inside the container |
| `AUTH_FILE` | `/etc/openvpn/auth.txt` | Path to the credentials file |

### OpenConnect Variables
| Variable | Default | Description |
|---|---|---|
| `VPN_SERVER` | _(empty)_ | OpenConnect server hostname / IP (e.g. `TCI.apibaz.org`) |
| `VPN_USER` | _(empty)_ | OpenConnect username (if not using auth file) |
| `VPN_PASSWORD` | _(empty)_ | OpenConnect password (if not using auth file) |
| `VPN_AUTH_FILE` | `/etc/openconnect/auth.txt` | Path to credentials file (Line 1: user, Line 2: pass) |
| `VPN_AUTO_ACCEPT_CERT`| `true` | Auto-confirm untrusted/self-signed certificate prompt with `"yes"` |
| `VPN_EXTRA_ARGS` | `--no-dtls` | Extra command-line arguments passed to `openconnect` |
| `VPN_AUTHGROUP` | _(empty)_ | Optional authgroup dropdown selection |

## Compose Files

### `docker-compose.yml` — Simple Deployment

Single VPN container with port-mapped SOCKS5 on port `1080`. Use this for a basic setup.

```bash
docker compose up -d
docker compose logs -f
```

### `docker-compose.bridge.yml` — Multi-VPN with Macvlan

Two VPN containers (`vpnbaz-bridge`, `eliteping-bridge`), each with a real LAN IP via macvlan. Requires the external `docker-ovpn-vlan` macvlan network to exist first (see `BRIDGE.md`).

```bash
docker compose -f docker-compose.bridge.yml up -d
docker compose -f docker-compose.bridge.yml logs -f
```

| Container | LAN IP | Port | Config |
|---|---|---|---|
| `vpnbaz-bridge` | `192.168.0.110` | `1080` | `nl1-typ2.ovpn` |
| `eliteping-bridge` | `192.168.0.120` | `1081` | `ir.de1.e-mix.ir.ovpn` |

### `docker-compose.test.yml` — Test Environment

Single container with `CREDENTIALS=false` for testing configs that don't require authentication.

```bash
docker compose -f docker-compose.test.yml up -d
```

## Adding More VPN Connections

1. Add a config directory with your `.ovpn` and `auth.txt`:

```bash
mkdir -p configs/vpn3
cp server.ovpn configs/vpn3/config.ovpn
cp credentials.txt configs/vpn3/auth.txt
```

2. Add a new service to your compose file using `extends`:

```yaml
vpn3-socks:
  extends:
    file: docker-compose.base.yml
    service: vpn-template
  container_name: vpn3-socks
  environment:
    - PROXY_PORT=1082
    - VPN_CONFIG=/etc/openvpn/config.ovpn
  ports:
    - "1082:1082"
  volumes:
    - ./configs/vpn3:/etc/openvpn:ro,z
```

3. Start the new service:

```bash
docker compose up -d vpn3-socks
```

## Usage Examples

### Command Line

```bash
# curl
curl --proxy socks5h://127.0.0.1:1080 https://ipinfo.io

# wget
wget -e use_proxy=yes -e https_proxy=socks5h://127.0.0.1:1080 https://ipinfo.io

# git
git config --global http.proxy socks5h://127.0.0.1:1080
```

### With SOCKS5 Authentication

If `PROXY_USER` and `PROXY_PASS` are set:

```bash
curl --proxy socks5h://user:pass@127.0.0.1:1080 https://ipinfo.io
```

### Browser (Firefox)

1. Settings → Network Settings → Manual proxy configuration
2. SOCKS Host: `127.0.0.1`, Port: `1080`
3. Select "SOCKS v5"

### Macvlan (Direct LAN Access)

```bash
# Access by real LAN IP from any device on the network
curl --proxy socks5://192.168.0.110:1080 https://ipinfo.io
```

## Management Commands

```bash
# View logs
docker compose logs -f

# View specific container logs
docker logs -f ovpn-socks

# Restart a service
docker compose restart ovpn-socks

# Stop all services
docker compose down

# Rebuild after changes
docker compose build --no-cache
docker compose up -d

# Shell access
docker exec -it ovpn-socks sh
```

## Troubleshooting

### Check VPN Tunnel

```bash
# Verify tun0 interface is up
docker exec ovpn-socks ip addr show tun0

# Check external IP through VPN
docker exec ovpn-socks curl ifconfig.me
```

### Check NAT Rules

```bash
# View iptables NAT rules
docker exec ovpn-socks iptables -t nat -L -n -v | grep MASQUERADE
```

### Check Routing Tables

```bash
# Main routing table
docker exec ovpn-socks ip route show

# Policy routing table (reply path fix)
docker exec ovpn-socks ip route show table 128

# Routing rules
docker exec ovpn-socks ip rule show
```

### Check Dante Status

```bash
# Verify Dante is running
docker exec ovpn-socks pgrep -a sockd
```

### Common Issues

**Problem:** Proxy connects but no internet

**Solution:** Verify the VPN tunnel is up and NAT is configured:

```bash
docker exec ovpn-socks ip addr show tun0
docker exec ovpn-socks iptables -t nat -L -n -v | grep MASQUERADE
```

**Problem:** Connections from LAN drop or reset

**Solution:** Check policy routing table 128 is set up (handles reply asymmetry for macvlan setups):

```bash
docker exec ovpn-socks ip route show table 128
docker exec ovpn-socks ip rule show
```

**Problem:** Local network addresses routed through VPN

**Solution:** LAN bypass routes should be present in the main table:

```bash
docker exec ovpn-socks ip route show | grep -E '10\.|172\.|192\.168'
```

**Problem:** `AUTH_FILE not found` on startup

**Solution:** Ensure `auth.txt` exists in the mounted config directory, or set `CREDENTIALS=false` if the VPN does not require authentication.

## Technical Details

### How It Works

1. `vpn-bootstrap.sh` validates env vars, builds a runtime `.ovpn` config with auto-reconnect directives and `up` hook, then starts OpenVPN
2. Once `tun0` is established, OpenVPN calls `vpn-nat.sh`
3. `vpn-nat.sh` configures iptables NAT (`MASQUERADE` on `tun0`), policy routing table 128 (reply path fix), LAN bypass routes, then starts Dante bound to `tun0`
4. Dante accepts SOCKS5 connections on `PROXY_PORT` and proxies them out through the VPN tunnel

### Security Considerations

- VPN credentials are stored in plaintext in `auth.txt` — use `chmod 600` and restrict volume mounts with `:ro`
- Containers require `NET_ADMIN` capability for network configuration
- Use `PROXY_USER`/`PROXY_PASS` to restrict SOCKS5 access if the port is exposed on a shared network
- Consider Docker secrets for production deployments

### Performance

- **Memory**: ~50MB per VPN container
- **CPU**: Minimal at idle, scales with traffic throughput
- **Latency**: Adds ~5–20ms depending on VPN server location

## Acknowledgments

- [Dante](https://www.inet.no/dante/) - SOCKS5 server
- [OpenVPN](https://openvpn.net/) - VPN protocol
- [Alpine Linux](https://alpinelinux.org/) - Base image

## License

:)
