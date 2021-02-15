FROM alpine:latest as opensmtpd-builder

RUN apk update && apk upgrade && apk add wget tar git gcc openssl-dev libevent-dev libc-dev fts-dev libasr-dev zlib-dev make bison file automake autoconf libtool bison

ENV version "6.8.0p2"
ENV file opensmtpd-${version}.tar.gz

# Downloading and extracting the package
RUN mkdir /build && cd /build && wget https://www.opensmtpd.org/archives/${file} && tar xvf ${file}
# Building the package
WORKDIR /build/opensmtpd-${version}
RUN ./bootstrap
RUN ./configure --with-pie --prefix=/usr && make -j4 && make install DESTDIR=/output

FROM alpine:latest as opensmtpd

# Install required software and deps
RUN apk upgrade --no-cache && apk add --no-cache openssl curl dovecot-lmtpd dovecot-pigeonhole-plugin dkimproxy libevent libasr fts lego bind-tools ca-certificates && update-ca-certificates

# Install opensmtpd
COPY --from=opensmtpd-builder /output/usr/libexec /usr/libexec
COPY --from=opensmtpd-builder /output/usr/sbin /usr/sbin
COPY config /root/config

VOLUME ["/data", "/root/.lego"]
EXPOSE 25/tcp
EXPOSE 587/tcp
EXPOSE 993/tcp
EXPOSE 4190/tcp

# TLS certificates
# Downloading a statically generated binary for le_dns_online
CMD /root/config/config.sh
