#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

log "Starting Single Gost Proxy Manager..."
log "Waiting for VPN containers..."
sleep 15

log "================================"
log "Resolving VPN container hostnames..."

# Docker DNS automatically resolves container names
VPN1_IP=$(getent hosts vpn1 | awk '{print $1}')
VPN2_IP=$(getent hosts vpn2 | awk '{print $1}')

log "VPN1 (vpn1) -> $VPN1_IP"
log "VPN2 (vpn2) -> $VPN2_IP"

log "Setting up routing..."

# Simple routing tables using resolved IPs
ip route add default via $VPN1_IP table 100 2>/dev/null || true
ip route add default via $VPN2_IP table 101 2>/dev/null || true

ip rule add fwmark 1 table 100 2>/dev/null || true
ip rule add fwmark 2 table 101 2>/dev/null || true

log "================================"

# Start SOCKS5 proxies
log "Starting SOCKS5 :1080 -> VPN1"
gost -L="socks5://0.0.0.0:1080?so_mark=1" &

log "Starting SOCKS5 :1081 -> VPN2"
gost -L="socks5://0.0.0.0:1081?so_mark=2" &

sleep 2

log "================================"
log "✓ Proxy Manager Ready"
log "  Port 1080 -> vpn1 ($VPN1_IP)"
log "  Port 1081 -> vpn2 ($VPN2_IP)"
log "================================"

tail -f /dev/null
