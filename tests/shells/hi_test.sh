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

# load.sh sets `-euo pipefail` at source time and only load() clears it, but
# the $CMDARG shape replaces load() outright - so the bootloader has to clear
# it itself or the user's command runs with an unset variable being fatal and
# any non-zero status ending the session. That killed `source $_HI_ALIASES` on
# any target without explicit toggles, which is the default.
function test_bootloader_drops_strict_mode_before_the_command() {
  local out strict cmd
  out="$(CMDARG='echo hi' _hi_bootloader)"
  strict="$(printf '%s\n' "$out" | grep -n 'set +euo pipefail' | head -1 | cut -d: -f1)"
  cmd="$(printf '%s\n' "$out" | grep -n 'echo hi' | head -1 | cut -d: -f1)"
  [ -n "$strict" ] && [ -n "$cmd" ] && [ "$strict" -lt "$cmd" ]
}

# ...and the strict-mode reset must land after load.sh is sourced, not before,
# or it's simply overwritten by load.sh's own `set -euo pipefail`
function test_bootloader_drops_strict_mode_after_sourcing_load() {
  local out src strict
  out="$(CMDARG='echo hi' _hi_bootloader)"
  src="$(printf '%s\n' "$out" | grep -n 'load\.sh' | head -1 | cut -d: -f1)"
  strict="$(printf '%s\n' "$out" | grep -n 'set +euo pipefail' | head -1 | cut -d: -f1)"
  [ -n "$src" ] && [ -n "$strict" ] && [ "$src" -lt "$strict" ]
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

# the no-bash target is one of the four entry points that has to source the
# settings ahead of paths.sh - paths.sh's local-only gate reads them, so lines
# arriving after it would be set too late to have any effect
function test_fallback_rc_sources_settings_before_paths() {
  local out settings_line paths_line
  out="$(CMDARG="" _hi_fallback_rc)"
  settings_line="$(printf '%s\n' "$out" | grep -n 'misc/settings\.sh' | head -1 | cut -d: -f1)"
  paths_line="$(printf '%s\n' "$out" | grep -n 'common/paths\.sh' | head -1 | cut -d: -f1)"
  [ -n "$settings_line" ] && [ -n "$paths_line" ] && [ "$settings_line" -lt "$paths_line" ]
}

# bash reads an --rcfile only when it is interactive, and decides that from its
# own stdin rather than the flag - so without the explicit -i, a target reached
# with no local tty (`ssh -t` can't allocate one then) silently ignores
# hi.bashrc, taking load.sh and $CMDARG with it, and `hi <target> <command>`
# from a script or a pipe does nothing at all while still exiting 0.
# The flag order is part of the assertion, not incidental: bash parses its GNU
# long options in a pass that ends at the first short one, so `bash -i --rcfile
# f` exits with "--: invalid option" and no shell at all.
# $hi_esc/$nc_esc/$DOMAIN are _say_hi's locals, supplied here because this file
# runs under `set -u`.
function test_remote_suffix_forces_an_interactive_bash() {
  # shellcheck disable=SC2016 # $_hi_rc_dir is the target's to expand, not ours
  [[ "$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)" == *'bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'* ]]
}

# the mirror of the above: every fallback shell already starts explicitly
# interactive, which is why they kept working when the bash arm didn't
function test_remote_suffix_fallbacks_are_interactive() {
  local out
  out="$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)"
  [[ "$out" == *'zsh -i'* && "$out" == *'sh -i'* && "$out" == *'fish -C'* ]]
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

# --- the config overlay -----------------------------------------------------
#
# $_HI_EXCLUDE only ever carried the *in-tree* misc/, so once the user's real
# settings/colors/packages live outside the tree they need their own stream or a
# target silently falls back to the shipped defaults. These assert the two
# halves that can be checked without a target: that nothing is sent when there
# is nothing to send, and that what is sent lands under the names paths.sh
# looks for.

function _hi_overlay_fixture() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  shift
  for f in "$@"; do printf 'x\n' >"$dir/$f"; done
  printf '%s' "$dir"
}

function test_overlay_is_empty_without_one() {
  local dir="$_HI_WORKDIR/no-overlay"
  mkdir -p "$dir"
  ! (_HI_CONFIG_DIR="$dir" _hi_has_overlay) &&
    [ -z "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar)" ]
}

function test_overlay_is_seen_when_present() {
  local dir
  dir="$(_hi_overlay_fixture some colors)"
  (_HI_CONFIG_DIR="$dir" _hi_has_overlay)
}

# members land at the archive's top level under their plain names, since it is
# unpacked *over* the target's misc/ - a "colors" that arrived as "hi.d/colors"
# or "./config/colors" would be invisible to paths.sh
function test_overlay_tar_members_are_bare_names() {
  local dir listing
  dir="$(_hi_overlay_fixture members colors packages settings.sh)"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  [ "$(printf '%s\n' "$listing" | sort | paste -sd, -)" = "colors,packages,settings.sh" ]
}

# only what the user actually has - an overlay holding one file must not carry
# a placeholder for the other two, which would shadow the tree's defaults
function test_overlay_tar_carries_only_what_exists() {
  local dir
  dir="$(_hi_overlay_fixture partial colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "colors" ]
}

# On a target, $_HI_CONFIG_DIR is the misc/ we just unpacked over, not
# ${XDG_CONFIG_HOME:-...}: a ~/.config/hi.d belonging to whoever we logged in as
# is not the config this session was asked to run with.
function test_fallback_rc_points_config_dir_at_the_shipped_tree() {
  # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand, not ours
  [[ "$(CMDARG="" _hi_fallback_rc)" == *'export _HI_CONFIG_DIR=$_HI_ROOT/misc'* ]]
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
  _hi_check "Bootloader drops strict mode before the command" test_bootloader_drops_strict_mode_before_the_command
  _hi_check "Bootloader drops strict mode after sourcing load.sh" test_bootloader_drops_strict_mode_after_sourcing_load
  _hi_check "Fallback rc sources paths and aliases" test_fallback_rc_sources_paths_and_aliases
  _hi_check "Fallback rc appends the command" test_fallback_rc_appends_the_command
  _hi_check "Fallback rc sources settings before paths" test_fallback_rc_sources_settings_before_paths

  _hi_h2 "Testing: remote shell handoff"
  _hi_check "The bash handoff is explicitly interactive" test_remote_suffix_forces_an_interactive_bash
  _hi_check "So is every no-bash fallback" test_remote_suffix_fallbacks_are_interactive

  _hi_h2 "Testing: payload excludes"
  _hi_check "Still strips .git/scripts/tests/hi.sh" test_exclude_list_covers_the_untravelled_paths

  _hi_h2 "Testing: the config overlay stream"
  _hi_check "Nothing sent without an overlay" test_overlay_is_empty_without_one
  _hi_check "Seen when present" test_overlay_is_seen_when_present
  _hi_check "Members are bare names" test_overlay_tar_members_are_bare_names
  _hi_check "Carries only what exists" test_overlay_tar_carries_only_what_exists
  _hi_check "Fallback rc points at the shipped tree" test_fallback_rc_points_config_dir_at_the_shipped_tree

  _hi_suite_end "hi.sh"
}

run_hi_tests
