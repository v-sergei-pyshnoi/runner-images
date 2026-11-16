#!/bin/bash -e
################################################################################
##  File:  verify-spike.sh
##  Desc:  Validate the Docker spike during provisioning and after image commit
################################################################################

set -euo pipefail

# shellcheck source=/dev/null
source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 26.04 || "$(uname -m)" != x86_64 ]]; then
    echo "Expected Ubuntu 26.04 x64." >&2
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
pwsh -NoProfile -Command 'Get-Host'
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
echo "Limited Docker spike passed. Full runner provisioning and ADC runtime are not tested."
