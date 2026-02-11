#!/bin/sh
set -e

VPN_CONFIG=${VPN_CONFIG:-/vpn/config.ovpn}
RUNTIME_CONFIG="/tmp/config-runtime.ovpn"

CREDENTIALS=${CREDENTIALS:-true}
AUTH_FILE=${AUTH_FILE:-/shared/auth.txt}
LOG_FILE=${LOG_FILE:-/logs/$(hostname).log}

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
error() {
	echo "[ERROR] $1" >&2
	exit 1
}

# Validations
cd /vpn || error "VPN config directory not found"
[ -f "$VPN_CONFIG" ] || error "$VPN_CONFIG not found"

if [ "$CREDENTIALS" = "true" ]; then
	[ -f "$AUTH_FILE" ] || error "$AUTH_FILE not found"

	if [ $(wc -l <"$AUTH_FILE") -lt 1 ]; then
		error "Invalid auth.txt format. Expected 2 lines (username and password)"
	fi
fi

# Create iptables setup script
cat >/tmp/setup-nat.sh <<'SCRIPT'
#!/bin/sh
sleep 5

iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "[$(date +'%Y-%m-%d %H:%M:%S')] NAT routing configured" >&2

gost -L dns://:53/1.1.1.1,tls://1.1.1.1:853?mode=udp &
echo "[$(date +'%Y-%m-%d %H:%M:%S')] DNS proxy started" >&2
SCRIPT

chmod +x /tmp/setup-nat.sh

log "Preparing configuration..."
cat "$VPN_CONFIG" >"$RUNTIME_CONFIG"
cat >>"$RUNTIME_CONFIG" <<EOF

# Auto-reconnect directives
ping-restart 120
persist-key
persist-tun
resolv-retry infinite
connect-retry 5
connect-retry-max 999999

script-security 2
up /tmp/setup-nat.sh
EOF

log "Starting OpenVPN..."
if [ "$CREDENTIALS" = "true" ]; then
	openvpn --config "$RUNTIME_CONFIG" \
		--auth-user-pass "$AUTH_FILE"
else
	openvpn --config "$RUNTIME_CONFIG"
fi
