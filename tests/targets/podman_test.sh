#!/bin/bash
# Drives hi.sh's real podman path - see test_lib.sh's
# _hi_container_backend_test for what this actually does and why it's shared
# with docker_test.sh. Podman keeps its own separate image/container store
# from docker, so this builds its own copies of the test images rather than
# reusing docker_test.sh's.
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_hi_container_backend_test podman
