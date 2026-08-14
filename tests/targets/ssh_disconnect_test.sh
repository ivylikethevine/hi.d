#!/bin/bash
# End-to-end test of hi.sh's ephemeral-target cleanup (the `trap 'rm -rf
# $_HI_CLEANUP' exit` set up in _say_hi's non-installed branch, see hi.sh)
# surviving an abrupt disconnect, not just a clean `exit`.
#
# Freezing the session takes *two* SIGSTOPs, not one. _say_hi multiplexes the
# install-probe and the real session over one connection (ControlMaster=auto /
# ControlPersist=30, see hi.sh), so by the time the session is up there is a
# backgrounded ControlPersist master holding the TCP socket alongside the `ssh
# -t ...` the test can see - and the master, not the session client, is what
# answers sshd's ClientAlive probes. Freeze only the client and sshd quite
# correctly keeps the session: that's a hung terminal, not a dead link. Both
# have to stop for this to model a real one, which is why _hi_ssh_mux_pids
# exists and why a missing master below is a hard failure.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

function _hi_ssh_client_pids() {
  pgrep -f -- "ssh .*-p $_HI_SSH_PORT .*hitest@127.0.0.1" 2>/dev/null || true
}

# hi.sh's ControlPath, read back out of the session client's own argv - the
# mux master is found by that exact path rather than by a `hi.cm.*` glob, so a
# concurrent hi session on the same machine (or one still persisting from the
# clean-exit case above) can't be matched by mistake.
function _hi_ssh_ctl_path() {
  local args
  if [ -r "/proc/$1/cmdline" ]; then
    args="$(tr '\0' ' ' <"/proc/$1/cmdline")"
  else
    args="$(ps -ww -o args= -p "$1" 2>/dev/null)"
  fi
  printf '%s' "$args" | grep -oE 'ControlPath=[^[:space:]]+' | head -1 | cut -d= -f2-
}

# The ControlPersist master renames itself to `ssh: <ControlPath> [mux]` via
# setproctitle, so its argv is gone and the client pattern above can never
# reach it.
function _hi_ssh_mux_pids() {
  local ctl="${1//./\\.}"
  pgrep -f -- "ssh: $ctl \[mux\]" 2>/dev/null || true
}

function _hi_ready_dir() {
  grep -oE 'READY:[^[:space:]]*' "$1" 2>/dev/null | sed 's/^READY://' | head -1
}

function _hi_cleanup_dir_gone() {
  ! docker exec "$_HI_CONTAINER" test -d "$1" 2>/dev/null
}

function test_clean_exit_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/clean.out" cleanup_dir

  _hi_pty_wrap 0 auto "no tty and no python3 to fake one - results may be unreliable"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_SSH_LAUNCH[@]}" 'echo READY:$_HI_CLEANUP' >"$out_file" 2>&1 || true

  cleanup_dir="$(_hi_ready_dir "$out_file")"
  [ -n "$cleanup_dir" ] || return 1
  ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null
}

function test_sudden_disconnect_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/disconnect.out" cleanup_dir launcher_pid pid ctl ok=0
  local -a pids=() mux=()
  : >"$out_file"

  _hi_pty_wrap 0 force "no python3 to give the launcher its own pty - ssh will raw-mode this terminal and the test kills it before it can restore, expect garbled output afterwards"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # the remote sleep has to outlast every poll below by a wide margin: if it
  # can expire inside the window, the session ends on its own timer and the
  # assertion passes without the disconnect having proved anything
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_SSH_LAUNCH[@]}" 'echo READY:$_HI_CLEANUP; sleep 600' </dev/null >"$out_file" 2>&1 &
  launcher_pid=$!

  # generous: this covers the whole connect + install-probe + tar copy of hi.d,
  # which is slow on a cold, small CI runner
  cleanup_dir="$(_hi_poll_value 60 0.5 _hi_ready_dir "$out_file")" || cleanup_dir=""
  if [ -z "$cleanup_dir" ] || ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null; then
    if [ -z "$cleanup_dir" ]; then
      _hi_cecho " | session never printed READY:\$_HI_CLEANUP - it never came up" "$RED"
      sed 's/^/      /' "$out_file" 2>/dev/null
    else
      _hi_cecho " | cleanup dir $cleanup_dir was never created on the target" "$RED"
    fi
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi

  mapfile -t pids < <(_hi_ssh_client_pids)
  if [ "${#pids[@]}" -eq 0 ]; then
    _hi_cecho " | no local ssh process found to freeze" "$RED"
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi
  ctl="$(_hi_ssh_ctl_path "${pids[0]}")"
  [ -n "$ctl" ] && mapfile -t mux < <(_hi_ssh_mux_pids "$ctl")
  # if hi.sh ever stops multiplexing, this is the check that says so - delete
  # it deliberately rather than letting the suite quietly go back to freezing a
  # client whose connection someone else is keeping alive
  if [ "${#mux[@]}" -eq 0 ]; then
    _hi_cecho " | no ControlPersist mux master found - freezing the client alone proves nothing" "$RED"
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi
  pids+=("${mux[@]}")
  for pid in "${pids[@]}"; do kill -STOP "$pid" 2>/dev/null || true; done

  # sshd's ClientAliveInterval=2/ClientAliveCountMax=1 reaps a frozen client in
  # ~4-6s; the rest is headroom for a loaded runner
  _hi_poll_bool 60 0.5 _hi_cleanup_dir_gone "$cleanup_dir" && ok=1
  [ "$ok" -eq 1 ] || _hi_cecho " | $cleanup_dir survived the disconnect" "$RED"

  for pid in "${pids[@]}"; do kill -9 "$pid" 2>/dev/null || true; done
  _hi_wait_pid "$launcher_pid" 5

  [ "$ok" -eq 1 ]
}

function run_ssh_disconnect_test() {
  _hi_require_backend docker
  _hi_require pgrep

  _hi_workdir sshdisconnecttest
  _hi_h1 "Testing hi's ssh cleanup trap survives an abrupt disconnect"
  _hi_ssh_keypair

  _hi_h2 "Building test image"
  _hi_sshd_image "this suite" || exit 0

  _HI_CONTAINER="hi-sshdisconnecttest-$$"
  _hi_sshd_container "$_HI_CONTAINER" "$_HI_SSHD_IMAGE" \
    -e "SSHD_OPTS=-o ClientAliveInterval=2 -o ClientAliveCountMax=1" || exit 1

  _hi_suite_begin

  _hi_h2 "Cleanup on disconnect"
  _hi_check "Clean exit removes the cleanup dir" test_clean_exit_removes_cleanup_dir
  _hi_check "Sudden (frozen-connection) disconnect still removes it" test_sudden_disconnect_removes_cleanup_dir

  _hi_suite_end "" \
    "hi's ssh cleanup trap survived every case ($_HI_TOTAL cases)" \
    "hi's ssh cleanup trap FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_ssh_disconnect_test
