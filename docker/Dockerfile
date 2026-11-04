# ═══════════════════════════════════════════════════════════════════════════════
# BASE STAGE - Alpine + gost (HTTP & SOCKS proxy on one port)
# ═══════════════════════════════════════════════════════════════════════════════
# Mirrors come from .env (see .env.example); empty = Docker Hub and the Alpine CDN
ARG DOCKER_REGISTRY=
FROM ${DOCKER_REGISTRY:+${DOCKER_REGISTRY}/}alpine:3.24 AS base

ARG ALPINE_APK_MIRROR=
ENV TERM=xterm-256color

# ── Mirror setup (only when ALPINE_APK_MIRROR is set, else keep the default repos) ──
RUN if [ -n "$ALPINE_APK_MIRROR" ]; then \
      v="v$(cut -d. -f1,2 /etc/alpine-release)"; \
      printf '%s/%s/main\n%s/%s/community\n' "$ALPINE_APK_MIRROR" "$v" "$ALPINE_APK_MIRROR" "$v" > /etc/apk/repositories; \
    fi

# ── Install base system requirements ─────────────────────────────────────────
RUN apk add bash ca-certificates tzdata curl \
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
