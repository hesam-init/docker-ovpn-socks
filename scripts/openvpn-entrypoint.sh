#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source /usr/local/lib/vpn-socks/common.sh

# ─── Configuration ────────────────────────────────────────────────────────────
CREDENTIALS=${CREDENTIALS:-true}
RUNTIME_CONFIG=/tmp/config-runtime.ovpn
AUTH_FILE=${AUTH_FILE:-/etc/openvpn/auth.txt}
VPN_CONFIG=${VPN_CONFIG:-/etc/openvpn/config.ovpn}

PROXY_PORT=${PROXY_PORT:-}
PROXY_USER=${PROXY_USER:-}
PROXY_PASS=${PROXY_PASS:-}

# ─── Steps ────────────────────────────────────────────────────────────────────
validate_config() {
	cd /etc/openvpn || die "VPN config directory not found"
	[[ -f $VPN_CONFIG ]] || die "$VPN_CONFIG not found"

	if [[ $CREDENTIALS == true ]]; then
		[[ -f $AUTH_FILE ]] || die "$AUTH_FILE not found"

		local -a lines
		mapfile -t lines <"$AUTH_FILE"
		local user=${lines[0]:-} pass=${lines[1]:-}
		if [[ -z ${user//$'\r'/} || -z ${pass//$'\r'/} ]]; then
			die "Invalid $AUTH_FILE: expected username on line 1 and password on line 2"
		fi
	fi

	validate_proxy_env
}

build_runtime_config() {
	log "Preparing OpenVPN configuration..."
	cat "$VPN_CONFIG" >"$RUNTIME_CONFIG"
	cat >>"$RUNTIME_CONFIG" <<EOF

# Auto-reconnect directives
persist-key
persist-tun
resolv-retry infinite
ping-restart 120
connect-retry 5
connect-retry-max 10

mute-replay-warnings

script-security 2
up /usr/local/bin/tunnel-up.sh
EOF
}

start_openvpn() {
	if [[ -n $PROXY_PORT ]]; then
		log "OpenVPN + Dante SOCKS5 proxy will start on :${PROXY_PORT} once tunnel is up"
	else
		log "OpenVPN starting (no proxy configured)"
	fi

	local -a args=(--config "$RUNTIME_CONFIG")
	if [[ $CREDENTIALS == true ]]; then
		args+=(--auth-user-pass "$AUTH_FILE")
	fi

	exec openvpn "${args[@]}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
	validate_config
	capture_orig_route
	save_proxy_env
	build_runtime_config
	start_openvpn
}

main "$@"
