#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=lib/common.sh
source /usr/local/lib/vpn-socks/common.sh

# ─── Configuration ────────────────────────────────────────────────────────────
# Only values captured by the entrypoint count, not the inherited environment
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""

load_proxy_env

# ─── Helpers ──────────────────────────────────────────────────────────────────
# Idempotent iptables: only appends the rule if it does not already exist
ipt_add() {
	local table=$1 chain=$2
	shift 2

	iptables -t "$table" -C "$chain" "$@" 2>/dev/null && return 1 # already existed
	iptables -t "$table" -A "$chain" "$@"                          # newly added
}

# Idempotent ip-rule: only adds "from <ip> table <n>" if it does not already exist
ip_rule_add() {
	local from=$1 table=$2

	if [[ -z $(ip rule show from "$from" table "$table") ]]; then
		ip rule add from "$from" table "$table"
	fi
}

# Percent-encodes $1 byte-wise for use as URL userinfo
urlencode() {
	local LC_ALL=C
	local s=$1 out="" c i
	for ((i = 0; i < ${#s}; i++)); do
		c=${s:i:1}
		case $c in
		[A-Za-z0-9._~-]) out+=$c ;;
		*) printf -v c '%%%02X' "'$c" && out+=$c ;;
		esac
	done
	printf '%s' "$out"
}

# ─── Steps ────────────────────────────────────────────────────────────────────
detect_networking() {
	# If pre-captured during the entrypoint phase, verify and use them
	if is_orig_dev "$ORIG_DEV" && [[ -n $ORIG_GW && -n $ORIG_IP ]]; then
		log "Using pre-captured network configuration:"
		log "  - Interface (ORIG_DEV): $ORIG_DEV"
		log "  - Gateway   (ORIG_GW):  $ORIG_GW"
		log "  - IP Address(ORIG_IP):  $ORIG_IP"
		return 0
	fi

	log "Detecting original default network route and interface..."

	# Look for standard default gateway via non-tun interface
	local line
	line=$(ip -4 route show default | grep -v 'dev tun' | grep -m1 'via' || true)
	if [[ -z $line ]]; then
		line=$(ip -4 route show | grep -E 'dev eth[0-9]+' | grep -m1 'via' || true)
	fi
	if [[ -n $line ]]; then
		parse_route "$line"
	fi

	# Fallback interface discovery if DEV is still invalid
	if ! is_orig_dev "$ORIG_DEV"; then
		local fallback_dev
		fallback_dev=$(ip -4 -o addr show | awk '$2 !~ /^(lo|tun)/ {print $2; exit}' || true)
		if [[ -n $fallback_dev ]]; then
			ORIG_DEV=$fallback_dev
		fi
	fi

	if is_orig_dev "$ORIG_DEV"; then
		ORIG_IP=$(iface_ipv4 "$ORIG_DEV")
	fi

	# Validation: Ensure ORIG_GW is a valid IPv4 address
	if [[ ! $ORIG_GW =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		ORIG_GW=""
	fi

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

	if ((changed)); then
		log "NAT configured successfully"
	else
		log "NAT already configured, skipping"
	fi
}

setup_policy_routing() {
	# Table 128 forces traffic sourced from the bridge IP to exit via the bridge
	# gateway. This prevents asymmetric routing when the container has multiple
	# interfaces (e.g. VLAN on eth1) and host port-forwards land on the bridge IP.
	if [[ -z $ORIG_IP || -z $ORIG_GW ]]; then
		warn "Missing IP or Gateway for policy routing — skipping policy routing"
		return 0
	fi

	log "Enforcing policy-based routing for port-forward replies on $ORIG_DEV ($ORIG_IP)..."
	ip_rule_add "$ORIG_IP" 128
	ip route replace table 128 to "$ORIG_IP/32" dev "$ORIG_DEV"
	ip route replace table 128 default via "$ORIG_GW" dev "$ORIG_DEV"
}

setup_lan_bypass() {
	# Allow the container to reach RFC-1918 private ranges directly via the bridge
	# gateway instead of tunneling them through the VPN. The kernel will still
	# prefer more-specific connected routes (e.g. the eth1 /24 VLAN subnet).
	if [[ -z $ORIG_GW || -z $ORIG_DEV ]]; then
		warn "Could not detect original default gateway — skipping LAN bypass"
		return 0
	fi

	log "Applying VPN bypass routes for RFC-1918 networks..."
	local net
	for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
		ip route replace "$net" via "$ORIG_GW" dev "$ORIG_DEV"
	done
}

setup_gost() {
	if [[ -z $PROXY_PORT ]]; then
		log "PROXY_PORT not set — skipping gost HTTP/SOCKS5 proxy"
		return 0
	fi

	if pgrep -x gost >/dev/null 2>&1; then
		log "gost HTTP/SOCKS5 proxy already running"
		return 0
	fi

	local auth=""
	local auth_desc="(no auth)"

	if [[ -n $PROXY_USER && -n $PROXY_PASS ]]; then
		auth="$(urlencode "$PROXY_USER"):$(urlencode "$PROXY_PASS")@"
		auth_desc="(auth: $PROXY_USER / ***)"
	fi

	# auto = HTTP + SOCKS4/5 on one port; interface=tun0 keeps egress inside the tunnel.
	# gost has no daemon mode, so it is backgrounded and outlives this hook.
	gost -L "auto://${auth}:${PROXY_PORT}?interface=tun0" </dev/null &
	log "gost HTTP/SOCKS5 proxy started on :${PROXY_PORT} ${auth_desc}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
	detect_networking
	setup_nat
	setup_policy_routing
	setup_lan_bypass
	setup_gost
}

main "$@"
