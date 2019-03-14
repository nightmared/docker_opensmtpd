#!/bin/sh -e

# Use this script with the argument --no-cache to force rebuilding the images from scratch
[ "z$1" = "z--no-cache" ] && DOCKER_BUILDER_ARGS="--no-cache"

# Let's build the damn image
docker build -t opensmtpd-builder -f Dockerfile.builder $DOCKER_BUILDER_ARGS .
rm -rf prefix
mkdir -p prefix
# Exfiltrating data from the container to prefix/
docker run --rm opensmtpd-builder tar Cczf /output - . | tar xzv -C prefix -f -

# Generate the config generator ;-)
cp config/config.sh config/config_gen.sh
# What, you really thought I would leak the key ? Giving you its position on my filesystem is already a lot !
sed -i "s/^export ONLINE_API_KEY=/export ONLINE_API_KEY=$(cat ~/online-api-key)/" config/config_gen.sh
sed -i "s/^export MAIL_PASSWD=/export MAIL_PASSWD=$(cat ~/mail-passwd)/" config/config_gen.sh

# TLS certificates
# Downloading a static generated binary for le_dns_online
wget -N https://nightmared.fr/le_dns_online 
cp le_dns_online config/acme.sh/dnsapi/le_dns_online

docker build -t opensmtpd -f Dockerfile.runner $DOCKER_BUILDER_ARGS .
