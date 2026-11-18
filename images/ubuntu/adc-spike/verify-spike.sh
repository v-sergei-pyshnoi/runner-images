#!/bin/bash -e
################################################################################
##  File:  verify-spike.sh
##  Desc:  Check installed files at build time or validate runtime in an ADC microVM
################################################################################

set -euo pipefail

case "${1:-}" in
    build|runtime) mode=$1 ;;
    *)
        echo "Usage: bash verify-spike.sh build|runtime" >&2
        exit 1
        ;;
esac

if [[ $# != 1 ]]; then
    echo "Expected exactly one validation mode: build or runtime." >&2
    exit 1
fi

export HELPER_SCRIPTS=/imagegeneration/helpers
export INSTALLER_SCRIPT_FOLDER=/imagegeneration/installers
storage_mode=$(cat /imagegeneration/adc-spike/docker-storage)
case "$storage_mode" in
    default|overlay2) ;;
    *)
        echo "Invalid Docker storage mode recorded in the image: $storage_mode" >&2
        exit 1
        ;;
esac

# shellcheck source=/dev/null
source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 26.04 || "$(uname -m)" != x86_64 ]]; then
    echo "Expected Ubuntu 26.04 x64." >&2
    exit 1
fi

docker --version
docker buildx version
docker compose version
docker-credential-ecr-login -v
shasum --version
pwsh -NoProfile -Command 'Import-Module Pester -ErrorAction Stop; Get-Host'
test -r /imagegeneration/tests/Tools.Tests.ps1
test -x /usr/local/bin/invoke_tests

if [[ "$storage_mode" == overlay2 ]]; then
    jq --exit-status \
        '.["storage-driver"] == "overlay2" and .features["containerd-snapshotter"] == false' \
        /etc/docker/daemon.json
fi

if [[ "$mode" == build ]]; then
    echo "Installed-file checks passed. Docker build/run and ADC runtime validation have NOT run."
    exit 0
fi

if systemd-detect-virt --container --quiet; then
    echo "Run runtime validation inside a fresh ADC microVM, not a Docker container." >&2
    exit 1
fi

if [[ "$(cat /proc/1/comm)" != systemd ]]; then
    echo "Expected systemd as PID 1." >&2
    exit 1
fi

if [[ ! -r /sys/fs/cgroup/cgroup.controllers ]]; then
    echo "Expected cgroup v2." >&2
    exit 1
fi

for attempt in {1..60}; do
    if systemctl is-active --quiet docker.service; then
        break
    fi
    if [[ "$attempt" == 60 ]]; then
        echo "Docker service did not become active within 120 seconds." >&2
        systemctl status docker.service --no-pager
        exit 1
    fi
    sleep 2
done

docker info
case "$storage_mode" in
    default)
        echo "Checking Docker with its default storage configuration."
        ;;
    overlay2)
        if [[ "$(docker info --format '{{.Driver}}')" != overlay2 ]]; then
            echo "Expected the explicitly requested overlay2 storage driver." >&2
            exit 1
        fi
        ;;
esac
invoke_tests "Tools" "Docker"

docker build --progress=plain --tag adc-spike-nested - <<'EOF'
FROM ubuntu:26.04
RUN printf '%s\n' 'adc-nested-docker-ok' > /proof
CMD ["/bin/cat", "/proof"]
EOF

if [[ "$(docker run --rm adc-spike-nested)" != adc-nested-docker-ok ]]; then
    echo "The nested Docker build/run returned an unexpected result." >&2
    exit 1
fi

df -h / /tmp
findmnt --target /
du -sh /var/lib/docker
echo "Docker runtime checks passed on this machine. Full runner toolset and ADC distribution are not tested."
