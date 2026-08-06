#!/bin/bash
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/bootstrap.sh
source "$_HI_TMPDIR/hi.d/common/bootstrap.sh"
# shellcheck source=./scripts/append.sh
command -v append >/dev/null || source "$_HI_APPEND"

# shared by config_bashrc/config_zshrc/config_fish: write $content to a temp
# file named $name under $tmpdir, then append any new lines onto $target
function config_shell() {
  local name="$1" content="$2" target="$3" tmpdir="$4"
  cecho "=== Checking $name ===" "$YELLOW"

  local tmpfile="$tmpdir/$name"
  printf '%s\n' "$content" >>"$tmpfile"
  append "$tmpfile" "$target" "$tmpdir"

  cecho "local $name up to date :)" "$GREEN"
}

function config_bashrc() {
  config_shell "bashrc" '# If not running interactively, exit   # added by hi during install
[[ $- != *i* ]] && return              # added by hi during install
source ~/hi.d/shells/bash.sh          # added by hi during install' "$_HI_HOME_BASHRC" "$1"
}

function config_zshrc() {
  config_shell "zshrc" 'source ~/hi.d/shells/zsh.zsh          # added by hi during install' "$_HI_HOME_ZSHRC" "$1"
}

function config_fish() {
  config_shell "config.fish" 'if status is-interactive               # added by hi during install
  source ~/hi.d/shells/config.fish    # added by hi during install
end                                    # added by hi during install' "$_HI_HOME_FISH_CONFIG" "$1"
}

function config_hi() {
  cecho "=== Checking hi.sh ===" "$YELLOW"
  local INSTALLED_HI="/usr/bin/hi"
  local NEW_HI="$HOME/hi.d/hi.sh"

  chmod +x "$NEW_HI"

  if diff --color=always -w -u "$NEW_HI" "$INSTALLED_HI" 2>/dev/null; then
    cecho "$INSTALLED_HI is same as $NEW_HI :)" "$GREEN"
    return 0
  else
    cecho "$INSTALLED_HI out of date, updating..." "$YELLOW"
    cecho "Removing old $INSTALLED_HI... [password required]" "$BLUE"
    sudo rm "$INSTALLED_HI"
    cecho "Linking $INSTALLED_HI to latest hi.sh... [password required]" "$BLUE"
    sudo ln -s "$NEW_HI" "$INSTALLED_HI"
  fi
}

function main() {
  cecho "~~~~~ Installing (or reinstalling) hi.sh! ~~~~~" "$BRGREEN"

  cecho "===== Checking $USER's login shell =====" "$BRCYAN"
  local shellname
  shellname=$(grep -e "$USER" /etc/passwd | xargs basename)
  cecho "===== [$shellname] shell detected! =====" "$CYAN"

  local TMP
  TMP=$(mktemp -d)
  if [ -z "$ZSH_VERSION" ]; then
    trap 'rm -rfv $TMP' exit
  else
    TRAPEXIT() { rm -rfv \$TMP; }
  fi

  config_bashrc "$TMP"
  config_zshrc "$TMP"
  config_fish "$TMP"

  config_hi

  rm -rfv "$TMP"

  cecho "~~~~~ Installed! ~~~~~ " "$BRGREEN"
}

main
