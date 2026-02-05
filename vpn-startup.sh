#!/bin/sh
set -e

VPN_CONFIG=${VPN_CONFIG:-config.ovpn}
AUTH_FILE=${AUTH_FILE:-/shared/auth.txt}
LOG_FILE=${LOG_FILE:-/logs/$(hostname).log}

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[ERROR] $1" >&2; exit 1; }

cd /vpn || error "VPN config directory not found"
[ -f "$VPN_CONFIG" ] || error "$VPN_CONFIG not found"
[ -f "$AUTH_FILE" ] || error "$AUTH_FILE not found"

log "Starting OpenVPN..."
openvpn --config "$VPN_CONFIG" --auth-user-pass "$AUTH_FILE" --log "$LOG_FILE" --verb 3 --daemon

log "Waiting for VPN tunnel..."
for i in $(seq 1 30); do
    ip link show tun0 >/dev/null 2>&1 && break
    sleep 1
    [ $i -eq 30 ] && error "VPN tunnel timeout"
done

sleep 5

# Setup NAT masquerading for containers in our network
log "Configuring NAT routing..."
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

log "NAT configured - container traffic will route through VPN"

VPN_IP=$(curl -s --max-time 10 --interface tun0 ifconfig.me 2>/dev/null || echo "Unknown")

log "================================"
log "Container: $(hostname)"
log "VPN IP: $VPN_IP"
log "NAT Gateway: ACTIVE"
log "================================"

tail -f "$LOG_FILE"
