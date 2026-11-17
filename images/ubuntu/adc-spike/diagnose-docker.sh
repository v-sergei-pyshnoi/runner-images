#!/bin/bash -e
################################################################################
##  File:  diagnose-docker.sh
##  Desc:  Collect nested Docker storage diagnostics without changing its configuration
################################################################################

set -uo pipefail

failed=0

collect() {
    printf '\n=== '
    printf '%q ' "$@"
    printf '===\n'
    if "$@"; then
        return 0
    else
        local status=$?
        echo "Diagnostic command failed with exit code $status." >&2
        failed=1
    fi
}

collect uname -a
collect cat /proc/self/status
collect cat /proc/self/uid_map
collect cat /proc/self/gid_map
collect findmnt --target /

for directory in /var/lib/docker /var/lib/containerd /var/lib/docker/containerd/daemon; do
    if [[ -d "$directory" ]]; then
        collect findmnt --target "$directory"
        collect stat --file-system "$directory"
        collect df -h "$directory"
    else
        echo "Storage directory does not exist: $directory"
    fi
done

for config in /etc/docker/daemon.json /etc/containerd/config.toml /var/run/docker/containerd/daemon/containerd.toml; do
    if [[ -f "$config" ]]; then
        collect cat "$config"
    else
        echo "Configuration file does not exist: $config"
    fi
done

if command -v docker > /dev/null; then
    collect docker version
    collect docker info
    collect docker info --format '{{json .DriverStatus}}'
else
    echo "Docker is not installed; provisioning failed before storage diagnostics were available."
fi

collect systemctl show docker.service containerd.service \
    --property=ActiveState,SubState,Result,ExecStart,FragmentPath,DropInPaths
collect journalctl --boot --no-pager --lines=200 \
    --unit=docker.service --unit=containerd.service

exit "$failed"
