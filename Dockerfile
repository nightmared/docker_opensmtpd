FROM alpine:edge as opensmtpd-builder

RUN apk update && apk upgrade && apk add wget tar

ENV version "6.4.1p2"
ENV package opensmtpd-${version}
ENV file ${package}.tar.gz

# Downloading and extracting the package
RUN mkdir /build && cd /build && wget https://www.opensmtpd.org/archives/${file} && tar xvf ${file}
WORKDIR /build/${package}

# Building the package
RUN apk add git gcc libressl-dev libevent-dev libc-dev fts-dev libasr-dev zlib-dev make bison file
RUN ./configure --with-pie --prefix=/usr && make -j4 && make install DESTDIR=/output
RUN git clone https://github.com/Neilpang/acme.sh.git /acme.sh

FROM alpine:edge as opensmtpd

# Install required software and deps
RUN apk update && apk upgrade && apk add openssl curl dovecot-lmtpd dovecot-pigeonhole-plugin dkimproxy libevent libasr fts libressl

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
RUN wget https://nightmared.fr/le_dns_online -O /root/config/acme.sh/dnsapi/le_dns_online
RUN wget https://raw.githubusercontent.com/nightmared/le_dns_online/master/dns_online_rust.sh -O /root/config/acme.sh/dnsapi/dns_online_rust.sh
CMD /root/config/config_gen.sh
