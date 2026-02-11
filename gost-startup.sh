#!/bin/sh
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
error() {
	log "ERROR: $1"
	exit 1
}

BASE_PORT=1080
MAX_PORT=1100
BASE_TABLE=100
BASE_MARK=1

# Web API settings
WEBAPI_PORT=${WEBAPI_PORT:-18080}
WEBAPI_USER=${WEBAPI_USER:-"admin"}
WEBAPI_PASS=${WEBAPI_PASS:-"gost"}

log "Starting Dynamic Gost Proxy Manager..."
log "Waiting for VPN containers..."
sleep 15

log "================================"
log "Auto-discovering VPN networks..."

# Find all VPN containers by hostname pattern
VPN_CONTAINERS=""
i=1
while [ $i -le 20 ]; do
	if getent hosts "vpn${i}" >/dev/null 2>&1; then
		VPN_IP=$(getent hosts "vpn${i}" | awk '{print $1}')
		VPN_CONTAINERS="${VPN_CONTAINERS}vpn${i}:${VPN_IP} "
		log "  ✓ Found vpn${i} at ${VPN_IP}"
	fi
	i=$((i + 1))
done

[ -z "$VPN_CONTAINERS" ] && error "No VPN containers found!"

VPN_COUNT=$(echo "$VPN_CONTAINERS" | wc -w)
log "Discovered $VPN_COUNT VPN container(s)"

log "================================"
log "Configuring routing..."

PORT=$BASE_PORT
TABLE=$BASE_TABLE
MARK=$BASE_MARK
GOST_ARGS=""

for vpn_entry in $VPN_CONTAINERS; do
	[ $PORT -gt $MAX_PORT ] && break

	VPN_NAME=$(echo "$vpn_entry" | cut -d':' -f1)
	VPN_IP=$(echo "$vpn_entry" | cut -d':' -f2)

	log "  Port $PORT -> $VPN_NAME ($VPN_IP)"

	# Setup routing
	ip route add default via $VPN_IP table $TABLE 2>/dev/null || true
	ip rule add fwmark $MARK table $TABLE 2>/dev/null || true

	# Build Gost arguments
	GOST_ARGS="$GOST_ARGS -L=socks5://0.0.0.0:${PORT}?so_mark=${MARK}&resolver=tcp://${VPN_IP}:54"
	
	PORT=$((PORT + 1))
	TABLE=$((TABLE + 1))
	MARK=$((MARK + 1))
done

log "================================"
log "Starting Gost with $VPN_COUNT proxies..."

gost $GOST_ARGS -api=${WEBAPI_USER}:${WEBAPI_PASS}@:${WEBAPI_PORT} &

sleep 3

log "================================"
log "✓ Dynamic Proxy Manager Ready"
log "================================"
log "Web API: http://0.0.0.0:$WEBAPI_PORT"
log "Username: $WEBAPI_USER"
log "Password: $WEBAPI_PASS"

PORT=$BASE_PORT
for vpn_entry in $VPN_CONTAINERS; do
	[ $PORT -gt $MAX_PORT ] && break

	VPN_NAME=$(echo "$vpn_entry" | cut -d':' -f1)
	VPN_IP=$(echo "$vpn_entry" | cut -d':' -f2)

	log "  socks5://0.0.0.0:$PORT -> $VPN_NAME ($VPN_IP)"
	PORT=$((PORT + 1))
done

log "================================"

tail -f /dev/null
