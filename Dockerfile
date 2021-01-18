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

RUN git clone https://github.com/Neilpang/acme.sh.git /acme.sh

FROM alpine:latest as opensmtpd

# Install required software and deps
RUN apk upgrade --no-cache && apk add --no-cache openssl curl dovecot-lmtpd dovecot-pigeonhole-plugin dkimproxy libevent libasr fts openssl

COPY config /root/config
COPY --from=opensmtpd-builder /acme.sh /root/config/acme.sh
# Install opensmtpd
COPY --from=opensmtpd-builder /output/usr/libexec /usr/libexec
COPY --from=opensmtpd-builder /output/usr/sbin /usr/sbin

VOLUME ["/data", "/root/.acme.sh"]
EXPOSE 25/tcp
EXPOSE 587/tcp
EXPOSE 993/tcp
EXPOSE 4190/tcp

# TLS certificates
# Downloading a statically generated binary for le_dns_online
RUN wget -q https://nightmared.fr/le_dns_online -O /root/config/acme.sh/dnsapi/le_dns_online
RUN wget -q https://raw.githubusercontent.com/nightmared/le_dns_online/master/lets_encrypt/dns_online_rust_preloaded.sh -O /root/config/acme.sh/dnsapi/dns_online_rust_preloaded.sh
CMD /root/config/config.sh
