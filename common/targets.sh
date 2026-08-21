#!/bin/sh
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each.
# The bash, zsh and fish completions (and `hi_colors`) all read this for
# connection, autocomplete, and autosuggest.
# Usage: sh targets.sh [ssh|docker|podman|nomad|kube|flags]
#        (no argument = every backend; `flags` = hi's own options instead)
# GLOSSARY: HI.26 - _HI_PROBE_TIMEOUT and _HI_TARGETS_TTL
# shellcheck disable=SC2329 # every function here is reached indirectly - by
# the completion hook that sources this file, or through emit_backend's
# dispatch - so "never invoked" is true of the file, not of five lines in it.

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
  printf '%s\n' --help --version --doctor --tmux --no-tmux
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

# emit_backend <label> <bin> <lister...> - kind gate, presence check, timeout
# wrap. Listers go through "$@" (hence SC2329).
emit_backend() {
  label="$1" bin="$2"
  shift 2
  { [ "$kind" = "$label" ] || [ "$kind" = all ]; } || return 0
  command -v "$bin" >/dev/null 2>&1 || return 0
  "$@"
}

emit_targets() {
  if [ "$kind" = ssh ] || [ "$kind" = all ]; then
    [ -f "${_HI_SSH_CONFIG:-$HOME/.ssh/config}" ] &&
      awk 'tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) break
          if ($i !~ /[*?]/) printf "%s\tssh\n", $i
        }
      }' "${_HI_SSH_CONFIG:-$HOME/.ssh/config}"
  fi

  emit_backend docker docker list_ps docker
  emit_backend podman podman list_ps podman
  emit_backend nomad nomad list_nomad
  emit_backend kube kubectl list_kube
  return 0
}

# The listers, each reached indirectly through emit_backend's "$@".

# docker and podman are one call (drop-in CLIs); the tag rides a `sed` over the
# result, so it holds whatever the backend does with --format
list_ps() {
  run_backend "$1" ps --format '{{.Names}}' 2>/dev/null | sed "s/\$/	$1/"
}

# The allocation, plus "alloc/task" per task when the group has more than one -
# the same shape list_kube emits, and the same syntax hi takes. The task names
# come from the same template as the ID, so this stays one call per job.
list_nomad() {
  run_backend nomad job status 2>/dev/null | awk 'NR > 1 { print $1 }' | while read -r job; do
    # shellcheck disable=SC2016 # $t/$s are nomad's Go template, not the shell's
    run_backend nomad job allocs -t \
      '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{range $t, $s := .TaskStates}}{{" "}}{{$t}}{{end}}{{"\n"}}{{end}}{{end}}' \
      "$job" 2>/dev/null
  done | while read -r alloc t1 t2 rest; do
    [ -n "$alloc" ] || continue
    printf '%s	nomad\n' "$alloc"
    if [ -n "$t2" ]; then
      for t in $t1 $t2 $rest; do printf '%s/%s	nomad\n' "$alloc" "$t"; done
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
      printf '%s	kube\n' "$pod"
      # c2 non-empty means more than one container, so the choice is real
      if [ -n "$c2" ]; then
        for c in $c1 $c2 $rest; do printf '%s/%s	kube\n' "$pod" "$c"; done
      fi
    done
}

# No cache wanted (or no writable place to put one): just answer.
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
  [ -d "$cache_dir" ] || {
    mkdir -p "$cache_dir" 2>/dev/null && chmod 700 "$cache_dir" 2>/dev/null
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
