#!/bin/bash
# Unit tests for common/targets.sh - the "<name>\t<kind>" list behind `hi`'s
# bash/zsh/fish completions and hi.sh's own _hi_is_ssh_host check.
#
# The ssh half runs against fixture ~/.ssh/config files in the scratch dir; the
# docker/podman/nomad/kube halves run against fake CLIs on $PATH, so the
# expected output is fixed instead of "whatever this machine happens to be
# running". A third PATH - a toolbox holding only the commands targets.sh
# itself needs - covers the "no backend installed at all" shape.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_SHIM_PATH=""
_HI_TOOLBOX_PATH=""
_HI_CONFIG=""
_HI_NO_CONFIG=""

# Fake backend CLIs, each answering only the exact invocation targets.sh makes
# and failing anything else, so a changed command shape shows up as a missing
# row rather than a silently passing test.
function _hi_write_shims() {
  local dir="$_HI_WORKDIR/shims" tool
  mkdir -p "$dir"

  cat >"$dir/docker" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'alpha\nbeta\n'
EOF

  cat >"$dir/podman" <<'EOF'
#!/bin/sh
[ "$1" = ps ] || exit 1
printf 'pod-one\n'
EOF

  # `nomad job status` (header row + one job), then `nomad job allocs` per job
  cat >"$dir/nomad" <<'EOF'
#!/bin/sh
case "$1 $2" in
"job status") printf 'ID    Type     Status\nweb   service  running\n' ;;
"job allocs") printf 'abc12345\n' ;;
*) exit 1 ;;
esac
EOF

  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
[ "$1" = get ] || exit 1
printf 'pod-a\npod-b\n'
EOF

  for tool in docker podman nomad kubectl; do
    chmod +x "$dir/$tool"
  done
  _HI_SHIM_PATH="$dir:$PATH"
}

# A PATH with the commands targets.sh runs and nothing else - no docker,
# podman, nomad or kubectl to find.
function _hi_write_toolbox() {
  local dir="$_HI_WORKDIR/toolbox" tool resolved
  mkdir -p "$dir"
  for tool in sh awk sed; do
    resolved="$(command -v "$tool")" || return 1
    ln -sf "$resolved" "$dir/$tool"
  done
  _HI_TOOLBOX_PATH="$dir"
}

function _hi_write_configs() {
  _HI_CONFIG="$_HI_WORKDIR/ssh_config"
  _HI_NO_CONFIG="$_HI_WORKDIR/no_such_ssh_config"
  cat >"$_HI_CONFIG" <<'EOF'
Host alpha beta
  HostName 10.0.0.1

# a wildcard entry, plus one with a single-character glob
Host *
  User nobody
Host web-?
  User nobody

host lowercase-keyword
  User nobody

Host commented # trailing comment, not a host
  User nobody
EOF
}

# targets.sh under the shimmed PATH: `_hi_targets <config> [kind]`
function _hi_targets() {
  local config="$1"
  shift
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$config" sh "$_HI_TARGETS" "$@"
}

function _hi_has_row() {
  printf '%s\n' "$1" | grep -qxF "$2"$'\t'"$3"
}

function test_multi_alias_host_yields_one_row_each() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  _hi_has_row "$out" alpha ssh && _hi_has_row "$out" beta ssh
}

function test_wildcard_patterns_are_skipped() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  ! printf '%s\n' "$out" | grep -qE '^(\*|web-\?)'
}

function test_lowercase_host_keyword_is_matched() {
  _hi_has_row "$(_hi_targets "$_HI_CONFIG" ssh)" lowercase-keyword ssh
}

function test_trailing_comment_is_not_a_host() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  _hi_has_row "$out" commented ssh || return 1
  ! printf '%s\n' "$out" | grep -q 'trailing\|comment,'
}

function test_missing_config_is_empty_and_succeeds() {
  local out
  out="$(_hi_targets "$_HI_NO_CONFIG" ssh)" || return 1
  [ -z "$out" ]
}

function test_ssh_kind_excludes_container_backends() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" ssh)"
  [ -n "$out" ] || return 1
  ! printf '%s\n' "$out" | grep -qv $'\tssh$'
}

function test_docker_kind_lists_running_containers() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" docker)"
  _hi_has_row "$out" alpha docker && _hi_has_row "$out" beta docker
}

function test_podman_kind_lists_running_containers() {
  _hi_has_row "$(_hi_targets "$_HI_CONFIG" podman)" pod-one podman
}

function test_nomad_kind_lists_running_allocs() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" nomad)"
  _hi_has_row "$out" abc12345 nomad || return 1
  # the `nomad job status` header row must not become a target of its own
  ! printf '%s\n' "$out" | grep -q '^ID'
}

function test_kube_kind_lists_running_pods() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" kube)"
  _hi_has_row "$out" pod-a kube && _hi_has_row "$out" pod-b kube
}

function test_no_argument_lists_every_kind() {
  local out kind
  out="$(_hi_targets "$_HI_CONFIG")"
  _hi_has_row "$out" alpha ssh || return 1
  for kind in docker podman nomad kube; do
    printf '%s\n' "$out" | grep -q $'\t'"$kind\$" || return 1
  done
}

function test_unknown_kind_is_empty_and_succeeds() {
  local out
  out="$(_hi_targets "$_HI_CONFIG" not-a-backend)" || return 1
  [ -z "$out" ]
}

function test_absent_backends_leave_only_ssh_rows() {
  local out
  out="$(PATH="$_HI_TOOLBOX_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" sh "$_HI_TARGETS")" || return 1
  _hi_has_row "$out" alpha ssh || return 1
  ! printf '%s\n' "$out" | grep -qv $'\tssh$'
}

function run_targets_tests() {
  _hi_workdir targetstest

  _hi_h1 "Testing common/targets.sh"

  _hi_write_configs
  _hi_write_shims
  _hi_write_toolbox

  _hi_suite_begin

  _hi_h2 "Testing: ssh hosts"
  _hi_check "Multi-alias Host line -> one row per alias" test_multi_alias_host_yields_one_row_each
  _hi_check "Wildcard patterns skipped" test_wildcard_patterns_are_skipped
  _hi_check "Lowercase 'host' keyword matched" test_lowercase_host_keyword_is_matched
  _hi_check "Trailing comment isn't a host" test_trailing_comment_is_not_a_host
  _hi_check "Missing config -> empty, exit 0" test_missing_config_is_empty_and_succeeds
  _hi_check "'ssh' argument excludes other kinds" test_ssh_kind_excludes_container_backends

  _hi_h2 "Testing: container/orchestrator backends"
  _hi_check "docker -> running containers" test_docker_kind_lists_running_containers
  _hi_check "podman -> running containers" test_podman_kind_lists_running_containers
  _hi_check "nomad -> running allocs, no header row" test_nomad_kind_lists_running_allocs
  _hi_check "kube -> running pods" test_kube_kind_lists_running_pods

  _hi_h2 "Testing: argument handling"
  _hi_check "No argument -> every kind" test_no_argument_lists_every_kind
  _hi_check "Unknown argument -> empty, exit 0" test_unknown_kind_is_empty_and_succeeds
  _hi_check "No backends installed -> ssh rows only" test_absent_backends_leave_only_ssh_rows

  _hi_suite_end "targets.sh"
}

run_targets_tests
