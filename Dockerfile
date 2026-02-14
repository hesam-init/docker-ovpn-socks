# ═══════════════════════════════════════════════════════════════════════════════
# BASE STAGE - Common dependencies and configurations
# ═══════════════════════════════════════════════════════════════════════════════
FROM docker.arvancloud.ir/alpine:3.23 AS base

RUN echo "https://mirror.arvancloud.ir/alpine/v3.23/main" > /etc/apk/repositories && \
    echo "https://mirror.arvancloud.ir/alpine/v3.23/community" >> /etc/apk/repositories

RUN apk update
RUN apk add --no-cache bash bind-tools curl gost iptables iproute2 openvpn

RUN rm -rf /var/cache/apk/*

# ═══════════════════════════════════════════════════════════════════════════════
# VPN STAGE - OpenVpn Bootstrap
# ═══════════════════════════════════════════════════════════════════════════════
FROM base AS vpn

COPY vpn-advanced.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

CMD ["/usr/local/bin/startup.sh"]

# ═══════════════════════════════════════════════════════════════════════════════
# GOST STAGE - Proxy Service
# ═══════════════════════════════════════════════════════════════════════════════
FROM base AS gost

COPY gost-startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

CMD ["/usr/local/bin/startup.sh"]