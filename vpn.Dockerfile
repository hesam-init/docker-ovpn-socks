FROM alpine:3.23

RUN echo "https://mirror.arvancloud.ir/alpine/v3.23/main" > /etc/apk/repositories && \
    echo "https://mirror.arvancloud.ir/alpine/v3.23/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache openvpn iptables curl iproute2

COPY vpn-startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

CMD ["/usr/local/bin/startup.sh"]