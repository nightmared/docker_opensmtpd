#!/bin/sh

export DOMAIN_NAME=nightmared.fr
export DKIM_SELECTOR=docker
# This will be replaced automatically by its value when the build script is invoked
export ONLINE_API_KEY=

cd /root/config



# Time to generate some certificates
cd acme.sh
curl -s https://raw.githubusercontent.com/nightmared/le_dns_online/master/dns_online.sh | sed -E "s/^export ONLINE_API_KEY\=.*$/export ONLINE_API_KEY=${ONLINE_API_KEY}/" > dnsapi/dns_online_rust.sh
sed -Ei 's/dns_online_/dns_online_rust_/' dnsapi/dns_online_rust.sh
chmod +x dnsapi/le_dns_online

#./acme.sh --issue -d mail.$DOMAIN_NAME -k 4096 --dns dns_online_rust --dnssleep 5 --staging
