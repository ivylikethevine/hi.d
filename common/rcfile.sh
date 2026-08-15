#!/bin/bash
# Ownership of the lines hi adds to a user's shell rc files: writing them
# (config_shell) and taking them back out (strip_marker), shared by
# scripts/install.sh and scripts/uninstall.sh so the two halves of one contract
# can't drift. $_HI_MARKER comes from common/paths.sh.
#
# Deliberately not merged with load.sh's configure_files/clean_all: those graft
# a whole file into a *target's* rc for one session, keyed by start/end block
# comments. These own individual lines in a permanent local rc, tagged one by
# one, and must keep recognising lines older installs wrote.

# Rewrite the hi-managed block (tagged with $_HI_MARKER) in $target to be
# exactly $@, leaving other content untouched - so this both installs on a fresh
# machine and repairs stale lines if hi.d has moved. Empty arguments are
# skipped, so a setting left at its default contributes nothing.
function config_shell() {
  local name="$1" target="$2" line existing desired="" tmpfile
  shift 2
  _hi_h2 "Checking $name"

  mkdir -p "$(dirname "$target")"
  touch "$target"
  for line in "$@"; do
    [ -n "$line" ] && desired+="$(printf '%-45s %s' "$line" "$_HI_MARKER")"$'\n'
  done

  existing="$(grep -F "$_HI_MARKER" "$target" || true)"
  if [ "$existing" = "${desired%$'\n'}" ]; then
    _hi_cecho " local $name up to date :)" "$GREEN"
    return 0
  fi

  _hi_cecho " local $name out of date, updating..." "$YELLOW"
  tmpfile="$(mktemp -t hi.append.XXXXXX)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  printf '%s' "$desired" >>"$tmpfile"
  mv "$tmpfile" "$target"
  _hi_cecho " local $name updated :)" "$GREEN"
}

# config_shell with an empty block, plus a quieter report for the common
# "there was nothing here anyway" case.
function strip_marker() {
  local name="$1" target="$2"
  if [ ! -f "$target" ] || ! grep -qF "$_HI_MARKER" "$target"; then
    _hi_h2 "Checking $name"
    _hi_cecho " local $name has no hi lines :)" "$GREEN"
    return 0
  fi
  config_shell "$name" "$target"
}
