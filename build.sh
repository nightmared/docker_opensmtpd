#!/bin/sh -e

IMAGE_NAME=opensmtpd
EXPORT=1

rm -f ${IMAGE_NAME}.tar


# Use this script with the argument --no-cache to force rebuilding the images from scratch
# Use this script with the argument --le-staging to use the staging LE environnement in the container
i=1
while [ $i -le $# ]; do
	[ "$(eval echo \${$i})" = "--no-cache" ] && DOCKER_BUILDER_ARGS="--no-cache"
	[ "$(eval echo \${$i})" = "--le-staging" ] && touch config/le_staging
	[ "$(eval echo \${$i})" = "--no-export" ] && EXPORT=0
	i=$((i+1))
done


docker build -t ${IMAGE_NAME} -f Dockerfile ${DOCKER_BUILDER_ARGS} .
[ $EXPORT = 1 ] && docker save ${IMAGE_NAME} > ${IMAGE_NAME}.tar

# Restore initial environment
rm -f config/le_staging
