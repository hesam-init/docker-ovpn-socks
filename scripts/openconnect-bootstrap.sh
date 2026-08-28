#!/bin/sh
set -e

# ─── Configuration ────────────────────────────────────────────────────────────
LOG_FILE=${LOG_FILE:-/logs/$(hostname).log}

CREDENTIALS=${CREDENTIALS:-true}
AUTH_FILE=${VPN_AUTH_FILE:-${AUTH_FILE:-/etc/openconnect/auth.txt}}

VPN_SERVER=${VPN_SERVER:-${OPENCONNECT_SERVER:-${SERVER:-}}}
VPN_USER=${VPN_USER:-${VPN_USERNAME:-${USER:-${USERNAME:-}}}}
VPN_PASSWORD=${VPN_PASSWORD:-${VPN_PASS:-${PASSWORD:-${PASS:-}}}}
VPN_AUTO_ACCEPT_CERT=${VPN_AUTO_ACCEPT_CERT:-true}
VPN_EXTRA_ARGS=${VPN_EXTRA_ARGS:---no-dtls}
VPN_AUTHGROUP=${VPN_AUTHGROUP:-}

PROXY_PORT=${PROXY_PORT:-}
PROXY_USER=${PROXY_USER:-}
PROXY_PASS=${PROXY_PASS:-}

RESOLVED_USER=""
RESOLVED_PASSWORD=""

# Pre-captured network variables
ORIG_DEV=""
ORIG_GW=""
ORIG_IP=""

# ─── Helpers ──────────────────────────────────────────────────────────────────
ts() { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] [INFO] $1" >&2; }
warn() { echo "[$(ts)] [WARN] $1" >&2; }
error() {
	echo "[$(ts)] [ERROR] $1" >&2
	exit 1
}

# ─── Steps ────────────────────────────────────────────────────────────────────
validate_and_resolve_config() {
	if [ -z "$VPN_SERVER" ]; then
		error "VPN_SERVER is required (e.g. VPN_SERVER=TCI.apibaz.org)"
	fi

	# Resolve credentials from auth file or environment
	if [ -f "$AUTH_FILE" ]; then
		log "Loading credentials from auth file: $AUTH_FILE"
		RESOLVED_USER=$(sed -n '1p' "$AUTH_FILE" | tr -d '\r\n')
		RESOLVED_PASSWORD=$(sed -n '2p' "$AUTH_FILE" | tr -d '\r\n')
	else
		RESOLVED_USER="$VPN_USER"
		RESOLVED_PASSWORD="$VPN_PASSWORD"
	fi

	if [ "$CREDENTIALS" = "true" ]; then
		if [ -z "$RESOLVED_USER" ] || [ -z "$RESOLVED_PASSWORD" ]; then
			error "Both username and password are required. Provide them via VPN_USER/VPN_PASSWORD env vars or in $AUTH_FILE"
		fi
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

capture_networking() {
	# Capture original default route before OpenConnect modifies routing
	local route_line
	route_line=$(ip -4 route show default | grep -v 'dev tun' | grep 'via' | head -n 1)
	if [ -z "$route_line" ]; then
		route_line=$(ip -4 route show default | head -n 1)
	fi

	if [ -n "$route_line" ]; then
		ORIG_GW=$(echo "$route_line" | sed -n 's/.*via \([0-9.]*\).*/\1/p')
		ORIG_DEV=$(echo "$route_line" | sed -n 's/.*dev \([a-zA-Z0-9_.-]*\).*/\1/p' | awk '{print $1}')
		if [ -n "$ORIG_DEV" ] && [ "$ORIG_DEV" != "tun0" ] && [ "$ORIG_DEV" != "link" ]; then
			ORIG_IP=$(ip -4 addr show dev "$ORIG_DEV" 2>/dev/null |
				awk '/inet / {split($2, a, "/"); print a[1]; exit}')
		fi
	fi
}

save_proxy_env() {
	cat >/tmp/proxy-env.sh <<EOF
PROXY_PORT='${PROXY_PORT}'
PROXY_USER='${PROXY_USER}'
PROXY_PASS='${PROXY_PASS}'
ORIG_DEV='${ORIG_DEV}'
ORIG_GW='${ORIG_GW}'
ORIG_IP='${ORIG_IP}'
EOF
}

start_openconnect() {
	if [ -n "$PROXY_PORT" ]; then
		log "OpenConnect + Dante SOCKS5 proxy will start on :${PROXY_PORT} once tunnel is up"
	else
		log "OpenConnect starting (no proxy configured)"
	fi

	local auth_label="${AUTH_FILE:+auth file $(basename "$AUTH_FILE")}"
	[ -n "$RESOLVED_USER" ] && auth_label="user '$RESOLVED_USER'"
	log "Connecting to OpenConnect VPN at $VPN_SERVER ($auth_label)..."

	local cmd_args="--interface=tun0 --script=/usr/local/bin/vpnc-wrapper.sh"

	if [ -n "$RESOLVED_USER" ]; then
		cmd_args="$cmd_args --user=$RESOLVED_USER"
	fi

	if [ -n "$VPN_AUTHGROUP" ]; then
		cmd_args="$cmd_args --authgroup=$VPN_AUTHGROUP"
	fi

	if [ -n "$VPN_EXTRA_ARGS" ]; then
		cmd_args="$cmd_args $VPN_EXTRA_ARGS"
	fi

	trap 'log "Terminating OpenConnect..."; pkill -TERM openconnect || true; exit 0' TERM INT

	while true; do
		log "Spawning OpenConnect process..."
		if [ "$VPN_AUTO_ACCEPT_CERT" = "true" ]; then
			log "Auto-accepting untrusted certificate prompts (VPN_AUTO_ACCEPT_CERT=true)..."
			# shellcheck disable=SC2086
			printf '%s\n%s\n' "yes" "$RESOLVED_PASSWORD" | openconnect $cmd_args "$VPN_SERVER" || true
		else
			# shellcheck disable=SC2086
			printf '%s\n' "$RESOLVED_PASSWORD" | openconnect --passwd-on-stdin $cmd_args "$VPN_SERVER" || true
		fi

		warn "OpenConnect disconnected or exited. Reconnecting in 5 seconds..."
		sleep 5
	done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
	validate_and_resolve_config
	capture_networking
	save_proxy_env
	start_openconnect
}

main "$@"
