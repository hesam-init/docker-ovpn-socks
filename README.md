# Docker VPN SOCKS Router

A lightweight, containerized solution for running multiple VPN connections with individual SOCKS5 proxies. One Gost container manages all proxies, routing traffic through separate OpenVPN containers based on port selection.

## Features

- **Single Proxy Manager**: One Gost container handles all SOCKS5 proxies
- **Multiple VPN Support**: Route different traffic through different VPN servers
- **Port-based Routing**: Each SOCKS5 port routes through a specific VPN
- **Pure Docker**: No host network configuration needed
- **Policy-based Routing**: Uses Linux fwmark and ip rules for traffic separation
- **Alpine Linux**: Minimal image size and resource usage
- **Easy to Scale**: Add more VPN connections by duplicating service blocks

## Architecture

```
Client → SOCKS5 Port 1080 → Gost Container → VPN1 Container → Internet (IP1)
Client → SOCKS5 Port 1081 → Gost Container → VPN2 Container → Internet (IP2)
```

### Components

- **VPN Containers** (`vpn1`, `vpn2`): OpenVPN clients with NAT masquerading
- **Gost Container** (`gost-proxy`): Single SOCKS5 server with policy-based routing
- **Docker Networks**: Separate networks for each VPN tunnel

## Prerequisites

- Docker and Docker Compose
- OpenVPN configuration files (.ovpn)
- VPN credentials

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/hesam-init/docker-ovpn-socks.git
cd docker-ovpn-socks
```

### 2. Setup Directory Structure

```bash
mkdir -p configs/{vpn1,vpn2} shared logs
```

### 3. Add VPN Configurations

```bash
# Add your OpenVPN config files
nano configs/vpn1/config.ovpn
nano configs/vpn2/config.ovpn

# Add VPN credentials
nano shared/auth.txt
```

**shared/auth.txt** format:

```
your_vpn_username
your_vpn_password
```

```bash
chmod 600 shared/auth.txt
```

### 4. Build and Start

```bash
docker compose build
docker compose up -d
```

### 5. Test Proxies

```bash
# Check your real IP
curl ifconfig.me

curl --proxy socks5h://127.0.0.1:1080 ifconfig.me
curl --proxy socks5h://127.0.0.1:1081 ifconfig.me
```

## Directory Structure

```
docker-vpn-socks/
├── Dockerfile              # Dockerfile
├── docker-compose.yml      # Service definitions
├── vpn-startup.sh          # VPN initialization script
├── gost-startup.sh         # Gost routing configuration
├── shared/
│   └── auth.txt            # VPN credentials (create this)
├── configs/
│   ├── vpn1/
│   │   └── config.ovpn     # VPN1 OpenVPN config (add yours)
│   └── vpn2/
│       └── config.ovpn     # VPN2 OpenVPN config (add yours)
└── logs/                   # OpenVPN logs
```

## Configuration

### Adding More VPN Connections

1. Create new config directory:

```bash
mkdir -p configs/vpn3
```

1. Add OpenVPN config:

```bash
nano configs/vpn3/config.ovpn
```

1. Add service to `docker-compose.yml`:

```yaml
vpn3:
  image: vpn-client:latest
  container_name: vpn3
  hostname: vpn3
  restart: unless-stopped
  cap_add:
    - NET_ADMIN
  devices:
    - /dev/net/tun
  networks:
    - vpn3-net
  volumes:
    - ./configs/vpn3:/vpn:ro
    - ./shared:/shared:ro
    - ./logs:/logs
  environment:
    - TZ=Asia/Tehran
  sysctls:
    - net.ipv4.ip_forward=1
    - net.ipv4.conf.all.src_valid_mark=1
  dns:
    - 8.8.8.8
```

1. Add network:

```yaml
vpn3-net:
  driver: bridge
```

1. Update Gost container networks:

```yaml
gost:
  networks:
    - vpn1-net
    - vpn2-net
    - vpn3-net # Add this
```

1. Update `gost-startup.sh` to add routing for vpn3:

```bash
VPN3_IP=$(getent hosts vpn3 | awk '{print $1}')
ip route add default via $VPN3_IP table 102 2>/dev/null || true
ip rule add fwmark 3 table 102 2>/dev/null || true
gost -L="socks5://0.0.0.0:1082?so_mark=3" &
```

1. Expose new port in docker-compose.yml:

```yaml
ports:
  - "1080:1080"
  - "1081:1081"
  - "1082:1082" # Add this
```

### Customizing Ports

Edit `gost-startup.sh` to change SOCKS5 ports:

```bash
gost -L="socks5://0.0.0.0:YOUR_PORT?so_mark=1" &
```

Update `docker-compose.yml` port mapping:

```yaml
ports:
  - "YOUR_PORT:YOUR_PORT"
```

## Usage Examples

### Browser Configuration

**Firefox:**

1. Settings → Network Settings → Manual proxy configuration
2. SOCKS Host: `127.0.0.1`, Port: `1080` (for VPN1)
3. Select "SOCKS v5"

### Command Line

```bash
# Using curl
curl --proxy socks5h://127.0.0.1:1080 https://ipinfo.io

# Using wget
wget -e use_proxy=yes -e https_proxy=socks5h://127.0.0.1:1080 https://ipinfo.io

# Using git
git config --global http.proxy socks5h://127.0.0.1:1080
```

## Management Commands

```bash
# View logs
docker compose logs -f

# View specific container logs
docker logs -f vpn1
docker logs -f gost-proxy

# Restart services
docker compose restart

# Restart specific VPN
docker compose restart vpn1

# Stop all services
docker compose down

# Rebuild after configuration changes
docker compose build --no-cache
docker compose up -d

# Shell access
docker exec -it vpn1 sh
docker exec -it gost-proxy sh
```

## Troubleshooting

### Check VPN Connection

```bash
# Check if VPN tunnel is up
docker exec vpn1 ip addr show tun0

# Check VPN IP
docker exec vpn1 curl ifconfig.me

# Check OpenVPN logs
tail -f logs/vpn1.log
```

### Check Routing

```bash
# Check Gost routing tables
docker exec gost-proxy ip route show table 100
docker exec gost-proxy ip route show table 101

# Check routing rules
docker exec gost-proxy ip rule show

# Check DNS resolution
docker exec gost-proxy getent hosts vpn1
docker exec gost-proxy getent hosts vpn2
```

### Check NAT Rules

```bash
# View iptables NAT rules in VPN container
docker exec vpn1 iptables -t nat -L -n -v
```

### Common Issues

**Problem:** "no route to host" errors

**Solution:** Check if VPN containers have established tunnels and NAT is configured:

```bash
docker exec vpn1 ip addr show tun0
docker exec vpn1 iptables -t nat -L -n -v | grep MASQUERADE
```

**Problem:** Proxy connects but no internet

**Solution:** Verify VPN container can access internet:

```bash
docker exec vpn1 curl -I google.com
```

**Problem:** DNS resolution fails

**Solution:** Ensure containers are on the same Docker network:

```bash
docker network inspect docker-vpn-socks-router_vpn1-net
```

## Technical Details

### How It Works

1. **VPN Containers** establish OpenVPN tunnels and configure iptables NAT masquerading
2. **Gost Container** connects to multiple Docker networks (one per VPN)
3. **Policy Routing** uses SO_MARK on sockets and ip rules to direct traffic
4. **Docker DNS** automatically resolves container hostnames to IPs
5. **NAT Forwarding** in VPN containers routes Gost traffic through VPN tunnels

### Network Flow

```
Application
    ↓ (SOCKS5 request to port 1080)
Gost Container
    ↓ (SO_MARK=1, routes via table 100)
Docker Network (vpn1-net)
    ↓ (to gateway vpn1)
VPN1 Container
    ↓ (iptables MASQUERADE to tun0)
OpenVPN Tunnel
    ↓
Internet (with VPN1 IP)
```

## Security Considerations

- VPN credentials are stored in plaintext in `shared/auth.txt` - use proper file permissions (chmod 600)
- Containers run with `NET_ADMIN` capability for network configuration
- OpenVPN logs may contain sensitive information
- Consider using Docker secrets for production deployments

## Performance

- **Memory**: ~50MB per VPN container, ~30MB for Gost container
- **CPU**: Minimal when idle, depends on traffic throughput
- **Latency**: Adds ~5-20ms depending on VPN server location

## License

:)

## Contributing

Pull requests are welcome! For major changes, please open an issue first.

## Acknowledgments

- [Gost](https://github.com/ginuerzh/gost) - GO Simple Tunnel
- [OpenVPN](https://openvpn.net/) - VPN protocol
- [Alpine Linux](https://alpinelinux.org/) - Base image

## Support

For issues and questions:

- Open an issue on GitHub
- Check existing issues for solutions
- Review Docker and OpenVPN logs

---

**Star this repo if you find it useful!** ⭐
