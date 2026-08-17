#!/bin/bash
# Unit tests for tests/test_lib.sh - the scaffolding every other suite is built
# on, and so the one file whose bugs would be invisible: a broken _hi_case
# under-counts failures and every suite still looks green. Covers the counters,
# the scratch-dir and container teardown, the skip-cleanly preamble, the
# target-side probe strings, and the polling/process helpers.
#
# Anything that exits or installs a trap runs in a subshell so it can't take
# this suite down, and $_HI_WORKDIR/$_HI_STARTED are saved around the cases that
# overwrite them - this suite uses the globals it is testing.
#
# Functions here are invoked indirectly (through "$@", or as a trap hook), which
# SC2329 can't see; the subshell containment above is the mechanism SC2030/2031
# would warn about.
# shellcheck disable=SC2329,SC2030,SC2031
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# runs "$@" with the counters sandboxed, so a case can call _hi_case/
# _hi_suite_begin freely without corrupting this suite's own tally
function _hi_sandboxed() {
  local saved_total="$_HI_TOTAL" saved_failed="$_HI_FAILED" rc=0
  "$@" || rc=$?
  _HI_TOTAL="$saved_total"
  _HI_FAILED="$saved_failed"
  return "$rc"
}

function _hi_true() { return 0; }
function _hi_false() { return 1; }

function test_case_counts_a_pass() {
  _hi_suite_begin
  _hi_case _hi_true
  [ "$_HI_TOTAL" -eq 1 ] && [ "$_HI_FAILED" -eq 0 ]
}

function test_case_counts_a_failure() {
  _hi_suite_begin
  _hi_case _hi_false
  [ "$_HI_TOTAL" -eq 1 ] && [ "$_HI_FAILED" -eq 1 ]
}

function test_case_keeps_running_after_a_failure() {
  _hi_suite_begin
  _hi_case _hi_false
  _hi_case _hi_true
  _hi_case _hi_false
  [ "$_HI_TOTAL" -eq 3 ] && [ "$_HI_FAILED" -eq 2 ]
}

function test_assert_passes_through_arguments() {
  local out
  out="$(_hi_assert "with args" test 1 -eq 1)"
  [[ "$out" == *"with args: OK"* ]]
}

function test_assert_reports_ok_and_returns_zero() {
  local out
  out="$(_hi_assert "some label" _hi_true)"
  [[ "$out" == *"some label: OK"* ]]
}

function test_assert_reports_failed_and_returns_nonzero() {
  local out rc=0
  out="$(_hi_assert "some label" _hi_false)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"some label: FAILED"* ]]
}

function test_check_counts_and_labels_in_one_call() {
  _hi_suite_begin
  _hi_check "a failing check" _hi_false >/dev/null
  [ "$_HI_TOTAL" -eq 1 ] && [ "$_HI_FAILED" -eq 1 ]
}

function test_suite_begin_zeroes_both_counters() {
  _HI_TOTAL=7
  _HI_FAILED=3
  _hi_suite_begin
  [ "$_HI_TOTAL" -eq 0 ] && [ "$_HI_FAILED" -eq 0 ]
}

function test_suite_end_exits_zero_when_nothing_failed() {
  (
    _HI_TOTAL=4
    _HI_FAILED=0
    _hi_suite_end thing >/dev/null
  )
}

function test_suite_end_exits_with_the_failure_count() {
  local rc=0
  (
    _HI_TOTAL=5
    _HI_FAILED=3
    _hi_suite_end thing >/dev/null
  ) || rc=$?
  [ "$rc" -eq 3 ]
}

function test_suite_end_default_wording_uses_the_subject() {
  local out
  out="$(
    _HI_TOTAL=2
    _HI_FAILED=0
    _hi_suite_end "check.sh"
  )"
  [[ "$out" == *"All check.sh checks passed (2 cases)"* ]]
}

function test_suite_end_default_failure_wording_shows_the_ratio() {
  local out
  out="$(
    _HI_TOTAL=5
    _HI_FAILED=2
    _hi_suite_end "check.sh"
  )" || true
  [[ "$out" == *"2/5 check.sh checks FAILED"* ]]
}

function test_suite_end_honours_custom_banners() {
  local pass fail
  pass="$(
    _HI_TOTAL=1
    _HI_FAILED=0
    _hi_suite_end "" "custom pass line" "custom fail line"
  )"
  fail="$(
    _HI_TOTAL=1
    _HI_FAILED=1
    _hi_suite_end "" "custom pass line" "custom fail line"
  )" || true
  [[ "$pass" == *"custom pass line"* && "$fail" == *"custom fail line"* ]]
}

function test_report_counts_writes_total_and_failed() {
  local file
  file="$_HI_WORKDIR/counts.reported"
  (
    _HI_COUNTS_FILE="$file"
    _hi_report_counts 9 2
  )
  [ "$(cat "$file")" = "9 2 0" ]
}

function test_report_counts_writes_the_skip_tally() {
  local file
  file="$_HI_WORKDIR/counts.skiptally"
  (
    _HI_COUNTS_FILE="$file"
    _hi_report_counts 9 2 3
  )
  [ "$(cat "$file")" = "9 2 3" ]
}

function test_note_failure_appends_the_label() {
  local file
  file="$_HI_WORKDIR/fails.noted"
  (
    _HI_FAILS_FILE="$file"
    _hi_note_failure "first case"
    _hi_note_failure "second case"
  )
  [ "$(cat "$file")" = "first case
second case" ]
}

function test_note_failure_is_a_noop_without_a_fails_file() {
  (
    unset _HI_FAILS_FILE
    _hi_note_failure "nobody listening"
  )
}

# run standalone (no runner above it) the helper must do nothing at all,
# rather than erroring on an unset path
function test_report_counts_is_a_noop_without_a_counts_file() {
  (
    unset _HI_COUNTS_FILE
    _hi_report_counts 1 0
  )
}

function test_report_skip_marks_the_suite_as_skipped() {
  local file
  file="$_HI_WORKDIR/counts.skipped"
  (
    _HI_COUNTS_FILE="$file"
    _hi_report_skip "no docker"
  )
  [ "$(cat "$file")" = "SKIP no docker" ]
}

function test_report_skip_is_a_noop_without_a_counts_file() {
  (
    unset _HI_COUNTS_FILE
    _hi_report_skip "no docker"
  )
}

# _hi_require's skip path has to reach the runner, or a suite that never ran
# a case still renders as a green PASS - the whole point of the status
function test_require_reports_a_skip_for_a_missing_binary() {
  local file
  file="$_HI_WORKDIR/counts.require"
  (
    _HI_COUNTS_FILE="$file"
    _hi_require definitely-not-a-real-binary >/dev/null 2>&1
  ) || true
  [[ "$(cat "$file")" == SKIP* ]]
}

# the counter has to be bumped in the *caller's* shell, so the output goes to
# a file rather than through $(...) - a command substitution would run
# _hi_skip in a subshell and lose the increment it is meant to prove
function test_skip_counts_the_case_without_passing_it() {
  local out file="$_HI_WORKDIR/skip.out"
  local _HI_SKIPPED=0
  _hi_skip "[case]" "no python3" >"$file"
  out="$(cat "$file")"
  [ "$_HI_SKIPPED" -eq 1 ] && [[ "$out" == *SKIPPED* ]] && [[ "$out" == *"no python3"* ]]
}

function test_suite_end_names_the_skipped_cases() {
  local out
  out="$(
    _HI_TOTAL=3
    _HI_FAILED=0
    _HI_SKIPPED=2
    _hi_suite_end demo
  )" || true
  [[ "$out" == *"3 cases, 2 skipped"* ]]
}

function test_suite_end_stays_quiet_with_nothing_skipped() {
  local out
  out="$(
    _HI_TOTAL=3
    _HI_FAILED=0
    _HI_SKIPPED=0
    _hi_suite_end demo
  )" || true
  [[ "$out" == *"3 cases)"* ]] && [[ "$out" != *skipped* ]]
}

function test_suite_end_reports_its_counts() {
  local file
  file="$_HI_WORKDIR/counts.suite_end"
  (
    _HI_COUNTS_FILE="$file"
    _HI_TOTAL=5
    _HI_FAILED=2
    _HI_SKIPPED=1
    _hi_suite_end thing >/dev/null
  ) || true
  [ "$(cat "$file")" = "5 2 1" ]
}

function test_workdir_creates_a_scratch_dir() {
  local dir
  dir="$(
    _hi_workdir probe
    printf '%s' "$_HI_WORKDIR"
  )"
  # the subshell's exit trap already removed it, which is the other half of
  # the contract - so assert on the shape and on its being gone
  [[ "$dir" == */hi.probe.* ]] && [ ! -d "$dir" ]
}

function test_test_cleanup_runs_the_extra_hook_first() {
  local marker="$_HI_WORKDIR/hook-ran"
  (
    _HI_WORKDIR="$(mktemp -d "$_HI_WORKDIR/inner.XXXXXX")"
    _HI_STARTED=()
    # shellcheck disable=SC2317 # invoked by _hi_test_cleanup through $_HI_EXTRA_CLEANUP
    function _hi_probe_hook() { : >"$marker"; }
    _HI_EXTRA_CLEANUP=_hi_probe_hook
    _hi_test_cleanup
  )
  [ -f "$marker" ]
}

function test_test_cleanup_removes_the_workdir_even_if_the_hook_fails() {
  local inner
  inner="$(mktemp -d "$_HI_WORKDIR/inner.XXXXXX")"
  (
    _HI_WORKDIR="$inner"
    _HI_STARTED=()
    _HI_EXTRA_CLEANUP=_hi_false
    _hi_test_cleanup
  )
  [ ! -d "$inner" ]
}

function test_track_container_appends_to_the_teardown_list() {
  (
    _HI_STARTED=()
    _hi_track_container one
    _hi_track_container two
    [ "${#_HI_STARTED[@]}" -eq 2 ] && [ "${_HI_STARTED[0]}" = one ] && [ "${_HI_STARTED[1]}" = two ]
  )
}

function test_require_returns_for_an_installed_command() {
  (_hi_require sh)
}

function test_require_exits_zero_and_warns_when_missing() {
  local out rc=0
  out="$( (_hi_require definitely-not-a-real-hi-test-command-xyz))" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"not installed, skipping"* ]]
}

function test_require_uses_a_custom_reason() {
  local out
  out="$( (_hi_require definitely-not-a-real-hi-test-command-xyz "unavailable here"))"
  [[ "$out" == *"unavailable here, skipping"* ]]
}

function test_require_backend_skips_when_the_cli_is_missing() {
  local out rc=0
  out="$( (_hi_require_backend definitely-not-a-real-hi-test-command-xyz))" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"skipping"* ]]
}

function test_require_backend_skips_when_the_backend_is_unreachable() {
  local fake="$_HI_WORKDIR/bin" out rc=0
  mkdir -p "$fake"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$fake/hi-fake-backend"
  chmod +x "$fake/hi-fake-backend"
  out="$(PATH="$fake:$PATH" bash -c 'source "$_HI_TEST_LIB"; _hi_require_backend hi-fake-backend')" || rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *"not reachable, skipping"* ]]
}

function _hi_probe_fixture() {
  local root="$1/hi.d"
  mkdir -p "$root"
  : >"$root/hi.sh"
  printf '%s\n' "alias hi_info='echo hi_info'" "alias sudo='command sudo '" >"$root/aliases.sh"
  printf '%s' "$root"
}

function _hi_probe_says_ok() {
  local shape="$1" prelude="$2" root_override="${3:-}" shell="${4:-bash}" home root out
  home="$(mktemp -d "$_HI_WORKDIR/probe.XXXXXX")"
  root="$(_hi_probe_fixture "$home")"
  out="$(HOME="$home" _HI_ROOT="${root_override:-$root}" _HI_ALIASES="$root/aliases.sh" \
    "$shell" -c "$prelude$(_hi_probe_cmd MARK "$shape")" 2>/dev/null)" || true
  [[ "$out" == *MARK* ]]
}

function test_probe_cmd_bash_shape_fires_only_with_a_real_root() {
  _hi_probe_says_ok bash "" &&
    ! _hi_probe_says_ok bash "" /nonexistent/hi.d
}

function test_probe_cmd_fallback_shape_fires_only_with_the_alias() {
  _hi_probe_says_ok fallback "alias sudo='x'; " &&
    ! _hi_probe_says_ok fallback ""
}

function test_probe_cmd_ssh_fallback_fires_only_with_hi_info() {
  _hi_probe_says_ok ssh_fallback "alias hi_info='x'; " &&
    ! _hi_probe_says_ok ssh_fallback "alias hi_info='x'; " /nonexistent/hi.d
}

function test_probe_cmd_installed_shape_fires_only_when_root_is_home() {
  _hi_probe_says_ok installed "" &&
    ! _hi_probe_says_ok installed "" /somewhere/else/hi.d
}

function test_probe_cmd_fish_shapes_run_under_fish() {
  command -v fish >/dev/null 2>&1 || return 0
  _hi_probe_says_ok fallback_fish "function sudo; end; " "" fish &&
    ! _hi_probe_says_ok fallback_fish "" "" fish &&
    _hi_probe_says_ok ssh_fallback_fish "function hi_info; end; " "" fish &&
    ! _hi_probe_says_ok ssh_fallback_fish "function hi_info; end; " /nonexistent/hi.d fish
}

# --- _hi_host_report ---------------------------------------------------------
#
# $_HI_ROOT is read at call time, so a case can point the tree check anywhere
# from inside a subshell without disturbing this suite's own environment.

function _hi_host_report_out() {
  _hi_host_report "${1:-$_HI_ROOT}" 2>&1
}

function test_host_report_names_this_bash_and_kernel() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *"$BASH_VERSION"* ]] && [[ "$out" == *"$(uname -s)"* ]]
}

function test_host_report_carries_the_tree_variables() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *"$_HI_HOME"* ]] && [[ "$out" == *"$_HI_ROOT"* ]]
}

function test_host_report_agrees_when_the_tree_matches() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *"the tree this run came from"* ]] &&
    [[ "$out" != *"another checkout"* ]]
}

# The reference is captured before the subshell moves $_HI_ROOT: written as an
# `_HI_ROOT=x _hi_host_tree_check "$_HI_ROOT"` prefix instead, the argument
# would expand to the *new* value and the two would agree again.
function test_host_report_warns_when_the_tree_differs() {
  local out ref="$_HI_ROOT"
  out="$(
    _HI_ROOT="$_HI_WORKDIR"
    _hi_host_report "$ref" 2>&1
  )"
  # both paths named: which tree ran, and which one it should have been
  [[ "$out" == *"another checkout"* ]] &&
    [[ "$out" == *"$_HI_WORKDIR"* ]] && [[ "$out" == *"$ref"* ]]
}

function test_host_tree_check_is_silent_and_zero_when_it_agrees() {
  local out rc=0
  out="$(_hi_host_tree_check "$_HI_ROOT" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && [ -z "$out" ]
}

function test_host_tree_check_returns_one_when_it_differs() {
  local rc=0 ref="$_HI_ROOT"
  (
    _HI_ROOT="$_HI_WORKDIR"
    _hi_host_tree_check "$ref"
  ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
}

function test_host_report_lists_the_lint_tools() {
  local out
  out="$(_hi_host_report_out)"
  [[ "$out" == *shellcheck* ]] && [[ "$out" == *shfmt* ]] && [[ "$out" == *checkbashisms* ]]
}

# The report is a debug aid: a host so stripped that not one probe resolves
# still has to get a block, and the run must survive it. An empty PATH is the
# cheapest way to be that host.
function test_host_report_survives_an_empty_path() {
  local rc=0
  (
    # shellcheck disable=SC2123 # emptying the search path is the case
    PATH=""
    _hi_host_report "$_HI_ROOT"
  ) >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
}

function test_host_report_marks_absent_tools_absent() {
  local out
  out="$(
    # shellcheck disable=SC2123 # emptying the search path is the case
    PATH=""
    _hi_host_report "$_HI_ROOT" 2>&1
  )"
  [[ "$out" == *"shellcheck (absent)"* ]] && [[ "$out" == *"docker: absent"* ]]
}

function test_tool_version_reports_a_number_for_a_real_tool() {
  [[ "$(_hi_tool_version bash)" =~ ^bash\ [0-9]+\.[0-9]+ ]]
}

function test_tool_version_says_absent_rather_than_failing() {
  local rc=0 out
  out="$(_hi_tool_version definitely-not-a-real-binary)" || rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "definitely-not-a-real-binary (absent)" ]
}

function test_probe_cmd_rejects_an_unknown_shape() {
  local rc=0
  _hi_probe_cmd MARK not-a-shape >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ]
}

function test_probe_cmd_every_shape_ends_with_the_marker() {
  local shape
  for shape in bash fallback fallback_fish ssh_fallback ssh_fallback_fish installed; do
    [[ "$(_hi_probe_cmd HI_MARKER_XYZ "$shape")" == *"HI_MARKER_XYZ" ]] || return 1
  done
}

function test_poll_bool_returns_zero_when_already_true() {
  _hi_poll_bool 3 0.01 _hi_true
}

function test_poll_bool_returns_one_when_never_true() {
  ! _hi_poll_bool 2 0.01 _hi_false
}

function test_poll_bool_succeeds_on_a_later_attempt() {
  local counter="$_HI_WORKDIR/poll-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_bool through "$@"
  function _hi_third_time_lucky() {
    printf 'x' >>"$counter"
    [ "$(wc -c <"$counter")" -ge 3 ]
  }
  _hi_poll_bool 10 0.01 _hi_third_time_lucky && [ "$(wc -c <"$counter")" -eq 3 ]
}

function test_poll_bool_passes_arguments_through() {
  _hi_poll_bool 2 0.01 test foo = foo && ! _hi_poll_bool 2 0.01 test foo = bar
}

function test_poll_bool_abort_predicate_stops_early() {
  local counter="$_HI_WORKDIR/abort-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_bool through "$@"
  function _hi_never_true() {
    printf 'x' >>"$counter"
    return 1
  }
  _hi_poll_bool -a _hi_false 50 0.01 _hi_never_true && return 1
  [ "$(wc -c <"$counter")" -eq 1 ]
}

function test_poll_bool_abort_predicate_does_not_block_success() {
  _hi_poll_bool -a _hi_true 3 0.01 _hi_true
}

function test_poll_bool_stops_at_the_wall_clock_budget() {
  local counter="$_HI_WORKDIR/slow-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_bool through "$@"
  function _hi_slow_false() {
    printf 'x' >>"$counter"
    sleep 0.3
    return 1
  }
  _hi_poll_bool 100 0.01 _hi_slow_false && return 1
  [ "$(wc -c <"$counter")" -lt 20 ]
}

function test_poll_value_prints_the_value_it_found() {
  local out
  out="$(_hi_poll_value 3 0.01 printf 'alloc-id')"
  [ "$out" = "alloc-id" ]
}

function test_poll_value_fails_when_output_stays_empty() {
  ! _hi_poll_value 2 0.01 true
}

function test_poll_value_keeps_polling_past_empty_output() {
  local counter="$_HI_WORKDIR/value-count"
  : >"$counter"
  # shellcheck disable=SC2317 # invoked by _hi_poll_value through "$@"
  function _hi_late_value() {
    printf 'x' >>"$counter"
    [ "$(wc -c <"$counter")" -ge 2 ] && printf 'ready'
    return 0
  }
  [ "$(_hi_poll_value 10 0.01 _hi_late_value)" = ready ]
}

function test_wait_pid_reports_a_clean_exit() {
  sleep 0.05 &
  _hi_wait_pid "$!" 5
  [ "$_HI_WAIT_EXIT" -eq 0 ]
}

function test_wait_pid_reports_the_real_exit_code() {
  bash -c 'exit 7' &
  _hi_wait_pid "$!" 5
  [ "$_HI_WAIT_EXIT" -eq 7 ]
}

# 124 is the timeout convention (same as timeout(1)); the process must
# actually be gone afterwards, or a hung launcher would outlive the suite
function test_wait_pid_kills_and_reports_124_on_timeout() {
  local pid
  sleep 30 &
  pid=$!
  _hi_wait_pid "$pid" 1
  [ "$_HI_WAIT_EXIT" -eq 124 ] && ! kill -0 "$pid" 2>/dev/null
}

function test_wait_pid_runs_the_timeout_hook_before_killing() {
  local marker="$_HI_WORKDIR/timeout-hook"
  rm -f "$marker"
  # shellcheck disable=SC2317 # invoked by _hi_wait_pid through "$@"
  function _hi_probe_timeout_hook() { : >"$marker"; }
  sleep 30 &
  _hi_wait_pid "$!" 1 _hi_probe_timeout_hook
  [ -f "$marker" ]
}

function test_wait_pid_skips_the_hook_on_a_clean_exit() {
  local marker="$_HI_WORKDIR/no-timeout-hook"
  rm -f "$marker"
  sleep 0.05 &
  _hi_wait_pid "$!" 5 _hi_probe_timeout_hook
  [ ! -f "$marker" ]
}

function test_pty_wrap_force_wraps_even_on_a_tty() {
  _hi_pty_wrap 0 force "no python3" >/dev/null
  if command -v python3 >/dev/null 2>&1; then
    [ "${#_HI_PTY_WRAP[@]}" -gt 0 ] && [ "${_HI_PTY_WRAP[0]}" = python3 ]
  else
    [ "${#_HI_PTY_WRAP[@]}" -eq 0 ]
  fi
}

function test_pty_wrap_auto_leaves_a_real_tty_alone() {
  _hi_pty_wrap 0 auto "no python3" >/dev/null
  # Three environments, three right answers: a real tty needs no fake, no tty
  # gets one, and no tty *and* no python3 to build one with leaves it empty
  # (which is the warning path, not a failure).
  if [ -t 0 ] || ! command -v python3 >/dev/null 2>&1; then
    [ "${#_HI_PTY_WRAP[@]}" -eq 0 ]
  else
    [ "${#_HI_PTY_WRAP[@]}" -gt 0 ]
  fi
}

function test_pty_wrap_actually_allocates_a_pty() {
  command -v python3 >/dev/null 2>&1 || return 0 # nothing to assert without it
  _hi_pty_wrap 0 force "no python3" >/dev/null
  [ "${#_HI_PTY_WRAP[@]}" -gt 0 ] || return 0
  # `test -t 0` inside the wrapper is the whole point: it must see a terminal
  ${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} sh -c 'test -t 0' >/dev/null 2>&1
}

function test_pty_wrap_resets_between_calls() {
  local first
  _hi_pty_wrap 0 force "no python3" >/dev/null
  first="${#_HI_PTY_WRAP[@]}"
  _hi_pty_wrap 0 force "no python3" >/dev/null
  [ "${#_HI_PTY_WRAP[@]}" -eq "$first" ]
}

function test_ssh_opts_never_touch_the_users_known_hosts() {
  local joined="${_HI_SSH_OPTS[*]}"
  [[ "$joined" == *"UserKnownHostsFile=/dev/null"* && "$joined" == *"StrictHostKeyChecking=no"* &&
    "$joined" == *"IdentitiesOnly=yes"* ]]
}

function test_sshd_entrypoint_body_passes_runtime_opts_to_sshd() {
  # shellcheck disable=SC2016 # matching literal text that expands on the target, not here
  [[ "$_HI_SSHD_ENTRYPOINT_BODY" == *'exec /usr/sbin/sshd'* && "$_HI_SSHD_ENTRYPOINT_BODY" == *'$SSHD_OPTS'* ]]
}

function test_sshd_entrypoint_body_unlocks_the_test_account() {
  # useradd/adduser -D leave the account locked and sshd refuses locked
  # accounts even for pubkey auth
  [[ "$_HI_SSHD_ENTRYPOINT_BODY" == *"chpasswd -e"* && "$_HI_SSHD_ENTRYPOINT_BODY" == *"authorized_keys"* ]]
}

function test_ssh_keypair_writes_a_usable_key() {
  command -v ssh-keygen >/dev/null 2>&1 || return 0
  (
    _HI_WORKDIR="$(mktemp -d "$_HI_WORKDIR/keys.XXXXXX")"
    _hi_ssh_keypair >/dev/null
    [ -f "$_HI_WORKDIR/id" ] && [ -f "$_HI_WORKDIR/id.pub" ] && [[ "$_HI_PUBKEY" == ssh-ed25519* ]]
  )
}

function test_ssh_reachable_fails_against_a_dead_port() {
  command -v ssh >/dev/null 2>&1 || return 0
  # port 1 has nothing listening; this must fail rather than hang or error
  # out. ssh's own "connection refused" is the expected noise, not a result -
  # _hi_poll_bool discards it the same way for real callers
  ! _hi_ssh_reachable 1 2>/dev/null
}
function run_test_lib_tests() {
  _hi_workdir testlibtest

  _hi_suite_begin

  _hi_h1 "Testing tests/test_lib.sh"

  _hi_h2 "Testing: _hi_case / _hi_assert / _hi_check"
  _hi_check "Counts a passing case" _hi_sandboxed test_case_counts_a_pass
  _hi_check "Counts a failing case" _hi_sandboxed test_case_counts_a_failure
  _hi_check "Keeps running after a failure" _hi_sandboxed test_case_keeps_running_after_a_failure
  _hi_check "Assert reports OK" test_assert_reports_ok_and_returns_zero
  _hi_check "Assert reports FAILED and returns non-zero" test_assert_reports_failed_and_returns_nonzero
  _hi_check "Assert forwards extra arguments" test_assert_passes_through_arguments
  _hi_check "Check counts and labels in one call" _hi_sandboxed test_check_counts_and_labels_in_one_call

  _hi_h2 "Testing: _hi_suite_begin / _hi_suite_end"
  _hi_check "Begin zeroes both counters" _hi_sandboxed test_suite_begin_zeroes_both_counters
  _hi_check "End exits 0 when nothing failed" test_suite_end_exits_zero_when_nothing_failed
  _hi_check "End exits with the failure count" test_suite_end_exits_with_the_failure_count
  _hi_check "End's default pass wording uses the subject" test_suite_end_default_wording_uses_the_subject
  _hi_check "End's default failure wording shows the ratio" test_suite_end_default_failure_wording_shows_the_ratio
  _hi_check "End honours custom banners" test_suite_end_honours_custom_banners

  _hi_h2 "Testing: _hi_report_counts / _hi_note_failure"
  _hi_check "Writes total and failed" test_report_counts_writes_total_and_failed
  _hi_check "Writes the skip tally" test_report_counts_writes_the_skip_tally
  _hi_check "No-op without a counts file" test_report_counts_is_a_noop_without_a_counts_file
  _hi_check "End reports its counts" test_suite_end_reports_its_counts
  _hi_check "Note_failure appends the label" test_note_failure_appends_the_label
  _hi_check "Note_failure is a no-op standalone" test_note_failure_is_a_noop_without_a_fails_file

  _hi_h2 "Testing: _hi_report_skip / _hi_skip"
  _hi_check "Report_skip marks the suite skipped" test_report_skip_marks_the_suite_as_skipped
  _hi_check "Report_skip is a no-op without a counts file" test_report_skip_is_a_noop_without_a_counts_file
  _hi_check "Require reports a skip for a missing binary" test_require_reports_a_skip_for_a_missing_binary
  _hi_check "Skip counts a case without passing it" test_skip_counts_the_case_without_passing_it
  _hi_check "End names the skipped cases" test_suite_end_names_the_skipped_cases
  _hi_check "End stays quiet with nothing skipped" test_suite_end_stays_quiet_with_nothing_skipped

  _hi_h2 "Testing: _hi_workdir / _hi_track_container / _hi_test_cleanup"
  _hi_check "Workdir creates a scratch dir" test_workdir_creates_a_scratch_dir
  _hi_check "Cleanup runs the suite-specific hook" test_test_cleanup_runs_the_extra_hook_first
  _hi_check "Cleanup removes the workdir even if the hook fails" test_test_cleanup_removes_the_workdir_even_if_the_hook_fails
  _hi_check "Track_container appends to the teardown list" test_track_container_appends_to_the_teardown_list

  _hi_h2 "Testing: _hi_require / _hi_require_backend"
  _hi_check "Returns for an installed command" test_require_returns_for_an_installed_command
  _hi_check "Skips (exit 0) when missing" test_require_exits_zero_and_warns_when_missing
  _hi_check "Uses a custom reason" test_require_uses_a_custom_reason
  _hi_check "Backend skips when the CLI is missing" test_require_backend_skips_when_the_cli_is_missing
  _hi_check "Backend skips when it's installed but unreachable" test_require_backend_skips_when_the_backend_is_unreachable

  _hi_h2 "Testing: _hi_host_report / _hi_host_tree_check"
  _hi_check "Names this bash and kernel" test_host_report_names_this_bash_and_kernel
  _hi_check "Carries \$_HI_HOME and \$_HI_ROOT" test_host_report_carries_the_tree_variables
  _hi_check "Agrees when the tree matches" test_host_report_agrees_when_the_tree_matches
  _hi_check "Warns, naming both, when it differs" test_host_report_warns_when_the_tree_differs
  _hi_check "Tree check stays silent on agreement" test_host_tree_check_is_silent_and_zero_when_it_agrees
  _hi_check "Tree check returns 1 on a mismatch" test_host_tree_check_returns_one_when_it_differs
  _hi_check "Lists the lint tools" test_host_report_lists_the_lint_tools
  _hi_check "Survives an empty PATH" test_host_report_survives_an_empty_path
  _hi_check "Marks absent tools absent" test_host_report_marks_absent_tools_absent
  _hi_check "Tool version reads a real number" test_tool_version_reports_a_number_for_a_real_tool
  _hi_check "Tool version says absent, not fails" test_tool_version_says_absent_rather_than_failing

  _hi_h2 "Testing: _hi_probe_cmd"
  _hi_check "Bash shape fires only with a real root" test_probe_cmd_bash_shape_fires_only_with_a_real_root
  _hi_check "Container fallback fires only with the alias" test_probe_cmd_fallback_shape_fires_only_with_the_alias
  _hi_check "Ssh fallback fires only with hi_info" test_probe_cmd_ssh_fallback_fires_only_with_hi_info
  _hi_check "Fish shapes run under fish" test_probe_cmd_fish_shapes_run_under_fish
  _hi_check "Installed shape fires only when \$_HI_ROOT is ~/hi.d" test_probe_cmd_installed_shape_fires_only_when_root_is_home
  _hi_check "Every shape ends with the marker" test_probe_cmd_every_shape_ends_with_the_marker
  _hi_check "Rejects an unknown shape" test_probe_cmd_rejects_an_unknown_shape

  _hi_h2 "Testing: _hi_poll_bool / _hi_poll_value"
  _hi_check "Poll_bool stops at the wall-clock budget" test_poll_bool_stops_at_the_wall_clock_budget
  _hi_check "Poll_bool returns 0 when already true" test_poll_bool_returns_zero_when_already_true
  _hi_check "Poll_bool returns 1 when never true" test_poll_bool_returns_one_when_never_true
  _hi_check "Poll_bool succeeds on a later attempt" test_poll_bool_succeeds_on_a_later_attempt
  _hi_check "Poll_bool passes arguments through" test_poll_bool_passes_arguments_through
  _hi_check "Poll_bool's abort predicate stops early" test_poll_bool_abort_predicate_stops_early
  _hi_check "Poll_bool's abort predicate doesn't block success" test_poll_bool_abort_predicate_does_not_block_success
  _hi_check "Poll_value prints what it found" test_poll_value_prints_the_value_it_found
  _hi_check "Poll_value fails on empty output" test_poll_value_fails_when_output_stays_empty
  _hi_check "Poll_value keeps polling past empty output" test_poll_value_keeps_polling_past_empty_output

  _hi_h2 "Testing: _hi_wait_pid"
  _hi_check "Reports a clean exit" test_wait_pid_reports_a_clean_exit
  _hi_check "Reports the real exit code" test_wait_pid_reports_the_real_exit_code
  _hi_check "Kills and reports 124 on timeout" test_wait_pid_kills_and_reports_124_on_timeout
  _hi_check "Runs the timeout hook before killing" test_wait_pid_runs_the_timeout_hook_before_killing
  _hi_check "Skips the hook on a clean exit" test_wait_pid_skips_the_hook_on_a_clean_exit

  _hi_h2 "Testing: _hi_pty_wrap"
  _hi_check "Force wraps regardless of the fd" test_pty_wrap_force_wraps_even_on_a_tty
  _hi_check "Auto leaves a real tty alone" test_pty_wrap_auto_leaves_a_real_tty_alone
  _hi_check "The wrapper really allocates a pty" test_pty_wrap_actually_allocates_a_pty
  _hi_check "Resets between calls" test_pty_wrap_resets_between_calls

  _hi_h2 "Testing: shared ssh fixtures"
  _hi_check "Ssh opts never touch the user's known_hosts" test_ssh_opts_never_touch_the_users_known_hosts
  _hi_check "Sshd entrypoint honours runtime \$SSHD_OPTS" test_sshd_entrypoint_body_passes_runtime_opts_to_sshd
  _hi_check "Sshd entrypoint unlocks the test account" test_sshd_entrypoint_body_unlocks_the_test_account
  _hi_check "Keypair lands in the workdir" test_ssh_keypair_writes_a_usable_key
  _hi_check "Reachability probe fails on a dead port" test_ssh_reachable_fails_against_a_dead_port

  _hi_suite_end "test_lib.sh"
}

run_test_lib_tests
