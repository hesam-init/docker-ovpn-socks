#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source /usr/local/lib/vpn-socks/common.sh

# ─── Configuration ────────────────────────────────────────────────────────────
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

# ─── Steps ────────────────────────────────────────────────────────────────────
validate_and_resolve_config() {
	[[ -n $VPN_SERVER ]] || die "VPN_SERVER is required (e.g. VPN_SERVER=TCI.apibaz.org)"

	# Resolve credentials from auth file or environment
	if [[ -f $AUTH_FILE ]]; then
		log "Loading credentials from auth file: $AUTH_FILE"
		local -a lines
		mapfile -t lines <"$AUTH_FILE"
		RESOLVED_USER=${lines[0]:-}
		RESOLVED_USER=${RESOLVED_USER//$'\r'/}
		RESOLVED_PASSWORD=${lines[1]:-}
		RESOLVED_PASSWORD=${RESOLVED_PASSWORD//$'\r'/}
	else
		RESOLVED_USER=$VPN_USER
		RESOLVED_PASSWORD=$VPN_PASSWORD
	fi

	if [[ $CREDENTIALS == true ]] && [[ -z $RESOLVED_USER || -z $RESOLVED_PASSWORD ]]; then
		die "Both username and password are required. Provide them via VPN_USER/VPN_PASSWORD env vars or in $AUTH_FILE"
	fi

	validate_proxy_env
}

start_openconnect() {
	if [[ -n $PROXY_PORT ]]; then
		log "OpenConnect + Dante SOCKS5 proxy will start on :${PROXY_PORT} once tunnel is up"
	else
		log "OpenConnect starting (no proxy configured)"
	fi

	local auth_label="no credentials"
	if [[ -n $RESOLVED_USER ]]; then
		auth_label="user '$RESOLVED_USER'"
	elif [[ -f $AUTH_FILE ]]; then
		auth_label="auth file $(basename "$AUTH_FILE")"
	fi
	log "Connecting to OpenConnect VPN at $VPN_SERVER ($auth_label)..."

	local -a args=(--interface=tun0 --script=/usr/local/bin/openconnect-hook.sh)
	if [[ -n $RESOLVED_USER ]]; then
		args+=("--user=$RESOLVED_USER")
	fi
	if [[ -n $VPN_AUTHGROUP ]]; then
		args+=("--authgroup=$VPN_AUTHGROUP")
	fi
	if [[ -n $VPN_EXTRA_ARGS ]]; then
		local -a extra
		read -ra extra <<<"$VPN_EXTRA_ARGS"
		args+=("${extra[@]}")
	fi

	if [[ $VPN_AUTO_ACCEPT_CERT == true ]]; then
		log "Auto-accepting untrusted certificate prompts (VPN_AUTO_ACCEPT_CERT=true)..."
	fi

	trap 'log "Terminating OpenConnect..."; pkill -TERM openconnect || true; exit 0' TERM INT

	# openconnect runs in the background so the trap fires while we wait on it
	while true; do
		log "Spawning OpenConnect process..."
		if [[ $VPN_AUTO_ACCEPT_CERT == true ]]; then
			# Answers the cert prompt, then the password prompt
			printf '%s\n%s\n' "yes" "$RESOLVED_PASSWORD" | openconnect "${args[@]}" "$VPN_SERVER" &
		else
			printf '%s\n' "$RESOLVED_PASSWORD" | openconnect --passwd-on-stdin "${args[@]}" "$VPN_SERVER" &
		fi
		wait "$!" || true

		warn "OpenConnect disconnected or exited. Reconnecting in 5 seconds..."
		sleep 5
	done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
	validate_and_resolve_config
	capture_orig_route
	save_proxy_env
	start_openconnect
}

main "$@"
