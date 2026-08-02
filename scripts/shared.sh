#!/bin/bash
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

function append() {
  local input="$1"
  local output="$2"
  local tmpdir="${3:-$(mktemp -d)}"
  local appendfile="$tmpdir/append.tmp"

  if ! test -f "$input"; then
    touch "$input"
  fi
  cat "$input" | grep -vxF -f "$output" > "$appendfile"
  cat "$output" >> "$appendfile"
  mv "$appendfile" "$output"
}
