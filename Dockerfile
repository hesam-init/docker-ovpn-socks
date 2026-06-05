# ═══════════════════════════════════════════════════════════════════════════════
# BASE STAGE - Common dependencies and configurations
# ═══════════════════════════════════════════════════════════════════════════════
FROM docker.arvancloud.ir/alpine:3.23 AS base

RUN echo "http://mirror.0-1.ir/alpine/v3.23/main" > /etc/apk/repositories && \
    echo "http://mirror.0-1.ir/alpine/v3.23/community" >> /etc/apk/repositories

RUN apk update
RUN apk add --no-cache bash bind-tools curl gost dante dante-server iptables iproute2 openvpn

RUN rm -rf /var/cache/apk/*

# ═══════════════════════════════════════════════════════════════════════════════
# VPN STAGE - OpenVpn Bootstrap
# ═══════════════════════════════════════════════════════════════════════════════
FROM base AS vpn

COPY scripts/vpn-bootstrap.sh /usr/local/bin/startup.sh
COPY scripts/vpn-nat.sh /usr/local/bin/setup-nat.sh
RUN chmod +x /usr/local/bin/startup.sh /usr/local/bin/setup-nat.sh

CMD ["/usr/local/bin/startup.sh"]

# ═══════════════════════════════════════════════════════════════════════════════
# GOST STAGE - Proxy Service
# ═══════════════════════════════════════════════════════════════════════════════
FROM base AS gost

COPY scripts/gost-bootstrap.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

CMD ["/usr/local/bin/startup.sh"]