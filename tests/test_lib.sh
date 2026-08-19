#!/bin/bash
# Shared scaffolding for every suite under tests
#
# Several functions here are only ever invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# Isolation, and it has to happen before bootstrap.sh: that resolves
# $_HI_SETTINGS/$_HI_COLORS/$_HI_PACKAGES against $_HI_CONFIG_DIR once, so by
# the time a suite runs it is too late to stop the developer's own
# ~/.config/hi.d from deciding what those point at. Deliberately a path that
# does not exist yet, so the baseline every suite starts from is "no overlay,
# in-tree defaults"; a test wanting an overlay mkdir's this and writes into it,
# and _hi_test_cleanup takes it away again. Same rule as never touching the
# real ~/hi.d.
export XDG_CONFIG_HOME="${TMPDIR:-/tmp}/hi.testcfg.$$"
export _HI_CONFIG_DIR="$XDG_CONFIG_HOME/hi.d"

# shellcheck source=../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"

# Scratch dir every suite works in, plus the ledger of everything its exit trap
# has to take away again: containers, docker networks, and processes a case
# SIGSTOPped. Both are set up by _hi_workdir and consumed by _hi_test_cleanup.
#
# The ledger is a *file* and not an array, for two reasons that both cost real
# containers on a real machine. A case may run in a background subshell (see
# _hi_par_case), where an array append dies with the subshell and the container
# it started is never registered. And a file can be written *before* the thing
# exists - the window between `docker run` returning and the name being
# recorded is exactly where a ^C leaks one, so every writer below registers
# first and starts second. Removing something twice is a no-op; removing
# something that never started is a no-op too. Missing one is not.
_HI_WORKDIR=""
_HI_EXTRA_CLEANUP=""
_HI_LEDGER=""

# Creates the suite's scratch dir as $_HI_WORKDIR and registers the one exit
# trap it needs. $1 is a slug for the mktemp template ("checktest", "sshtest",
# ...); $2, if given, names a suite-specific cleanup function (stopping a nomad
# agent, deleting a kind cluster, ...) run before the generic teardown.
# _hi_on_exit installs a *single* trap rather than appending to one, so
# everything that has to happen on the way out goes through here.
function _hi_workdir() {
  _HI_WORKDIR="$(mktemp -d -t "hi.$1.XXXXXX")"
  _HI_EXTRA_CLEANUP="${2:-}"
  _HI_LEDGER="$_HI_WORKDIR/.ledger"
  : >"$_HI_LEDGER"
  _hi_on_exit _hi_test_cleanup
}

# _hi_ledger <kind> <value> - one line on the teardown ledger. A single short
# printf to a file opened O_APPEND, which is what makes concurrent cases writing
# it safe: one write, far under PIPE_BUF, so lines never interleave.
function _hi_ledger() {
  [ -n "$_HI_LEDGER" ] || return 0
  printf '%s %s\n' "$1" "$2" >>"$_HI_LEDGER"
  return 0
}

# _hi_ledger_rows <kind> - the values registered under <kind>, one per line.
function _hi_ledger_rows() {
  local kind value
  [ -n "$_HI_LEDGER" ] && [ -f "$_HI_LEDGER" ] || return 0
  while read -r kind value; do
    [ "$kind" = "$1" ] && printf '%s\n' "$value"
  done <"$_HI_LEDGER"
  return 0
}

# Registers a container for teardown by _hi_test_cleanup. Suites driving a
# non-docker CLI set _HI_BACKEND (podman) first - every backend that
# reaches here takes docker's `rm -f <name>` shape.
function _hi_track_container() { _hi_ledger container "$1"; }

# The same, for a docker network: the relay suite builds one per case, and it
# can only go after the containers on it (hence the sweep order below).
function _hi_track_network() { _hi_ledger network "$1"; }

# Every step is guarded and the whole thing ends in `return 0`: this runs as
# an exit trap under `set -e`, where one failing step would otherwise skip
# every step after it - leaving containers or the scratch dir behind.
#
# The order is not arbitrary. Background cases are killed first - before the
# suite's own hook, even: a case still running would put a container, a job or a
# pod back behind whatever the hook and the sweep have just taken away. Frozen pids come next, and
# before their containers: a SIGSTOPped process cannot act on SIGKILL until it
# is scheduled again (see _hi_thaw_frozen), and taking its sshd away first
# leaves it stopped forever, holding a socket to nothing. Networks come last,
# because docker refuses to remove one that still has a container on it.
function _hi_test_cleanup() {
  local c
  _hi_par_kill
  if [ -n "$_HI_EXTRA_CLEANUP" ]; then
    "$_HI_EXTRA_CLEANUP" || true
  fi
  for c in $(_hi_ledger_rows frozen); do
    kill -CONT "$c" 2>/dev/null || true
    kill -9 "$c" 2>/dev/null || true
  done
  for c in $(_hi_ledger_rows container); do
    _hi_rm_container "$c"
  done
  for c in $(_hi_ledger_rows network); do
    "${_HI_BACKEND:-docker}" network rm "$c" >/dev/null 2>&1 || true
  done
  if [ -n "$_HI_WORKDIR" ]; then
    rm -rf "$_HI_WORKDIR" || true
  fi
  # the isolated config overlay from the top of this file, if a test made one
  rm -rf "$XDG_CONFIG_HOME" || true
  return 0
}

# _hi_rm_container <name> - the eager between-cases teardown, as one idiom:
# every e2e case removes its container the moment its verdict is in rather
# than letting them pile up until _hi_test_cleanup sweeps the stragglers.
function _hi_rm_container() {
  "${_HI_BACKEND:-docker}" rm -f "$1" >/dev/null 2>&1 || true
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
    _hi_note_failure "$label"
    return 1
  fi
}

# _hi_check <label> <predicate...> - one counted, labelled assertion.
function _hi_check() {
  _hi_case _hi_assert "$@"
}

# --- running cases in parallel -------------------------------------------------
#
# The container suites are nearly the whole cost of a full run, and nearly all
# of that is spent waiting on one container at a time while the machine idles.
# Every case already builds its own container under its own name, so the
# containers never collided - the harness around them did, in three places:
#
#   - **the counters.** _hi_case increments $_HI_TOTAL/$_HI_FAILED in the
#     current shell, and a background subshell's increments die with it. A case
#     writes its verdict to a file instead and _hi_par_wait tallies them in the
#     parent, which is the shape common/header.sh's _hi_probe_start /
#     _hi_probe_wait already uses for the header's backend probes.
#   - **teardown registration.** See the ledger above.
#   - **the transcript.** Concurrent _hi_cecho lines are unreadable, so each
#     case's output is buffered to its own file and replayed *in submission
#     order* once the batch is done. That is test_runner.sh's
#     collapse-and-replay idea one level down rather than a second mechanism:
#     a parallel run reads exactly like a serial one, only the timings overlap.
#
# Cases that share state stay serial through _hi_case - ssh_test.sh's two
# _hi_transcript_is_clean checks read files the bash32 cases write, so they run
# after the batch, not in it.
_HI_PAR_DIR=""
_HI_PAR_N=0
_HI_PAR_SLOTS=1
declare -a _HI_PAR_PIDS=()
declare -a _HI_PAR_LABELS=()
declare -a _HI_PAR_RUNNING=()

# How wide to fan out. Unbounded is the wrong answer on a laptop: twenty sshd
# containers, twenty ssh clients and twenty pty feeders thrash the docker daemon
# and swap the box, which is both slower and flakier than four. So the default
# is four, or the CPU count when that is smaller. $_HI_PAR_WIDTH overrides it,
# and _HI_PAR_WIDTH=1 is a genuine serial run down this same code path - what a
# suite whose fixtures are not case-scoped asks for (nomad's job list), and what
# bisecting a flake wants.
function _hi_par_width() {
  local cpus
  if [ -n "${_HI_PAR_WIDTH:-}" ]; then
    printf '%s' "$_HI_PAR_WIDTH"
    return 0
  fi
  cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || true)"
  case "$cpus" in '' | *[!0-9]*) cpus=2 ;; esac
  [ "$cpus" -lt 1 ] && cpus=1
  [ "$cpus" -gt 4 ] && cpus=4
  printf '%s' "$cpus"
}

# _hi_par_begin [what] - open a batch, and say out loud how wide it will run.
# A capped run must never read as "everything at once": same honesty rule the
# bench suite states about hyperfine, one directory over.
function _hi_par_begin() {
  _HI_PAR_DIR="$_HI_WORKDIR/par"
  rm -rf "$_HI_PAR_DIR"
  mkdir -p "$_HI_PAR_DIR"
  _HI_PAR_N=0
  _HI_PAR_PIDS=()
  _HI_PAR_LABELS=()
  _HI_PAR_RUNNING=()
  _HI_PAR_SLOTS="$(_hi_par_width)"
  if [ "$_HI_PAR_SLOTS" -le 1 ]; then
    _hi_cecho " | ${1:-cases}: one at a time (_HI_PAR_WIDTH=$_HI_PAR_SLOTS)" "$YELLOW"
  else
    _hi_cecho " | ${1:-cases}: $_HI_PAR_SLOTS at a time, transcripts replayed in submission order below" "$BLUE"
  fi
  return 0
}

# Blocks until a slot frees up. `wait <pid>` on each in turn and never `wait -n`
# (macOS ships bash 3.2, as header.sh's probes note), so a finished case is
# spotted by polling kill -0 and then reaped - the reap is what keeps the
# process table clean, and it returns immediately for a pid that has already
# exited.
function _hi_par_slot() {
  local pid
  local -a keep
  while [ "${#_HI_PAR_RUNNING[@]}" -ge "$_HI_PAR_SLOTS" ]; do
    keep=()
    for pid in ${_HI_PAR_RUNNING[@]+"${_HI_PAR_RUNNING[@]}"}; do
      if kill -0 "$pid" 2>/dev/null; then
        keep+=("$pid")
      else
        wait "$pid" 2>/dev/null || true
      fi
    done
    _HI_PAR_RUNNING=(${keep[@]+"${keep[@]}"})
    [ "${#_HI_PAR_RUNNING[@]}" -ge "$_HI_PAR_SLOTS" ] && sleep 0.25
  done
  return 0
}

# _hi_par_case <label> <fn> [args...] - _hi_case's parallel twin: same contract
# (one counted case, non-zero means failed), run in a background subshell once a
# slot is free. The verdict file carries the exit status *and* the case's own
# skip tally, since _hi_skip increments a variable that would otherwise die with
# the subshell too. A case that leaves no verdict at all - killed, or `exit`ed
# out from under us - is counted as a failure by _hi_par_wait rather than
# quietly vanishing from the totals.
function _hi_par_case() {
  local label="$1"
  shift
  _hi_par_slot
  _HI_PAR_N=$((_HI_PAR_N + 1))
  _HI_PAR_LABELS+=("$label")
  local out="$_HI_PAR_DIR/$_HI_PAR_N.out" res="$_HI_PAR_DIR/$_HI_PAR_N.res"
  _hi_cecho " | [$label] started" "$BLUE"
  (
    # the subshell-local counters SC2030/SC2031 warn about are the mechanism,
    # not the bug: they are reset here, written to the verdict file below, and
    # summed back into the caller's by _hi_par_wait
    # shellcheck disable=SC2030
    _HI_SKIPPED=0
    _hi_par_rc=0
    "$@" || _hi_par_rc=$?
    printf '%s %s\n' "$_hi_par_rc" "${_HI_SKIPPED:-0}" >"$res"
  ) >"$out" 2>&1 &
  _HI_PAR_RUNNING+=("$!")
  _HI_PAR_PIDS+=("$!")
  return 0
}

# Waits out the batch, then replays and tallies it in submission order.
function _hi_par_wait() {
  local pid i=0 label rc skipped
  for pid in ${_HI_PAR_PIDS[@]+"${_HI_PAR_PIDS[@]}"}; do wait "$pid" 2>/dev/null || true; done
  for label in ${_HI_PAR_LABELS[@]+"${_HI_PAR_LABELS[@]}"}; do
    i=$((i + 1))
    [ -f "$_HI_PAR_DIR/$i.out" ] && cat "$_HI_PAR_DIR/$i.out"
    rc=1
    skipped=0
    if [ -s "$_HI_PAR_DIR/$i.res" ]; then
      read -r rc skipped <"$_HI_PAR_DIR/$i.res"
    else
      _hi_cecho " | [$label] -- FAILED: the case left no verdict (killed, or it exited the subshell)" "$RED"
      _hi_note_failure "[$label] left no verdict"
    fi
    _HI_TOTAL=$((_HI_TOTAL + 1))
    [ "$rc" -eq 0 ] || _HI_FAILED=$((_HI_FAILED + 1))
    # shellcheck disable=SC2031 # this is the parent's copy, which is the point
    _HI_SKIPPED=$((${_HI_SKIPPED:-0} + skipped))
  done
  _HI_PAR_PIDS=()
  _HI_PAR_LABELS=()
  _HI_PAR_RUNNING=()
  _HI_PAR_N=0
  return 0
}

# The teardown half, reached from _hi_test_cleanup: stop anything still running
# before the ledger is swept, or a case mid-`docker run` puts a container back
# behind it. TERM first so a case's own traps get their chance, KILL after.
function _hi_par_kill() {
  local pid
  for pid in ${_HI_PAR_PIDS[@]+"${_HI_PAR_PIDS[@]}"}; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in ${_HI_PAR_PIDS[@]+"${_HI_PAR_PIDS[@]}"}; do
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  _HI_PAR_PIDS=()
  _HI_PAR_RUNNING=()
  return 0
}

# _hi_before <text> <first-pattern> <second-pattern> - both patterns present
# in <text>, and the first's earliest match on an earlier line. The ordering
# assertion several suites make about generated rc/bootloader content.
# `grep -m1` and a here-string, not `printf | grep | head | cut`: two processes
# per pattern instead of four, across ten call sites in the fast suites. The
# patterns stay grep's BREs on purpose - bash's own `=~` is an ERE, where the
# unescaped `+` in a caller's 'set +euo pipefail' silently stops being literal.
function _hi_before() {
  local a b
  a="$(grep -n -m1 "$2" <<<"$1")"
  b="$(grep -n -m1 "$3" <<<"$1")"
  [ -n "$a" ] && [ -n "$b" ] && [ "${a%%:*}" -lt "${b%%:*}" ]
}

# _hi_strip_ansi <text> - the palette taken back out, for suites asserting on
# geometry or plain content. The inverse of _hi_rendered, and one home for a
# regex that was hand-written in six suites, where a silent stop-matching is
# the failure mode.
function _hi_strip_ansi() {
  local out="$1" restore=0
  shopt -q extglob || {
    shopt -s extglob
    restore=1
  }
  out="${out//$'\e'\[*([0-9;])m/}"
  ((restore)) && shopt -u extglob
  printf '%s' "$out"
}

# _hi_table_is_rectangular <text> - every line of every boxed table in <text>
# is the same printed width. Both preview suites assert it through this one
# function, so they cannot segment tables differently. A table is a run of
# adjacent lines starting with `+` or `|`, so blank lines and prose between
# two tables separate them without being measured.
function _hi_table_is_rectangular() {
  local line stripped width=0 len seen=0
  while IFS= read -r line; do
    stripped="$(_hi_strip_ansi "$line")"
    case "$stripped" in
    [+\|]*)
      len=${#stripped}
      if [ "$width" -eq 0 ]; then
        width=$len
        seen=1
      elif [ "$len" -ne "$width" ]; then
        return 1
      fi
      ;;
    # anything else ends the current table; the next run measures itself afresh,
    # since two tables in one output need not share a width
    *) width=0 ;;
    esac
  done <<<"$1"
  [ "$seen" -eq 1 ]
}

# _hi_check_requires <bin> <label> <predicate...> - _hi_check, unless <bin> is
# missing, in which case the case counts as SKIPPED. The guard lives here, not
# inside the case body, where a `return 0` would report a green OK for a case
# that never ran.
function _hi_check_requires() {
  local bin="$1"
  shift
  if command -v "$bin" >/dev/null 2>&1; then
    _hi_check "$@"
  else
    _hi_skip "$1" "no $bin"
  fi
}

# _hi_fake_path <name> <bin...> - a $_HI_WORKDIR/<name> directory of no-op
# executables, printed - for suites that prove a resolution ladder
# ("candidate X is missing, does it fall through to Y") against a PATH they
# control rather than against whatever this machine has. Built once per name:
# the callers ask for the same set many times over.
function _hi_fake_path() {
  local dir="$_HI_WORKDIR/$1" bin
  shift
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    for bin in "$@"; do
      printf '%s\n' '#!/bin/sh' 'exit 0' >"$dir/$bin"
      chmod +x "$dir/$bin"
    done
  fi
  printf '%s' "$dir"
}

# _hi_real_path <name> <tool...> - the real-binary half of _hi_fake_path, same
# build-once-per-name contract: a $_HI_WORKDIR/<name> directory of symlinks to
# the named tools as this machine resolves them, printed. For suites that
# replace $PATH outright and still need a few real tools on it. A tool the
# machine doesn't have is skipped, so the caller's cases fail (or skip) on the
# missing tool itself rather than on the toolbox build.
function _hi_real_path() {
  local dir="$_HI_WORKDIR/$1" tool
  shift
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    for tool in "$@"; do
      command -v "$tool" >/dev/null 2>&1 && ln -sf "$(command -v "$tool")" "$dir/$tool"
    done
  fi
  printf '%s' "$dir"
}

# _hi_git_fixture - a fresh one-commit repo on a branch literally named "main"
# (forced via symbolic-ref, so git's initial-branch config can't decide it),
# printed. Built once per suite as a template, then copied per call: every
# caller wants the identical starting point, and one `cp -r` is one process
# where building from scratch is six git invocations. Each call still gets its
# own private directory, so nothing leaks between cases - only the setup cost
# is shared. The template holds one clean tracked file.txt; cases wanting
# another branch or a dirty tree arrange that themselves.
function _hi_git_fixture() {
  local dir template="$_HI_WORKDIR/git-template"
  if [ ! -d "$template" ]; then
    mkdir -p "$template"
    git -C "$template" init -q
    git -C "$template" symbolic-ref HEAD refs/heads/main
    git -C "$template" config user.email test@example.com
    git -C "$template" config user.name "Test"
    printf 'one\n' >"$template/file.txt"
    git -C "$template" add file.txt
    git -C "$template" commit -q -m initial
  fi
  dir="$(mktemp -d "$_HI_WORKDIR/repo.XXXXXX")"
  cp -r "$template/." "$dir/"
  printf '%s' "$dir"
}

# _hi_probe_shims <dir> [running-name] - fake docker/podman/nomad/kubectl in
# <dir>, each answering only the exact invocations hi.sh's backend predicates
# make (plus docker/podman's bare `ps`, doctor.sh's liveness probe) and
# failing anything else, so a changed command shape shows up as a failing
# predicate rather than a silently passing test. The target named
# <running-name> (default "yes") is running; anything else is not. The argv
# shapes spelled out here are the suite-side statement of that contract - one
# home, next to _hi_probe_cmd, rather than a copy per suite.
function _hi_probe_shims() {
  local dir="$1" running="${2:-yes}"
  mkdir -p "$dir"

  cat >"$dir/docker" <<EOF
#!/bin/sh
[ "\$1" = ps ] && exit 0
[ "\$1 \$2 \$3" = "container inspect -f" ] || exit 1
case "\$5" in $running) printf 'true\n' ;; *) printf 'false\n' ;; esac
EOF

  # podman is a drop-in for docker in hi.sh, so the shim is the same file
  cp "$dir/docker" "$dir/podman"

  cat >"$dir/nomad" <<EOF
#!/bin/sh
[ "\$1 \$2 \$3" = "alloc status -t" ] || exit 1
case "\$5" in $running) printf 'running\n' ;; *) printf 'pending\n' ;; esac
EOF

  cat >"$dir/kubectl" <<EOF
#!/bin/sh
[ "\$1 \$2 \$4" = "get pod -o" ] || exit 1
case "\$3" in $running) printf 'Running\n' ;; *) printf 'Pending\n' ;; esac
EOF

  chmod +x "$dir/docker" "$dir/podman" "$dir/nomad" "$dir/kubectl"
}

# _hi_alias_probe <shell> <name> [NAME=VALUE ...] - "yes"/"no": does sourcing
# paths.sh then aliases.sh in a real <shell> leave alias (fish: function)
# <name> defined? The fish-vs-POSIX dialect split lives here once rather than
# per suite. _HI_CLEANUP is scrubbed so the runner's own session state can't
# decide a tree-lifetime-gated alias; extra NAME=VALUE pairs ride the env.
function _hi_alias_probe() {
  local shell="$1" name="$2" script
  shift 2
  if [ "$shell" = fish ]; then
    script="source $_HI_ROOT/common/paths.sh; source $_HI_ALIASES; functions -q -- $name; and echo yes; or echo no"
  else
    script=". $_HI_ROOT/common/paths.sh; . $_HI_ALIASES; alias $name >/dev/null 2>&1 && echo yes || echo no"
  fi
  env -u _HI_CLEANUP _HI_HOME="$_HI_HOME" "$@" "$shell" -c "$script" 2>/dev/null
}

# _hi_scratch_tree <name> <dir...> - a throwaway hi.d under $_HI_WORKDIR/<name>
# holding copies of the named top-level directories, and prints the _HI_HOME
# that points at it. What a "minimal shipped tree" needs is one edit here
# rather than one per suite that stands one up.
function _hi_scratch_tree() {
  local name="$1" root="$_HI_WORKDIR/$1/hi.d" dir
  shift
  mkdir -p "$root"
  for dir in "$@"; do cp -r "$_HI_ROOT/$dir" "$root/"; done
  printf '%s' "$_HI_WORKDIR/$name"
}

# _hi_settings_fixture <name> <fn...> - run <fn...> with $_HI_ROOT,
# $_HI_CONFIG_DIR and $_HI_SETTINGS pointed at throwaway paths under
# $_HI_WORKDIR/<name>. scripts/install.sh's writers (config_shell,
# ensure_settings_shebang) and its uninstall half (strip_settings) all reach for
# those three, which in a real run are this very checkout and the developer's
# own overlay - the same shadowing load_test.sh's _hi_clean_all wrapper does
# before letting clean_all near $_HI_ROOT.
#
# The scratch overlay is deliberately a *different* directory from the scratch
# tree's misc/, so "writes land outside the tree" is something the tests can see
# rather than assume.
function _hi_settings_fixture() {
  local dir="$_HI_WORKDIR/$1"
  local _HI_ROOT="$dir" _HI_CONFIG_DIR="$dir/config"
  local _HI_SETTINGS="$dir/config/settings.sh"
  mkdir -p "$dir/common" "$dir/misc" "$dir/config"
  shift
  "$@" >/dev/null
}

# where _hi_settings_fixture's run writes, as the assertions see it
function _hi_fixture_settings() { printf '%s' "$_HI_WORKDIR/$1/config/settings.sh"; }

# The suites' small <key> -> <value> maps (which shell image built, where a
# binary is), as a newline-separated "<key>=<value>" string in a plain variable:
# associative arrays are bash 4 and macOS still ships bash 3.2, where `local -A`
# is a fatal "invalid option". _hi_kv_set appends and _hi_kv_get returns the
# *last* value set for a key, so re-setting one wins with no rewriting.
_HI_KV_NL=$'\n'

# _hi_kv_set <var> <key> <value> - eval, because bash 3.2 has no namerefs; the
# caller's `local` is reachable through bash's dynamic scoping either way.
function _hi_kv_set() {
  local _hi_kv_var="$1" _hi_kv_key="$2" _hi_kv_value="$3"
  eval "$_hi_kv_var=\"\${$_hi_kv_var:-}\$_hi_kv_key=\$_hi_kv_value\$_HI_KV_NL\""
}

# _hi_kv_get <var> <key> - print the value, non-zero if the key was never set
function _hi_kv_get() {
  local _hi_kv_var="$1" _hi_kv_key="$2" _hi_kv_store _hi_kv_entry found="" rc=1
  eval "_hi_kv_store=\${$_hi_kv_var:-}"
  while IFS= read -r _hi_kv_entry; do
    [ "${_hi_kv_entry%%=*}" = "$_hi_kv_key" ] || continue
    found="${_hi_kv_entry#*=}"
    rc=0
  done <<<"$_hi_kv_store"
  printf '%s' "$found"
  return "$rc"
}

# _hi_transcript_is_clean <label> <transcript-file> - fail if the session
# printed shell error noise.
#
# The assertion the bash 3.2 cases need, because a bash-4-only builtin on an old
# bash is rarely *fatal*: `mapfile ... && count=${#lines[@]}` just stops that
# one AND-list, `shopt -s globstar` complains and carries on, and load() has
# already turned `set -e` back off by the time the header runs. The session
# still comes up and every marker still lands - it simply spits
# "mapfile: command not found" at the user on every connect, which is the actual
# bug reported from macOS and the thing no other check here would notice.
_HI_SHELL_ERROR_RE='command not found|invalid option|unbound variable|bad substitution|syntax error|not a valid identifier'

function _hi_transcript_is_clean() {
  local label="$1" file="$2" hits
  hits="$(grep -nE "$_HI_SHELL_ERROR_RE" "$file" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    _hi_cecho " | [$label] -- transcript is free of shell errors OK" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED: the session printed shell errors" "$RED"
  printf '%s\n' "$hits" | sed 's/^/      /'
  _hi_note_failure "[$label] transcript has shell errors"
  return 1
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
  _HI_SKIPPED=0
}

# A single case the suite couldn't run (no python3 to drive a pty, say) - as
# opposed to _hi_report_skip, which is the whole suite standing down. Counted
# rather than silently passed, so _hi_suite_end's banner can say how much of
# what it just reported was actually exercised.
function _hi_skip() {
  _HI_SKIPPED=$((${_HI_SKIPPED:-0} + 1))
  _hi_cecho " | $1: SKIPPED${2:+ ($2)}" "$YELLOW"
}

# _hi_report_counts <total> <failed> [skipped] - hand this suite's tally up to
# test_runner.sh, which sums every suite's into the pass/fail/skip columns of
# its summary table. $_HI_COUNTS_FILE is only set when running under the
# runner, so a suite executed on its own is a no-op here. A suite that exits
# before reporting (_hi_require's skip path) contributes nothing, which is why
# the runner renders "-" rather than 0 for those. _hi_suite_end calls this for
# every suite built on the standard counters; shellcheck_test.sh, whose unit
# is files rather than cases, calls it directly.
function _hi_report_counts() {
  [ -n "${_HI_COUNTS_FILE:-}" ] || return 0
  printf '%s %s %s\n' "$1" "$2" "${3:-0}" >"$_HI_COUNTS_FILE"
}

# _hi_note_failure <label> - the failing case's name, up to the runner, which
# repeats every suite's under its summary table so finding what broke never
# means scrolling back through the whole transcript. Same no-op-when-standalone
# rule as _hi_report_counts.
function _hi_note_failure() {
  [ -n "${_HI_FAILS_FILE:-}" ] || return 0
  printf '%s\n' "$1" >>"$_HI_FAILS_FILE"
}

# _hi_report_skip <reason> - the same channel, saying "this suite ran nothing"
# rather than a tally. A skipped suite exits 0, so without this the runner
# would render it a green PASS and a run could report every suite passing
# while several of them never executed a case. Same no-op-when-standalone
# rule as _hi_report_counts.
function _hi_report_skip() {
  [ -n "${_HI_COUNTS_FILE:-}" ] || return 0
  printf 'SKIP %s\n' "$1" >"$_HI_COUNTS_FILE"
}

function _hi_suite_end() {
  local subject="$1" skipped=""
  [ "${_HI_SKIPPED:-0}" -gt 0 ] && skipped=", ${_HI_SKIPPED} skipped"
  _hi_report_counts "$_HI_TOTAL" "$_HI_FAILED" "${_HI_SKIPPED:-0}"
  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "${2:-All $subject checks passed ($_HI_TOTAL cases$skipped)}" "$BRGREEN"
  else
    _hi_h1 "${3:-$_HI_FAILED/$_HI_TOTAL $subject checks FAILED}" "$RED"
  fi
  exit "$_HI_FAILED"
}

# _hi_stand_down <reason> [message] - the whole suite stops here, honestly:
# yellow note, SKIP reported to the runner, exit 0. _hi_require covers
# requirements known at startup; this is also for *runtime* failures (an image
# that didn't build, a cluster that never came up), which must report a skip
# rather than exiting 0 unreported and painting the suite green.
function _hi_stand_down() {
  _hi_cecho "${2:-$1, skipping}" "$YELLOW"
  _hi_report_skip "$1"
  exit 0
}

function _hi_require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  _hi_stand_down "no $1" "$1 ${2:-not installed}, skipping"
}

function _hi_require_backend() {
  _hi_require "$@"
  "$1" info >/dev/null 2>&1 && return 0
  _hi_stand_down "$1 unreachable" "$1 not reachable, skipping"
}

# --- the host report ---------------------------------------------------------
#
# When a suite fails on someone's machine and passes in CI (or the reverse),
# the first three questions are always the same and none of them are in the
# output: what bash is this, what userland, and is $_HI_HOME even pointing at
# this checkout. This block answers them once at the top of a run, behind
# test_runner.sh's --host-report (or _HI_HOST_REPORT=1), so CI logs can always
# carry it without noising up a local one.
#
# Every probe is guarded and every substitution falls back: this is a debug
# aid, and it must never be the thing that fails a run. A host with nothing on
# its PATH still gets a block, reading "absent" in every row - which is itself
# a test case (see tests/harness/lib_test.sh).

# _hi_host_row <label> <text> [color]
function _hi_host_row() {
  _hi_cecho " | $(printf '%-9s' "$1") $2" "${3:-}"
}

# _hi_host_resolve <dir> - <dir> with symlinks resolved, empty if it is not a
# directory. `cd -P`, not `readlink -f`: that is a GNU extension, and this
# file has to give the same answer on the macOS job.
function _hi_host_resolve() {
  [ -n "${1:-}" ] || return 0
  (cd -P "$1" 2>/dev/null && pwd) || true
}

# _hi_tool_version <cmd> - "<cmd> X.Y.Z", or "<cmd> (absent)". One extractor
# for every tool below: the first version-shaped token anywhere in --version's
# output, which is all shellcheck (version on line 2), checkbashisms (a
# sentence), shfmt (a bare vX.Y.Z) and the four shells agree on. </dev/null so
# a tool that answers --version by starting a REPL exits instead of hanging.
function _hi_tool_version() {
  local out
  command -v "$1" >/dev/null 2>&1 || {
    printf '%s (absent)' "$1"
    return 0
  }
  out="$("$1" --version 2>&1 </dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
  printf '%s %s' "$1" "${out:-?}"
}

# _hi_host_versions <cmd...> - the row body for a group of tools.
function _hi_host_versions() {
  local cmd out=""
  for cmd in "$@"; do out="$out${out:+, }$(_hi_tool_version "$cmd")"; done
  printf '%s' "$out"
}

# What the e2e suites need, reported rather than enforced: docker and podman
# have to *answer*, not merely exist (_hi_require_backend runs the same `info`,
# and a downed daemon is why an e2e suite skips); the rest only have to be on
# PATH. Probed through _hi_probe, so a wedged daemon costs the same ceiling
# here as it does in the header.
_HI_HOST_BACKENDS=(docker podman nomad kubectl kind ssh)

function _hi_host_backend_state() {
  local bin out="" t0
  for bin in "${_HI_HOST_BACKENDS[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      out="$out${out:+, }$bin: absent"
      continue
    fi
    case "$bin" in
    docker | podman)
      t0="$(_hi_now)"
      if _hi_probe "$bin" info >/dev/null 2>&1; then
        out="$out${out:+, }$bin: answering ($(_hi_elapsed "$t0" "$(_hi_now)")s)"
      else
        out="$out${out:+, }$bin: NOT answering"
      fi
      ;;
    *) out="$out${out:+, }$bin: present" ;;
    esac
  done
  printf '%s' "$out"
}

# _hi_host_tree_check <reference-tree> - is $_HI_ROOT the tree this run was
# invoked from? Silent when it is; one yellow line and a non-zero return when
# it is not. The reference has to come from the caller, because everything
# derived from $_HI_HOME - this file included - moves with the mistake: only
# the script the user actually typed the path of knows which tree that was.
#
# A warning, never a failure: pointing a run at another tree is legal and
# test_runner.sh --help documents it. Doing it *by accident* is the thing -
# a login profile exporting _HI_HOME is how - and it shows up nowhere else
# than as suites quietly running fewer cases.
function _hi_host_tree_check() {
  local here="${1:-}" there
  there="$(_hi_host_resolve "${_HI_ROOT:-}")"
  [ -n "$here" ] && [ "$here" = "$there" ] && return 0
  _hi_cecho " | _HI_ROOT is ${there:-${_HI_ROOT:-unset} (missing)}, not the tree this run came from${here:+ ($here)} - the suites are testing another checkout" "$YELLOW"
  return 1
}

# _hi_host_report <reference-tree> - the block itself.
function _hi_host_report() {
  local ref="${1:-}" kernel os userland sed_ver loc glyphs

  _hi_h2 "The host"
  _hi_host_row bash "${BASH_VERSION:-?} (${BASH:-?})"

  kernel="$(uname -srm 2>/dev/null || true)"
  os=""
  if [ -f "${_HI_LINUX_RELEASE:-/etc/os-release}" ]; then
    os="$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' \
      "${_HI_LINUX_RELEASE:-/etc/os-release}" 2>/dev/null || true)"
  elif command -v sw_vers >/dev/null 2>&1; then
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
  fi
  _hi_host_row os "${kernel:-?}${os:+ - $os}"

  # GNU or not decides `sed -i`, `mktemp -t`, `base64 -D` and half the reasons
  # a suite passes here and fails on the macOS job
  sed_ver="$(sed --version 2>&1 </dev/null || true)"
  case "$sed_ver" in
  *GNU*) userland="GNU" ;;
  *[Bb]usy[Bb]ox*) userland="busybox" ;;
  *) userland="BSD/other (sed has no --version)" ;;
  esac
  if command -v timeout >/dev/null 2>&1; then
    userland="$userland, timeout present"
  else
    # core.sh's _hi_probe degrades to a bare call without it, so nothing on
    # this host is actually bounded by $_HI_PROBE_TIMEOUT
    userland="$userland, NO timeout - probes are unbounded here"
  fi
  _hi_host_row userland "$userland"

  loc="${LC_ALL:-${LC_CTYPE:-${LANG:-unset}}}"
  if _hi_use_ascii; then glyphs="ASCII marks"; else glyphs="UTF-8 glyphs"; fi
  _hi_host_row locale "$loc ($glyphs)"

  _hi_host_row _HI_HOME "${_HI_HOME:-unset}"
  # on disagreement the check prints its own line, which says more than a row
  if _hi_host_tree_check "$ref"; then
    _hi_host_row tree "${_HI_ROOT:-unset} - the tree this run came from" "$GREEN"
  fi

  _hi_host_row backends "$(_hi_host_backend_state)"
  _hi_host_row harness "$(_hi_host_versions python3 pgrep git tar)"
  _hi_host_row shells "$(_hi_host_versions bash zsh fish ksh mksh dash)"
  _hi_host_row lint "$(_hi_host_versions shellcheck shfmt checkbashisms)"
  return 0
}

# The command each e2e suite runs *on the target* to prove hi landed there: it
# echoes $1 (the marker) only if the assertion holds, and the suite greps the
# transcript for it. $2 picks the shape, which differs by what each branch has
# in scope:
#
#   bash              the main branch: asserts the copy landed and sources
#                     aliases.sh itself, which that branch does not
#   fallback          the container fallback copies only aliases.sh - no
#                     paths.sh, so hi_info isn't in scope; check a plain alias
#   fallback_fish     the same, in fish's dialect (its aliases are functions)
#   ssh_fallback      the ssh fallback rc *does* source paths.sh, so hi_info is
#   ssh_fallback_fish ssh_fallback in fish's dialect
#   installed         a permanent hi.d: asserts $_HI_ROOT is ~/hi.d, i.e.
#                     _say_hi loaded it in place rather than shipping a tree
#
# Every string stays single-quoted: the variables expand on the target.
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
# Filled here rather than by a function four suites had to remember to call
# first: it takes no arguments and reads nothing that varies between cases.
_HI_PTY_FORCED=()
command -v python3 >/dev/null 2>&1 && _HI_PTY_FORCED=(python3 -c "$_HI_PTY_SPAWN")

# The _hi_pty_wrap preamble every suite that backgrounds the launcher needs:
# stash our real stdin on fd 3 and decide the pty wrap from *that*. $1 is the
# mode, $2 the warning. `exec -it` refuses a remote tty unless our stdin is one,
# which it isn't in CI, so the local fake is what makes these suites reliable
# off an interactive terminal.
#
# The check must use the duplicated fd: bash rewires a backgrounded job's stdin
# to /dev/null with job control off, so testing `-t 0` here and handing the job
# fd 0 later would report a terminal and still fail. fd 3 plus `<&3` in
# _hi_exec_case keeps the original tty-ness - which is why they go together.
function _hi_pty_stdin() {
  exec 3<&0
  _hi_pty_wrap 3 "$1" "$2"
}

function _hi_poll_budget() {
  awk -v t="$1" -v i="$2" \
    'BEGIN { b = t * i; b = (b == int(b) ? b : int(b) + 1); printf "%d", (b < 1 ? 1 : b) }'
}

# _hi_free_port_base [count] - a base port with $count consecutive free ports
# from it, printed on stdout. A suite that binds a well-known port collides
# with any real service of the same kind already on the host (and with a
# second copy of itself), which is a failure that looks exactly like a bug in
# the code under test. The ssh fixtures avoid this by letting docker map an
# ephemeral port; anything hi runs directly has to pick its own, so it asks
# here. Probing is a connect attempt: refused means nothing is listening.
# Racy in principle, since something could claim the port between the probe
# and the bind, but bounded - and unlike a hardcoded port it is usually right.
function _hi_free_port_base() {
  local count="${1:-1}" base i ok attempt
  for ((attempt = 0; attempt < 20; attempt++)); do
    base=$((20000 + RANDOM % 20000))
    ok=1
    for ((i = 0; i < count; i++)); do
      if (exec 3<>"/dev/tcp/127.0.0.1/$((base + i))") 2>/dev/null; then
        ok=0
        break
      fi
    done
    if [ "$ok" -eq 1 ]; then
      printf '%s' "$base"
      return 0
    fi
  done
  return 1
}

# Both pollers take (tries, interval) - the shape every call site speaks -
# but tries*interval only sizes the wall-clock budget: the deadline is the
# one bound, for _hi_wait_pid's reason (an iteration counter stretches
# without bound exactly when the machine is busiest).
function _hi_poll_bool() {
  local abort=""
  if [ "$1" = -a ]; then
    abort="$2"
    shift 2
  fi
  local tries="$1" interval="$2" deadline
  shift 2
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval")))
  while :; do
    "$@" >/dev/null 2>&1 && return 0
    if [ -n "$abort" ] && ! "$abort"; then
      return 1
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep "$interval"
  done
}

function _hi_poll_value() {
  local tries="$1" interval="$2" out deadline
  shift 2
  deadline=$((SECONDS + $(_hi_poll_budget "$tries" "$interval")))
  while :; do
    out="$("$@" 2>/dev/null)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep "$interval"
  done
}

# Wall-clock, not iteration count: `for ((i = 0; i < timeout_s * 4))` at
# sleep 0.25 only equals timeout_s when nothing else is competing for the
# machine, and stretches without bound when something is - which is exactly
# when an e2e suite is most likely to need the timeout. _hi_poll_bool and
# _hi_poll_value already use this deadline; this now matches them.
function _hi_wait_pid() {
  local pid="$1" timeout_s="$2" deadline
  shift 2
  _HI_WAIT_EXIT=0
  deadline=$((SECONDS + timeout_s))
  while [ "$SECONDS" -lt "$deadline" ]; do
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

# _hi_timed_out <label> <timeout_s> [hook] - _hi_wait_pid's timeout callback,
# reached through its "$@". One top-level function: a per-runner
# `_hi_on_timeout` would be global anyway, and the second definition would
# silently redefine the first.
# shellcheck disable=SC2329
function _hi_timed_out() {
  _hi_h3 " | [$1] -- TIMED OUT after ${2}s, killing" "$RED"
  [ -n "${3:-}" ] && "$3"
  return 0
}

# _hi_case_result <label> <what> <exit> <t0> <t1> <out_file> <marker...> - the
# verdict both case runners reach: OK with a timing, or FAILED with the
# transcript indented under it. Every marker given must be present.
function _hi_case_result() {
  local label="$1" what="$2" exit_code="$3" t0="$4" t1="$5" out_file="$6" marker ok=1
  shift 6
  for marker in "$@"; do
    grep -qF "$marker" "$out_file" 2>/dev/null || ok=0
  done
  if [ "$ok" -eq 1 ]; then
    _hi_cecho " | [$label] -- $what OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)" "$RED"
  sed 's/^/      /' "$out_file" 2>/dev/null
  _hi_note_failure "[$label] $what (exit $exit_code)"
  return 1
}

function _hi_exec_case() {
  local label="$1" what="$2" marker="$3" timeout_s="$4" target="$5" cmd="$6" hook="${7:-}"
  local out_file="$_HI_WORKDIR/$label.out" exit_code t0 t1

  _hi_cecho " | Running: $_HI_LAUNCHER $target $cmd"
  t0="$(_hi_now)"
  # ${a[@]+"${a[@]}"}: _HI_PTY_WRAP is empty whenever we already have a real
  # tty, and on bash 3.2 (macOS) expanding an empty array under `set -u` is fatal
  ${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "$_HI_LAUNCHER" "$target" "$cmd" <&3 >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "$timeout_s" _hi_timed_out "$label" "$timeout_s" "$hook"
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  _hi_case_result "$label" "$what" "$exit_code" "$t0" "$t1" "$out_file" "$marker"
}

# True once the target's session has actually reached a shell, so
# _hi_interactive_case knows when its input will be read rather than guessing.
# Both shapes count: load()'s full path announces the shell it picked, and the
# no-bash fallback says so instead - a readiness check that only knew about
# the first would hang out the full timeout on any target without bash.
function _hi_session_ready() {
  grep -qE 'hi loaded with|aliases only' "$1" 2>/dev/null
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
# _hi_interactive_case [-c <closing>] [-m <marker>]... [-f <fn>] \
#   <label> <what> <marker> <timeout_s> <launcher...> -
# where <launcher...> is the *bare* command, with no pty prefix of its own:
# _HI_PTY_FORCED is prepended here; it is filled at source time, so no suite
# has to remember to ask for it. The options are what let every pty-driven
# suite share this one driver instead of forking it:
#   -c <closing>  the line whose appearance means the session is over - the
#                 feeder holds the pipe open until it lands, and it is
#                 asserted as a marker. Default: load()'s "hi closing"; a tier
#                 that never reaches load.sh names its own (the mksh git case
#                 waits on the echoed marker instead).
#   -m <marker>   a further must-appear transcript marker (repeatable)
#   -f <fn>       runs inside the feeder between the marker line and the
#                 `exit`: its stdout is typed into the live session, and it
#                 may also do host-side work mid-session
function _hi_interactive_case() {
  local closing="hi closing" feeder=""
  local -a extra=()
  while :; do
    case "${1:-}" in
    -c)
      closing="$2"
      shift 2
      ;;
    -m)
      extra+=("$2")
      shift 2
      ;;
    -f)
      feeder="$2"
      shift 2
      ;;
    *) break ;;
    esac
  done
  local label="$1" what="$2" marker="$3" timeout_s="$4"
  shift 4
  local out_file="$_HI_WORKDIR/$label.interactive.out" exit_code t0 t1
  # a pty echoes back everything we type, so the line we send must not itself
  # contain what we grep for - the shell has to assemble it. printf's two
  # arguments arrive space-separated on the echoed line and hyphen-joined only
  # in the real output, in every shell load() might hand us.
  local expected="$marker-INTERACTIVE"

  if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
    _hi_skip "[$label]" "no python3 to drive an interactive pty"
    return 0
  fi

  _hi_cecho " | Running (interactive): $*"
  t0="$(_hi_now)"
  : >"$out_file"
  # The left side of the pipe runs alongside the session, so it can watch the
  # transcript the session is writing rather than guessing how long it needs.
  # A fixed sleep here was the suite's worst flake: on a loaded runner the
  # input landed before the shell was ready and the marker never appeared.
  # $_HI_INTERACTIVE_SETTLE is the ceiling now, not the wait itself.
  #
  # Reading $out_file on the left while the right writes it is the whole
  # mechanism, not the accident SC2094 warns about: the two sides are separate
  # processes and the reader only ever polls, so there is no truncate-then-read
  # race to hit.
  # shellcheck disable=SC2094
  {
    _hi_poll_bool "$((${_HI_INTERACTIVE_SETTLE:-4} * 4))" 0.25 _hi_session_ready "$out_file" || true
    printf "printf '%%s-%%s\\\\n' %s INTERACTIVE\n" "$marker"
    [ -z "$feeder" ] || "$feeder"
    printf 'exit\n'
    # ...and the same on the way out: hold the pipe open until the closing
    # line lands rather than for a flat two seconds
    _hi_poll_bool 20 0.25 grep -q "$closing" "$out_file" || true
  } | "${_HI_PTY_FORCED[@]}" "$@" >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "$timeout_s" _hi_timed_out "$label" "$timeout_s"
  exit_code="$_HI_WAIT_EXIT"
  t1="$(_hi_now)"

  # both markers: the interactive shell really came up and ran our line, and
  # the session reached its closing line rather than dying early
  # (${a[@]+...}: bash 3.2 + set -u, as above)
  _hi_case_result "$label" "$what" "$exit_code" "$t0" "$t1" "$out_file" \
    "$expected" "$closing" ${extra[@]+"${extra[@]}"}
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

# _hi_sshd_entrypoint <ctx-dir> <shebang> [extra-line...] - the entrypoint.sh
# every sshd image ships: shebang + set -e, any per-image lines, the shared body
function _hi_sshd_entrypoint() {
  local ctx="$1" shebang="$2"
  shift 2
  {
    printf '#!%s\nset -e\n' "$shebang"
    [ $# -eq 0 ] || printf '%s\n' "$@"
    printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
  } >"$ctx/entrypoint.sh"
}

function _hi_sshd_image() {
  local ctx="$_HI_WORKDIR/sshd"
  mkdir -p "$ctx"

  cat >"$ctx/Dockerfile" <<'EOF'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server bash dash zsh fish \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

  # shellcheck disable=SC2016 # entrypoint.sh content, resolved on the container
  _hi_sshd_entrypoint "$ctx" /bin/bash 'usermod -s "${LOGIN_SHELL:-/bin/bash}" hitest'

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
#
# $_HI_SSH_PORT is the *caller's* to own: every case that boots a container
# declares `local _HI_SSH_PORT` first, so the port a case connects to - and
# greps the process table by, in _hi_ssh_client_pids - is the port that case
# started, not whichever case started one last. It was a single global, which
# is fine until two cases run at once and then is a race that reads as a bug in
# the code under test.
function _hi_sshd_container() {
  local name="$1" image="$2"
  shift 2

  # registered *before* the run, not after: the container exists the moment
  # docker returns, and a ^C in that window leaks it (see the ledger)
  _hi_track_container "$name"
  if ! docker run -d --rm --name "$name" -p 127.0.0.1::22 -e "PUBKEY=$_HI_PUBKEY" "$@" "$image" \
    >/dev/null 2>"$_HI_WORKDIR/$name.log"; then
    _hi_cecho " | Failed to start container (see $_HI_WORKDIR/$name.log)" "$RED"
    return 1
  fi

  _HI_SSH_PORT="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
  _hi_cecho " | Container: $name (port: $_HI_SSH_PORT)"
  _hi_cecho " | Waiting for sshd on 127.0.0.1:$_HI_SSH_PORT"
  if ! _hi_poll_bool 40 0.25 _hi_ssh_reachable "$_HI_SSH_PORT"; then
    _hi_cecho " | Sshd never came up" "$RED"
    return 1
  fi
}

# --- freezing a live session ---------------------------------------------------
#
# Proving a cleanup trap fires on a *dropped* link means killing the link from
# outside, and doing that takes two SIGSTOPs: _say_hi multiplexes, so a
# backgrounded ControlPersist master holds the socket beside the visible
# `ssh -t`, and it is the master that answers sshd's ClientAlive probes.
# Freeze only the client and sshd correctly keeps the session - that is a hung
# terminal, not a dead link. Hence _hi_ssh_mux_pids, and hence both ssh
# suites treating a missing master as a hard failure rather than carrying on.

# Clients of the throwaway sshd on $_HI_SSH_PORT - the port is what keeps a
# concurrent hi session on this machine out of the match.
function _hi_ssh_client_pids() {
  pgrep -f -- "ssh .*-p $_HI_SSH_PORT .*hitest@127.0.0.1" 2>/dev/null || true
}

# hi.sh's ControlPath, read back out of the session client's own argv - the
# mux master is found by that exact path rather than by a `hi.cm.*` glob, so a
# concurrent hi session on the same machine (or one still persisting from an
# earlier case) can't be matched by mistake.
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

# Every local pid a suite has SIGSTOPped, so its exit trap can undo it. The
# window between the freeze and the kill is tens of seconds of polling: an
# abort in there (^C, a runner timeout, `set -e` upstream) would otherwise
# leave stopped ssh clients and a mux master holding a socket open
# indefinitely. Suites that freeze pass _hi_thaw_frozen to _hi_workdir.
_HI_FROZEN_PIDS=()

function _hi_freeze() {
  local pid
  for pid in "$@"; do
    _HI_FROZEN_PIDS+=("$pid")
    # ...and on the ledger as well, which is the copy that survives: a case
    # running in a background subshell keeps its own $_HI_FROZEN_PIDS, so an
    # abort between the STOP and the KILL would leave nothing for the suite's
    # exit trap to thaw
    _hi_ledger frozen "$pid"
    kill -STOP "$pid" 2>/dev/null || true
  done
}

# CONT before KILL: a SIGSTOPped process can't act on SIGKILL's cleanup path
# until it is scheduled again, so thawing first is what makes the kill land.
function _hi_thaw_frozen() {
  local pid
  for pid in "${_HI_FROZEN_PIDS[@]:-}"; do
    [ -n "$pid" ] || continue
    kill -CONT "$pid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
  done
  _HI_FROZEN_PIDS=()
  return 0
}

# _hi_freeze_session - freezes the live session's client *and* its mux master,
# named for the report if either is missing. Returns 1 without freezing
# anything when there is nothing to freeze, or when hi has stopped
# multiplexing - which would make freezing the client alone prove nothing, and
# is worth failing on deliberately rather than passing quietly.
function _hi_freeze_session() {
  local ctl
  local -a pids=() mux=()
  _hi_read_lines pids < <(_hi_ssh_client_pids)
  if [ "${#pids[@]}" -eq 0 ]; then
    _hi_cecho " | no local ssh process found to freeze" "$RED"
    return 1
  fi
  ctl="$(_hi_ssh_ctl_path "${pids[0]}")"
  [ -n "$ctl" ] && _hi_read_lines mux < <(_hi_ssh_mux_pids "$ctl")
  if [ "${#mux[@]}" -eq 0 ]; then
    _hi_cecho " | no ControlPersist mux master found - freezing the client alone proves nothing" "$RED"
    return 1
  fi
  pids+=(${mux[@]+"${mux[@]}"})
  _hi_freeze ${pids[@]+"${pids[@]}"}
}

# The client-side launcher invocation both ssh suites make: hi.sh pointed at
# the throwaway sshd on 127.0.0.1:$1, with the keypair and flags the fixtures
# above set up. Left in the array $_HI_SSH_LAUNCH rather than run here, since
# the callers redirect and background it differently - append the remote
# command and go. Call it *after* _hi_pty_wrap, whose result it captures.
# $_HI_SSH_LAUNCH_BARE is the same command without that prefix, for
# _hi_interactive_case, which brings its own (see _HI_PTY_FORCED).
function _hi_ssh_launch() {
  _HI_SSH_LAUNCH_BARE=("$_HI_LAUNCHER" -p "$1" -i "$_HI_WORKDIR/id"
    "${_HI_SSH_OPTS[@]}" -o ConnectTimeout=5 hitest@127.0.0.1)
  _HI_SSH_LAUNCH=(${_HI_PTY_WRAP[@]+"${_HI_PTY_WRAP[@]}"} "${_HI_SSH_LAUNCH_BARE[@]}")
}

# --- the shared container-backend case runners --------------------------------
#
# Top-level rather than nested in _hi_container_backend_test, so any suite that
# boots a throwaway container around one case can use them. They read the
# conventions the e2e suites already set: $_HI_BACKEND (the CLI to drive) and
# $_HI_TEST_MARKER (the transcript marker _hi_probe_cmd echoes). The started
# container's name is left in $_HI_CONTAINER.
_HI_CONTAINER=""

function _hi_container_running() {
  [ "$("${_HI_BACKEND:-docker}" container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}

# _hi_start_case_container <label> <image> - boot one throwaway container for
# a case (kept alive by `tail -f`), registered for teardown, waited until the
# backend reports it running.
function _hi_start_case_container() {
  local label="$1" image="$2"

  _HI_CONTAINER="hi-${_HI_BACKEND}test-$label-$$"
  _hi_h3 "Testing shell: $label"

  # tracked before the run, for the reason _hi_sshd_container states
  _hi_track_container "$_HI_CONTAINER"
  if ! "$_HI_BACKEND" run -d --name "$_HI_CONTAINER" "$image" tail -f /dev/null \
    >/dev/null 2>"$_HI_WORKDIR/$label.run.log"; then
    _hi_cecho " | Failed to start container (image: $image)" "$RED"
    return 1
  fi
  _hi_cecho " | Container: $_HI_CONTAINER (image: $image)"

  if ! _hi_poll_bool 40 0.25 _hi_container_running "$_HI_CONTAINER"; then
    _hi_cecho " | Container never reported running" "$RED"
    return 1
  fi
}

# _hi_backend_case <label> <image> <cmd> [timeout_s] - one command-shaped case:
# boot, run hi against the container, tear down, report.
function _hi_backend_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local ok=0
  # the case's own, not the suite's: _hi_start_case_container assigns into this
  # frame, so two cases running at once cannot read each other's container
  local _HI_CONTAINER=""

  _hi_start_case_container "$label" "$image" || return 1
  _hi_exec_case "$label" "$_HI_BACKEND path" "$_HI_TEST_MARKER" "$timeout_s" "$_HI_CONTAINER" "$cmd" && ok=1
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

# _hi_backend_interactive_case <label> <image> [timeout_s] - the interactive
# shape, plus the cleanup assertion: the disposable tree must be gone from the
# container once the session ends.
function _hi_backend_interactive_case() {
  local label="$1" image="$2" timeout_s="${3:-60}"
  local ok=0
  local _HI_CONTAINER=""

  _hi_start_case_container "$label" "$image" || return 1
  if _hi_interactive_case "$label" "$_HI_BACKEND path (interactive)" "$_HI_TEST_MARKER" \
    "$timeout_s" "$_HI_LAUNCHER" "$_HI_CONTAINER"; then
    ok=1
    if "$_HI_BACKEND" exec "$_HI_CONTAINER" sh -c 'ls -d /tmp/*.hi.log.* >/dev/null 2>&1'; then
      _hi_cecho " | [$label] -- FAILED: hi.d's copy was left behind in the container" "$RED"
      ok=0
    fi
  fi
  _hi_rm_container "$_HI_CONTAINER"
  [ "$ok" -eq 1 ]
}

# Boots throwaway containers - one per shell environment - and drives hi.sh's
# real _say_hi_container against each of them over `<backend> exec`. Podman's
# CLI is a full drop-in for docker's here, so
# docker_test.sh and podman_test.sh are both just `_hi_container_backend_test
# docker|podman` - this one function proves both branches of
# _say_hi_container: the bash-present main path (tar copy + `bash --rcfile`),
# and every arm of the bash-less fallback's ladder ($_HI_SHELL_LADDER).
# Everything is ephemeral and nothing touches host ssh config. Skips cleanly
# if $backend isn't installed/running. Needs network access the first time it
# runs, to pull/build the test images.
function _hi_container_backend_test() {
  local backend="$1"

  _hi_require_backend "$backend"
  _HI_BACKEND="$backend"
  _hi_workdir "${backend}test"
  _hi_h1 "Testing hi's $backend path across container shell environments"

  _hi_h2 "Building test images"
  # shellcheck disable=SC2034 # read back through _hi_kv_get, which shellcheck
  # cannot follow (the name is a string there)
  local shell shell_ok=""
  local -a built_images=()
  for shell in zsh fish mksh; do
    mkdir -p "$_HI_WORKDIR/$shell"
    printf 'FROM alpine:3.20\nRUN apk add --no-cache %s\n' "$shell" >"$_HI_WORKDIR/$shell/Dockerfile"
    if _hi_build_image "$shell" "hi-${backend}test-$shell-$$" "the $shell fallback" "$_HI_WORKDIR/$shell"; then
      _hi_kv_set shell_ok "$shell" 1
    else
      _hi_kv_set shell_ok "$shell" 0
    fi
    # recorded whether or not the build succeeded: a half-built tag still
    # wants removing, and `image rm -f` on a name that never existed is a no-op
    built_images+=("hi-${backend}test-$shell-$$")
  done

  _HI_TEST_MARKER="HI_$(printf '%s' "$backend" | tr '[:lower:]' '[:upper:]')_TEST_OK"

  _hi_pty_stdin auto "no tty and no python3 to fake one - $backend exec -it will fail outright, results may be unreliable"

  _hi_suite_begin

  # Every case here boots its own container and reads nothing another case
  # writes, so the whole battery is one parallel batch.
  _hi_par_begin "$backend shell environments"
  _hi_par_case bash _hi_backend_case bash debian:bookworm-slim "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
  _hi_par_case bash-interactive _hi_backend_interactive_case bash-interactive debian:bookworm-slim
  local spec
  for spec in zsh:fallback fish:fallback_fish mksh:fallback; do
    shell="${spec%%:*}"
    if [ "$(_hi_kv_get shell_ok "$shell")" = 1 ]; then
      _hi_par_case "$shell" _hi_backend_case "$shell" "hi-${backend}test-$shell-$$" "$(_hi_probe_cmd "$_HI_TEST_MARKER" "${spec#*:}")"
    fi
  done
  _hi_par_case sh _hi_backend_case sh alpine:3.20 "$(_hi_probe_cmd "$_HI_TEST_MARKER" fallback)"
  _hi_par_wait

  # $$-suffixed like the container names: without it a second run of this
  # suite on the same host removes the images the first is still running from.
  # The list comes from the build loop rather than being spelled again, so a
  # shell added there cannot be left behind here.
  "$backend" image rm -f "${built_images[@]}" >/dev/null 2>&1 || true

  _hi_suite_end "$backend" \
    "hi's $backend path survived every shell environment tested ($_HI_TOTAL cases)" \
    "hi's $backend path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

# _hi_backend_pair_cases <label> <thing tested> - the bash-present + bash-less
# case pair every ephemeral-cluster suite (kube, nomad) ends with, once its
# own cluster/agent is up, $_HI_TEST_MARKER is set, and a suite-local
# _hi_run_case is in scope. _say_hi_container's fallback logic past the
# initial `command -v bash` probe is identical for every backend and already
# proven by _hi_container_backend_test above, so these suites only need to
# prove their own backend's probe/attach argument shapes - once with bash
# present, once without.
# The pair runs as a batch, which is a real saving on kube (two pods scheduled
# together on a cluster that took 40s to exist) and none at all on nomad - whose
# suite tracks its jobs in a shell array and therefore asks for _HI_PAR_WIDTH=1,
# so this path stays one code path either way.
function _hi_backend_pair_cases() {
  local label="$1" thing="$2"

  _hi_suite_begin

  _hi_par_begin "$label cases"
  _hi_par_case bash _hi_run_case bash debian:bookworm-slim "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
  _hi_par_case sh _hi_run_case sh alpine:3.20 "$(_hi_probe_cmd "$_HI_TEST_MARKER" fallback)"
  _hi_par_wait

  _hi_suite_end "" \
    "hi's $label path survived every $thing tested ($_HI_TOTAL cases)" \
    "hi's $label path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}
