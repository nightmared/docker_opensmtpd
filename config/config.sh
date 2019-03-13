#!/bin/sh

# Those are the only two lines you need to tweak here
export DOMAIN_NAME=nightmared.fr
export DKIM_SELECTOR=docker
# This will be replaced automatically by its value when the build script is invoked
export ONLINE_API_KEY=

mkdir /etc/mail

export BASEDIR=/root/config

cd $BASEDIR

# smtpd.conf
while read line ;
do
    eval "echo \"$line\""
done <smtpd.conf >/etc/mail/smtpd.conf
cp aliases /etc/mail/


# DKIM configuration
while read line ;
do
    eval "echo \"$line\""
done <dkimproxy_out.conf >/etc/dkimproxy/dkimproxy_out.conf
openssl genrsa -out /etc/dkimproxy/private.key 4096
openssl rsa -in /etc/dkimproxy/private.key -pubout -out /etc/dkimproxy/public.key

# TODO: dovecot

# Prepare acme.sh
cd acme.sh/dnsapi
curl -s https://raw.githubusercontent.com/nightmared/le_dns_online/master/dns_online_rust.sh | sed -E "s/^export ONLINE_API_KEY\=.*$/export ONLINE_API_KEY=${ONLINE_API_KEY}/" > dns_online_rust.sh
chmod +x le_dns_online

# Add the DKIM key to the DNS
./le_dns_online add_record "DKIM-${DKIM_SELECTOR}-$(date +%s)" ${ONLINE_API_KEY} "${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME}." "\"v=DKIM1; p=$(cat /etc/dkimproxy/public.key)\""

# Time to generate some certificates
cd $BASEDIR/acme.sh
./acme.sh --issue -d mail.$DOMAIN_NAME -k 4096 --dns dns_online_rust --dnssleep 5 --staging
# Call cron every week ot update certificates if necessary
echo "/root/config/acme.sh/acme.sh --cron --home /root/config.acme.sh > /dev/null" > /etc/periodic/weekly/acme.sh
