#!/bin/sh
set -e

# Source variables captured during container startup stage
if [ -f /tmp/proxy-env.sh ]; then
    . /tmp/proxy-env.sh
fi

ts() { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1" >&2; }

# ─── 1. Detect Primary Bridge Interface & IP ──────────────────────────────────
ORIG_GW=$(ip -4 route show default | head -n 1 | awk '{print $3}')
ORIG_DEV=$(ip -4 route show default | head -n 1 | awk '{print $5}')

if [ -n "$ORIG_DEV" ]; then
    ORIG_IP=$(ip -4 addr show "$ORIG_DEV" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
fi

log "Checking NAT configuration..."
if iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null; then
    log "NAT already configured, skipping"
else
    log "Setting up NAT..."
    iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
    iptables -A FORWARD -i eth+ -o tun0 -j ACCEPT
    iptables -A FORWARD -i tun0 -o eth+ -m state --state RELATED,ESTABLISHED -j ACCEPT
    log "NAT configured"
fi

# ─── 2. Policy-Based Routing (The Multi-Homing Fix) ───────────────────────────
if [ -n "$ORIG_IP" ] && [ -n "$ORIG_GW" ]; then
    log "Enforcing Policy-Based Routing for port-forward replies on $ORIG_DEV ($ORIG_IP)..."
    
    # Create a dedicated routing table (128) that forces traffic out the bridge gateway.
    # This guarantees replies to host port-forwards (192.168.0.10:1080) exit correctly via eth0,
    # preventing the VLAN (eth1) routes from causing asymmetric connection drops.
    ip rule add from "$ORIG_IP" table 128 2>/dev/null || true
    ip route add table 128 to "$ORIG_IP/32" dev "$ORIG_DEV" 2>/dev/null || true
    ip route add table 128 default via "$ORIG_GW" dev "$ORIG_DEV" 2>/dev/null || true
fi

# ─── 3. Main Table LAN Bypass ─────────────────────────────────────────────────
if [ -n "$ORIG_GW" ] && [ -n "$ORIG_DEV" ]; then
    log "Applying VPN bypass routes for local networks..."
    
    # We still add the broad bypass routes to the main table so the container 
    # can initiate connections to local networks without going through OpenVPN.
    # Note: The kernel will automatically prefer the more specific eth1 /24 route 
    # for direct VLAN neighbors, which is the correct native behavior.
    ip route add 10.0.0.0/8 via "$ORIG_GW" dev "$ORIG_DEV" 2>/dev/null || true
    ip route add 172.16.0.0/12 via "$ORIG_GW" dev "$ORIG_DEV" 2>/dev/null || true
    ip route add 192.168.0.0/16 via "$ORIG_GW" dev "$ORIG_DEV" 2>/dev/null || true
else
    log "WARNING: Could not automatically detect original default gateway."
fi

# ─── 4. SOCKS5 Proxy (Dante Server) ───────────────────────────────────────────
if [ -n "$PROXY_PORT" ]; then
    if pgrep sockd >/dev/null 2>&1; then
        log "Dante SOCKS5 proxy already running"
    else
        if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
            if ! id "$PROXY_USER" >/dev/null 2>&1; then
                adduser -D -H -s /sbin/nologin "$PROXY_USER"
            fi
            echo "$PROXY_USER:$PROXY_PASS" | chpasswd
            SOCKSMETHOD="username"
            AUTH_DESC="(auth: $PROXY_USER / ***)"
        else
            SOCKSMETHOD="none"
            AUTH_DESC="(no auth)"
        fi

        cat > /tmp/sockd.conf << EOF
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
    fi
else
    log "PROXY_PORT not set — skipping Dante SOCKS5 proxy"
fi