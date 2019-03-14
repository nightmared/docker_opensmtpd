#!/bin/sh -e

# Those are the only two lines you need to tweak here
export DOMAIN_NAME=nightmared.fr
export DKIM_SELECTOR=docker
# This will be replaced automatically by its value when the build script is invoked
export ONLINE_API_KEY=
export MAIL_PASSWD=
export BASEDIR=/root/config

# Create users
mkdir -p /var/empty
adduser -D -g "SMTP Daemon" -h /var/empty -s /sbin/nologin _smtpd
adduser -D -g "SMTPD Queue" -h /var/empty -s /sbin/nologin _smtpq
adduser -D -g "Mail client" -h /data -s /sbin/nologin contact
echo "contact:${MAIL_PASSWD}" | chpasswd 2>/dev/null

cd $BASEDIR

# smtpd.conf
mkdir /etc/mail
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

echo "Generating a new DKIM private key..."
openssl genrsa -out /etc/dkimproxy/private.key 4096
openssl rsa -in /etc/dkimproxy/private.key -pubout -out /etc/dkimproxy/public.key
DKIM_KEY=$(cat /etc/dkimproxy/public.key | sed -n '/PUBLIC KEY/!p')

# TODO: dovecot

# Prepare acme.sh
cd acme.sh/dnsapi
curl -s https://raw.githubusercontent.com/nightmared/le_dns_online/master/dns_online_rust.sh | sed -E "s/^export ONLINE_API_KEY\=.*$/export ONLINE_API_KEY=${ONLINE_API_KEY}/" > dns_online_rust.sh
chmod +x le_dns_online

echo "Updating DKIM entries..."
# Remove previous DKIM entries
./le_dns_online -a ${ONLINE_API_KEY} -o delete -n ${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME}. -v clean-dkim-$(date +%s) 1>&2
# Add the DKIM key to the DNS
./le_dns_online -a ${ONLINE_API_KEY} -o add -v dkim-${DKIM_SELECTOR}-$(date +%s) -n ${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME}. -d "\"v=DKIM1; p=${DKIM_KEY}\"" 1>&2

# Time to generate some certificates
cd $BASEDIR/acme.sh
echo "Generating a SSL certificate..."
./acme.sh --issue -d mail.$DOMAIN_NAME -k 4096 --dns dns_online_rust --dnssleep 5 --staging 1>&2
ls -a /root/.acme.sh
# Call cron every week ot update certificates if necessary
echo "/root/config/acme.sh/acme.sh --cron --home /root/config.acme.sh > /dev/null" > /etc/periodic/weekly/acme.sh

echo ""
echo ""
echo "Yay, generation succeeded !"
echo "Starting now..."

crond
/usr/sbin/smtpd -d -f /etc/mail/smtpd.conf
