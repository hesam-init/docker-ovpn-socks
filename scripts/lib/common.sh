# shellcheck shell=bash
# Shared helpers for the bootstrap, vpnc-wrapper and NAT scripts.
# Installed as /usr/local/lib/vpn-socks/common.sh and sourced, never executed.

# State handed from startup.sh to setup-nat.sh (they run in separate processes)
PROXY_ENV_FILE=/tmp/proxy-env.sh

# Original (pre-VPN) default route
ORIG_DEV=""
ORIG_GW=""
ORIG_IP=""

# ─── Logging ──────────────────────────────────────────────────────────────────
ts() { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] [INFO] $*" >&2; }
warn() { echo "[$(ts)] [WARN] $*" >&2; }
die() {
	echo "[$(ts)] [ERROR] $*" >&2
	exit 1
}

# ─── Validation ───────────────────────────────────────────────────────────────
validate_proxy_env() {
	if [[ -z $PROXY_PORT ]]; then
		return 0
	fi

	[[ $PROXY_PORT =~ ^[0-9]+$ ]] || die "PROXY_PORT must be a number (got: $PROXY_PORT)"
	((${#PROXY_PORT} <= 5 && 10#$PROXY_PORT >= 1 && 10#$PROXY_PORT <= 65535)) ||
		die "PROXY_PORT out of range: $PROXY_PORT"

	if [[ -n $PROXY_USER && -z $PROXY_PASS ]] || [[ -z $PROXY_USER && -n $PROXY_PASS ]]; then
		die "Set both PROXY_USER and PROXY_PASS, or neither (open proxy)"
	fi
}

# ─── Networking ───────────────────────────────────────────────────────────────
# True if $1 is usable as the original (non-tunnel) interface
is_orig_dev() {
	[[ -n $1 && $1 != tun0 && $1 != link ]]
}

# First IPv4 address of interface $1
iface_ipv4() {
	ip -4 -o addr show dev "$1" 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}' || true
}

# Sets ORIG_GW and ORIG_DEV from the "via" and "dev" fields of route line $1
parse_route() {
	local -a f
	local i
	read -ra f <<<"$1"

	ORIG_GW=""
	ORIG_DEV=""
	for ((i = 0; i < ${#f[@]} - 1; i++)); do
		case ${f[i]} in
		via) ORIG_GW=${f[i + 1]} ;;
		dev) ORIG_DEV=${f[i + 1]} ;;
		esac
	done
}

# Captures ORIG_GW, ORIG_DEV and ORIG_IP. Must run before the VPN rewrites routes.
capture_orig_route() {
	local line
	line=$(ip -4 route show default | grep -v 'dev tun' | grep -m1 'via' || true)
	if [[ -z $line ]]; then
		line=$(ip -4 route show default | head -n 1 || true)
	fi

	if [[ -n $line ]]; then
		parse_route "$line"
		if is_orig_dev "$ORIG_DEV"; then
			ORIG_IP=$(iface_ipv4 "$ORIG_DEV")
		fi
	fi
}

# ─── Shared state ─────────────────────────────────────────────────────────────
save_proxy_env() {
	local v
	(
		umask 077
		for v in PROXY_PORT PROXY_USER PROXY_PASS ORIG_DEV ORIG_GW ORIG_IP; do
			printf '%s=%q\n' "$v" "${!v}"
		done >"$PROXY_ENV_FILE"
	)
}

load_proxy_env() {
	if [[ -f $PROXY_ENV_FILE ]]; then
		# shellcheck source=/dev/null
		source "$PROXY_ENV_FILE"
	fi
}
