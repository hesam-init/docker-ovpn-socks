# ═══════════════════════════════════════════════════════════════════════════════
# BASE STAGE - Alpine + gost (HTTP & SOCKS proxy on one port)
# ═══════════════════════════════════════════════════════════════════════════════
FROM docker.arvancloud.ir/alpine:3.24 AS base

ENV TERM=xterm-256color

# ── Mirror setup ────────────────────────────────────────────────────────────
RUN echo "http://repo.iut.ac.ir/repo/alpine/v3.24/main" > /etc/apk/repositories && \
    echo "http://repo.iut.ac.ir/repo/alpine/v3.24/community" >> /etc/apk/repositories

# ── Install base system requirements ─────────────────────────────────────────
RUN apk add --no-cache \
    bash ca-certificates tzdata curl \
    gost openvpn openconnect vpnc \
    iptables iproute2

# ═══════════════════════════════════════════════════════════════════════════════
# VPN STAGE - OpenVpn Bootstrap
# ═══════════════════════════════════════════════════════════════════════════════
FROM base AS ovpn

COPY scripts/lib/common.sh /usr/local/lib/vpn-socks/common.sh
COPY scripts/tunnel-up.sh /usr/local/bin/tunnel-up.sh
COPY scripts/openvpn-entrypoint.sh /usr/local/bin/openvpn-entrypoint.sh
RUN chmod +x /usr/local/bin/openvpn-entrypoint.sh /usr/local/bin/tunnel-up.sh

CMD ["/usr/local/bin/openvpn-entrypoint.sh"]

# ═══════════════════════════════════════════════════════════════════════════════
# OPENCONNECT STAGE - OpenConnect Bootstrap
# ═══════════════════════════════════════════════════════════════════════════════
FROM base AS openconnect

COPY scripts/lib/common.sh /usr/local/lib/vpn-socks/common.sh
COPY scripts/tunnel-up.sh /usr/local/bin/tunnel-up.sh
COPY scripts/openconnect-hook.sh /usr/local/bin/openconnect-hook.sh
COPY scripts/openconnect-entrypoint.sh /usr/local/bin/openconnect-entrypoint.sh
RUN chmod +x /usr/local/bin/openconnect-entrypoint.sh /usr/local/bin/tunnel-up.sh /usr/local/bin/openconnect-hook.sh

CMD ["/usr/local/bin/openconnect-entrypoint.sh"]
