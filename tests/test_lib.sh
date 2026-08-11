#!/bin/bash
# Shared scaffolding for every suite under tests/ - the bits that were
# previously copy-pasted near-identically across the files in compat/,
# scripts/ and targets/: the pass/fail assert and its counters, the scratch
# workdir and its exit trap, the "backend isn't installed, skip cleanly"
# preamble, the marker probe commands the e2e suites run on the target, the
# throwaway sshd fixtures ssh_test.sh and ssh_disconnect_test.sh both need,
# faking a pty when one's needed but our own stdin isn't one, and polling some
# backend (docker/kubectl/nomad/ssh) until a condition comes true instead of
# racing its own async startup. Sourced through common/bootstrap.sh, same as
# every other common/*.sh file.
#
# Several functions here are only ever invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

# ---- suite scaffolding ----------------------------------------------------

# Scratch dir every suite works in, plus the containers a suite has started
# that its exit trap has to tear down. Both are set up by _hi_workdir and
# consumed by _hi_test_cleanup below.
_HI_WORKDIR=""
_HI_EXTRA_CLEANUP=""
declare -a _HI_STARTED=()

# Creates the suite's scratch dir as $_HI_WORKDIR and registers the one exit
# trap it needs. $1 is a slug for the mktemp template ("checktest", "sshtest",
# ...); $2, if given, names a suite-specific cleanup function (stopping a nomad
# agent, deleting a kind cluster, ...) run before the generic teardown.
# _hi_on_exit installs a *single* trap rather than appending to one, so
# everything that has to happen on the way out goes through here.
function _hi_workdir() {
  _HI_WORKDIR="$(mktemp -d -t "hi.$1.XXXXXX")"
  _HI_EXTRA_CLEANUP="${2:-}"
  _hi_on_exit _hi_test_cleanup
}

# Every step is guarded and the whole thing ends in `return 0`: this runs as
# an exit trap under `set -e`, where one failing step would otherwise skip
# every step after it - leaving containers or the scratch dir behind.
function _hi_test_cleanup() {
  local c
  if [ -n "$_HI_EXTRA_CLEANUP" ]; then
    "$_HI_EXTRA_CLEANUP" || true
  fi
  for c in "${_HI_STARTED[@]:-}"; do
    if [ -n "$c" ]; then
      "${_HI_STARTED_BACKEND:-docker}" rm -f "$c" >/dev/null 2>&1 || true
    fi
  done
  if [ -n "$_HI_WORKDIR" ]; then
    rm -rf "$_HI_WORKDIR" || true
  fi
  return 0
}

# Registers a container for teardown by _hi_test_cleanup. Suites driving a
# non-docker CLI set _HI_STARTED_BACKEND (podman) first - every backend that
# reaches here takes docker's `rm -f <name>` shape.
function _hi_track_container() {
  _HI_STARTED+=("$1")
}

# Runs "$@" as one sub-case of a multi-case test file (one shell, one
# container shape, one scenario, ...), bumping the caller's _HI_TOTAL/
# _HI_FAILED counters accordingly. Set both to 0 via _hi_suite_begin before
# the first case runs, so _hi_suite_end can report "$_HI_FAILED/$_HI_TOTAL
# cases failed" instead of a bare pass/fail.
function _hi_case() {
  _HI_TOTAL=$((_HI_TOTAL + 1))
  "$@" || _HI_FAILED=$((_HI_FAILED + 1))
}

# Runs "$@" (a predicate function or command) and reports it under $1 as a
# human-readable label. The unit suites always want this wrapped in _hi_case,
# which is what _hi_check below is; the e2e suites bring their own case
# runners, which report their own timings, and so use _hi_case directly.
function _hi_assert() {
  local label="$1"
  shift
  if "$@"; then
    _hi_cecho " | $label: OK" "$GREEN"
  else
    _hi_cecho " | $label: FAILED" "$RED"
    return 1
  fi
}

# _hi_check <label> <predicate...> - one counted, labelled assertion.
function _hi_check() {
  _hi_case _hi_assert "$@"
}

function _hi_suite_begin() {
  _HI_FAILED=0
  _HI_TOTAL=0
}

# Closing banner + exit status for a suite: green when nothing failed, red
# with the failed/total count otherwise, exiting with the number of failed
# cases (which is what test_runner.sh reports per suite). $1 is the subject
# for the default wording ("check.sh" -> "All check.sh checks passed (N
# cases)"); $2/$3 override the pass/fail lines outright, for suites whose
# banners aren't about "checks" (shells, scenarios, connection paths).
function _hi_suite_end() {
  local subject="$1"
  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "${2:-All $subject checks passed ($_HI_TOTAL cases)}"
  else
    _hi_h1 "${3:-$_HI_FAILED/$_HI_TOTAL $subject checks FAILED}" "$RED"
  fi
  exit "$_HI_FAILED"
}

# Skips the whole suite (exit 0, not a failure - see test_runner.sh's summary)
# unless $1 is on PATH. $2 overrides the default "not installed" reason, for
# the backends whose absence needs explaining (nomad's dev agent needing
# docker, kind needing it to run cluster nodes, ...).
function _hi_require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_cecho "$1 ${2:-not installed}, skipping" "$YELLOW"
  exit 0
}

# _hi_require for a container backend, which also has to be reachable, not
# just installed - `docker info` is what actually proves the daemon answers.
function _hi_require_backend() {
  _hi_require "$1" "${2:-not installed}"
  "$1" info >/dev/null 2>&1 && return 0
  _hi_cecho "$1 not reachable, skipping" "$YELLOW"
  exit 0
}

# ---- target-side probe commands -------------------------------------------

# The command each e2e suite runs *on the target* to prove hi actually landed
# there; it echoes $1 (the suite's marker) only if the assertion holds, and
# the suite greps the session transcript for that marker. $2 picks the shape:
#
#   bash              hi.sh's main branch chainloads straight to `bash
#                     --rcfile hi.bashrc` without sourcing aliases.sh itself,
#                     so this asserts the copy landed *and* sources it directly
#   fallback          the container fallback branch (see _say_hi_container's
#                     `no bash` arm) only copies+sources shells/aliases.sh -
#                     it never touches common/paths.sh, so $_HI_ALIASES and
#                     hi_info aren't in scope; check a plain alias instead
#   fallback_fish     fish aliases are functions, and its `alias name` (no
#                     value) is a syntax error rather than an existence check
#                     - same assertion as fallback, in fish's own dialect
#   ssh_fallback      the *ssh* fallback rc (see hi.sh's _hi_fallback_rc) does
#                     source paths.sh before running our command, unlike the
#                     container one - so hi_info is in scope here
#   ssh_fallback_fish ssh_fallback in fish's dialect
#   installed         the target already has a permanent hi.d: asserts _say_hi
#                     pointed straight at it ($_HI_ROOT = ~/hi.d) instead of
#                     shipping a fresh tree over
#
# Every string below stays single-quoted: the variables in it expand on the
# target, not here.
# shellcheck disable=SC2016 # these expand later, on the target
function _hi_probe_cmd() {
  local marker="$1"
  case "$2" in
  bash) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  fallback) printf '%s%s' 'alias sudo >/dev/null 2>&1 && echo ' "$marker" ;;
  fallback_fish) printf '%s%s' 'functions -q sudo; and echo ' "$marker" ;;
  ssh_fallback) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  ssh_fallback_fish) printf '%s%s' 'test -f "$_HI_ROOT/hi.sh"; and functions -q hi_info; and echo ' "$marker" ;;
  installed) printf '%s%s' 'test "$_HI_ROOT" = "$HOME/hi.d" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo ' "$marker" ;;
  *)
    _hi_cecho "unknown probe shape: $2" "$RED"
    return 1
    ;;
  esac
}

# ---- polling / process helpers --------------------------------------------

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
#
# An optional leading `-a <fn>` gives up early when <fn> starts failing: for
# waits on something that can die outright rather than just stay false (a
# backgrounded agent process, say), there's no point burning the full timeout
# once it's gone.
function _hi_poll_bool() {
  local abort=""
  if [ "$1" = -a ]; then
    abort="$2"
    shift 2
  fi
  local tries="$1" interval="$2" i
  shift 2
  for ((i = 0; i < tries; i++)); do
    "$@" >/dev/null 2>&1 && return 0
    if [ -n "$abort" ] && ! "$abort"; then
      return 1
    fi
    sleep "$interval"
  done
  return 1
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

# ---- throwaway sshd fixtures ----------------------------------------------

# The one debian sshd image ssh_test.sh and ssh_disconnect_test.sh share.
# Deliberately *not* removed on the way out of either suite: it's a
# multi-minute apt-based build, it's tagged deterministically, and having the
# second suite reuse what the first built is the whole point. The
# suite-specific images layered on or beside it (the alpine variants, the
# pre-installed one) are still cleaned up by their own suites.
_HI_SSHD_IMAGE=hi-test-sshd

# Everything both sshd entrypoints do past the shebang/login-shell line -
# useradd/adduser -D both lock the account, and sshd refuses locked accounts
# outright even for pubkey auth, so both need the chpasswd unlock. Kept as a
# string rather than a file so the alpine images in ssh_test.sh can prepend
# their own `#!/bin/sh` header to the same body.
#
# $SSHD_OPTS is appended unquoted so a suite can pass extra sshd flags at
# `docker run` time instead of baking a second near-identical image:
# ssh_disconnect_test.sh needs a short ClientAliveInterval so the server gives
# up on a gone-silent client in seconds rather than the OS-default TCP timeout.
_HI_SSHD_ENTRYPOINT_BODY="$(
  cat <<'EOF'
echo "hitest:*" | chpasswd -e
chown hitest:hitest /home/hitest
install -d -m 700 -o hitest -g hitest /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown hitest:hitest /home/hitest/.ssh/authorized_keys
chmod 600 /home/hitest/.ssh/authorized_keys
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e -o PasswordAuthentication=no -o PermitRootLogin=no -o UsePAM=no $SSHD_OPTS
EOF
)"

# Client-side ssh flags every connection in both suites needs: never touch the
# user's real known_hosts, never fall back to their real keys, stay quiet.
declare -a _HI_SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o IdentitiesOnly=yes
)

# Throwaway ed25519 keypair at $_HI_WORKDIR/id, with the public half left in
# $_HI_PUBKEY for the container entrypoint to install as authorized_keys.
function _hi_ssh_keypair() {
  _hi_h2 "Generating throwaway ed25519 keypair at $_HI_WORKDIR/id"
  ssh-keygen -t ed25519 -N '' -q -f "$_HI_WORKDIR/id"
  _HI_PUBKEY="$(cat "$_HI_WORKDIR/id.pub")"
}

# Builds $_HI_SSHD_IMAGE. It carries the superset of shells both suites want
# (bash's presence, not the login shell, is what _say_hi branches on, so one
# image covers every with-bash login shell) and picks its login shell up from
# $LOGIN_SHELL at run time. Returns non-zero if the build failed, leaving the
# reason in $_HI_WORKDIR/sshd.log.
function _hi_sshd_image() {
  local ctx="$_HI_WORKDIR/sshd"
  mkdir -p "$ctx"

  cat >"$ctx/Dockerfile" <<'EOF'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server openssl bash dash zsh fish \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

  {
    # shellcheck disable=SC2016 # this is entrypoint.sh content, resolved on the container
    printf '#!/bin/bash\nset -e\nusermod -s "${LOGIN_SHELL:-/bin/bash}" hitest\n'
    printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
  } >"$ctx/entrypoint.sh"

  _hi_h3 "Building $_HI_SSHD_IMAGE from $ctx"
  docker build -q -t "$_HI_SSHD_IMAGE" "$ctx" >/dev/null 2>"$_HI_WORKDIR/sshd.log"
}

# Polls until the container's sshd on 127.0.0.1:$1 actually completes a
# handshake, so the real test isn't racing the container's boot. Uses the
# keypair _hi_ssh_keypair left in $_HI_WORKDIR.
function _hi_ssh_reachable() {
  ssh -i "$_HI_WORKDIR/id" -p "$1" -o BatchMode=yes "${_HI_SSH_OPTS[@]}" \
    -o ConnectTimeout=2 hitest@127.0.0.1 true
}

# ---- the docker/podman end-to-end suite -----------------------------------

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
  local backend="$1" marker

  _hi_require_backend "$backend"
  _HI_STARTED_BACKEND="$backend"
  _hi_workdir "${backend}test"
  _hi_h1 "Testing hi's $backend path across container shell environments"

  # --- build the test images ----------------------------------------------
  # debian ships bash out of the box, so it alone exercises _say_hi_container's
  # main branch. The other three are bash-less images, each with exactly one of
  # zsh/fish/sh on PATH, so each exercises exactly one arm of the fallback's
  # `for s in zsh fish sh` probe - a plain alpine image already has nothing but
  # sh, so it needs no image build of its own.
  _hi_h2 "Building test images"
  local shell zsh_ok=1 fish_ok=1
  for shell in zsh fish; do
    mkdir -p "$_HI_WORKDIR/$shell"
    printf 'FROM alpine:3.20\nRUN apk add --no-cache %s\n' "$shell" >"$_HI_WORKDIR/$shell/Dockerfile"
    _hi_h3 "Building hi-${backend}test-$shell" "$BLUE"
    if ! "$backend" build -q -t "hi-${backend}test-$shell" "$_HI_WORKDIR/$shell" \
      >/dev/null 2>"$_HI_WORKDIR/$shell.log"; then
      _hi_cecho " | $shell image failed to build, skipping the $shell fallback (see $_HI_WORKDIR/$shell.log)" "$YELLOW"
      if [ "$shell" = zsh ]; then zsh_ok=0; else fish_ok=0; fi
    fi
  done

  # --- the actual per-shell test -------------------------------------------
  marker="HI_$(printf '%s' "$backend" | tr '[:lower:]' '[:upper:]')_TEST_OK"

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

  _hi_suite_begin

  # polls until the container is actually running, so the real test isn't
  # racing the container's start
  function _hi_container_running() { [ "$("$backend" container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

  function _hi_run_case() {
    local label="$1" image="$2" cmd="$3" timeout_s="${4:-20}"
    local name out_file out exit_code=0 t0 t1 ok=1

    name="hi-${backend}test-$label-$$"
    _hi_h3 "Testing shell: $label"
    t0="$(_hi_now)"

    if ! "$backend" run -d --name "$name" "$image" tail -f /dev/null >/dev/null 2>"$_HI_WORKDIR/$label.run.log"; then
      _hi_cecho " | Failed to start container (image: $image)" "$RED"
      return 1
    fi
    _hi_track_container "$name"
    _hi_cecho " | Container: $name (image: $image)"

    if ! _hi_poll_bool 40 0.25 _hi_container_running "$name"; then
      _hi_cecho " | Container never reported running" "$RED"
      return 1
    fi

    out_file="$_HI_WORKDIR/$label.out"
    _hi_cecho " | Running: $_HI_LAUNCHER $name $cmd"
    # backgrounded so a hung fallback (e.g. a shell that never honors the
    # trailing `exit`) can't wedge the whole test suite
    "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" "$name" "$cmd" <&3 >"$out_file" 2>&1 &
    function _hi_on_timeout() { _hi_h3 " | [$label] -- TIMED OUT after ${timeout_s}s, killing"; }
    _hi_wait_pid "$!" "$timeout_s" _hi_on_timeout
    exit_code="$_HI_WAIT_EXIT"
    t1="$(_hi_now)"

    out="$(cat "$out_file" 2>/dev/null)"
    if printf '%s' "$out" | grep -q "$marker"; then
      _hi_cecho " | [$label] -- $backend path OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    else
      _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)"
      printf '%s\n' "$out" | sed 's/^/      /'
      ok=0
    fi

    "$backend" rm -f "$name" >/dev/null 2>&1
    [ "$ok" -eq 1 ]
  }

  # each guarded with `if`, not `&&`: under `set -e` a failing `[ ... ] && ...`
  # list is itself a failing command, which would abandon the cases after it
  _hi_case _hi_run_case bash debian:bookworm-slim "$(_hi_probe_cmd "$marker" bash)"
  if [ "$zsh_ok" -eq 1 ]; then
    _hi_case _hi_run_case zsh "hi-${backend}test-zsh" "$(_hi_probe_cmd "$marker" fallback)"
  fi
  if [ "$fish_ok" -eq 1 ]; then
    _hi_case _hi_run_case fish "hi-${backend}test-fish" "$(_hi_probe_cmd "$marker" fallback_fish)"
  fi
  _hi_case _hi_run_case sh alpine:3.20 "$(_hi_probe_cmd "$marker" fallback)"

  "$backend" image rm -f "hi-${backend}test-zsh" "hi-${backend}test-fish" >/dev/null 2>&1 || true

  _hi_suite_end "$backend" \
    "hi's $backend path survived every shell environment tested ($_HI_TOTAL cases)" \
    "hi's $backend path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}
