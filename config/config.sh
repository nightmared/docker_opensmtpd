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
adduser -D -g "DKIM proxy" -h /var/empty -s /sbin/nologin _dkim
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

# dovecot.conf
while read line ;
do
    eval "echo \"$line\""
done <dovecot.conf >/etc/dovecot/dovecot.conf
UID=$(cat /etc/passwd |grep contact | cut -d: -f3)
CRYPT=$(echo ${MAIL_PASSWD} | /usr/bin/cryptpw -m sha512)
echo "contact:{SHA512-CRYPT}${CRYPT}:${UID}:${UID}::/data::userdb_mail=maildir:~/Maildir" > /etc/dovecot/imap.passwd

# DKIM configuration
while read line ;
do
    eval "echo \"$line\""
done <dkimproxy_out.conf >/etc/dkimproxy/dkimproxy_out.conf

# Time to generate some certificates
cd $BASEDIR/acme.sh
sed -i -E "s/^export ONLINE_API_KEY\=.*$/export ONLINE_API_KEY=${ONLINE_API_KEY}/" dnsapi/dns_online_rust.sh
chmod +x dnsapi/le_dns_online
echo "Generating a SSL certificate..."
./acme.sh --issue -d mail.${DOMAIN_NAME} -k 4096 --dns dns_online_rust --dnssleep 5 1>&2 || :
# Set proper permissions on certificate files
chmod 640 /root/.acme.sh/mail.${DOMAIN_NAME}/mail.${DOMAIN_NAME}.key

echo "Generating a new DKIM private key..."
openssl genrsa -out /etc/dkimproxy/private.key 2048
openssl rsa -in /etc/dkimproxy/private.key -pubout -out /etc/dkimproxy/public.key
chown -R _dkim:_dkim /etc/dkimproxy
DKIM_KEY=$(cat /etc/dkimproxy/public.key | sed -n '/PUBLIC KEY/!p' | tr -d '\n')
echo "Updating DKIM entries..."
# Remove previous DKIM entries
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o delete -n ${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME}. -z clean-dkim-$(date +%s) 1>&2
# Add the DKIM key to the DNS
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o add -z dkim-${DKIM_SELECTOR}-$(date +%s) -n ${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME}. -d "\"v=DKIM1; p=${DKIM_KEY}\"" 1>&2

PUBLIC_IP=$(curl -s -4 ifconfig.me/ip)
[ "z${PUBLIC_IP}" = "z" ] && echo "Couldn't determine your public ip address !" && exit 1
echo "Updating mail.${DOMAIN_NAME} DNS entry (beware, IPv4 only !)..."
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o delete -t "A" -n mail.${DOMAIN_NAME}. -z clean-dns-$(date +%s) 1>&2
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o add -t "A" -z dns-mail-$(date +%s) -n mail.${DOMAIN_NAME}. -d ${PUBLIC_IP} 1>&2

# Setting up permissions
chown -R contact:contact /data
chmod 777 /data
chmod -R 770 /data/Maildir

echo ""
echo ""
echo "Yay, generation succeeded !"
echo "Starting now..."

/usr/sbin/dkimproxy.out --conf_file=/etc/dkimproxy/dkimproxy_out.conf --user=_dkim --group=_dkim >>/data/dkimproxy.log 2>&1 &
/usr/sbin/smtpd -f /etc/mail/smtpd.conf -d >>/data/smtp.log 2>&1 &
/usr/sbin/dovecot -F >>/data/dovecot.log 2>&1 &
# This container auto-stop after 15 days, this is a simple way of ensuring the TLS certificates are always good (as well as maintaining an important key turnover)
sleep 15d
