#!/bin/sh -e

# Use this script with the argument --no-cache to force rebuilding the images from scratch
[ "z$1" = "z--no-cache" ] && DOCKER_BUILDER_ARGS="--no-cache"

# Generate the config generator ;-)
cp config/config.sh config/config_gen.sh

# Mount the logins folder if necessary
[ -z "`mount | grep "$(realpath $HOME/logins)"`" ] && sudo mount.zfs zstore/home/logins $HOME/logins

# What, you really thought I would leak the key ? Giving you its position on my filesystem is already a lot !
sed -i "s/^export ONLINE_API_KEY=/export ONLINE_API_KEY=$(cat ~/logins/online-api-key)/" config/config_gen.sh
sed -i "s/^export MAIL_PASSWD=/export MAIL_PASSWD=$(cat ~/logins/mail-passwd)/" config/config_gen.sh

# umount the folder as soon as possible
sudo umount $HOME/logins

docker build -t opensmtpd -f Dockerfile $DOCKER_BUILDER_ARGS .
docker save opensmtpd > openstmpd.tar

# Perform some mandatory cleanup
rm config/config_gen.sh
