#!/bin/bash
# Drives hi.sh's real docker path - see test_lib.sh's
# _hi_container_backend_test for what this actually does and why it's shared
# with podman_test.sh. docker also gets one extra case podman does not:
# compose service aliases, docker-only per hi.sh's _hi_compose_container.
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# Boots a container the way _hi_start_case_container does, but with the
# compose label _hi_start_case_container has no room for, and drives hi.sh
# against the *alias*, not $_HI_CONTAINER - the whole point is proving
# _hi_compose_container resolves it, not just that the real name still works
# (docker_test.sh's plain "bash" case already covers that path).
function _hi_docker_compose_alias_case() {
  local label="compose" alias="hi-dockertest-composesvc-$$"
  local _HI_CONTAINER="hi-dockertest-compose-$$"
  local ok=0

  _hi_h3 "Testing shell: $label"
  _hi_track_container "$_HI_CONTAINER"
  if ! docker run -d --name "$_HI_CONTAINER" \
    --label "com.docker.compose.service=$alias" \
    debian:bookworm-slim tail -f /dev/null \
    >/dev/null 2>"$_HI_WORKDIR/$label.run.log"; then
    _hi_dump_log "Failed to start container:" "$_HI_WORKDIR/$label.run.log"
    return 1
  fi
  _hi_cecho " | Container: $_HI_CONTAINER (alias: $alias)"

  if _hi_poll_bool 40 0.25 _hi_container_running "$_HI_CONTAINER"; then
    _hi_exec_case "$label" "docker path (compose alias)" "$_HI_TEST_MARKER" 30 \
      "$alias" "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)" && ok=1
  else
    _hi_cecho " | Container never reported running" "$RED"
  fi
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

_hi_container_backend_test docker _hi_docker_compose_alias_case
