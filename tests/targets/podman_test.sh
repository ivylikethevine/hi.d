#!/bin/bash
# Drives hi.sh's real podman path - see test_lib.sh's
# _hi_container_backend_test for what this actually does and why it's shared
# with docker_test.sh. Podman keeps its own separate image/container store
# from docker, so this builds its own copies of the test images rather than
# reusing docker_test.sh's.
set -euo pipefail

# test_lib.sh sources core.sh itself; $_HI_TEST_LIB wins under the runner
# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

_hi_container_backend_test podman
