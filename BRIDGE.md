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

### 2. Main Compose (`docker-compose.bridge.yml`)

```bash
docker compose -f docker-compose.bridge.yml up -d
docker compose -f docker-compose.bridge.yml logs -f

docker compose -f docker-compose.bridge.yml stop
```

### 3. Test Compose (`docker-compose.test.yml`)

```bash
docker compose -f docker-compose.test.yml up -d
docker compose -f docker-compose.test.yml logs -f

docker compose -f docker-compose.test.yml stop
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
