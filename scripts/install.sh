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
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)" # hi.d's parent, usually $HOME
export _HI_HOME

# shellcheck source=../common/bootstrap.sh
source "$_HI_HOME/hi.d/common/bootstrap.sh"

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

# Only emit an _HI_HOME export when hi.d isn't at $HOME/hi.d - every consumer
# already defaults _HI_HOME to $HOME, so the common case stays free of it.
function tmpdir_line() {
  [ "$_HI_HOME" = "$HOME" ] && return 0
  case "$1" in
  fish) printf 'set -gx _HI_HOME "%s"' "$_HI_HOME" ;;
  *) printf 'export _HI_HOME="%s"' "$_HI_HOME" ;;
  esac
}

function config_hi() {
  _hi_h2 "Checking hi.sh"
  chmod +x "$_HI_LAUNCHER"
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" = "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK already points at $_HI_LAUNCHER :)" "$GREEN"
    return 0
  fi
  _hi_cecho " Linking $_HI_LINK -> $_HI_LAUNCHER... [password required]" "$BLUE"
  sudo ln -sfn "$_HI_LAUNCHER" "$_HI_LINK"
}

# _hi_cecho " ~~~~~ Installing (or reinstalling) hi.sh! ~~~~~" "$BRGREEN"
_hi_h1 "Installing (or reinstalling) hi.sh!"
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | login shell: ${SHELL##*/}" "$BLUE"

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

_hi_h1 "Installed!"
