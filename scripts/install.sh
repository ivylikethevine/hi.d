#!/bin/bash
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"
# shellcheck source=./shared.sh
command -v append >/dev/null || source "$_HI_TMPDIR/hi.d/scripts/shared.sh"

function config_bashrc() {
  cecho "=== Checking bashrc ===" "$YELLOW"

  local tmpdir="$1"
  local tmp_bashrc="$tmpdir/bashrc"
  cat <<'EOF' >> "$tmp_bashrc"
# If not running interactively, exit   # added by hi during install
[[ $- != *i* ]] && return              # added by hi during install
source ~/hi.d/shells/bash.sh          # added by hi during install
EOF
  append "$tmp_bashrc" "$_HI_HOME_BASHRC" "$tmpdir"

  cecho "local bashrc up to date :)" "$GREEN"
}

function config_zshrc() {
  cecho "=== Checking zshrc ===" "$YELLOW"

  local tmpdir="$1"
  local tmp_zshrc="$tmpdir/zshrc"
  cat <<'EOF' >> "$tmp_zshrc"
source ~/hi.d/shells/zsh.zsh          # added by hi during install
EOF
  append "$tmp_zshrc" "$_HI_HOME_ZSHRC" "$tmpdir"

  cecho "local zshrc up to date :)" "$GREEN"
}

function config_fish() {
  cecho "=== Checking config.fish ===" "$YELLOW"

  local tmpdir="$1"
  local tmp_fish="$tmpdir/config.fish"
  cat <<'EOF' >> "$tmp_fish"
if status is-interactive               # added by hi during install
  source ~/hi.d/shells/config.fish    # added by hi during install
end                                    # added by hi during install
EOF
  append "$tmp_fish" "$_HI_HOME_FISH_CONFIG" "$tmpdir"

  cecho "local config.fish up to date :)" "$GREEN"
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
  shellname=$(cat /etc/passwd | grep -e "$USER" | xargs basename)
  cecho "===== [$shellname] shell detected! =====" "$CYAN"

  local TMP
  TMP=$(mktemp -d)
  if [ -z "$ZSH_VERSION" ]; then
    trap 'rm -rf $TMP' exit
  else
    TRAPEXIT() { rm -rf \$TMP; }
  fi

  config_bashrc "$TMP"
  config_zshrc "$TMP"
  config_fish "$TMP"

  config_hi

  cecho "===== Running hi_colorgen =====" "$BRCYAN"
  # shellcheck source=./colorgen.sh
  source "$_HI_COLORGEN"
  initial_colorgen
  rm -rf "$TMP"

  cecho "~~~~~ Installed! ~~~~~ " "$BRGREEN"
}

main
