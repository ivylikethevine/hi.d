#!/bin/bash
# Points the local shells at hi.d's configs and links hi.sh onto $PATH.
# Safe to re-run: it repairs the lines it owns and leaves everything else alone.
set -euo pipefail

# Locate hi.d relative to this script (resolving symlinks).
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"
  _HI_SELF="$(readlink "$_HI_SELF")"
  [[ $_HI_SELF == /* ]] || _HI_SELF="$_HI_SELF_DIR/$_HI_SELF"
done
_HI_TMPDIR="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)" # hi.d's parent, usually $HOME
export _HI_TMPDIR

# shellcheck source=../common/bootstrap.sh
source "$_HI_TMPDIR/hi.d/common/bootstrap.sh"

_HI_MARKER="# added by hi during install"
_HI_LINK="/usr/bin/hi"

# Rewrite the block of hi-managed lines (tagged with $_HI_MARKER) in $target to
# be exactly $@, leaving any other user content untouched. This both installs
# the sourcing on a fresh machine and repairs it if hi.d has since moved -
# stale lines pointing at an old location are replaced, not left dangling
# alongside new ones. Empty arguments are skipped.
function config_shell() {
  local name="$1" target="$2" line existing desired="" tmpfile
  shift 2
  cecho "=== Checking $name ===" "$YELLOW"

  mkdir -p "$(dirname "$target")"
  touch "$target"
  for line in "$@"; do
    [ -n "$line" ] && desired+="$(printf '%-45s %s' "$line" "$_HI_MARKER")"$'\n'
  done

  existing="$(grep -F "$_HI_MARKER" "$target" || true)"
  if [ "$existing" = "${desired%$'\n'}" ]; then
    cecho "local $name up to date :)" "$GREEN"
    return 0
  fi

  cecho "local $name out of date, updating..." "$YELLOW"
  tmpfile="$(mktemp -t hi.append.XXXXXX)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  printf '%s' "$desired" >>"$tmpfile"
  mv "$tmpfile" "$target"
  cecho "local $name updated :)" "$GREEN"
}

# Only emit an _HI_TMPDIR export when hi.d isn't at $HOME/hi.d - every consumer
# already defaults _HI_TMPDIR to $HOME, so the common case stays free of it.
function tmpdir_line() {
  [ "$_HI_TMPDIR" = "$HOME" ] && return 0
  case "$1" in
  fish) printf 'set -gx _HI_TMPDIR "%s"' "$_HI_TMPDIR" ;;
  *) printf 'export _HI_TMPDIR="%s"' "$_HI_TMPDIR" ;;
  esac
}

function config_hi() {
  cecho "=== Checking hi.sh ===" "$YELLOW"
  chmod +x "$_HI_LAUNCHER"
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" = "$_HI_LAUNCHER" ]; then
    cecho "$_HI_LINK already points at $_HI_LAUNCHER :)" "$GREEN"
    return 0
  fi
  cecho "Linking $_HI_LINK -> $_HI_LAUNCHER... [password required]" "$BLUE"
  sudo ln -sfn "$_HI_LAUNCHER" "$_HI_LINK"
}

cecho "~~~~~ Installing (or reinstalling) hi.sh! ~~~~~" "$BRGREEN"
cecho "pwd: $PWD | hi_root: $_HI_ROOT | hi_tmpdir: $_HI_TMPDIR | shell: ${SHELL##*/}" "$BLUE"

config_shell bashrc "$_HI_HOME_BASHRC" \
  "$(tmpdir_line sh)" \
  '[[ $- != *i* ]] && return' \
  "source \"$_HI_BASHRC\""

config_shell zshrc "$_HI_HOME_ZSHRC" \
  "$(tmpdir_line sh)" \
  "source \"$_HI_ZSHRC\""

config_shell config.fish "$_HI_HOME_FISH_CONFIG" \
  "$(tmpdir_line fish)" \
  'if status is-interactive' \
  "  source \"$_HI_FISH_CONFIG\"" \
  'end'

config_hi

cecho "~~~~~ Installed! ~~~~~ " "$BRGREEN"
