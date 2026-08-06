#!/bin/sh
# Everything `hi <target>` can connect to, one "<name>\t<kind>" line each.
# The bash, zsh and fish completions (and `hi_colors`) all read this same
# output, so there is one implementation instead of three.
# Usage: sh targets.sh [ssh|docker|nomad]   (no argument = all of them)
kind="${1:-all}"

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
    docker ps --format '{{.Names}}' 2>/dev/null | sed 's/$/\tdocker/'
fi

if [ "$kind" = nomad ] || [ "$kind" = all ]; then
  command -v nomad >/dev/null 2>&1 &&
    nomad job status 2>/dev/null | awk 'NR > 1 { print $1 }' | while read -r job; do
      nomad job allocs -t \
        '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{"\n"}}{{end}}{{end}}' \
        "$job" 2>/dev/null | sed 's/$/\tnomad/'
    done
fi

exit 0
