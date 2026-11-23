#!/bin/bash -e
################################################################################
##  File:  prepare-build.sh
##  Desc:  Prepare a stock Ubuntu container for the shared VM software installers
################################################################################

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update --error-on=any
apt-get install -y --no-install-recommends \
    ca-certificates curl dbus gnupg jq libdigest-sha-perl libicu-dev libssl-dev \
    lsb-release man-db snapd sudo systemd systemd-sysv wget

mkdir -p /imagegeneration /etc/cloud/templates
chmod 777 /imagegeneration
useradd --create-home --shell /bin/bash "$IMAGE_INSTALL_USER"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$IMAGE_INSTALL_USER" > /etc/sudoers.d/adc-image-builder
chmod 440 /etc/sudoers.d/adc-image-builder
printf 'PATH=%s\n' "$PATH" >> /etc/environment
echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90assumeyes
# Start PID 1 only after installation, and keep /tmp on disk during provisioning.
systemctl mask tmp.mount
touch /run/start-systemd
for ((attempt=0; attempt<60; attempt++)); do
    if [[ "$(cat /proc/1/comm)" == systemd ]]; then
        systemctl start dbus
        exit 0
    fi
    sleep 2
done
echo "systemd and dbus did not start within 120 seconds." >&2
exit 1
