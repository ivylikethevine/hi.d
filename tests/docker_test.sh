#!/bin/bash
# Drives hi.sh's real docker path - see test_lib.sh's
# _hi_container_backend_test for what this actually does and why it's shared
# with podman_test.sh.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./test_lib.sh
source "$_HI_TEST_LIB"

_hi_container_backend_test docker
