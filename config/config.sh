#!/bin/sh -e

export BASEDIR=/root/config
source ${BASEDIR}/env

create_users() {
	echo "Creating users..."

	echo -e "\t* Creating system users..."
	mkdir -p /var/empty
	adduser -D -g "DKIM proxy" -h /var/empty -s /sbin/nologin _dkim
	adduser -D -g "SMTP Daemon" -h /var/empty -s /sbin/nologin _smtpd
	adduser -D -g "SMTPD Queue" -h /var/empty -s /sbin/nologin _smtpq

	echo -e "\t* Creating user accounts..."

	# Cleanup the dovecot password
	rm -f /etc/dovecot/imap.passwd

	[ ! -e /data/users-descr ] && echo "/data/users-descr does not exist, make sure to provide one" && exit 1
	mkdir -p /data/users
	while read line;
	do
		uid="$(echo ${line} | cut -d: -f1)"
		user="$(echo ${line} | cut -d: -f2)"
		password="$(echo ${line} | cut -d: -f3)"

		# Create user
		adduser -D -g "Mail user" -h "/data/users/${user}" -s /sbin/nologin -u ${uid} "${user}"
		echo "${user}:${password}" | chpasswd 2>/dev/null

		# Assign user to the dovecot auth database
		UID=$(cat /etc/passwd |grep -E "^${user}:" | cut -d: -f3)
		CRYPT=$(echo ${password} | /usr/bin/cryptpw -m sha512)
		echo "contact:{SHA512-CRYPT}${CRYPT}:${UID}:${UID}::/data/users/${user}::userdb_mail=maildir:~/Maildir" > /etc/dovecot/imap.passwd
	done </data/users-descr

	# Delete the password file prior to launchng services
	echo -e "\t* Deleting the user-password backing store /data/users"
	rm -f /data/users-descr
}

evaluate_file() {
	while read line ;
	do
		eval "echo \"$line\""
	done <$1 >$2
}

update_dns_entry() {
	# for some bad reason (a limitation of nsupdate as of bind 9.16), we must split long entries as chunks of less than 255 characters. here we handle only the case where strlen \in [0, 510]
	strlen=$(echo -n "$3" | wc -c)
	if [ "$strlen" -ge 256 ]; then
		part0=\"$(echo -n "$3" | dd bs=1 count=255 2>/dev/null)\"
		part1=\"$(echo -n "$3" | dd bs=1 skip=255 count=255 2>/dev/null)\"
	else
		part0="$3"
		part1=""
	fi
	(echo "server ${DOMAIN_NAME}";
	echo "zone ${DOMAIN_NAME}";
	echo "update delete $1 $2";
	echo "update add $1 3600 $2 $part0 $part1";
	echo "send") | nsupdate -k /root/bind.keys
}

cd $BASEDIR

echo "Welcome to the all-in-one docker_smtpd service..."
create_users

# Evaluate our smtpd.conf to substitute variables
mkdir /etc/mail
evaluate_file smtpd.conf /etc/mail/smtpd.conf
cp aliases whitelisted_local_ips /etc/mail/

# generate dovecot.conf
evaluate_file dovecot.conf /etc/dovecot/dovecot.conf

# DKIM configuration
evaluate_file dkimproxy_out.conf /etc/dkimproxy/dkimproxy_out.conf

# Time to generate some certificates
echo "Generating a SSL certificate..."

mkdir -p /root/.lego
if [ -e "/root/.lego/certificates/mail.${DOMAIN_NAME}.crt" ]; then
       LEGO_CMD="renew --days 30 --reuse-key"
else
       LEGO_CMD="run"
fi

lego --accept-tos --path /root/.lego -d mail.${DOMAIN_NAME} --email "contact+le@nightmared.fr" --key-type ec256 --dns rfc2136 --dns.disable-cp $LEGO_OPTS $LEGO_CMD

# Set proper permissions on certificate files
chmod 640 /root/.lego/certificates/mail.${DOMAIN_NAME}.crt
chmod 640 /root/.lego/certificates/mail.${DOMAIN_NAME}.key

echo "Generating a new DKIM private key..."
openssl genrsa -out /etc/dkimproxy/private.key 2048
openssl rsa -in /etc/dkimproxy/private.key -pubout -out /etc/dkimproxy/public.key
chown -R _dkim:_dkim /etc/dkimproxy
DKIM_KEY=$(cat /etc/dkimproxy/public.key | sed -n '/PUBLIC KEY/!p' | tr -d '\n')

echo "Adding DKIM entries in the DNS registry..."
update_dns_entry ${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME} TXT "v=DKIM1;p=${DKIM_KEY}"

# Request our public IP
PUBLIC_IP=$(curl -m 3 -s -4 https://api.ipify.org)
[ -z "${PUBLIC_IP}" ] && echo "Couldn't determine your public ip address !" && exit 1

echo "Updating mail.${DOMAIN_NAME} DNS entry (beware, IPv4 only !)..."
update_dns_entry mail.${DOMAIN_NAME} A ${PUBLIC_IP}

echo "Yay, preparation succeeded !"
echo "Starting now..."

/usr/sbin/dkimproxy.out --conf_file=/etc/dkimproxy/dkimproxy_out.conf --user=_dkim --group=_dkim >>/data/dkimproxy.log 2>&1 &
/usr/sbin/smtpd -f /etc/mail/smtpd.conf -d >>/data/smtp.log 2>&1 &
/usr/sbin/dovecot -F >>/data/dovecot.log 2>&1 &

# This container auto-stop after 15 days, this is a simple way of ensuring the TLS certificates are always good (as well as maintaining an important DKIM key turnover)
sleep 15d
