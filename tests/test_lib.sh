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

# Waits up to <timeout_s> for backgrounded <pid> to finish (polled in 0.25s
# steps), killing it and setting _HI_WAIT_EXIT=124 if it never does -
# otherwise _HI_WAIT_EXIT is its real exit code. Shared by every e2e test's
# "launcher hung" guard (docker/podman/nomad/kube_test.sh), so a hung fallback
# shell can't wedge the whole suite. On timeout, "$@" (if given, e.g.
# nomad_test.sh's alloc-status dump) runs before the kill, while the process
# is still alive to inspect; relies on bash's dynamic scoping to see the
# caller's locals ($label, $alloc, ...), same as _hi_container_running/
# _hi_pod_running already do when passed to _hi_poll_bool by name.
function _hi_wait_pid() {
  local pid="$1" timeout_s="$2" i
  shift 2
  _HI_WAIT_EXIT=0
  for ((i = 0; i < timeout_s * 4; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    [ $# -gt 0 ] && "$@"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    _HI_WAIT_EXIT=124
  else
    wait "$pid" 2>/dev/null || _HI_WAIT_EXIT=$?
  fi
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

# Boots throwaway containers - one per shell environment - and drives hi.sh's
# real _say_hi_container against each of them over `<backend> exec`. Podman's
# CLI is a full drop-in for docker's here (inspect/exec/-i/-it all take
# identical flags - see hi.sh's own comment on _hi_is_podman_container), so
# docker_test.sh and podman_test.sh are both just `_hi_container_backend_test
# docker|podman` - this one function proves both branches of
# _say_hi_container: the bash-present main path (tar copy + `bash --rcfile`),
# and every arm of the bash-less fallback's `for s in zsh fish sh` probe.
# Everything is ephemeral and nothing touches host ssh config. Skips cleanly
# if $backend isn't installed/running. Needs network access the first time it
# runs, to pull/build the test images (cached by $backend afterwards).
function _hi_container_backend_test() {
  local backend="$1" marker workdir
  local -a started=()

  command -v "$backend" >/dev/null 2>&1 || { _hi_cecho "$backend not installed, skipping" "$YELLOW"; exit 0; }
  "$backend" info >/dev/null 2>&1 || { _hi_cecho "$backend not reachable, skipping" "$YELLOW"; exit 0; }

  workdir="$(mktemp -d -t "hi.${backend}test.XXXXXX")"

  # shellcheck disable=SC2329 # trap function is never invoked directly
  function _hi_cleanup() {
    local c
    for c in "${started[@]:-}"; do
      [ -n "$c" ] && "$backend" rm -f "$c" >/dev/null 2>&1
    done
    rm -rf "$workdir"
  }
  _hi_on_exit _hi_cleanup
  _hi_h1 "Testing hi's $backend path across container shell environments"

  # --- build the test images ----------------------------------------------
  # debian ships bash out of the box, so it alone exercises _say_hi_container's
  # main branch. The other three are bash-less images, each with exactly one of
  # zsh/fish/sh on PATH, so each exercises exactly one arm of the fallback's
  # `for s in zsh fish sh` probe - a plain alpine image already has nothing but
  # sh, so it needs no image build of its own.
  mkdir -p "$workdir/zsh" "$workdir/fish"

  cat >"$workdir/zsh/Dockerfile" <<'EOF'
FROM alpine:3.20
RUN apk add --no-cache zsh
EOF

  cat >"$workdir/fish/Dockerfile" <<'EOF'
FROM alpine:3.20
RUN apk add --no-cache fish
EOF

  _hi_h2 "Building test images"
  local zsh_ok=1 fish_ok=1
  _hi_h3 "building hi-${backend}test-zsh from $workdir/zsh (log: $workdir/zsh.log)"
  "$backend" build -q -t "hi-${backend}test-zsh" "$workdir/zsh" >/dev/null 2>"$workdir/zsh.log" || zsh_ok=0
  _hi_h3 "building hi-${backend}test-fish from $workdir/fish (log: $workdir/fish.log)"
  "$backend" build -q -t "hi-${backend}test-fish" "$workdir/fish" >/dev/null 2>"$workdir/fish.log" || fish_ok=0

  [ "$zsh_ok" -eq 1 ] || _hi_cecho " | zsh image failed to build, skipping the zsh fallback (see $workdir/zsh.log)" "$YELLOW"
  [ "$fish_ok" -eq 1 ] || _hi_cecho " | fish image failed to build, skipping the fish fallback (see $workdir/fish.log)" "$YELLOW"

  # --- the actual per-shell test -------------------------------------------
  marker="HI_$(printf '%s' "$backend" | tr '[:lower:]' '[:upper:]')_TEST_OK"
  # the bash branch chainloads straight to `bash --rcfile hi.bashrc` without
  # sourcing aliases.sh itself - same as the ssh path - so this asserts the
  # copy landed *and* sources it directly
  # shellcheck disable=2016 # this expands later
  local cmd_bash='test -f "$_HI_ROOT/hi.sh" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo '"$marker"
  # the fallback branch only copies+sources shells/aliases.sh directly (see
  # _say_hi_container's `no bash` arm in hi.sh) - it never touches
  # common/paths.sh, so $_HI_ALIASES/hi_info aren't in scope here. This checks
  # an ordinary alias from aliases.sh instead, to assert the copy landed and
  # the fallback shell actually sourced it
  # shellcheck disable=2016 # this expands later
  local cmd_fallback='alias sudo >/dev/null 2>&1 && echo '"$marker"
  # fish aliases are functions, and its `alias name` (no value) is a syntax
  # error rather than an existence check - same assertion as cmd_fallback, in
  # fish's own dialect
  # shellcheck disable=2016 # this expands later
  local cmd_fallback_fish='functions -q sudo; and echo '"$marker"

  # <backend> exec -it refuses to allocate a remote tty unless our own stdin
  # already is one - true whenever this runs headless/CI. Route through a
  # locally-faked pty in that case so the test is reliable everywhere, not just
  # when someone happens to run it from an interactive terminal.
  #
  # The check has to happen against a duplicated fd, not fd 0 directly: this
  # function backgrounds the actual launcher with `&` below (_hi_run_case), and
  # since job control is off in a non-interactive script, bash silently
  # rewires a backgrounded job's stdin to /dev/null regardless of what the
  # script's own stdin was - so testing `-t 0` here and then handing the
  # background job fd 0 later would report a real terminal and still fail.
  # Duplicating to fd 3 up front and threading `<&3` through to the background
  # command (see _hi_run_case) keeps the original tty-ness intact either way.
  exec 3<&0
  _hi_pty_wrap 3 auto "no tty and no python3 to fake one - $backend exec -it will fail outright, results may be unreliable"

  _HI_FAILED=0
  _HI_TOTAL=0

  # polls until the container is actually running, so the real test isn't
  # racing the container's start
  # shellcheck disable=SC2329 # invoked indirectly, via _hi_poll_bool's "$@"
  function _hi_container_running() { [ "$("$backend" container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

  # shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
  function _hi_run_case() {
    local label="$1" image="$2" cmd="$3" timeout_s="${4:-20}"
    local name out_file out exit_code=0 t0 t1 ok=1

    name="hi-${backend}test-$label-$$"
    _hi_h3 "Testing shell: $label"
    t0="$(_hi_now)"

    if ! "$backend" run -d --name "$name" "$image" tail -f /dev/null >/dev/null 2>"$workdir/$label.run.log"; then
      _hi_cecho " | failed to start container (image: $image)" "$RED"
      return 1
    fi
    started+=("$name")
    _hi_cecho " | container: $name (image: $image)"

    if ! _hi_poll_bool 40 0.25 _hi_container_running "$name"; then
      _hi_cecho " | container never reported running" "$RED"
      return 1
    fi

    out_file="$workdir/$label.out"
    _hi_cecho " | running: $_HI_LAUNCHER $name $cmd"
    # backgrounded so a hung fallback (e.g. a shell that never honors the
    # trailing `exit`) can't wedge the whole test suite
    "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" "$name" "$cmd" <&3 >"$out_file" 2>&1 &
    # shellcheck disable=SC2329 # invoked indirectly, as _hi_wait_pid's on-timeout hook
    function _hi_on_timeout() { _hi_h3 " | $label -- TIMED OUT after ${timeout_s}s, killing"; }
    _hi_wait_pid "$!" "$timeout_s" _hi_on_timeout
    exit_code="$_HI_WAIT_EXIT"
    t1="$(_hi_now)"

    out="$(cat "$out_file" 2>/dev/null)"
    if printf '%s' "$out" | grep -q "$marker"; then
      _hi_cecho " | $label -- $backend path OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    else
      _hi_h3 " | $label -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)"
      printf '%s\n' "$out" | sed 's/^/      /'
      ok=0
    fi

    "$backend" rm -f "$name" >/dev/null 2>&1
    [ "$ok" -eq 1 ]
  }

  _hi_case _hi_run_case bash debian:bookworm-slim "$cmd_bash"
  [ "$zsh_ok" -eq 1 ] && _hi_case _hi_run_case zsh "hi-${backend}test-zsh" "$cmd_fallback"
  [ "$fish_ok" -eq 1 ] && _hi_case _hi_run_case fish "hi-${backend}test-fish" "$cmd_fallback_fish"
  _hi_case _hi_run_case sh alpine:3.20 "$cmd_fallback"

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "hi's $backend path survived every shell environment tested ($_HI_TOTAL cases)"
  else
    _hi_h1 "hi's $backend path FAILED: $_HI_FAILED/$_HI_TOTAL cases" "$RED"
  fi

  "$backend" image rm -f "hi-${backend}test-zsh" "hi-${backend}test-fish" >/dev/null 2>&1 || true
  exit "$_HI_FAILED"
}
