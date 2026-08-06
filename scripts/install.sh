#!/bin/bash
set -eou pipefail

# Locate hi.d relative to this script (resolving symlinks) so install works no matter where the repo lives.
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"
  _HI_SELF="$(readlink "$_HI_SELF")"
  [[ $_HI_SELF == /* ]] || _HI_SELF="$_HI_SELF_DIR/$_HI_SELF"
done
_HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"

_HI_ROOT="$(dirname "$_HI_SELF_DIR")" # .../hi.d
_HI_TMPDIR="$(dirname "$_HI_ROOT")"   # wherever hi.d's parent dir is (usually $HOME)
export _HI_TMPDIR

# shellcheck source=./common/bootstrap.sh
source "$_HI_ROOT/common/bootstrap.sh"

readonly _HI_MARKER="# added by hi during install"

# Rewrite the block of hi-managed lines (tagged with $_HI_MARKER) in $target to
# match $content, leaving any other user content untouched. This both installs
# the sourcing on a fresh machine and repairs it if hi.d has since moved -
# stale lines pointing at an old location are replaced, not left dangling
# alongside new ones.
function config_shell() {
  local name="$1" content="$2" target="$3"
  cecho "=== Checking $name ===" "$YELLOW"

  mkdir -p "$(dirname "$target")"
  touch "$target"

  local existing desired
  existing="$(grep -F "$_HI_MARKER" "$target" || true)"
  desired="$(printf '%s\n' "$content" | grep -F "$_HI_MARKER" || true)"

  if [ "$existing" = "$desired" ]; then
    cecho "local $name up to date :)" "$GREEN"
    return 0
  fi

  cecho "local $name out of date, updating..." "$YELLOW"
  local tmpfile
  tmpfile="$(mktemp)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  printf '%s\n' "$content" >>"$tmpfile"
  mv "$tmpfile" "$target"
  cecho "local $name updated :)" "$GREEN"
}

# Only emit an _HI_TMPDIR export when hi.d isn't at $HOME/hi.d - every
# consumer already defaults _HI_TMPDIR to $HOME on its own, so the common
# case stays free of an extra rc line.
function hi_tmpdir_line_sh() {
  [ "$_HI_TMPDIR" = "$HOME" ] && return 0
  printf 'export _HI_TMPDIR="%s"                 %s' "$_HI_TMPDIR" "$_HI_MARKER"
}

function hi_tmpdir_line_fish() {
  [ "$_HI_TMPDIR" = "$HOME" ] && return 0
  printf 'set -gx _HI_TMPDIR "%s"                 %s' "$_HI_TMPDIR" "$_HI_MARKER"
}

function config_bashrc() {
  local content line
  content=""
  line="$(hi_tmpdir_line_sh)"
  [ -n "$line" ] && content+="$line"$'\n'
  content+="# If not running interactively, exit   $_HI_MARKER"$'\n'
  content+="[[ \$- != *i* ]] && return              $_HI_MARKER"$'\n'
  content+="source \"$_HI_ROOT/shells/bash.sh\"          $_HI_MARKER"
  config_shell "bashrc" "$content" "$_HI_HOME_BASHRC"
}

function config_zshrc() {
  local content line
  content=""
  line="$(hi_tmpdir_line_sh)"
  [ -n "$line" ] && content+="$line"$'\n'
  content+="source \"$_HI_ROOT/shells/zsh.zsh\"          $_HI_MARKER"
  config_shell "zshrc" "$content" "$_HI_HOME_ZSHRC"
}

function config_fish() {
  local content line
  content=""
  line="$(hi_tmpdir_line_fish)"
  [ -n "$line" ] && content+="$line"$'\n'
  content+="if status is-interactive               $_HI_MARKER"$'\n'
  content+="  source \"$_HI_ROOT/shells/config.fish\"    $_HI_MARKER"$'\n'
  content+="end                                    $_HI_MARKER"
  config_shell "config.fish" "$content" "$_HI_HOME_FISH_CONFIG"
}

function config_hi() {
  cecho "=== Checking hi.sh ===" "$YELLOW"
  local INSTALLED_HI="/usr/bin/hi"
  local NEW_HI="$_HI_ROOT/hi.sh"

  chmod +x "$NEW_HI"

  if diff --color=always -w -u "$NEW_HI" "$INSTALLED_HI" 2>/dev/null; then
    cecho "$INSTALLED_HI is same as $NEW_HI :)" "$GREEN"
    return 0
  else
    cecho "$INSTALLED_HI out of date, updating..." "$YELLOW"
    cecho "Removing old $INSTALLED_HI... [password required]" "$BLUE"
    sudo rm -f "$INSTALLED_HI"
    cecho "Linking $INSTALLED_HI to latest hi.sh... [password required]" "$BLUE"
    sudo ln -s "$NEW_HI" "$INSTALLED_HI"
  fi
}

function main() {
  cecho "~~~~~ Installing (or reinstalling) hi.sh! ~~~~~" "$BRGREEN"
  echo "pwd: $PWD | hi_root: $_HI_ROOT | hi_tmpdir: $_HI_TMPDIR"
  cecho "===== Checking $USER's login shell =====" "$BRCYAN"
  local shellname
  shellname=$(grep -e "$USER" /etc/passwd | xargs basename)
  cecho "===== [$shellname] shell detected! =====" "$CYAN"

  config_bashrc
  config_zshrc
  config_fish

  config_hi

  cecho "~~~~~ Installed! ~~~~~ " "$BRGREEN"
}

main
