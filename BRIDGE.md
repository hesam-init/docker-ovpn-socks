# Docker Bridge + Macvlan Networking Guide (VPN-SOCKS Repo)

- **Bridge** (`vpn1-net`, `vpn2-net`, `vpn3-net`): Gost discovers VPN containers via Docker DNS (`getent hosts vpn1`), routes via policy tables (fwmark).
- **Macvlan** (`docker-ovpn-vlan`): VPN containers get real LAN IPs for direct access (e.g., ping `192.168.0.65`). [docs.docker](https://docs.docker.com/engine/network/drivers/macvlan/)
- **Gost**: Connects only to bridges, exposes `1080-1100` SOCKS5 ports per VPN.

## Setup: External Macvlan (No Conflicts)

### 1. Create Shared Macvlan (Once)

```bash
docker network create \
  --driver macvlan \
  -o parent=eno1 \
  --subnet=192.168.0.0/24 \
  --ip-range=192.168.0.64/26 \
  docker-ovpn-vlan
```

**Reserved**: `192.168.0.64–127` (64 IPs for VPN containers). [reddit](https://www.reddit.com/r/docker/comments/18x9d84/create_macvlan_with_same_ip_range_as_subnet/)

Verify:

```bash
docker network inspect docker-ovpn-vlan --format '{{json .IPAM.Config}}'
```

### 2. Main Compose (`docker-ovpn-bridge.yml`)

```yaml
services:
  vpn1:
    build:
      context: .
      dockerfile: Dockerfile
      target: vpn
    image: vpn-client:latest
    container_name: vpn1
    networks:
      - vpn1-net
      - docker-ovpn-vlan # LAN IP: auto from 192.168.0.64/26
    volumes:
      - ./configs/vpn1:/vpn:ro,z
      - ./shared:/shared:ro,z
      - ./logs:/logs,z
    environment:
      - TZ=Asia/Tehran
      - CREDENTIALS=true # Uses shared/auth.txt
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1

  # rest vpn profiles...

  gost:
    build:
      context: .
      dockerfile: Dockerfile
      target: gost
    image: gost-proxy:latest
    container_name: gost-proxy
    depends_on:
      - vpn1
      - vpn2
      - vpn3
    networks:
      - vpn1-net
      - vpn2-net
      - vpn3-net # No macvlan—internal routing only
    ports:
      - "1080-1100:1080-1100"
      - "18080:18080"
    environment:
      - TZ=Asia/Tehran
      - WEBAPI_PORT=18080
      - WEBAPI_USER=admin
      - WEBAPI_PASS=gost
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    ulimits:
      nofile:
        soft: 65536
        hard: 65536

networks:
  vpn1-net:
    driver: bridge
  vpn2-net:
    driver: bridge
  vpn3-net:
    driver: bridge

  docker-ovpn-vlan:
    external: true
```

### Manage (`docker-ovpn-bridge.yml`)

```bash
docker compose -f docker-ovpn-bridge.yml up -d
docker compose -f docker-ovpn-bridge.yml logs -f

docker compose -f docker-ovpn-bridge.yml stop
```

### 3. Test Compose (`docker-ovpn-test.yml`)

```yaml
services:
  vpn-test:
    build:
      context: .
      dockerfile: Dockerfile
      target: vpn
    image: vpn-client:latest
    container_name: vpn-test
    networks:
      vpn-test: {}
      docker-ovpn-vlan:
        ipv4_address: 192.168.0.164 # Safe (outside .64/26)
    volumes:
      - ./configs/test:/vpn:ro,z
      - ./shared:/shared:ro,z
      - ./logs:/logs,z
    environment:
      - TZ=Asia/Tehran
      - CREDENTIALS=false
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    dns:
      - 172.17.0.1 # local host machine dns
      - 8.8.8.8

networks:
  vpn-test:
    driver: bridge

  docker-ovpn-vlan:
    external: true
```

### Manage (`docker-ovpn-test.yml`)

```bash
docker compose -f docker-ovpn-test.yml up -d
docker compose -f docker-ovpn-test.yml logs -f

docker compose -f docker-ovpn-test.yml stop
```

### Util Commands

```bash
# VPN IPs on LAN
docker inspect vpn1 vpn2 vpn3 vpn-test --format '{{.Name}}: {{index .NetworkSettings.Networks "docker-ovpn-vlan" "IPAddress"}}'

# Gost routes (in container)
docker exec gost-proxy ip rule show; ip route show table 100

# Test SOCKS
curl --proxy socks5://127.0.0.1:1080 ifconfig.me  # VPN1 IP
curl --proxy socks5://127.0.0.1:1081 ifconfig.me  # VPN2 IP
```

## Host Ping Fix (Shim)

```bash
sudo ip link add docker-shim link eno1 type macvlan mode bridge
sudo ip addr add 192.168.0.163/32 dev docker-shim
sudo ip link set docker-shim up
sudo ip route add 192.168.0.64/26 dev docker-shim
ping 192.168.0.65  # Now works!
```

## Scaling

- **Add vpn4**: Duplicate service + `./configs/vpn4` + `vpn4-net` + Gost networks/ports.
- **More tests**: Any compose can use `docker-ovpn-vlan: { ipv4_address: XXX }`.
- **Cleanup**: `docker network rm docker-ovpn-vlan` (stops all attached containers first). [reddit](https://www.reddit.com/r/docker/comments/bonlwu/dockercompose_macvlan_failed_to_allocate_gateway/)
