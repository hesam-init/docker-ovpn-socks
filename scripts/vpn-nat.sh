#!/bin/sh
set -e

# Source variables captured during container startup stage
if [ -f /tmp/proxy-env.sh ]; then
    . /tmp/proxy-env.sh
fi

# ─── Helpers ──────────────────────────────────────────────────────────────────

ts()  { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1" >&2; }

# Idempotent iptables: only appends the rule if it does not already exist.
ipt_add() {
    table="$1"; chain="$2"; shift 2
    if ! iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
        iptables -t "$table" -A "$chain" "$@"
        return 0  # newly added
    fi
    return 1  # already existed
}

# Idempotent ip-rule: only adds the rule if it does not already exist.
ip_rule_add() {
    if ! ip rule show | grep -qF "$*"; then
        ip rule add "$@"
    fi
}

# ─── 1. Detect Primary Bridge Interface & IP (single pass) ───────────────────

eval "$(ip -4 route show default | head -n 1 | awk '{
    printf "ORIG_GW=%s\nORIG_DEV=%s\n", $3, $5
}')"

if [ -n "$ORIG_DEV" ]; then
    ORIG_IP=$(ip -4 addr show "$ORIG_DEV" 2>/dev/null \
        | awk '/inet / {split($2, a, "/"); print a[1]; exit}')
fi

# ─── 2. NAT & Forwarding ─────────────────────────────────────────────────────

setup_nat() {
    log "Checking NAT & forwarding rules..."

    local changed=0
    ipt_add nat POSTROUTING -o tun0 -j MASQUERADE                                && changed=1
    ipt_add filter FORWARD -i eth+ -o tun0 -j ACCEPT                             && changed=1
    ipt_add filter FORWARD -i tun0 -o eth+ -m state --state RELATED,ESTABLISHED -j ACCEPT && changed=1

    if [ "$changed" -eq 1 ]; then
        log "NAT configured"
    else
        log "NAT already configured, skipping"
    fi
}

# ─── 3. Policy-Based Routing (Multi-Homing Fix) ──────────────────────────────
#
# Table 128 forces traffic sourced from the bridge IP to exit via the bridge
# gateway. This prevents asymmetric routing when the container has multiple
# interfaces (e.g. VLAN on eth1) and host port-forwards land on the bridge IP.

setup_policy_routing() {
    [ -n "$ORIG_IP" ] && [ -n "$ORIG_GW" ] || return 0

    log "Enforcing policy-based routing for port-forward replies on $ORIG_DEV ($ORIG_IP)..."

    ip_rule_add from "$ORIG_IP" table 128
    ip route replace table 128 to "$ORIG_IP/32"  dev "$ORIG_DEV"
    ip route replace table 128 default via "$ORIG_GW" dev "$ORIG_DEV"
}

# ─── 4. LAN Bypass Routes ────────────────────────────────────────────────────
#
# Allow the container to reach RFC-1918 private ranges directly via the bridge
# gateway instead of tunneling them through OpenVPN. The kernel will still
# prefer more-specific connected routes (e.g. the eth1 /24 VLAN subnet).

setup_lan_bypass() {
    [ -n "$ORIG_GW" ] && [ -n "$ORIG_DEV" ] || {
        log "WARNING: Could not detect original default gateway — skipping LAN bypass"
        return 0
    }

    log "Applying VPN bypass routes for RFC-1918 networks..."

    ip route replace 10.0.0.0/8     via "$ORIG_GW" dev "$ORIG_DEV"
    ip route replace 172.16.0.0/12  via "$ORIG_GW" dev "$ORIG_DEV"
    ip route replace 192.168.0.0/16 via "$ORIG_GW" dev "$ORIG_DEV"
}

# ─── 5. SOCKS5 Proxy (Dante Server) ──────────────────────────────────────────

setup_dante() {
    if [ -z "$PROXY_PORT" ]; then
        log "PROXY_PORT not set — skipping Dante SOCKS5 proxy"
        return 0
    fi

    if pgrep sockd >/dev/null 2>&1; then
        log "Dante SOCKS5 proxy already running"
        return 0
    fi

    if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
        id "$PROXY_USER" >/dev/null 2>&1 || adduser -D -H -s /sbin/nologin "$PROXY_USER"
        echo "$PROXY_USER:$PROXY_PASS" | chpasswd
        SOCKSMETHOD="username"
        AUTH_DESC="(auth: $PROXY_USER / ***)"
    else
        SOCKSMETHOD="none"
        AUTH_DESC="(no auth)"
    fi

    cat > /tmp/sockd.conf <<EOF
logoutput: stderr
internal: 0.0.0.0 port = ${PROXY_PORT}
external: tun0
socksmethod: ${SOCKSMETHOD}
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
    log "Dante SOCKS5 proxy started on :${PROXY_PORT} ${AUTH_DESC}"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

setup_nat
setup_policy_routing
setup_lan_bypass
setup_dante
