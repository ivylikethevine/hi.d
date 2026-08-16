#!/bin/sh
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each.
# The bash, zsh and fish completions (and `hi_colors`) all read this for
# connection, autocomplete, and autosuggest.
# Usage: sh targets.sh [ssh|docker|podman|nomad|kube] (no argument = all of them)
#
# Runs on every TAB after `hi `, the most latency-sensitive path in hi.d and the
# slowest (four of five backends are a subprocess each). Two knobs keep it honest:
#   _HI_PROBE_TIMEOUT  seconds any one backend CLI gets (default 2, needs GNU
#                      `timeout`), or an unreachable daemon hangs completion
#                      unbounded. Shared with common/core.sh's _hi_probe.
#   _HI_TARGETS_TTL    seconds a result is reused (default 5, 0 disables). A
#                      just-started container may not appear until it expires;
#                      the trade for not paying ~110ms per TAB.
kind="${1:-all}"
ttl="${_HI_TARGETS_TTL:-5}"

# `timeout` is GNU coreutils, absent on a stock macOS, so it stays optional.
# Called only from list_*, which SC2329 can't follow.
# shellcheck disable=SC2329
if command -v timeout >/dev/null 2>&1; then
  run_backend() { timeout "${_HI_PROBE_TIMEOUT:-2}" "$@"; }
else
  run_backend() { "$@"; }
fi

# Everything below the first line of $1, fork-free - faster than a `tail` exec
# at this size, and it keeps the cache working on a PATH with no coreutils.
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

# emit_backend <label> <bin> <lister...> - kind gate + presence check +
# timeout wrap. Listers go through "$@" (hence SC2329).
# shellcheck disable=SC2329
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
# shellcheck disable=SC2329

# docker and podman are the same call - podman's CLI is a drop-in - so only the
# binary differs. One `sed` over the whole result rather than the CLI's format
# string, so the tagging holds whatever the backend does with --format.
list_ps() {
  run_backend "$1" ps --format '{{.Names}}' 2>/dev/null | sed "s/\$/	$1/"
}

# shellcheck disable=SC2329
list_nomad() {
  run_backend nomad job status 2>/dev/null | awk 'NR > 1 { print $1 }' | while read -r job; do
    run_backend nomad job allocs -t \
      '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{"\n"}}{{end}}{{end}}' \
      "$job" 2>/dev/null
  done | sed 's/$/	nomad/'
}

# shellcheck disable=SC2329
list_kube() {
  run_backend kubectl get pods --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed 's/$/	kube/'
}

# No cache wanted (or no writable place to put one): just answer.
if [ "$ttl" -le 0 ]; then
  emit_targets
  exit 0
fi

# $XDG_RUNTIME_DIR is per-user and 0700 where it exists; the fallback makes its
# own private directory rather than a predictable name in a shared /tmp.
cache_dir="${XDG_RUNTIME_DIR:-}"
if [ -z "$cache_dir" ] || [ ! -d "$cache_dir" ]; then
  cache_dir="${TMPDIR:-/tmp}/hi-$(id -u 2>/dev/null || echo unknown)"
  # only on the first TAB - mkdir+chmod otherwise cost two execs per completion
  # on any host without $XDG_RUNTIME_DIR (macOS, most containers)
  [ -d "$cache_dir" ] || {
    mkdir -p "$cache_dir" 2>/dev/null && chmod 700 "$cache_dir" 2>/dev/null
  }
fi
cache="$cache_dir/hi.targets.$kind"
now="$(date +%s 2>/dev/null || echo 0)"

# The timestamp is the cache's first line, not the file's mtime: every portable
# way to read an mtime in seconds is a GNU `find`/`stat` extension.
if [ -f "$cache" ] && [ -r "$cache" ]; then
  # `read < file`, not $(head -n1): this is the cache-*hit* path, where the
  # subshell+exec was most of the cost.
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

# Swept once into a variable, then written to a temp file and moved into place,
# so a completion reading mid-refresh sees the old answer or the new one, never
# half of one. A cache that can't be written is not an error - answer anyway.
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
