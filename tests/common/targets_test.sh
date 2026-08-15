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

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
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
  # _HI_TARGETS_TTL=0 disables the result cache. Every case below changes what
  # the fake CLIs answer between runs, so a cached "all" would be handed
  # straight back to the next case and the shims it is meant to be exercising
  # would never run. The cache gets its own cases instead, further down.
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$config" _HI_TARGETS_TTL=0 sh "$_HI_TARGETS" "$@"
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

# --- the result cache -------------------------------------------------------
#
# 110ms of backend CLIs on every TAB is what this exists to avoid, so what
# matters is that a hit really does skip the backends. Each case gets its own
# XDG_RUNTIME_DIR so it starts from a cold cache and can't see another's.

function _hi_targets_cached() {
  local dir="$1" ttl="$2"
  shift 2
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    XDG_RUNTIME_DIR="$dir" _HI_TARGETS_TTL="$ttl" sh "$_HI_TARGETS" "$@"
}

function test_cache_reuses_the_first_answer() {
  local dir="$_HI_WORKDIR/cache-hit" shim="$_HI_WORKDIR/shims/docker" first second ok=0
  mkdir -p "$dir"
  first="$(_hi_targets_cached "$dir" 60 docker)"
  # take the shim away: a miss now produces nothing, a hit still has the rows,
  # which is the only way to prove the backend really wasn't run again
  mv "$shim" "$shim.aside"
  second="$(_hi_targets_cached "$dir" 60 docker)"
  mv "$shim.aside" "$shim"
  [ -n "$first" ] && [ "$first" = "$second" ] && ok=1
  [ "$ok" -eq 1 ]
}

function test_cache_is_bypassed_at_ttl_zero() {
  local dir="$_HI_WORKDIR/cache-off" out
  mkdir -p "$dir"
  printf '%s\nstale\tdocker\n' "$(date +%s)" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 0 docker)"
  ! printf '%s\n' "$out" | grep -qxF "stale"$'\t'"docker"
}

function test_cache_expires_with_its_ttl() {
  local dir="$_HI_WORKDIR/cache-stale" out
  mkdir -p "$dir"
  # stamped an hour ago, so any sane ttl has to treat it as a miss
  printf '%s\nstale\tdocker\n' "$(($(date +%s) - 3600))" >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 5 docker)"
  ! printf '%s\n' "$out" | grep -qxF "stale"$'\t'"docker"
}

# a hand-edited or truncated cache file must be re-derived, not printed
function test_cache_ignores_a_file_with_no_timestamp() {
  local dir="$_HI_WORKDIR/cache-junk" out
  mkdir -p "$dir"
  printf 'not-a-timestamp\nstale\tdocker\n' >"$dir/hi.targets.docker"
  out="$(_hi_targets_cached "$dir" 60 docker)"
  _hi_has_row "$out" alpha docker && ! printf '%s\n' "$out" | grep -qxF "stale"$'\t'"docker"
}

# the timestamp is bookkeeping, not a target - it must never reach completion
function test_cache_does_not_leak_its_timestamp() {
  local dir="$_HI_WORKDIR/cache-stamp" out
  mkdir -p "$dir"
  _hi_targets_cached "$dir" 60 docker >/dev/null
  out="$(_hi_targets_cached "$dir" 60 docker)"
  ! printf '%s\n' "$out" | grep -qE '^[0-9]+$'
}

function test_absent_backends_leave_only_ssh_rows() {
  local out
  out="$(PATH="$_HI_TOOLBOX_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" sh "$_HI_TARGETS")" || return 1
  _hi_has_row "$out" alpha ssh || return 1
  ! printf '%s\n' "$out" | grep -qv $'\tssh$'
}

# shells/bash.sh's completion function, the other half of this file's subject:
# the cases above prove targets.sh produces the right rows, these prove
# _hi_complete turns them into the right COMPREPLY. It reads $_HI_TARGETS,
# $COMP_WORDS and $COMP_CWORD, so all three are set here and the shimmed PATH
# gives it the same fixed backend list every other case sees.
# A child bash rather than a source into this one: shells/bash.sh is an
# interactive rc, and sourcing it here would drop its aliases (rm -iv, cp -rv)
# and readline binds on every case that runs after. The three toggles switch
# off everything except the completion itself, which sits outside all of them.
function _hi_completions_for() {
  PATH="$_HI_SHIM_PATH" _HI_SSH_CONFIG="$_HI_CONFIG" \
    _HI_DISABLE_ALIASES=1 _HI_DISABLE_PERSONAL=1 _HI_DISABLE_PROMPT=1 \
    bash -c '
      # shellcheck source=../../shells/bash.sh
      source "$_HI_BASHRC"
      COMP_WORDS=(hi "$1")
      COMP_CWORD=1
      COMPREPLY=()
      _hi_complete
      printf "%s\n" "${COMPREPLY[@]}"
    ' _ "$1"
}

function test_complete_offers_every_target() {
  local out
  out="$(_hi_completions_for "")"
  printf '%s\n' "$out" | grep -qx alpha &&
    printf '%s\n' "$out" | grep -qx pod-one &&
    printf '%s\n' "$out" | grep -qx abc12345
}

function test_complete_filters_by_the_typed_prefix() {
  local out
  out="$(_hi_completions_for pod-)"
  printf '%s\n' "$out" | grep -qx pod-one || return 1
  ! printf '%s\n' "$out" | grep -qx alpha
}

# targets.sh emits "<name>\t<kind>"; only the name is a completion, or every
# suggestion would arrive with a literal tab and its backend glued on
function test_complete_drops_the_kind_column() {
  ! _hi_completions_for "" | grep -q $'\t'
}

function test_complete_is_empty_for_an_unmatched_prefix() {
  [ -z "$(_hi_completions_for zzz-no-such-target)" ]
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

  _hi_h2 "Testing: the result cache"
  _hi_check "A hit skips the backend entirely" test_cache_reuses_the_first_answer
  _hi_check "TTL 0 bypasses it" test_cache_is_bypassed_at_ttl_zero
  _hi_check "An expired entry is re-derived" test_cache_expires_with_its_ttl
  _hi_check "A file with no timestamp is re-derived" test_cache_ignores_a_file_with_no_timestamp
  _hi_check "The timestamp never reaches completion" test_cache_does_not_leak_its_timestamp

  _hi_h2 "Testing: shells/bash.sh's _hi_complete"
  _hi_check "Offers every target" test_complete_offers_every_target
  _hi_check "Filters by the typed prefix" test_complete_filters_by_the_typed_prefix
  _hi_check "Drops the kind column" test_complete_drops_the_kind_column
  _hi_check "Empty for an unmatched prefix" test_complete_is_empty_for_an_unmatched_prefix

  _hi_suite_end "targets.sh"
}

run_targets_tests
