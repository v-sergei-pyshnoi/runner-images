#!/bin/bash -e
################################################################################
##  File:  run-docker-provisioner.sh
##  Desc:  Reload installer environment for non-login Docker provisioning
################################################################################

set -eo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/etc-environment.sh"
reload_etc_environment
export SUDO_USER=$1
shift
exec "$@"
