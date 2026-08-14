#!/bin/bash
# Unit tests for hi.sh - the client entry point.
#
# hi.sh is only ever *executed*, so it ends with the same `[[ BASH_SOURCE ==
# $0 ]] || return 0` hatch scripts/install.sh and scripts/uninstall.sh use:
# sourcing it here defines every function without connecting to anything.
#
# What that leaves reachable is the pure half of the file - argument parsing,
# the backend predicates, and the heredoc generators - none of which the e2e
# suites can pin down, since there a mis-parse surfaces only as a confusing
# connection failure. _say_hi/_say_hi_container stay e2e-only by nature.
#
# The predicates run against fake docker/podman/nomad/kubectl CLIs on $PATH
# (same approach as targets_test.sh), so their answers are fixed rather than
# "whatever this machine is running".
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see. SC2317 rides along for the same
# reason once more: shellcheck follows the `source "$_HI_LAUNCHER"` below into
# hi.sh's trailing `_hi "$@"`, decides that call never returns, and marks this
# whole file unreachable - it doesn't model the BASH_SOURCE guard above it.
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

_HI_SHIM_PATH=""

# Each shim answers only the exact invocation hi.sh makes and fails anything
# else, so a changed command shape shows up as a failing predicate rather than
# a silently passing test. "yes" is running/Running, "no" is not.
function _hi_write_shims() {
  local dir="$_HI_WORKDIR/shims"
  mkdir -p "$dir"

  cat >"$dir/docker" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "container inspect -f" ] || exit 1
case "$5" in yes) printf 'true\n' ;; *) printf 'false\n' ;; esac
EOF

  cat >"$dir/podman" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "container inspect -f" ] || exit 1
case "$5" in yes) printf 'true\n' ;; *) printf 'false\n' ;; esac
EOF

  cat >"$dir/nomad" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "alloc status -t" ] || exit 1
case "$5" in yes) printf 'running\n' ;; *) printf 'pending\n' ;; esac
EOF

  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
[ "$1 $2 $4" = "get pod -o" ] || exit 1
case "$3" in yes) printf 'Running\n' ;; *) printf 'Pending\n' ;; esac
EOF

  chmod +x "$dir"/*
  _HI_SHIM_PATH="$dir:$PATH"
}

# _hi_parse writes to the globals DOMAIN/CMDARG/SSHARGS and can exit outright,
# so every case runs it in a subshell and prints what it produced. Fields are
# newline-separated: DOMAIN, CMDARG, then one line per SSHARGS entry.
function _hi_parse_out() {
  (
    unset DOMAIN CMDARG
    _hi_parse "$@" >/dev/null 2>&1
    printf '%s\n%s\n' "${DOMAIN:-}" "${CMDARG:-}"
    [ "${#SSHARGS[@]}" -eq 0 ] || printf '%s\n' "${SSHARGS[@]}"
  )
}

function test_parse_takes_a_bare_target() {
  [ "$(_hi_parse_out myhost)" = "$(printf 'myhost\n\n')" ]
}

function test_parse_keeps_valueless_flags() {
  [ "$(_hi_parse_out -v myhost)" = "$(printf 'myhost\n\n-v\n')" ]
}

function test_parse_pairs_a_flag_with_its_value() {
  [ "$(_hi_parse_out -p 2222 myhost)" = "$(printf 'myhost\n\n-p\n2222\n')" ]
}

# the regression this list exists for: -J takes a value, so without it in the
# case arm "bastion" becomes DOMAIN and hi connects to the wrong machine
function test_parse_treats_jump_host_as_a_value_not_the_target() {
  [ "$(_hi_parse_out -J bastion myhost)" = "$(printf 'myhost\n\n-J\nbastion\n')" ]
}

function test_parse_treats_bind_interface_as_a_value_not_the_target() {
  [ "$(_hi_parse_out -B eth0 myhost)" = "$(printf 'myhost\n\n-B\neth0\n')" ]
}

function test_parse_handles_several_flags_before_the_target() {
  [ "$(_hi_parse_out -4 -o StrictHostKeyChecking=no -i /tmp/k myhost)" = \
    "$(printf 'myhost\n\n-4\n-o\nStrictHostKeyChecking=no\n-i\n/tmp/k\n')" ]
}

# a trailing command becomes CMDARG - suffixed with "; exit" so the target
# shell closes after it - and never a second target. The spacing between the
# two is incidental (_hi_parse pastes '; ' and ' exit'), so don't pin it.
function test_parse_turns_trailing_words_into_a_command() {
  local out
  out="$(_hi_parse_out myhost echo hello)"
  [[ "$out" == myhost*"echo hello;"*exit* ]]
}

function test_parse_leaves_cmdarg_empty_for_a_plain_session() {
  [ "$(_hi_parse_out myhost | sed -n 2p)" = "" ]
}

# a value-taking flag with nothing after it must report itself, not die on an
# unbound $2 or swallow the next argument
function test_parse_rejects_a_flag_missing_its_value() {
  local rc=0
  (_hi_parse -p >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ]
}

function test_parse_names_the_offending_flag() {
  local out
  out="$( (_hi_parse -o 2>&1 >/dev/null) || true)"
  [[ "$out" == *"-o"* ]]
}

function test_is_docker_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_docker_container yes
}

function test_is_docker_container_rejects_a_stopped_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_docker_container no
}

function test_is_podman_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_podman_container yes
}

function test_is_nomad_alloc_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc yes
}

function test_is_nomad_alloc_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc no
}

function test_is_k8s_pod_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod yes
}

function test_is_k8s_pod_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod no
}

# with no backend CLI on $PATH at all, every predicate must answer "no"
# rather than erroring - that is what lets _hi fall through to ssh
function test_predicates_are_false_without_their_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  ! PATH="$empty" _hi_is_docker_container yes &&
    ! PATH="$empty" _hi_is_podman_container yes &&
    ! PATH="$empty" _hi_is_nomad_alloc yes &&
    ! PATH="$empty" _hi_is_k8s_pod yes
}

# an interactive session chainloads load.sh then calls load()
function test_bootloader_calls_load_for_a_session() {
  local out
  out="$(CMDARG="" _hi_bootloader)"
  # shellcheck disable=SC2016 # the rc must carry a literal $_HI_ROOT for the target to expand
  [[ "$out" == *'source $_HI_ROOT/load.sh'* && "$out" == *$'\nload'* ]]
}

# ...and a one-off command replaces that call outright, so load() - and with
# it the header, the rc grafting and clean_all - never runs
function test_bootloader_replaces_load_with_the_command() {
  local out
  out="$(CMDARG='echo hi; exit' _hi_bootloader)"
  [[ "$out" == *'echo hi; exit'* && "$out" != *$'\nload\n'* ]]
}

function test_fallback_rc_sources_paths_and_aliases() {
  local out
  out="$(CMDARG="" _hi_fallback_rc)"
  # shellcheck disable=SC2016 # same as above - $_HI_ROOT is the target's to expand
  [[ "$out" == *'$_HI_ROOT/common/paths.sh'* && "$out" == *'$_HI_ROOT/shells/aliases.sh'* ]]
}

function test_fallback_rc_appends_the_command() {
  [[ "$(CMDARG='echo hi; exit' _hi_fallback_rc)" == *'echo hi; exit'* ]]
}

# the payload excludes must keep stripping the things that make a shipped tree
# either broken (scripts/, tests/ - see paths.sh's helper aliases) or huge
function test_exclude_list_covers_the_untravelled_paths() {
  local want
  for want in .git scripts tests hi.sh; do
    [[ "${_HI_EXCLUDE[*]}" == *"$want"* ]] || {
      _hi_cecho " | not excluded from the payload: $want" "$RED"
      return 1
    }
  done
}

function run_hi_tests() {
  _hi_workdir hitest
  _hi_write_shims

  _hi_suite_begin

  _hi_h1 "Testing hi.sh"

  _hi_h2 "Testing: _hi_parse (targets and flags)"
  _hi_check "A bare target" test_parse_takes_a_bare_target
  _hi_check "Keeps valueless flags" test_parse_keeps_valueless_flags
  _hi_check "Pairs a flag with its value" test_parse_pairs_a_flag_with_its_value
  _hi_check "-J's value is not mistaken for the target" test_parse_treats_jump_host_as_a_value_not_the_target
  _hi_check "-B's value is not mistaken for the target" test_parse_treats_bind_interface_as_a_value_not_the_target
  _hi_check "Several flags before the target" test_parse_handles_several_flags_before_the_target

  _hi_h2 "Testing: _hi_parse (commands and errors)"
  _hi_check "Trailing words become a command" test_parse_turns_trailing_words_into_a_command
  _hi_check "A plain session has no command" test_parse_leaves_cmdarg_empty_for_a_plain_session
  _hi_check "Rejects a flag missing its value" test_parse_rejects_a_flag_missing_its_value
  _hi_check "Names the offending flag" test_parse_names_the_offending_flag

  _hi_h2 "Testing: backend predicates"
  _hi_check "docker: running" test_is_docker_container_accepts_a_running_one
  _hi_check "docker: stopped" test_is_docker_container_rejects_a_stopped_one
  _hi_check "podman: running" test_is_podman_container_accepts_a_running_one
  _hi_check "nomad: running" test_is_nomad_alloc_accepts_a_running_one
  _hi_check "nomad: pending" test_is_nomad_alloc_rejects_a_pending_one
  _hi_check "kube: running" test_is_k8s_pod_accepts_a_running_one
  _hi_check "kube: pending" test_is_k8s_pod_rejects_a_pending_one
  _hi_check "All false with no CLI installed" test_predicates_are_false_without_their_cli

  _hi_h2 "Testing: bootloader / fallback rc"
  _hi_check "A session calls load" test_bootloader_calls_load_for_a_session
  _hi_check "A command replaces load" test_bootloader_replaces_load_with_the_command
  _hi_check "Fallback rc sources paths and aliases" test_fallback_rc_sources_paths_and_aliases
  _hi_check "Fallback rc appends the command" test_fallback_rc_appends_the_command

  _hi_h2 "Testing: payload excludes"
  _hi_check "Still strips .git/scripts/tests/hi.sh" test_exclude_list_covers_the_untravelled_paths

  _hi_suite_end "hi.sh"
}

run_hi_tests
