#!/bin/bash
# Unified test runner - runs every test in tests/ (or a chosen subset), times
# each one, and prints a colored pass/fail summary table at the end.
#
# Usage: tests/test_runner.sh [name ...]
#   no args     - run every test suite
#   name ...    - run only the named suite(s), e.g. `tests/test_runner.sh docker kube`
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

# name:path (relative to this directory), in the order they run - fast local
# checks first, the docker/kind/nomad-backed end-to-end tests after.
if ! declare -p _HI_TESTS >/dev/null 2>&1; then
  _HI_TESTS=(
    "aliases:compat/alias_test.sh"
    "alias_fallthrough:compat/alias_fallthrough_test.sh"
    "shellcheck:compat/shellcheck_test.sh"
    "install:scripts/install_test.sh"
    "uninstall:scripts/uninstall_test.sh"
    "check:compat/check_test.sh"
    "header:compat/header_test.sh"
    "shared:compat/shared_test.sh"
    "git_prompt:compat/git_prompt_test.sh"
    "test_lib:harness/test_lib_test.sh"
    "test_runner:harness/runner_test.sh"
    "ssh:targets/ssh_test.sh"
    "ssh_disconnect:targets/ssh_disconnect_test.sh"
    "docker:targets/docker_test.sh"
    "podman:targets/podman_test.sh"
    "nomad:targets/nomad_test.sh"
    "kube:targets/kube_test.sh"
  )
fi

_HI_TESTS_DIR="${_HI_TESTS_DIR:-$_HI_ROOT/tests}"

declare -a _HI_SELECTED=()
if [ "$#" -eq 0 ]; then
  _HI_SELECTED=("${_HI_TESTS[@]}")
else
  for _hi_t in "${_HI_TESTS[@]}"; do
    for _hi_arg in "$@"; do
      [ "${_hi_t%%:*}" = "$_hi_arg" ] && _HI_SELECTED+=("$_hi_t")
    done
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test suite matches: $* (known: $(printf '%s ' "${_HI_TESTS[@]%%:*}"))" "$RED"
    exit 1
  fi
fi

_hi_h1 "Running ${#_HI_SELECTED[@]} test suite(s)"

# An e2e suite that drives a pty (ssh_disconnect, ssh, ...) can hand a real
# `ssh -t` our terminal and then kill it before it restores the terminal modes
# it changed, leaving every later suite's output staircased. The suites are
# responsible for not doing that, but one slip shouldn't corrupt the rest of
# the run - so snapshot the terminal here and put it back after every suite.
_HI_TTY_STATE=""
if [ -t 0 ] && command -v stty >/dev/null 2>&1; then
  _HI_TTY_STATE="$(stty -g </dev/tty 2>/dev/null || true)"
fi

function _hi_restore_tty() {
  [ -n "$_HI_TTY_STATE" ] || return 0
  stty "$_HI_TTY_STATE" </dev/tty 2>/dev/null || true
}
trap _hi_restore_tty EXIT

declare -a _HI_NAMES=() _HI_STATUSES=() _HI_DURATIONS=()
_HI_SUITE_FAILED=0
_HI_RUN_T0="$(_hi_now)"

for _hi_t in "${_HI_SELECTED[@]}"; do
  _hi_name="${_hi_t%%:*}"
  _hi_path="$_HI_TESTS_DIR/${_hi_t#*:}"

  if [ ! -f "$_hi_path" ]; then
    _hi_cecho " | $_hi_name: script missing ($_hi_path), skipping" "$YELLOW"
    _HI_NAMES+=("$_hi_name")
    _HI_STATUSES+=("MISSING")
    _HI_DURATIONS+=("-")
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
    continue
  fi

  _hi_h2 "Running $_hi_name ($_hi_path)"
  _hi_t0="$(_hi_now)"
  if "$_hi_path"; then
    _hi_code=0
  else
    _hi_code=$?
  fi
  _hi_dur="$(_hi_elapsed "$_hi_t0" "$(_hi_now)")s"
  _hi_restore_tty

  _HI_NAMES+=("$_hi_name")
  _HI_DURATIONS+=("$_hi_dur")
  if [ "$_hi_code" -eq 0 ]; then
    _HI_STATUSES+=("PASS")
  else
    _HI_STATUSES+=("FAILED ($_hi_code)")
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
  fi
done

_hi_h1 "Summary"
_hi_width=0
for _hi_name in "${_HI_NAMES[@]}"; do
  ((${#_hi_name} > _hi_width)) && _hi_width=${#_hi_name}
done

for _hi_i in "${!_HI_NAMES[@]}"; do
  _hi_color="$GREEN"
  [ "${_HI_STATUSES[_hi_i]}" = PASS ] || _hi_color="$RED"
  # shellcheck disable=SC2059 # _hi_width is a computed field-width, not user data
  _hi_cecho "$(printf " | %-${_hi_width}s  %-14s  %s" "${_HI_NAMES[_hi_i]}" "${_HI_STATUSES[_hi_i]}" "${_HI_DURATIONS[_hi_i]}")" "$_hi_color"
done

_HI_TOTAL_DUR="$(_hi_elapsed "$_HI_RUN_T0" "$(_hi_now)")s"
if [ "$_HI_SUITE_FAILED" -eq 0 ]; then
  _hi_h1 "All ${#_HI_SELECTED[@]} test suites passed ($_HI_TOTAL_DUR)"
else
  _hi_h1 "$_HI_SUITE_FAILED/${#_HI_SELECTED[@]} test suites FAILED ($_HI_TOTAL_DUR)" "$RED"
fi

exit "$_HI_SUITE_FAILED"
