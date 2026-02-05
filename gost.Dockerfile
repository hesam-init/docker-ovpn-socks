FROM alpine:3.23

RUN echo "https://mirror.arvancloud.ir/alpine/v3.23/main" > /etc/apk/repositories && \
    echo "https://mirror.arvancloud.ir/alpine/v3.23/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache gost curl iproute2 bash

COPY gost-startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

CMD ["/usr/local/bin/startup.sh"]