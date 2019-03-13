#!/bin/sh

docker build -t opensmtpd-builder .
rm -rf ../prefix
mkdir -p ../prefix
# Copying data from /output in the container to ../prefix
docker run --rm opensmtpd-builder tar Cczf /output - . | tar xzv -C ../prefix -f -
