FROM alpine:latest as smtpd

# Install required software and deps
RUN apk upgrade --no-cache && apk add --no-cache openssl curl dovecot-lmtpd dovecot-pigeonhole-plugin opendkim lego bind-tools ca-certificates postfix && update-ca-certificates

# Install opensmtpd
COPY config /root/config

VOLUME ["/data", "/root/.lego"]
EXPOSE 25/tcp
EXPOSE 587/tcp
EXPOSE 993/tcp
EXPOSE 4190/tcp

# TLS certificates
# Downloading a statically generated binary for le_dns_online
CMD /root/config/config.sh
