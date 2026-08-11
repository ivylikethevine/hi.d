#!/bin/bash
# Shared helpers for the container/remote end-to-end tests (docker_test.sh,
# podman_test.sh, kube_test.sh, nomad_test.sh, ssh_test.sh) - the bits that
# were previously copy-pasted near-identically across all five: faking a pty
# when one's needed but our own stdin isn't one, and polling some backend
# (docker/kubectl/nomad/ssh) until a condition comes true instead of racing
# its own async startup. Sourced through common/bootstrap.sh, same as every
# other common/*.sh file.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

# Sets the global array _HI_PTY_WRAP to a python3-based pty-spawn prefix
# whenever it's needed, empty otherwise. $1 is the fd to check for tty-ness,
# $2 is "auto" (only wrap if fd $1 isn't a real tty) or "force" (always
# wrap - for callers where the fd being checked is never the right proxy for
# whether the *launcher* ends up with a real tty), $3 is the warning printed
# if python3 isn't available to build the fake.
function _hi_pty_wrap() {
  local fd="$1" mode="$2" warning="$3"
  _HI_PTY_WRAP=()
  if [ "$mode" = force ] || [ ! -t "$fd" ]; then
    if command -v python3 >/dev/null 2>&1; then
      _HI_PTY_WRAP=(python3 -c 'import pty, sys; sys.exit(pty.spawn(sys.argv[1:]))')
    else
      _hi_cecho " | $warning" "$YELLOW"
    fi
  fi
}

# Polls "$@" (a command or function) up to <tries> times, <interval> seconds
# apart, until it exits 0. Every attempt's stdout/stderr is discarded - this
# is for conditions the caller only needs a yes/no for (container running,
# ssh reachable, ...). Returns 1 if it never succeeded.
function _hi_poll_bool() {
  local tries="$1" interval="$2" i
  shift 2
  for ((i = 0; i < tries; i++)); do
    "$@" >/dev/null 2>&1 && return 0
    sleep "$interval"
  done
  return 1
}

# Runs "$@" as one sub-case of a multi-case test file (one shell, one
# container shape, one scenario, ...), bumping the caller's _HI_TOTAL/
# _HI_FAILED counters accordingly. Callers declare both as plain (non-local)
# ints set to 0 before the first case runs, so a final "$_HI_FAILED/$_HI_TOTAL
# cases failed" can be reported in the closing banner instead of a bare
# pass/fail.
function _hi_case() {
  _HI_TOTAL=$((_HI_TOTAL + 1))
  "$@" || _HI_FAILED=$((_HI_FAILED + 1))
}

# Polls "$@" up to <tries> times, <interval> seconds apart, until it prints
# non-empty stdout - for conditions where the caller also needs the value
# that showed up (e.g. an allocation ID), not just a yes/no. Prints that
# value and returns 0 on success; returns 1 if nothing ever showed up.
function _hi_poll_value() {
  local tries="$1" interval="$2" out i
  shift 2
  for ((i = 0; i < tries; i++)); do
    out="$("$@" 2>/dev/null)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    sleep "$interval"
  done
  return 1
}
