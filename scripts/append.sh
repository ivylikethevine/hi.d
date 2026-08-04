#!/bin/bash
set -eou pipefail

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
