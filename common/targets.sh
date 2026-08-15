#!/bin/sh
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each.
# The bash, zsh and fish completions (and `hi_colors`) all read this for
# connection, autocomplete, and autosuggest.
# Usage: sh targets.sh [ssh|docker|podman|nomad|kube] (no argument = all of them)
#
# This runs on every TAB after `hi `, which makes it the most latency-sensitive
# path in hi.d - and the slowest, because four of the five backends are a
# subprocess each. Two things keep it honest:
#
#   _HI_TARGETS_TIMEOUT  seconds any one backend CLI gets before it's given up
#                        on (default 2, needs GNU coreutils' `timeout`). An
#                        unreachable docker daemon or a kubectl pointed at a
#                        dead cluster would otherwise hang the completion with
#                        no upper bound at all.
#   _HI_TARGETS_TTL      seconds a result is reused for (default 5, 0 disables).
#                        A container started in the last few seconds may not
#                        appear until the entry expires; that is the trade for
#                        not paying ~110ms on every single TAB.
kind="${1:-all}"
ttl="${_HI_TARGETS_TTL:-5}"

# `timeout` is GNU coreutils - absent on a stock macOS, so it stays optional
# rather than becoming a hard requirement of the completion path.
if command -v timeout >/dev/null 2>&1; then
  run_backend() { timeout "${_HI_TARGETS_TIMEOUT:-2}" "$@"; }
else
  run_backend() { "$@"; }
fi

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

  if [ "$kind" = docker ] || [ "$kind" = all ]; then
    command -v docker >/dev/null 2>&1 &&
      run_backend docker ps --format '{{.Names}}' 2>/dev/null | sed 's/$/\tdocker/'
  fi

  if [ "$kind" = podman ] || [ "$kind" = all ]; then
    command -v podman >/dev/null 2>&1 &&
      run_backend podman ps --format '{{.Names}}' 2>/dev/null | sed 's/$/\tpodman/'
  fi

  if [ "$kind" = nomad ] || [ "$kind" = all ]; then
    command -v nomad >/dev/null 2>&1 &&
      run_backend nomad job status 2>/dev/null | awk 'NR > 1 { print $1 }' | while read -r job; do
        run_backend nomad job allocs -t \
          '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{"\n"}}{{end}}{{end}}' \
          "$job" 2>/dev/null | sed 's/$/\tnomad/'
      done
  fi

  if [ "$kind" = kube ] || [ "$kind" = all ]; then
    command -v kubectl >/dev/null 2>&1 &&
      run_backend kubectl get pods --field-selector=status.phase=Running \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed 's/$/\tkube/'
  fi
  return 0
}

# No cache wanted (or no writable place to put one): just answer.
if [ "$ttl" -le 0 ]; then
  emit_targets
  exit 0
fi

# $XDG_RUNTIME_DIR is already per-user and 0700 where it exists, which is what
# this wants; the fallback makes its own private directory rather than writing
# a predictable name straight into a shared /tmp.
cache_dir="${XDG_RUNTIME_DIR:-}"
if [ -z "$cache_dir" ] || [ ! -d "$cache_dir" ]; then
  cache_dir="${TMPDIR:-/tmp}/hi-$(id -u 2>/dev/null || echo unknown)"
  mkdir -p "$cache_dir" 2>/dev/null && chmod 700 "$cache_dir" 2>/dev/null
fi
cache="$cache_dir/hi.targets.$kind"
now="$(date +%s 2>/dev/null || echo 0)"

# The timestamp is the cache's own first line rather than the file's mtime:
# every portable way to read an mtime in seconds is a GNU `find` or `stat`
# extension, and this file has to stay POSIX sh.
if [ -f "$cache" ] && [ -r "$cache" ]; then
  stamp="$(head -n 1 "$cache" 2>/dev/null)"
  case "$stamp" in
  '' | *[!0-9]*) ;; # not a timestamp - treat as a miss and rewrite it
  *)
    if [ "$now" -ge "$stamp" ] && [ "$((now - stamp))" -lt "$ttl" ]; then
      tail -n +2 "$cache"
      exit 0
    fi
    ;;
  esac
fi

# Written to a temp file and moved into place, so a second completion reading
# the cache mid-refresh sees either the old answer or the new one, never half
# of one. A cache that can't be written is not an error - answer anyway.
tmp="$cache.$$"
if {
  printf '%s\n' "$now"
  emit_targets
} >"$tmp" 2>/dev/null; then
  mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  tail -n +2 "$cache" 2>/dev/null || emit_targets
else
  rm -f "$tmp" 2>/dev/null
  emit_targets
fi
exit 0
