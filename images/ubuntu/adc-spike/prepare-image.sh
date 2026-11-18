#!/bin/bash -e
################################################################################
##  File:  prepare-image.sh
##  Desc:  Stop build-time Docker and reject device nodes before committing for ADC
################################################################################

set -euo pipefail

systemctl stop docker.socket docker.service
systemctl stop containerd.service

# Docker recreates this backing-filesystem device when it starts in the microVM.
rm -f -- /var/lib/docker/volumes/backingFsBlockDev

device_nodes=$(find / -xdev \( -type b -o -type c \) -print)
if [[ -n "$device_nodes" ]]; then
    printf 'Unsupported device nodes remain in the image filesystem:\n%s\n' "$device_nodes" >&2
    exit 1
fi

echo "Image filesystem contains no block or character device nodes."
