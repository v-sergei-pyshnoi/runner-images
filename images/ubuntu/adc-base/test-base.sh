#!/bin/bash -e
################################################################################
##  File:  test-base.sh
##  Desc:  Check an ADC base image on a disposable Linux Docker host
################################################################################

set -euo pipefail

: "${BASE_IMAGE:?Set BASE_IMAGE to the local image tag.}"
container="adc-base-test-$$"
work_directory=$(mktemp -d)
container_started=false

cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$container_started" == true ]]; then
        if [[ "$status" != 0 ]]; then
            docker logs "$container"
            docker exec "$container" journalctl --no-pager -u ssh.service -n 80
        fi
        docker rm --force "$container"
    fi
    rm -f "$work_directory/key" "$work_directory/key.pub" "$work_directory/known_hosts"
    rmdir "$work_directory"
    exit "$status"
}
trap cleanup EXIT

platform=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$BASE_IMAGE")
[[ "$platform" == linux/amd64 ]]
docker run --rm --entrypoint /bin/bash "$BASE_IMAGE" -ec '
    source /etc/os-release
    [[ "$ID" == ubuntu && "$VERSION_ID" == 26.04 ]]
    [[ -z "$(find /etc/ssh -name "ssh_host_*_key*" -print)" ]]
    [[ ! -s /root/.ssh/authorized_keys ]]
    systemctl is-enabled ssh.service
    devtunnel --version
'

docker run --detach --name "$container" --privileged --cgroupns=private \
    --tmpfs /run --tmpfs /run/lock "$BASE_IMAGE"
container_started=true
ready=false
for ((attempt=0; attempt<60; attempt++)); do
    if docker exec "$container" bash -ec '
        [[ "$(cat /proc/1/comm)" == systemd ]]
        systemctl is-active --quiet dbus.service ssh.service
    '; then
        ready=true
        break
    fi
    sleep 2
done
if [[ "$ready" != true ]]; then
    echo "systemd, dbus and SSH did not become ready within 120 seconds." >&2
    exit 1
fi

ssh-keygen -q -t ed25519 -N '' -f "$work_directory/key"
docker exec "$container" install -d -m 700 /root/.ssh
docker cp "$work_directory/key.pub" "$container:/root/.ssh/authorized_keys"
docker exec "$container" chown root:root /root/.ssh/authorized_keys
docker exec "$container" chmod 600 /root/.ssh/authorized_keys
docker exec "$container" bash -ec '
    config=$(/usr/sbin/sshd -T)
    grep -qx "passwordauthentication no" <<< "$config"
    grep -qx "kbdinteractiveauthentication no" <<< "$config"
    grep -qx "pubkeyauthentication yes" <<< "$config"
'
docker exec "$container" cat /etc/ssh/ssh_host_ed25519_key.pub > "$work_directory/known_hosts"
address=$(docker inspect --format '{{.NetworkSettings.IPAddress}}' "$container")
sed -i "s/^/$address /" "$work_directory/known_hosts"
ssh -F /dev/null -i "$work_directory/key" \
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$work_directory/known_hosts" -o ConnectTimeout=10 \
    "root@$address" 'test "$(id -u)" = 0 && systemctl is-active ssh.service'
echo "Docker checks passed. ACA boot, Dev Tunnel connectivity and disk commit are NOT tested."
