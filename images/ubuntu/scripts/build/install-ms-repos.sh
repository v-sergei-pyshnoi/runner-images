#!/bin/bash -e
################################################################################
##  File:  install-ms-repos.sh
##  Desc:  Install official Microsoft package repos for the distribution
################################################################################

set -o pipefail

os_label=$(lsb_release -rs)

# Install Microsoft repository
wget "https://packages.microsoft.com/config/ubuntu/$os_label/packages-microsoft-prod.deb"
dpkg -i packages-microsoft-prod.deb

codename=$(lsb_release -cs)
case "$codename" in
    jammy)
        curl_version="7.81.0-1ubuntu1.29"
        curl_libraries=(libcurl3-gnutls libcurl4)
        ;;
    noble)
        curl_version="8.5.0-2ubuntu10.15"
        curl_libraries=(libcurl3t64-gnutls libcurl4t64)
        ;;
    resolute)
        curl_version="8.18.0-1ubuntu2.7"
        curl_libraries=(libcurl3t64-gnutls libcurl4t64)
        ;;
    *)
        echo "No curl rollback version configured for Ubuntu '${codename}'" >&2
        exit 1
        ;;
esac

# Remove this workaround once the Git PPA includes the compatibility fix.
# This deliberately rolls back security fixes; see actions/runner-images#15014.
# Keep signature verification enabled, but allow the historical Release file to expire.
cat <<EOF > /etc/apt/sources.list.d/curl-rollback.list
deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/20261013T000000Z/ ${codename}-updates main universe
EOF

# Never select unrelated packages from the snapshot. Only the exact curl version
# can override current repositories, including when the base VM already has newer curl.
cat <<EOF > /etc/apt/preferences.d/curl-rollback
Package: curl libcurl*
Pin: version ${curl_version}
Pin-Priority: 1001

Package: *
Pin: origin "snapshot.ubuntu.com"
Pin-Priority: -1
EOF

apt-get update

# Include installed development packages so their exact-version dependencies remain consistent.
installed_packages=$(dpkg-query -W -f '${binary:Package}\t${source:Package}\t${db:Status-Status}\n')
curl_package_names=$(
    {
        printf '%s\n' curl "${curl_libraries[@]}"
        awk '$2 == "curl" && $3 == "installed" { print $1 }' <<< "$installed_packages"
    } | sort -u
)
curl_packages=()
while read -r package; do
    curl_packages+=("${package}=${curl_version}")
done <<< "$curl_package_names"

apt-get install --yes --allow-downgrades --no-remove "${curl_packages[@]}"

# update
apt-get install apt-transport-https ca-certificates curl software-properties-common
apt-get update
apt-get dist-upgrade

while read -r package; do
    installed_version=$(dpkg-query -W -f '${Version}' "$package")
    if [[ "$installed_version" != "$curl_version" ]]; then
        echo "Expected ${package}=${curl_version} after dist-upgrade, found ${installed_version}" >&2
        exit 1
    fi
    candidate_version=$(LC_ALL=C apt-cache policy "$package" | awk '/Candidate:/ { print $2 }')
    if [[ "$candidate_version" != "$curl_version" ]]; then
        echo "Expected APT candidate ${package}=${curl_version}, found ${candidate_version}" >&2
        exit 1
    fi
done <<< "$curl_package_names"

apt-cache policy curl "${curl_libraries[@]}"
