#!/bin/sh
set -e

# Source variables captured during container startup stage
if [ -f /tmp/proxy-env.sh ]; then
    . /tmp/proxy-env.sh
fi

# ─── Automated LAN Gateway & Interface Detection ──────────────────────────────
ORIG_GW=$(ip route show default | awk '/default/ {print $3}')
ORIG_DEV=$(ip route show default | awk '/default/ {print $5}')

ts() { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1" >&2; }

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

# ─── Automated LAN Bypass Routing ─────────────────────────────────────────────
if [ -n "$ORIG_GW" ] && [ -n "$ORIG_DEV" ]; then
    log "Automating local network routing via original gateway: ${ORIG_GW} on ${ORIG_DEV}..."
    # Force standard private RFC 1918 networks to route back out of the Docker bridge gateway.
    # This prevents asymmetric routing for local network nodes trying to access the container directly.
    ip route add 10.0.0.0/8 via "$ORIG_GW" dev "$ORIG_DEV" 2>/dev/null || true
    ip route add 172.16.0.0/12 via "$ORIG_GW" dev "$ORIG_DEV" 2>/dev/null || true
    ip route add 192.168.0.0/16 via "$ORIG_GW" dev "$ORIG_DEV" 2>/dev/null || true
    log "Local LAN bypass routes applied dynamically."
else
    log "WARNING: Could not automatically detect original default gateway — skipping LAN bypass routing."
fi

# ─── DNS Proxy ────────────────────────────────────────────────────────────────
if ! pgrep -f "gost.*dns" >/dev/null 2>&1; then
    gost -L "dns://:53/1.1.1.1?mode=udp" -L "dns://:54/1.1.1.1?mode=tcp" &
    log "DNS proxy started on :53 (UDP) and :54 (TCP)"
else
    log "DNS proxy already running"
fi

# ─── SOCKS5 Proxy (Dante Server Implementation) ───────────────────────────────
if [ -n "$PROXY_PORT" ]; then
    if pgrep sockd >/dev/null 2>&1; then
        log "Dante SOCKS5 proxy already running"
    else
        if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
            # Create a non-system login worker account dynamically for Dante authentication
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

        # Dynamically generate Dante configuration file
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

        # Start Dante as a daemon process background worker
        sockd -D -f /tmp/sockd.conf
        log "Dante SOCKS5 proxy started on :${PROXY_PORT} ${AUTH_DESC}"
    fi
else
    log "PROXY_PORT not set — skipping Dante SOCKS5 proxy"
fi