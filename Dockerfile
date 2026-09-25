# ═══════════════════════════════════════════════════════════════════════════════
# BASE STAGE - Common dependencies and configurations
# ═══════════════════════════════════════════════════════════════════════════════
FROM docker.arvancloud.ir/debian:bookworm AS base

ENV TERM=xterm-256color
ENV DEBIAN_FRONTEND=noninteractive

# ── Mirror setup ────────────────────────────────────────────────────────────
RUN rm /etc/apt/sources.list.d/debian.sources
# RUN echo "deb http://mirror.arvancloud.ir/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list
RUN echo "deb http://repo.iut.ac.ir/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list

# ── Base system update ───────────────────────────────────────────────────────
RUN apt update && apt upgrade -y --no-install-recommends

# ── Install base system requirements ─────────────────────────────────────────────────────────
RUN apt install -y --no-install-recommends \
    bash ca-certificates \
    dante-client dante-server openvpn openconnect vpnc-scripts \
    net-tools iputils-ping \
    wget curl axel \
    iptables nftables iproute2

# ── Cleanup ──────────────────────────────────────────────────────────────────
RUN apt clean && rm -rf /var/lib/apt/lists/*

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