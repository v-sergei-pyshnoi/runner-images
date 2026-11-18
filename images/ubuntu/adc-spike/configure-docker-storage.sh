#!/bin/bash -e
################################################################################
##  File:  configure-docker-storage.sh
##  Desc:  Select an explicit nested Docker storage experiment before installation
################################################################################

set -euo pipefail

case "${ADC_SPIKE_DOCKER_STORAGE:?Set the Docker storage experiment mode.}" in
    default)
        echo "Leaving nested Docker storage configuration unchanged."
        ;;
    overlay2)
        if [[ -e /etc/docker/daemon.json ]]; then
            echo "Refusing to overwrite an existing Docker daemon configuration." >&2
            exit 1
        fi
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "overlay2",
  "features": {
    "containerd-snapshotter": false
  }
}
EOF
        echo "Explicit experiment: classic overlay2 with containerd image store disabled."
        cat /etc/docker/daemon.json
        ;;
    *)
        echo "Unsupported Docker storage experiment: $ADC_SPIKE_DOCKER_STORAGE" >&2
        exit 1
        ;;
esac
