#!/bin/bash
# Boots throwaway containers - one per shell environment - and drives hi.sh's
# real podman path (_say_hi_container) against each of them over `podman
# exec`, not ssh or docker. This proves the podman branch of _say_hi_container
# added alongside docker's - same command shapes (exec/-i/-it), same fallback
# probe - just a different CLI underneath. Mirrors docker_test.sh's coverage
# exactly, one-for-one, against podman instead.
# Everything is ephemeral and nothing touches host ssh config. Skips cleanly
# if podman isn't installed/reachable. Needs network access the first time it
# runs, to pull/build the test images (cached by podman afterwards). Podman
# keeps its own separate image/container store from docker, so this builds
# its own copies of the test images rather than reusing docker_test.sh's.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./test_lib.sh
source "$_HI_TEST_LIB"

command -v podman >/dev/null 2>&1 || { _hi_cecho "podman not installed, skipping" "$YELLOW"; exit 0; }
podman info >/dev/null 2>&1 || { _hi_cecho "podman not reachable, skipping" "$YELLOW"; exit 0; }

_HI_WORKDIR="$(mktemp -d -t hi.podmantest.XXXXXX)"
declare -a _HI_STARTED=()

# shellcheck disable=SC2329 # trap function is never invoked directly
function _hi_cleanup() {
  local c
  for c in "${_HI_STARTED[@]:-}"; do
    [ -n "$c" ] && podman rm -f "$c" >/dev/null 2>&1
  done
  rm -rf "$_HI_WORKDIR"
}
_hi_on_exit _hi_cleanup
_hi_h1 "Testing hi's podman path across container shell environments"

# --- build the test images ----------------------------------------------
# debian ships bash out of the box, so it alone exercises _say_hi_container's
# main branch. The other three are bash-less images, each with exactly one of
# zsh/fish/sh on PATH, so each exercises exactly one arm of the fallback's
# `for s in zsh fish sh` probe - a plain alpine image already has nothing but
# sh, so it needs no image build of its own.
mkdir -p "$_HI_WORKDIR/zsh" "$_HI_WORKDIR/fish"

cat >"$_HI_WORKDIR/zsh/Dockerfile" <<'EOF'
FROM alpine:3.20
RUN apk add --no-cache zsh
EOF

cat >"$_HI_WORKDIR/fish/Dockerfile" <<'EOF'
FROM alpine:3.20
RUN apk add --no-cache fish
EOF

_hi_h2 "Building test images"
_HI_ZSH_OK=1
_HI_FISH_OK=1
_hi_h3 "building hi-podmantest-zsh from $_HI_WORKDIR/zsh (log: $_HI_WORKDIR/zsh.log)"
podman build -q -t hi-podmantest-zsh "$_HI_WORKDIR/zsh" >/dev/null 2>"$_HI_WORKDIR/zsh.log" || _HI_ZSH_OK=0
_hi_h3 "building hi-podmantest-fish from $_HI_WORKDIR/fish (log: $_HI_WORKDIR/fish.log)"
podman build -q -t hi-podmantest-fish "$_HI_WORKDIR/fish" >/dev/null 2>"$_HI_WORKDIR/fish.log" || _HI_FISH_OK=0

[ "$_HI_ZSH_OK" -eq 1 ] || _hi_cecho " | zsh image failed to build, skipping the zsh fallback (see $_HI_WORKDIR/zsh.log)" "$YELLOW"
[ "$_HI_FISH_OK" -eq 1 ] || _hi_cecho " | fish image failed to build, skipping the fish fallback (see $_HI_WORKDIR/fish.log)" "$YELLOW"

# --- the actual per-shell test -------------------------------------------
_HI_MARKER="HI_PODMAN_TEST_OK"
# the bash branch chainloads straight to `bash --rcfile hi.bashrc` without
# sourcing aliases.sh itself - same as the ssh/docker paths - so this asserts
# the copy landed *and* sources it directly
# shellcheck disable=2016 # this expands later
_HI_CMD_BASH='test -f "$_HI_ROOT/hi.sh" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo '"$_HI_MARKER"
# the fallback branch only copies+sources shells/aliases.sh directly (see
# _say_hi_container's `no bash` arm in hi.sh) - it never touches
# common/paths.sh, so $_HI_ALIASES/hi_info aren't in scope here. This checks
# an ordinary alias from aliases.sh instead, to assert the copy landed and
# the fallback shell actually sourced it
# shellcheck disable=2016 # this expands later
_HI_CMD_FALLBACK='alias sudo >/dev/null 2>&1 && echo '"$_HI_MARKER"
# fish aliases are functions, and its `alias name` (no value) is a syntax
# error rather than an existence check - same assertion as _HI_CMD_FALLBACK,
# in fish's own dialect
# shellcheck disable=2016 # this expands later
_HI_CMD_FALLBACK_FISH='functions -q sudo; and echo '"$_HI_MARKER"

# podman exec -it refuses to allocate a remote tty unless our own stdin
# already is one - true whenever this runs headless/CI. Route through a
# locally-faked pty in that case so the test is reliable everywhere, not just
# when someone happens to run it from an interactive terminal.
#
# The check has to happen against a duplicated fd, not fd 0 directly: this
# script backgrounds the actual launcher with `&` below (_hi_run_case), and
# since job control is off in a non-interactive script, bash silently
# rewires a backgrounded job's stdin to /dev/null regardless of what the
# script's own stdin was - so testing `-t 0` here and then handing the
# background job fd 0 later would report a real terminal and still fail.
# Duplicating to fd 3 up front and threading `<&3` through to the background
# command (see _hi_run_case) keeps the original tty-ness intact either way.
exec 3<&0
_hi_pty_wrap 3 auto "no tty and no python3 to fake one - podman exec -it will fail outright, results may be unreliable"

_HI_FAILED=0
_HI_TOTAL=0

# polls until the container is actually running, so the real test isn't
# racing the container's start
# shellcheck disable=SC2329 # invoked indirectly, via _hi_poll_bool's "$@"
function _hi_container_running() { [ "$(podman container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-20}"
  local name out_file out exit_code=0 i pid t0 t1 ok=1

  name="hi-podmantest-$label-$$"
  _hi_h3 "Testing shell: $label"
  t0="$(_hi_now)"

  if ! podman run -d --name "$name" "$image" tail -f /dev/null >/dev/null 2>"$_HI_WORKDIR/$label.run.log"; then
    _hi_cecho " | failed to start container (image: $image)" "$RED"
    return 1
  fi
  _HI_STARTED+=("$name")
  _hi_cecho " | container: $name (image: $image)"

  if ! _hi_poll_bool 40 0.25 _hi_container_running "$name"; then
    _hi_cecho " | container never reported running" "$RED"
    return 1
  fi

  out_file="$_HI_WORKDIR/$label.out"
  _hi_cecho " | running: $_HI_LAUNCHER $name $cmd"
  # backgrounded so a hung fallback (e.g. a shell that never honors the
  # trailing `exit`) can't wedge the whole test suite
  "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" "$name" "$cmd" <&3 >"$out_file" 2>&1 &
  pid=$!
  for ((i = 0; i < timeout_s * 4; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    _hi_h3 " | $label -- TIMED OUT after ${timeout_s}s, killing"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    exit_code=124
  else
    wait "$pid" 2>/dev/null || exit_code=$?
  fi
  t1="$(_hi_now)"

  out="$(cat "$out_file" 2>/dev/null)"
  if printf '%s' "$out" | grep -q "$_HI_MARKER"; then
    _hi_cecho " | $label -- podman path OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
  else
    _hi_h3 " | $label -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)"
    printf '%s\n' "$out" | sed 's/^/      /'
    ok=0
  fi

  podman rm -f "$name" >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

_hi_case _hi_run_case bash debian:bookworm-slim "$_HI_CMD_BASH"
[ "$_HI_ZSH_OK" -eq 1 ] && _hi_case _hi_run_case zsh hi-podmantest-zsh "$_HI_CMD_FALLBACK"
[ "$_HI_FISH_OK" -eq 1 ] && _hi_case _hi_run_case fish hi-podmantest-fish "$_HI_CMD_FALLBACK_FISH"
_hi_case _hi_run_case sh alpine:3.20 "$_HI_CMD_FALLBACK"

if [ "$_HI_FAILED" -eq 0 ]; then
  _hi_h1 "hi's podman path survived every shell environment tested ($_HI_TOTAL cases)"
else
  _hi_h1 "hi's podman path FAILED: $_HI_FAILED/$_HI_TOTAL cases" "$RED"
fi

podman image rm -f hi-podmantest-zsh hi-podmantest-fish >/dev/null 2>&1 || true
exit "$_HI_FAILED"
