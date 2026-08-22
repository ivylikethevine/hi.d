#!/bin/sh
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each.
# The bash, zsh and fish completions (and `hi_colors`) all read this for
# connection, autocomplete, and autosuggest.
# Usage: sh targets.sh [ssh|docker|podman|nomad|kube|flags]
#        (no argument = every backend; `flags` = hi's own options instead)
# GLOSSARY: HI.26 - _HI_PROBE_TIMEOUT and _HI_TARGETS_TTL
#
# The backends are probed *together*, not in turn. Each is capped at
# $_HI_PROBE_TIMEOUT on its own, so one after another two wedged daemons cost
# the sum of the ceilings and four cost 8s of a single TAB; started together
# they cost the longest. That is the trade common/header.sh's _hi_probe_start
# already makes for the banner, in the one dialect this file is allowed.
# Emission order stays the roster's - the rows are read back per backend, never
# in the order the daemons answered - and a host with no writable scratch
# directory simply gets the old in-turn sweep, which is slow, not wrong.
# shellcheck disable=SC2329 # every function here is reached indirectly - by
# the completion hook that sources this file, through run_lister's dispatch, or
# as a background job - so "never invoked" is true of the file, not of five
# lines in it.

kind="${1:-all}"

# hi's own flags, so `hi --<TAB>` completes them the way a target does. They
# live here rather than in each shell because this file is already the one thing
# all three completions read, and the only one fish can run - a roster in
# core.sh would be unreachable from `complete -c hi`.
#
# Answered before anything else below: a flag list must never wait on a docker
# daemon or an ssh config, and this exits before the cache and the probes.
#
# tests/common/targets_test.sh drift-checks both halves against hi.sh's --help,
# so a flag added there and forgotten here fails the fast suite.
if [ "$kind" = flags ]; then
  # always offered - these work on a client and inside a session alike
  printf '%s\n' --help --version --doctor
  # ...and these do not: every one needs the full checkout, which the payload
  # deliberately does not carry, so offering them on a target completes straight
  # into hi.sh's $_HI_NO_CHECKOUT refusal. Filtered on the same variable the
  # session itself is marked with.
  if [ "${_HI_REMOTE_SESSION:-0}" != 1 ]; then
    printf '%s\n' --install --uninstall --configure --check-configs \
      --overlay-init --update --color-preview --packages-preview --test
  fi
  exit 0
fi

ttl="${_HI_TARGETS_TTL:-5}"

# `timeout` is GNU, absent on stock macOS - optional. Called via list_*.
if command -v timeout >/dev/null 2>&1; then
  run_backend() { timeout "${_HI_PROBE_TIMEOUT:-2}" "$@"; }
else
  run_backend() { "$@"; }
fi

# Everything below the first line of $1, fork-free: faster than a `tail` exec
# at this size, and the cache keeps working on a PATH with no coreutils.
cache_body() {
  _hi_first=1
  while IFS= read -r _hi_line || [ -n "$_hi_line" ]; do
    if [ "$_hi_first" = 1 ]; then
      _hi_first=0
      continue
    fi
    printf '%s\n' "$_hi_line"
  done <"$1"
}

# The roster, "<label>:<bin>", in the order the rows are emitted.
backends='docker:docker podman:podman nomad:nomad kube:kubectl'

# Somewhere private to collect a fan-out's output, made at most once per run
# and only on a path that has a fan-out to collect - so a host with no backends
# at all (and the suite's toolbox PATH, which carries sh, awk and sed and
# nothing else) never reaches for `mkdir`. Not $XDG_RUNTIME_DIR: this is
# per-run scratch rather than a cache, and it is removed on the way out.
#
# `mkdir -m 700`, and deliberately no `-p`: with -p the call *succeeds* on a
# path that already exists, so a name somebody else got to first would be
# adopted here and then removed by emit_targets' `rm -rf` on the way out. The
# mode rides the same call rather than a chmod after it, which left a window
# where the directory existed on the default umask.
scratch=""
scratch_dir() {
  [ -n "$scratch" ] && return 0
  _hi_scratch="${TMPDIR:-/tmp}/hi-probe.$$"
  mkdir -m 700 "$_hi_scratch" 2>/dev/null || return 1
  scratch="$_hi_scratch"
}

# backend_wanted <label> <bin> - does the kind gate pass, and is the CLI here?
# Both halves are builtins, so the whole roster is sized before anything forks.
backend_wanted() {
  { [ "$kind" = "$1" ] || [ "$kind" = all ]; } || return 1
  command -v "$2" >/dev/null 2>&1
}

# run_lister <label> - that backend's rows on stdout, in turn or backgrounded.
run_lister() {
  case "$1" in
  docker | podman) list_ps "$1" ;;
  nomad) list_nomad ;;
  kube) list_kube ;;
  esac
}

emit_targets() {
  # ssh first and in line: a local file read and one awk, already faster than
  # the bookkeeping backgrounding it would cost.
  if [ "$kind" = ssh ] || [ "$kind" = all ]; then
    [ -f "${_HI_SSH_CONFIG:-$HOME/.ssh/config}" ] &&
      awk 'tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) break
          if ($i !~ /[*?]/) printf "%s\tssh\n", $i
        }
      }' "${_HI_SSH_CONFIG:-$HOME/.ssh/config}"
  fi

  wanted="" n_wanted=0
  for spec in $backends; do
    backend_wanted "${spec%%:*}" "${spec#*:}" || continue
    wanted="${wanted}${wanted:+ }${spec%%:*}"
    n_wanted=$((n_wanted + 1))
  done
  [ "$n_wanted" -gt 0 ] || return 0

  # worth its two forks only where something actually fans out: two or more
  # backends, or nomad, whose per-job calls fan out on their own
  if [ "$n_wanted" -ge 2 ] || [ "$wanted" = nomad ]; then
    scratch_dir || :
  fi

  if [ "$n_wanted" -ge 2 ] && [ -n "$scratch" ]; then
    for label in $wanted; do
      run_lister "$label" >"$scratch/$label" 2>/dev/null &
    done
    wait
    files=""
    for label in $wanted; do files="$files $scratch/$label"; done
    # shellcheck disable=SC2086 # deliberate split: the roster-ordered file list
    cat $files 2>/dev/null
  else
    for label in $wanted; do run_lister "$label"; done
  fi

  [ -n "$scratch" ] && rm -rf "$scratch" 2>/dev/null
  scratch=""
  return 0
}

# The listers, each reached indirectly through run_lister's dispatch.

# docker and podman are one call (drop-in CLIs); the tag is appended by the
# read loop rather than by a `sed` over the result - one fewer exec per backend
# on the path that runs on every TAB, for the reason cache_body gives.
list_ps() {
  run_backend "$1" ps --format '{{.Names}}' 2>/dev/null |
    while IFS= read -r _hi_name || [ -n "$_hi_name" ]; do
      [ -n "$_hi_name" ] || continue
      printf '%s\t%s\n' "$_hi_name" "$1"
    done
}

# nomad_allocs <job> - the running allocations of one job, and the task names
# riding the same template as the ID, so this stays one call per job.
nomad_allocs() {
  # shellcheck disable=SC2016 # $t/$s are nomad's Go template, not the shell's
  run_backend nomad job allocs -t \
    '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{range $t, $s := .TaskStates}}{{" "}}{{$t}}{{end}}{{"\n"}}{{end}}{{end}}' \
    "$1" 2>/dev/null
}

# The allocation, plus "alloc/task" per task when the group has more than one -
# the same shape list_kube emits, and the same syntax hi takes.
#
# The per-job calls go out together where there is a scratch dir to collect
# them: each carries its own $_HI_PROBE_TIMEOUT, so run in turn N wedged jobs
# cost N ceilings and nothing bounds the total. This is the file's one fan-out
# sized by the host rather than by the roster.
list_nomad() {
  _hi_jobs="$(run_backend nomad job status 2>/dev/null | awk 'NR > 1 { print $1 }')"
  [ -n "$_hi_jobs" ] || return 0
  if [ -n "$scratch" ]; then
    _hi_j=0
    for _hi_job in $_hi_jobs; do
      _hi_j=$((_hi_j + 1))
      nomad_allocs "$_hi_job" >"$scratch/nomad.$_hi_j" 2>/dev/null &
    done
    wait
    # the glob cannot catch the "nomad" the backend fan-out writes: no dot
    cat "$scratch"/nomad.* 2>/dev/null
  else
    for _hi_job in $_hi_jobs; do nomad_allocs "$_hi_job"; done
  fi | while read -r alloc t1 t2 rest; do
    [ -n "$alloc" ] || continue
    printf '%s\tnomad\n' "$alloc"
    if [ -n "$t2" ]; then
      for t in $t1 $t2 $rest; do printf '%s/%s\tnomad\n' "$alloc" "$t"; done
    fi
  done
}

# The pod, and - when it has more than one container - a "pod/container" line
# per container as well, which is the syntax hi takes for picking one. A
# single-container pod emits only its own name: the suffix would be noise on a
# target where there is nothing to choose.
#
# One jsonpath, not one call per pod: this runs on every TAB.
list_kube() {
  run_backend kubectl get pods --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{range .spec.containers[*]}{" "}{.name}{end}{"\n"}{end}' 2>/dev/null |
    while read -r pod c1 c2 rest; do
      [ -n "$pod" ] || continue
      printf '%s\tkube\n' "$pod"
      # c2 non-empty means more than one container, so the choice is real
      if [ -n "$c2" ]; then
        for c in $c1 $c2 $rest; do printf '%s/%s\tkube\n' "$pod" "$c"; done
      fi
    done
}

# No cache wanted (or no writable place to put one): just answer. Reached
# before the two forks below, so a TTL of 0 pays for neither.
if [ "$ttl" -le 0 ]; then
  emit_targets
  exit 0
fi

# $XDG_RUNTIME_DIR is per-user and 0700 where it exists; the fallback makes a
# private directory of its own, not a predictable name in a shared /tmp.
cache_dir="${XDG_RUNTIME_DIR:-}"
if [ -z "$cache_dir" ] || [ ! -d "$cache_dir" ]; then
  cache_dir="${TMPDIR:-/tmp}/hi-$(id -u 2>/dev/null || echo unknown)"
  # first TAB only: otherwise two execs per completion on any host without
  # $XDG_RUNTIME_DIR (macOS, most containers)
  # -m 700 on the create, so a fresh cache is never even briefly world-readable
  # - and no -p, which would silently adopt a path somebody else made. The
  # chmod is the other arm rather than a follow-on: it runs only when the mkdir
  # declined, which past the `-d` test above means losing a race with another
  # shell, and this directory is *meant* to outlive the run.
  [ -d "$cache_dir" ] || {
    mkdir -m 700 "$cache_dir" 2>/dev/null || chmod 700 "$cache_dir" 2>/dev/null
  }
fi
cache="$cache_dir/hi.targets.$kind"
now="$(date +%s 2>/dev/null || echo 0)"

# The timestamp is the cache's first line, not the mtime: every portable way to
# read an mtime in seconds is a GNU `find`/`stat` extension.
if [ -f "$cache" ] && [ -r "$cache" ]; then
  # `read < file`, not $(head -n1): on the cache-*hit* path the subshell+exec
  # was most of the cost
  IFS= read -r stamp <"$cache" 2>/dev/null || stamp=""
  case "$stamp" in
  '' | *[!0-9]*) ;; # not a timestamp - treat as a miss and rewrite it
  *)
    if [ "$now" -ge "$stamp" ] && [ "$((now - stamp))" -lt "$ttl" ]; then
      cache_body "$cache"
      exit 0
    fi
    ;;
  esac
fi

# Swept once, then temp-file-and-mv so a mid-refresh reader sees old or new,
# never half. A cache that can't be written is not an error - answer anyway.
out="$(emit_targets)"
tmp="$cache.$$"
if {
  printf '%s\n' "$now"
  [ -n "$out" ] && printf '%s\n' "$out"
  true
} >"$tmp" 2>/dev/null; then
  mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
  rm -f "$tmp" 2>/dev/null
fi
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
