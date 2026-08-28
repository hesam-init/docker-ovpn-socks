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

COPY scripts/_vpn-nat.sh /usr/local/bin/setup-nat.sh
COPY scripts/ovpn-bootstrap.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh /usr/local/bin/setup-nat.sh

CMD ["/usr/local/bin/startup.sh"]

# ═══════════════════════════════════════════════════════════════════════════════
# OPENCONNECT STAGE - OpenConnect Bootstrap
# ═══════════════════════════════════════════════════════════════════════════════
FROM base AS openconnect

COPY scripts/_vpn-nat.sh /usr/local/bin/setup-nat.sh
COPY scripts/vpnc-wrapper.sh /usr/local/bin/vpnc-wrapper.sh
COPY scripts/openconnect-bootstrap.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh /usr/local/bin/setup-nat.sh /usr/local/bin/vpnc-wrapper.sh

CMD ["/usr/local/bin/startup.sh"]