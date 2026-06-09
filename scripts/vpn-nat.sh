#!/bin/sh
set -e

# ─── Configuration ────────────────────────────────────────────────────────────
# Load variables captured during container startup stage
if [ -f /tmp/proxy-env.sh ]; then
	. /tmp/proxy-env.sh
fi

PROXY_PORT=${PROXY_PORT:-}
PROXY_USER=${PROXY_USER:-}
PROXY_PASS=${PROXY_PASS:-}

# Network environment variables (detected dynamically at runtime by detect_networking)
ORIG_DEV=""
ORIG_GW=""
ORIG_IP=""

# ─── Helpers ──────────────────────────────────────────────────────────────────
ts()    { date +'%Y-%m-%d %H:%M:%S'; }
log()   { echo "[$(ts)] [INFO] $1" >&2; }
warn()  { echo "[$(ts)] [WARN] $1" >&2; }
error() { echo "[$(ts)] [ERROR] $1" >&2; exit 1; }

# Idempotent iptables: only appends the rule if it does not already exist
ipt_add() {
	local table="$1"
	local chain="$2"
	shift 2

	if ! iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
		iptables -t "$table" -A "$chain" "$@"
		return 0 # newly added
	fi
	return 1 # already existed
}

# Idempotent ip-rule: only adds the rule if it does not already exist
ip_rule_add() {
	if ! ip rule show | grep -qF "$*"; then
		ip rule add "$@"
	fi
}

# ─── Steps ────────────────────────────────────────────────────────────────────
detect_networking() {
	log "Detecting original default network route and interface..."

	# Get the default route line (e.g. "default via 172.18.0.1 dev eth0")
	local default_route
	default_route=$(ip -4 route show default | head -n 1)

	if [ -z "$default_route" ]; then
		warn "No default IPv4 route detected."
		return
	fi

	# Parse the gateway and device from the default route line
	ORIG_GW=$(echo "$default_route" | awk '{print $3}')
	ORIG_DEV=$(echo "$default_route" | awk '{print $5}')

	# Parse the IP address assigned to the original interface
	if [ -n "$ORIG_DEV" ]; then
		ORIG_IP=$(ip -4 addr show dev "$ORIG_DEV" 2>/dev/null \
			| awk '/inet / {split($2, a, "/"); print a[1]; exit}')
	fi

	# Log the detected configuration for debugging/transparency
	log "Detected network configuration:"
	log "  - Interface (ORIG_DEV): ${ORIG_DEV:-unknown}"
	log "  - Gateway   (ORIG_GW):  ${ORIG_GW:-unknown}"
	log "  - IP Address(ORIG_IP):  ${ORIG_IP:-unknown}"
}

setup_nat() {
	log "Checking NAT & forwarding rules..."
	local changed=0
	
	ipt_add nat POSTROUTING -o tun0 -j MASQUERADE && changed=1
	ipt_add filter FORWARD -i eth+ -o tun0 -j ACCEPT && changed=1
	ipt_add filter FORWARD -i tun0 -o eth+ -m state --state RELATED,ESTABLISHED -j ACCEPT && changed=1

	if [ "$changed" -eq 1 ]; then
		log "NAT configured successfully"
	else
		log "NAT already configured, skipping"
	fi
}

setup_policy_routing() {
	# Table 128 forces traffic sourced from the bridge IP to exit via the bridge
	# gateway. This prevents asymmetric routing when the container has multiple
	# interfaces (e.g. VLAN on eth1) and host port-forwards land on the bridge IP.
	if [ -z "$ORIG_IP" ] || [ -z "$ORIG_GW" ]; then
		warn "Missing IP or Gateway for policy routing — skipping policy routing"
		return 0
	fi

	log "Enforcing policy-based routing for port-forward replies on $ORIG_DEV ($ORIG_IP)..."
	ip_rule_add from "$ORIG_IP" table 128
	ip route replace table 128 to "$ORIG_IP/32" dev "$ORIG_DEV"
	ip route replace table 128 default via "$ORIG_GW" dev "$ORIG_DEV"
}

setup_lan_bypass() {
	# Allow the container to reach RFC-1918 private ranges directly via the bridge
	# gateway instead of tunneling them through OpenVPN. The kernel will still
	# prefer more-specific connected routes (e.g. the eth1 /24 VLAN subnet).
	if [ -z "$ORIG_GW" ] || [ -z "$ORIG_DEV" ]; then
		warn "Could not detect original default gateway — skipping LAN bypass"
		return 0
	fi

	log "Applying VPN bypass routes for RFC-1918 networks..."
	ip route replace 10.0.0.0/8     via "$ORIG_GW" dev "$ORIG_DEV"
	ip route replace 172.16.0.0/12  via "$ORIG_GW" dev "$ORIG_DEV"
	ip route replace 192.168.0.0/16 via "$ORIG_GW" dev "$ORIG_DEV"
}

setup_dante() {
	if [ -z "$PROXY_PORT" ]; then
		log "PROXY_PORT not set — skipping Dante SOCKS5 proxy"
		return 0
	fi

	if pgrep sockd >/dev/null 2>&1; then
		log "Dante SOCKS5 proxy already running"
		return 0
	fi

	local socks_method="none"
	local auth_desc="(no auth)"

	if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
		if ! id "$PROXY_USER" >/dev/null 2>&1; then
			adduser -D -H -s /sbin/nologin "$PROXY_USER"
		fi
		echo "$PROXY_USER:$PROXY_PASS" | chpasswd
		socks_method="username"
		auth_desc="(auth: $PROXY_USER / ***)"
	fi

	cat > /tmp/sockd.conf <<EOF
logoutput: stderr
internal: 0.0.0.0 port = ${PROXY_PORT}
external: tun0
socksmethod: ${socks_method}
clientmethod: none

user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF

	sockd -D -f /tmp/sockd.conf
	log "Dante SOCKS5 proxy started on :${PROXY_PORT} ${auth_desc}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
	detect_networking
	setup_nat
	setup_policy_routing
	setup_lan_bypass
	setup_dante
}

main "$@"
