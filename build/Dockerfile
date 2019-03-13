FROM alpine:edge

RUN apk update && apk upgrade && apk add wget tar

ENV version "6.4.1p2"
ENV package opensmtpd-${version}
ENV file ${package}.tar.gz

# Downloading and extracting the package
RUN mkdir /build && cd /build && wget https://www.opensmtpd.org/archives/${file} && tar xvf ${file}
WORKDIR /build/${package}

# Building the package
RUN apk add gcc libressl-dev libevent-dev libc-dev fts-dev libasr-dev zlib-dev make bison file
RUN ./configure --with-pie --prefix=/output && make -j4 && make install

#RUN rm -rf /build

#WORKDIR /etc/mail/
# Create users
#RUN mkdir -p /var/empty && adduser -g "SMTP Daemon" -h /var/empty -s /sbin/nologin _smtpd && adduser -g "SMTPD Queue" -h /var/empty -s /sbin/nologin _smtpq
