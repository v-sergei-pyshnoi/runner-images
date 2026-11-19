#!/bin/bash -e
################################################################################
##  File:  build-and-push.sh
##  Desc:  Bootstrap an Ubuntu 26.04 x64 host, build the shared template and push to ACR
################################################################################

# Usage:
#   export ACR_USERNAME=... ACR_PASSWORD=...
#   bash images/ubuntu/adc-spike/build-and-push.sh
# Optional: ACR_REGISTRY, IMAGE_REPOSITORY, IMAGE_TAG, OUTPUT_DIRECTORY,
#           MIN_FREE_GB (default 120, checked on both Docker and output filesystems).
# Run only on a dedicated build VM: installs packages and runs privileged containers.

set +x
set -euo pipefail

if [[ "$EUID" != 0 ]]; then
    exec sudo --preserve-env=ACR_USERNAME,ACR_PASSWORD,ACR_REGISTRY,IMAGE_REPOSITORY,IMAGE_TAG,OUTPUT_DIRECTORY,MIN_FREE_GB \
        bash "$(realpath "$0")" "$@"
fi

: "${ACR_USERNAME:?Set ACR_USERNAME in your environment.}"
: "${ACR_PASSWORD:?Set ACR_PASSWORD in your environment.}"
# Keep credentials out of installer, Packer and Docker build subprocess environments.
export -n ACR_USERNAME ACR_PASSWORD

# shellcheck source=/dev/null
source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 26.04 || "$(uname -m)" != x86_64 ]]; then
    echo "Expected a dedicated Ubuntu 26.04 x64 build VM." >&2
    exit 1
fi
if [[ $# != 0 ]]; then
    echo "This script takes configuration from environment variables, not arguments." >&2
    exit 1
fi

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd "$script_directory/../../.." && pwd)
registry=${ACR_REGISTRY:-runnerubuntu26test.azurecr.io}
image_repository=${IMAGE_REPOSITORY:-ubuntu2604-spike}
image_tag=${IMAGE_TAG:-$(date -u +%Y%m%d-%H%M%S)}
min_free_gb=${MIN_FREE_GB:-120}
if [[ ! "$registry" =~ ^[a-z0-9][a-z0-9.-]*\.azurecr\.io$ ||
      ! "$image_repository" =~ ^[a-z0-9]+([._/-][a-z0-9]+)*$ ||
      ! "$image_tag" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ||
      ! "$min_free_gb" =~ ^[1-9][0-9]{0,3}$ ]]; then
    echo "Invalid registry, repository, tag or MIN_FREE_GB. Use the ACR hostname without https:// or a trailing slash." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update --error-on=any
apt-get install -y ca-certificates curl gnupg unzip jq python3 git

if ! command -v docker > /dev/null || ! docker buildx version > /dev/null 2>&1; then
    if dpkg --get-selections | awk '$1 ~ /^(docker.io|containerd|runc)$/ && $2 == "install" {found=1} END {exit !found}'; then
        echo "Conflicting distribution Docker packages found. Resolve them before installing Docker CE; this script will not remove them." >&2
        exit 1
    fi
    install -m 0755 -d /etc/apt/keyrings
    curl --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update --error-on=any
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
fi
systemctl enable --now docker
docker version
docker buildx version
docker info

output_directory=${OUTPUT_DIRECTORY:-/var/tmp/adc-builds/$image_tag}
mkdir -p "$output_directory"
output_directory=$(realpath "$output_directory")
work_directory=$(mktemp -d "$output_directory/work.XXXXXX")
export DOCKER_CONFIG="$work_directory/docker-auth"
mkdir -m 0700 "$DOCKER_CONFIG"

cleanup() {
    local status=$?
    trap - EXIT
    rm -f -- "$DOCKER_CONFIG/config.json"
    if [[ "$status" != 0 ]]; then
        echo "Build or push failed (exit $status). Logs and intermediate files: $output_directory" >&2
    fi
    exit "$status"
}
trap cleanup EXIT

check_space() {
    local path=$1 available_kb
    available_kb=$(df -Pk "$path" | awk 'END {print $4}')
    if (( available_kb < min_free_gb * 1024 * 1024 )); then
        echo "Need at least $min_free_gb GiB free on $path; available: $((available_kb / 1024 / 1024)) GiB." >&2
        exit 1
    fi
}
docker_root=$(docker info --format '{{.DockerRootDir}}')
check_space "$docker_root"
check_space "$output_directory"

packer_version=1.15.4
packer_archive="packer_${packer_version}_linux_amd64.zip"
for filename in "$packer_archive" "packer_${packer_version}_SHA256SUMS"; do
    curl --fail --silent --show-error --location --retry 3 \
        "https://releases.hashicorp.com/packer/$packer_version/$filename" \
        -o "$work_directory/$filename"
done
(
    cd "$work_directory"
    grep "  $packer_archive\$" "packer_${packer_version}_SHA256SUMS" > packer.sha256
    sha256sum --check packer.sha256
    unzip -q "$packer_archive" packer
)
packer="$work_directory/packer"
"$packer" version

# Stage the original template unchanged, preserving its relative source paths.
template_directory="$work_directory/images/ubuntu/templates"
mkdir -p "$template_directory"
for directory in scripts assets toolsets; do
    ln -s "$repository_root/images/ubuntu/$directory" "$work_directory/images/ubuntu/$directory"
done
ln -s "$script_directory" "$work_directory/images/ubuntu/adc-spike"
ln -s "$repository_root/helpers" "$work_directory/helpers"
cp "$repository_root/images/ubuntu/templates/build.ubuntu-26_04.pkr.hcl" \
    "$repository_root/images/ubuntu/templates/variable.ubuntu.pkr.hcl" \
    "$script_directory/docker.pkr.hcl" "$template_directory/"

target_image="$registry/$image_repository:$image_tag"
bootstrap_image="adc-ubuntu2604-bootstrap:$image_tag"
container_name="adc-build-$(date -u +%Y%m%d%H%M%S)-$$"
export PKR_VAR_cloud_provider=docker PKR_VAR_image_os=ubuntu26
export PKR_VAR_image_version="$image_tag" PKR_VAR_base_image="$bootstrap_image"
export PKR_VAR_container_name="$container_name" PKR_VAR_privileged=true
export PKR_VAR_docker_storage=default PKR_VAR_skip_docker_image_preload=true
export PACKER_LOG=1 PACKER_LOG_PATH="$output_directory/packer-debug.log"

docker pull --platform linux/amd64 ubuntu:26.04
base_image=$(docker image inspect --format '{{index .RepoDigests 0}}' ubuntu:26.04)
docker build --platform linux/amd64 --build-arg "BASE_IMAGE=$base_image" \
    --tag "$bootstrap_image" "$script_directory" 2>&1 | tee "$output_directory/bootstrap.log"
"$packer" init "$template_directory"
"$packer" validate "$template_directory"
"$packer" build -on-error=abort "$template_directory" 2>&1 | tee "$output_directory/packer-build.log"

cp "$template_directory/packer-manifest.json" \
    "$work_directory/images/ubuntu/Ubuntu2604-Readme.md" \
    "$work_directory/images/ubuntu/software-report.json" "$output_directory/"
image_id=$(jq --exit-status --raw-output '.builds[-1].artifact_id' "$output_directory/packer-manifest.json")
docker image tag "$image_id" "$target_image"
docker run --rm --entrypoint /bin/bash "$target_image" \
    /imagegeneration/adc-spike/verify-spike.sh build 2>&1 | tee "$output_directory/image-checks.log"

# An uncompressed archive avoids repeated gzip decompression while inspecting large layers.
docker image save --output "$output_directory/image.tar" "$target_image"
python3 "$script_directory/check-image-archive.py" "$output_directory/image.tar" \
    | tee "$output_directory/device-check.log"
(cd "$output_directory" && sha256sum image.tar > image.tar.sha256)

printf '%s' "$ACR_PASSWORD" | docker login "$registry" --username "$ACR_USERNAME" --password-stdin
unset ACR_USERNAME ACR_PASSWORD
docker image push "$target_image" 2>&1 | tee "$output_directory/push.log"
docker buildx imagetools inspect "$target_image" --format '{{json .Manifest}}' \
    > "$output_directory/registry-manifest.json"
digest=$(jq --exit-status --raw-output '.digest' "$output_directory/registry-manifest.json")
if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Registry returned an invalid image digest." >&2
    exit 1
fi
printf '%s/%s@%s\n' "$registry" "$image_repository" "$digest" | tee "$output_directory/image-reference.txt"
echo "Push verified. ADC runtime checks have NOT run. Results: $output_directory"
