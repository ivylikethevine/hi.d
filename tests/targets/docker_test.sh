#!/bin/bash
# Drives hi.sh's real docker path - see test_lib.sh's
# _hi_container_backend_test for what this actually does and why it's shared
# with podman_test.sh.
set -euo pipefail

: "${_HI_HOME:=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=../../common/core.sh
source "$_HI_HOME/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_hi_container_backend_test docker
