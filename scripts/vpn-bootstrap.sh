#!/bin/sh
set -e

# ─── Configuration ────────────────────────────────────────────────────────────
LOG_FILE=${LOG_FILE:-/logs/$(hostname).log}

CREDENTIALS=${CREDENTIALS:-true}
RUNTIME_CONFIG="/tmp/config-runtime.ovpn"
AUTH_FILE=${AUTH_FILE:-/etc/openvpn/auth.txt}
VPN_CONFIG=${VPN_CONFIG:-/etc/openvpn/config.ovpn}

PROXY_PORT=${PROXY_PORT:-}
PROXY_USER=${PROXY_USER:-}
PROXY_PASS=${PROXY_PASS:-}

# ─── Helpers ──────────────────────────────────────────────────────────────────
ts() { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] [INFO] $1" >&2; }
warn() { echo "[$(ts)] [WARN] $1" >&2; }
error() {
	echo "[$(ts)] [ERROR] $1" >&2
	exit 1
}

# ─── Steps ────────────────────────────────────────────────────────────────────
validate_config() {
	cd /etc/openvpn || error "VPN config directory not found"
	[ -f "$VPN_CONFIG" ] || error "$VPN_CONFIG not found"

	if [ "$CREDENTIALS" = "true" ]; then
		[ -f "$AUTH_FILE" ] || error "$AUTH_FILE not found"
		[ "$(wc -l <"$AUTH_FILE")" -ge 1 ] || error "Invalid auth.txt: expected username and password lines"
	fi

	if [ -n "$PROXY_PORT" ]; then
		case "$PROXY_PORT" in
		'' | *[!0-9]*) error "PROXY_PORT must be a number (got: $PROXY_PORT)" ;;
		esac
		[ "$PROXY_PORT" -ge 1 ] && [ "$PROXY_PORT" -le 65535 ] || error "PROXY_PORT out of range: $PROXY_PORT"

		if { [ -n "$PROXY_USER" ] && [ -z "$PROXY_PASS" ]; } ||
			{ [ -z "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; }; then
			error "Set both PROXY_USER and PROXY_PASS, or neither (open proxy)"
		fi
	fi
}

save_proxy_env() {
	# Save environmental snapshot configuration for OpenVPN lifecycle script context
	cat >/tmp/proxy-env.sh <<EOF
PROXY_PORT='${PROXY_PORT}'
PROXY_USER='${PROXY_USER}'
PROXY_PASS='${PROXY_PASS}'
EOF
}

build_runtime_config() {
	log "Preparing OpenVPN configuration..."
	cat "$VPN_CONFIG" >"$RUNTIME_CONFIG"
	cat >>"$RUNTIME_CONFIG" <<EOF

# Auto-reconnect directives
ping-restart 120
persist-key
persist-tun
resolv-retry infinite
connect-retry 5
connect-retry-max 10

route-delay 5
route-nopull
redirect-gateway def1 bypass-dhcp

mute-replay-warnings

script-security 2
up /usr/local/bin/setup-nat.sh
EOF
}

start_openvpn() {
	if [ -n "$PROXY_PORT" ]; then
		log "OpenVPN + Dante SOCKS5 proxy will start on :${PROXY_PORT} once tunnel is up"
	else
		log "OpenVPN starting (no proxy configured)"
	fi

	if [ "$CREDENTIALS" = "true" ]; then
		exec openvpn --config "$RUNTIME_CONFIG" --auth-user-pass "$AUTH_FILE"
	else
		exec openvpn --config "$RUNTIME_CONFIG"
	fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
	validate_config
	save_proxy_env
	build_runtime_config
	start_openvpn
}

main "$@"
