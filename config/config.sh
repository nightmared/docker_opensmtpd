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
		user="$(echo ${line} | cut -d: -f1)"
		password="$(echo ${line} | cut -d: -f2)"

		# Create user
		adduser -D -g "Mail user" -h "/data/users/${user}" -s /sbin/nologin "${user}"
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

cd $BASEDIR

echo "Welcome to the all-in-one docker_smtpd service..."
create_users

# Evaluate our smtpd.conf to substitute variables
mkdir /etc/mail
evaluate_file smtpd.conf /etc/mail/smtpd.conf
cp aliases /etc/mail/

# generate dovecot.conf
evaluate_file dovecot.conf /etc/dovecot/dovecot.conf

# DKIM configuration
evaluate_file dkimproxy_out.conf /etc/dkimproxy/dkimproxy_out.conf

# Time to generate some certificates
cd $BASEDIR/acme.sh
echo "Generating a SSL certificate..."

# Update the api key in the LE challenge script
sed -i -E "s/^export ONLINE_API_KEY\=.*$/export ONLINE_API_KEY=${ONLINE_API_KEY}/" dnsapi/dns_online_rust.sh
chmod +x dnsapi/le_dns_online

./acme.sh --issue -d mail.${DOMAIN_NAME} -k 4096 --dns dns_online_rust --dnssleep 5 $ACME_OPTS 1>&2 || :

[ ! -e /root/.acme.sh/mail.${DOMAIN_NAME}/mail.${DOMAIN_NAME}.key ] && echo "The private key could not be found" && exit 1

# Set proper permissions on certificate files
chmod 640 /root/.acme.sh/mail.${DOMAIN_NAME}/mail.${DOMAIN_NAME}.key

echo "Generating a new DKIM private key..."
openssl genrsa -out /etc/dkimproxy/private.key 2048
openssl rsa -in /etc/dkimproxy/private.key -pubout -out /etc/dkimproxy/public.key
chown -R _dkim:_dkim /etc/dkimproxy
DKIM_KEY=$(cat /etc/dkimproxy/public.key | sed -n '/PUBLIC KEY/!p' | tr -d '\n')

echo "Adding DKIM entries in the DNS registry..."
# Remove previous DKIM entries
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o delete -n ${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME}. -z clean-dkim-$(date +%s) 1>&2
# Add the DKIM key to the DNS
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o add -z dkim-${DKIM_SELECTOR}-$(date +%s) -n ${DKIM_SELECTOR}._domainkey.${DOMAIN_NAME}. -d "\"v=DKIM1; p=${DKIM_KEY}\"" 1>&2

# Request our public IP
PUBLIC_IP=$(curl -m 3 -s -4 https://nightmared.fr/ip)
[ -z "${PUBLIC_IP}" ] && echo "Couldn't determine your public ip address !" && exit 1

echo "Updating mail.${DOMAIN_NAME} DNS entry (beware, IPv4 only !)..."
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o delete -t "A" -n mail.${DOMAIN_NAME}. -z clean-dns-$(date +%s) 1>&2
dnsapi/le_dns_online -a ${ONLINE_API_KEY} -o add -t "A" -z dns-mail-$(date +%s) -n mail.${DOMAIN_NAME}. -d ${PUBLIC_IP} 1>&2

echo ""
echo ""
echo "Yay, preparation succeeded !"
echo "Starting now..."

onexit() {
	echo "Child process exited. Quitting..."
	exit 1
}
trap onexit SIGCHLD

/usr/sbin/dkimproxy.out --conf_file=/etc/dkimproxy/dkimproxy_out.conf --user=_dkim --group=_dkim >>/data/dkimproxy.log 2>&1 &
/usr/sbin/smtpd -f /etc/mail/smtpd.conf -d >>/data/smtp.log 2>&1 &
/usr/sbin/dovecot -F >>/data/dovecot.log 2>&1 &

# This container auto-stop after 15 days, this is a simple way of ensuring the TLS certificates are always good (as well as maintaining an important DKIM key turnover)
sleep 15d
