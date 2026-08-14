#!/bin/bash
# End-to-end test of hi.sh's ephemeral-target cleanup (the `trap 'rm -rf
# $_HI_CLEANUP' exit` set up in _say_hi's non-installed branch, see hi.sh)
# surviving an abrupt disconnect, not just a clean `exit`.
#
# A real network partition can't be produced from here without extra
# privileges (iptables/NET_ADMIN inside the container), so this simulates one
# the way that's actually reachable from an unprivileged test: freeze every
# local ssh process for the session with SIGSTOP rather than killing it. The
# underlying TCP socket stays open and nothing sent to it gets answered -
# indistinguishable, from the target's point of view, from the cable getting
# pulled. The target-side sshd (started below with a 2s ClientAliveInterval
# and ClientAliveCountMax=1) is what actually notices and tears the session
# down, exactly as it would for a real dead link - so this proves the trap
# fires from a real server-side session teardown, not from a clean
# client-initiated close. hi.sh's own ControlMaster (see _hi_remote_root)
# means there can be two local ssh processes for one session - the persistent
# multiplexing master plus the interactive `-t` client - so every matching
# pid gets frozen, not just the obvious one.
#
# Skips cleanly if docker or pgrep aren't available.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_hi_require_backend docker
_hi_require pgrep

_hi_workdir sshdisconnecttest
_hi_h1 "Testing hi's ssh cleanup trap survives an abrupt disconnect"
_hi_ssh_keypair

# --- build the throwaway sshd image ---------------------------------------
# the same image ssh_test.sh uses, built once for both suites (see
# _hi_sshd_image); the short ClientAlive setting this suite needs - so the
# server gives up on a gone-silent client in a few seconds instead of the
# OS-default TCP timeout of minutes to hours, which is what's actually under
# test here - is passed per-container below rather than baked into an image of
# its own
_hi_h2 "Building test image"
_hi_sshd_image "this suite" || exit 0

# --- start the one container both cases share -----------------------------
_HI_CONTAINER="hi-sshdisconnecttest-$$"
_hi_sshd_container "$_HI_CONTAINER" "$_HI_SSHD_IMAGE" \
  -e "SSHD_OPTS=-o ClientAliveInterval=2 -o ClientAliveCountMax=1" || exit 1

# every local ssh process belonging to this session - the interactive client
# plus hi.sh's own ControlMaster, if the multiplexed connection spun one up
function _hi_ssh_disconnect_pids() {
  pgrep -f -- "ssh .*-p $_HI_SSH_PORT .*hitest@127.0.0.1" 2>/dev/null || true
}

# hi.sh's own connect-progress output has no trailing newline before the
# command's output starts, so READY: often lands mid-line behind raw terminal
# escape/erase codes from the pty transcript - extract it by pattern, not by
# anchoring on the start of a line.
function _hi_ready_dir() {
  grep -oE 'READY:[^[:space:]]*' "$1" 2>/dev/null | sed 's/^READY://' | head -1
}

function _hi_cleanup_dir_gone() {
  ! docker exec "$_HI_CONTAINER" test -d "$1" 2>/dev/null
}

# ---- the actual cases -------------------------------------------------

function test_clean_exit_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/clean.out" cleanup_dir

  _hi_pty_wrap 0 auto "no tty and no python3 to fake one - results may be unreliable"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_SSH_LAUNCH[@]}" 'echo READY:$_HI_CLEANUP' >"$out_file" 2>&1 || true

  cleanup_dir="$(_hi_ready_dir "$out_file")"
  [ -n "$cleanup_dir" ] || return 1
  # the session already ran to completion (ssh above was synchronous), so the
  # target-side trap has already had its chance to fire by now
  ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null
}

function test_sudden_disconnect_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/disconnect.out" cleanup_dir launcher_pid pid ok=0
  local -a pids=()
  : >"$out_file"

  # `ssh -t` puts whatever terminal it's handed into raw mode and only undoes
  # that on its way out - and the whole point of this case is that it never
  # gets one, since it's SIGSTOPped below and then SIGKILLed. Handed our own
  # terminal it would leave it raw forever, staircasing everything printed
  # after this suite. So always give the launcher a throwaway pty of its own
  # (force, not auto - our stdin being a tty says nothing about whether it
  # should be *the* tty here), and keep the real one out of reach entirely:
  # pty.spawn allocates the child's pty regardless of its own stdin, so
  # /dev/null below costs nothing and means even a SIGKILLed python3 can't
  # strand our terminal.
  _hi_pty_wrap 0 force "no python3 to give the launcher its own pty - ssh will raw-mode this terminal and the test kills it before it can restore, expect garbled output afterwards"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_SSH_LAUNCH[@]}" 'echo READY:$_HI_CLEANUP; sleep 30' </dev/null >"$out_file" 2>&1 &
  launcher_pid=$!

  # confirm the session is actually up before freezing anything - racing the
  # freeze against a connection that hasn't started yet would be a false pass.
  # _hi_poll_value both waits for READY: to land and hands back the path it
  # carried, so there's no second pass over the file to keep in step.
  cleanup_dir="$(_hi_poll_value 40 0.25 _hi_ready_dir "$out_file")" || cleanup_dir=""
  if [ -z "$cleanup_dir" ] || ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null; then
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi

  mapfile -t pids < <(_hi_ssh_disconnect_pids)
  if [ "${#pids[@]}" -eq 0 ]; then
    _hi_cecho " | no local ssh process found to freeze" "$RED"
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi
  for pid in "${pids[@]}"; do kill -STOP "$pid" 2>/dev/null || true; done

  _hi_poll_bool 60 0.5 _hi_cleanup_dir_gone "$cleanup_dir" && ok=1

  for pid in "${pids[@]}"; do kill -9 "$pid" 2>/dev/null || true; done
  _hi_wait_pid "$launcher_pid" 5

  [ "$ok" -eq 1 ]
}

_hi_suite_begin

_hi_h2 "Cleanup on disconnect"
_hi_check "Clean exit removes the cleanup dir" test_clean_exit_removes_cleanup_dir
_hi_check "Sudden (frozen-connection) disconnect still removes it" test_sudden_disconnect_removes_cleanup_dir

_hi_suite_end "" \
  "hi's ssh cleanup trap survived every case ($_HI_TOTAL cases)" \
  "hi's ssh cleanup trap FAILED: $_HI_FAILED/$_HI_TOTAL cases"
