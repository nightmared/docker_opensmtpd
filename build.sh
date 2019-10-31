#!/bin/sh -e

# Use this script with the argument --no-cache to force rebuilding the images from scratch
# Use this script with the argument --le-staging to use the staging LE environnement in the container
i=1
while [ $i -le $# ]; do
	[ "$(eval echo \${$i})" = "--no-cache" ] && DOCKER_BUILDER_ARGS="--no-cache"
	[ "$(eval echo \${$i})" = "--le-staging" ] && touch config/le_staging
	i=$((i+1))
done

IMAGE_NAME=opensmtpd-test

docker build -t ${IMAGE_NAME} -f Dockerfile ${DOCKER_BUILDER_ARGS} .
docker save ${IMAGE_NAME} > ${IMAGE_NAME}.tar

# Restore initial environment
rm -f config/le_staging
