#!/bin/bash
set -eou pipefail

function append() {
  local input="$1"
  local output="$2"
  local tmpdir="${3:-$(mktemp -d)}"
  local appendfile="$tmpdir/append.tmp"

  touch "$input" "$output"
  cat "$output" > "$appendfile"
  grep -vxF -f "$output" "$input" >> "$appendfile"
  mv "$appendfile" "$output"
}
