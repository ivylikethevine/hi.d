#!/bin/bash
# Shared scaffolding for every suite under tests
#
# Several functions here are only ever invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

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
      "${_HI_BACKEND:-docker}" rm -f "$c" >/dev/null 2>&1 || true
    fi
  done
  if [ -n "$_HI_WORKDIR" ]; then
    rm -rf "$_HI_WORKDIR" || true
  fi
  return 0
}

# Registers a container for teardown by _hi_test_cleanup. Suites driving a
# non-docker CLI set _HI_BACKEND (podman) first - every backend that
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

function _hi_rendered() {
  printf '%b' "$1"
}

function _hi_has_rendered() {
  local needle
  printf -v needle '%b' "$2"
  [[ "$1" == *"$needle"* ]]
}

function _hi_suite_begin() {
  _HI_FAILED=0
  _HI_TOTAL=0
}

# _hi_report_counts <total> <failed> - hand this suite's tally up to
# test_runner.sh, which sums every suite's into the pass/fail columns of its
# summary table. $_HI_COUNTS_FILE is only set when running under the runner,
# so a suite executed on its own is a no-op here. A suite that exits before
# reporting (_hi_require's skip path) contributes nothing, which is why the
# runner renders "-" rather than 0 for those. _hi_suite_end calls this for
# every suite built on the standard counters; shellcheck_test.sh, whose unit
# is files rather than cases, calls it directly.
function _hi_report_counts() {
  [ -n "${_HI_COUNTS_FILE:-}" ] || return 0
  printf '%s %s\n' "$1" "$2" >"$_HI_COUNTS_FILE"
}

function _hi_suite_end() {
  local subject="$1"
  _hi_report_counts "$_HI_TOTAL" "$_HI_FAILED"
  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "${2:-All $subject checks passed ($_HI_TOTAL cases)}"
  else
    _hi_h1 "${3:-$_HI_FAILED/$_HI_TOTAL $subject checks FAILED}" "$RED"
  fi
  exit "$_HI_FAILED"
}

function _hi_require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_cecho "$1 ${2:-not installed}, skipping" "$YELLOW"
  exit 0
}

function _hi_require_backend() {
  _hi_require "$@"
  "$1" info >/dev/null 2>&1 && return 0
  _hi_cecho "$1 not reachable, skipping" "$YELLOW"
  exit 0
}

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

_HI_PTY_SPAWN='import pty, sys; sys.exit(pty.spawn(sys.argv[1:]))'

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
      _HI_PTY_WRAP=(python3 -c "$_HI_PTY_SPAWN")
    else
      _hi_cecho " | $warning" "$YELLOW"
    fi
  fi
}

# The same prefix in its own array, always built, alongside whatever
# _hi_pty_wrap decided. _hi_interactive_case needs one even when the suite is
# running on a real terminal: it drives the session by *writing* to the
# launcher's stdin, so that stdin is a pipe from us rather than the terminal,
# and both `ssh -t` and `<backend> exec -it` want a tty there. Left empty when
# python3 is missing, which is what makes those cases skip rather than fail.
_HI_PTY_FORCED=()
function _hi_pty_force() {
  _HI_PTY_FORCED=()
  command -v python3 >/dev/null 2>&1 && _HI_PTY_FORCED=(python3 -c "$_HI_PTY_SPAWN")
  return 0
}

# The _hi_pty_wrap preamble every suite that backgrounds the launcher through
# _hi_exec_case needs: stashes our real stdin on fd 3 and decides the pty
# wrap from *that*. $1 is _hi_pty_wrap's mode, $2 its warning.
#
# `<backend> exec -it` and `kubectl exec -it` refuse to allocate a remote tty
# unless our own stdin already is one - true whenever this runs headless/CI -
# so a locally-faked pty is what makes these suites reliable everywhere rather
# than only from an interactive terminal.
#
# The tty check has to happen against a duplicated fd, not fd 0 directly: the
# launcher runs backgrounded with `&`, and since job control is off in a
# non-interactive script, bash silently rewires a backgrounded job's stdin to
# /dev/null regardless of what the script's own stdin was - so testing `-t 0`
# here and then handing the background job fd 0 later would report a real
# terminal and still fail. Duplicating to fd 3 up front and threading `<&3`
# through to the background command (which _hi_exec_case does) keeps the
# original tty-ness intact either way - which is also why the two have to be
# used together.
function _hi_pty_stdin() {
  exec 3<&0
  _hi_pty_wrap 3 "$1" "$2"
}

function _hi_poll_budget() {
  awk -v t="$1" -v i="$2" \
    'BEGIN { b = t * i; b = (b == int(b) ? b : int(b) + 1); printf "%d", (b < 1 ? 1 : b) }'
}

function _hi_poll_bool() {
  local abort=""
  if [ "$1" = -a ]; then
    abort="$2"
    shift 2
  fi
  local tries="$1" interval="$2" i deadline
  shift 2
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval")))
  for ((i = 0; i < tries; i++)); do
    "$@" >/dev/null 2>&1 && return 0
    if [ -n "$abort" ] && ! "$abort"; then
      return 1
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep "$interval"
  done
  return 1
}

function _hi_poll_value() {
  local tries="$1" interval="$2" out i deadline
  shift 2
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval")))
  for ((i = 0; i < tries; i++)); do
    out="$("$@" 2>/dev/null)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep "$interval"
  done
  return 1
}

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

function _hi_exec_case() {
  local label="$1" what="$2" marker="$3" timeout_s="$4" target="$5" cmd="$6" hook="${7:-}"
  local out_file="$_HI_WORKDIR/$label.out" exit_code t0 t1

  _hi_cecho " | Running: $_HI_LAUNCHER $target $cmd"
  t0="$(_hi_now)"
  "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" "$target" "$cmd" <&3 >"$out_file" 2>&1 &
  function _hi_on_timeout() {
    _hi_h3 " | [$label] -- TIMED OUT after ${timeout_s}s, killing" "$RED"
    [ -n "$hook" ] && "$hook"
    return 0
  }
  _hi_wait_pid "$!" "$timeout_s" _hi_on_timeout
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  if grep -q "$marker" "$out_file" 2>/dev/null; then
    _hi_cecho " | [$label] -- $what OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)" "$RED"
  sed 's/^/      /' "$out_file" 2>/dev/null
  return 1
}

# Like _hi_exec_case, but drives a real *interactive* session instead of a
# one-off command - the only shape that reaches load.sh's load(). hi.sh's
# $CMDARG replaces `load` outright in the bootloader (see _hi_bootloader), so a
# command-shaped case never exercises the header, the rc grafting, the shell
# handoff or clean_all; this one does. The session is driven by piping a
# printf and an `exit` into it after a settle, and it asserts both the marker
# (an interactive shell really came up and ran our line) and load()'s closing
# line (its exit path ran, rather than the session dying early).
#
# _hi_interactive_case <label> <what> <marker> <timeout_s> <launcher...> -
# where <launcher...> is the *bare* command, with no pty prefix of its own:
# _HI_PTY_FORCED is prepended here (see _hi_pty_force, which the suite must
# have called first).
function _hi_interactive_case() {
  local label="$1" what="$2" marker="$3" timeout_s="$4"
  shift 4
  local out_file="$_HI_WORKDIR/$label.interactive.out" exit_code t0 t1
  # a pty echoes back everything we type, so the line we send must not itself
  # contain what we grep for - the shell has to assemble it. printf's two
  # arguments arrive space-separated on the echoed line and hyphen-joined only
  # in the real output, in every shell load() might hand us.
  local expected="$marker-INTERACTIVE"

  if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
    _hi_cecho " | [$label] -- skipped: no python3 to drive an interactive pty" "$YELLOW"
    return 0
  fi

  _hi_cecho " | Running (interactive): $*"
  t0="$(_hi_now)"
  # the leading sleep lets the session get all the way to its shell before the
  # input lands; the trailing one keeps the pipe open long enough for load()'s
  # closing lines to make it into the transcript
  {
    sleep "${_HI_INTERACTIVE_SETTLE:-4}"
    printf "printf '%%s-%%s\\\\n' %s INTERACTIVE\nexit\n" "$marker"
    sleep 2
  } | "${_HI_PTY_FORCED[@]}" "$@" >"$out_file" 2>&1 &
  function _hi_on_timeout() {
    _hi_h3 " | [$label] -- TIMED OUT after ${timeout_s}s, killing" "$RED"
    return 0
  }
  _hi_wait_pid "$!" "$timeout_s" _hi_on_timeout
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  if grep -qF "$expected" "$out_file" 2>/dev/null && grep -q "hi closing" "$out_file" 2>/dev/null; then
    _hi_cecho " | [$label] -- $what OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)" "$RED"
  sed 's/^/      /' "$out_file" 2>/dev/null
  return 1
}

_HI_SSHD_IMAGE=hi-test-sshd

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

function _hi_build_image() {
  local label="$1" tag="$2" what="$3"
  shift 3
  _hi_h3 "Building $tag" "$BLUE"
  "${_HI_BACKEND:-docker}" build -q -t "$tag" "$@" >/dev/null 2>"$_HI_WORKDIR/$label.log" && return 0
  _hi_cecho " | $tag failed to build, skipping $what (see $_HI_WORKDIR/$label.log)" "$YELLOW"
  return 1
}

declare -a _HI_SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o IdentitiesOnly=yes
)

function _hi_ssh_keypair() {
  _hi_h2 "Generating throwaway ed25519 keypair at $_HI_WORKDIR/id"
  ssh-keygen -t ed25519 -N '' -q -f "$_HI_WORKDIR/id"
  _HI_PUBKEY="$(cat "$_HI_WORKDIR/id.pub")"
}

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

  _hi_build_image sshd "$_HI_SSHD_IMAGE" "$1" "$ctx"
}

function _hi_ssh_reachable() {
  ssh -i "$_HI_WORKDIR/id" -p "$1" -o BatchMode=yes "${_HI_SSH_OPTS[@]}" \
    -o ConnectTimeout=2 hitest@127.0.0.1 true
}

# Boots one throwaway sshd container <name> from <image>, waits until its sshd
# actually answers, and leaves the mapped port in $_HI_SSH_PORT. Any further
# arguments go to `docker run` ahead of the image - that's how the per-suite
# `-e` vars ride in (LOGIN_SHELL, SSHD_OPTS), instead of each wanting an image
# of its own. Registers the container for teardown, and returns non-zero,
# having said why, if it never came up.
function _hi_sshd_container() {
  local name="$1" image="$2"
  shift 2

  if ! docker run -d --rm --name "$name" -p 127.0.0.1::22 -e "PUBKEY=$_HI_PUBKEY" "$@" "$image" \
    >/dev/null 2>"$_HI_WORKDIR/$name.log"; then
    _hi_cecho " | Failed to start container (see $_HI_WORKDIR/$name.log)" "$RED"
    return 1
  fi
  _hi_track_container "$name"

  _HI_SSH_PORT="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
  _hi_cecho " | Container: $name (port: $_HI_SSH_PORT)"
  _hi_cecho " | Waiting for sshd on 127.0.0.1:$_HI_SSH_PORT"
  if ! _hi_poll_bool 40 0.25 _hi_ssh_reachable "$_HI_SSH_PORT"; then
    _hi_cecho " | Sshd never came up" "$RED"
    return 1
  fi
}

# The client-side launcher invocation both ssh suites make: hi.sh pointed at
# the throwaway sshd on 127.0.0.1:$1, with the keypair and flags the fixtures
# above set up. Left in the array $_HI_SSH_LAUNCH rather than run here, since
# the callers redirect and background it differently - append the remote
# command and go. Call it *after* _hi_pty_wrap, whose result it captures.
# $_HI_SSH_LAUNCH_BARE is the same command without that prefix, for
# _hi_interactive_case, which brings its own (see _hi_pty_force).
function _hi_ssh_launch() {
  _HI_SSH_LAUNCH_BARE=("$_HI_LAUNCHER" -p "$1" -i "$_HI_WORKDIR/id"
    "${_HI_SSH_OPTS[@]}" -o ConnectTimeout=5 hitest@127.0.0.1)
  _HI_SSH_LAUNCH=("${_HI_PTY_WRAP[@]}" "${_HI_SSH_LAUNCH_BARE[@]}")
}

# Boots throwaway containers - one per shell environment - and drives hi.sh's
# real _say_hi_container against each of them over `<backend> exec`. Podman's
# CLI is a full drop-in for docker's here, so
# docker_test.sh and podman_test.sh are both just `_hi_container_backend_test
# docker|podman` - this one function proves both branches of
# _say_hi_container: the bash-present main path (tar copy + `bash --rcfile`),
# and every arm of the bash-less fallback's `for s in zsh fish sh` probe.
# Everything is ephemeral and nothing touches host ssh config. Skips cleanly
# if $backend isn't installed/running. Needs network access the first time it
# runs, to pull/build the test images.
function _hi_container_backend_test() {
  local backend="$1" marker _HI_CONTAINER=""

  _hi_require_backend "$backend"
  _HI_BACKEND="$backend"
  _hi_workdir "${backend}test"
  _hi_h1 "Testing hi's $backend path across container shell environments"

  _hi_h2 "Building test images"
  local shell
  local -A shell_ok=()
  for shell in zsh fish; do
    mkdir -p "$_HI_WORKDIR/$shell"
    printf 'FROM alpine:3.20\nRUN apk add --no-cache %s\n' "$shell" >"$_HI_WORKDIR/$shell/Dockerfile"
    shell_ok[$shell]=1
    _hi_build_image "$shell" "hi-${backend}test-$shell" "the $shell fallback" "$_HI_WORKDIR/$shell" ||
      shell_ok[$shell]=0
  done

  marker="HI_$(printf '%s' "$backend" | tr '[:lower:]' '[:upper:]')_TEST_OK"

  _hi_pty_stdin auto "no tty and no python3 to fake one - $backend exec -it will fail outright, results may be unreliable"
  _hi_pty_force

  _hi_suite_begin

  function _hi_container_running() { [ "$("$backend" container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]; }

  function _hi_start_case_container() {
    local label="$1" image="$2"

    _HI_CONTAINER="hi-${backend}test-$label-$$"
    _hi_h3 "Testing shell: $label"

    if ! "$backend" run -d --name "$_HI_CONTAINER" "$image" tail -f /dev/null \
      >/dev/null 2>"$_HI_WORKDIR/$label.run.log"; then
      _hi_cecho " | Failed to start container (image: $image)" "$RED"
      return 1
    fi
    _hi_track_container "$_HI_CONTAINER"
    _hi_cecho " | Container: $_HI_CONTAINER (image: $image)"

    if ! _hi_poll_bool 40 0.25 _hi_container_running "$_HI_CONTAINER"; then
      _hi_cecho " | Container never reported running" "$RED"
      return 1
    fi
  }

  function _hi_run_case() {
    local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
    local ok=0

    _hi_start_case_container "$label" "$image" || return 1
    _hi_exec_case "$label" "$backend path" "$marker" "$timeout_s" "$_HI_CONTAINER" "$cmd" && ok=1
    "$backend" rm -f "$_HI_CONTAINER" >/dev/null 2>&1
    [ "$ok" -eq 1 ]
  }

  function _hi_run_interactive_case() {
    local label="$1" image="$2" timeout_s="${3:-60}"
    local ok=0

    _hi_start_case_container "$label" "$image" || return 1
    if _hi_interactive_case "$label" "$backend path (interactive)" "$marker" \
      "$timeout_s" "$_HI_LAUNCHER" "$_HI_CONTAINER"; then
      ok=1
      if "$backend" exec "$_HI_CONTAINER" sh -c 'ls -d /tmp/*.hi.log.* >/dev/null 2>&1'; then
        _hi_cecho " | [$label] -- FAILED: hi.d's copy was left behind in the container" "$RED"
        ok=0
      fi
    fi
    "$backend" rm -f "$_HI_CONTAINER" >/dev/null 2>&1
    [ "$ok" -eq 1 ]
  }

  _hi_case _hi_run_case bash debian:bookworm-slim "$(_hi_probe_cmd "$marker" bash)"
  _hi_case _hi_run_interactive_case bash-interactive debian:bookworm-slim
  local spec
  for spec in zsh:fallback fish:fallback_fish; do
    shell="${spec%%:*}"
    if [ "${shell_ok[$shell]}" -eq 1 ]; then
      _hi_case _hi_run_case "$shell" "hi-${backend}test-$shell" "$(_hi_probe_cmd "$marker" "${spec#*:}")"
    fi
  done
  _hi_case _hi_run_case sh alpine:3.20 "$(_hi_probe_cmd "$marker" fallback)"

  "$backend" image rm -f "hi-${backend}test-zsh" "hi-${backend}test-fish" >/dev/null 2>&1 || true

  _hi_suite_end "$backend" \
    "hi's $backend path survived every shell environment tested ($_HI_TOTAL cases)" \
    "hi's $backend path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}
