#!/bin/sh -e

# Use this script with the argument --no-cache to force rebuilding the images from scratch
[ "z$1" = "z--no-cache" ] && DOCKER_BUILDER_ARGS="--no-cache"

docker build -t opensmtpd-builder -f Dockerfile.builder $DOCKER_BUILDER_ARGS .
rm -rf prefix
mkdir -p prefix
# Copying data from /output in the container to ./prefix
docker run --rm opensmtpd-builder tar Cczf /output - . | tar xzv -C prefix -f -

docker build -t opensmtpd -f Dockerfile.runner $DOCKER_BUILDER_ARGS .
