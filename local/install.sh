#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-~}
# shellcheck source=./common/paths.sh
source "$HI_TMPDIR/.hi.d/common/paths.sh"
# shellcheck source=./common/aliases.sh
source "$_HI_ALIASES_PATH"

install_tmpdir=$(mktemp -d)
tmp_bashrc="$install_tmpdir/bashrc"
tmp_zshrc="$install_tmpdir/zshrc"
tmp_fish="$install_tmpdir/config.fish"

if ! command cecho 2>/dev/null; then
  # shellcheck source=./../common/prompt_colors.sh
  source "$_HI_PROMPT_COLORS_PATH"
fi

function append() {
  local input="$1"
  local output="$2"
  if ! test -f "$input"; then
    touch "$input"
  fi
  cat "$input" | grep -vxF -f "$output" > "$install_tmpdir/append.tmp"
  cat "$output" >> "$install_tmpdir/append.tmp"
  mv "$install_tmpdir/append.tmp" "$2"
}

function config_bashrc() {
  cecho "Checking bashrc ========" "$CYAN"
  cat <<'EOF' >> "$tmp_bashrc"
# If not running interactively, exit   # added by hi during install
[[ $- != *i* ]] && return              # added by hi during install
source ~/.hi.d/shells/bash.sh          # added by hi during install
EOF
  append "$tmp_bashrc" "$HOME_BASHRC"
  cecho "local bashrc up to date :)" "$GREEN"
}

function config_zshrc() {
  cecho "Checking zshrc ========" "$CYAN"
  cat <<'EOF' >> "$tmp_zshrc"
source ~/.hi.d/shells/zsh.zsh          # added by hi during install
EOF
  append "$tmp_zshrc" "$HOME_ZSHRC"
  cecho "local zshrc up to date :)" "$GREEN"
}

function config_fish() {
  cecho "Checking config.fish ========" "$CYAN"
  cat <<'EOF' >> "$tmp_fish"
if status is-interactive               # added by hi during install
  source ~/.hi.d/shells/config.fish    # added by hi during install
end                                    # added by hi during install
EOF
  append "$tmp_fish" "$HOME_FISH"
  cecho "local config.fish up to date :)" "$GREEN"
}

function config_hi() {
  cecho "Checking hi.sh ========" "$CYAN"
  local INSTALLED_HI="/usr/bin/hi"
  local NEW_HI="$HOME/.hi.d/hi.sh"

  chmod +x "$NEW_HI"

  if diff --color=always -w -u "$NEW_HI" "$INSTALLED_HI" 2>/dev/null; then
    cecho "$INSTALLED_HI is same as $NEW_HI :)" "$GREEN"
    return 0
  else
    cecho "$INSTALLED_HI out of date, updating..." "$YELLOW"
    cecho "Removing old $INSTALLED_HI... [password required]" "$BLUE"
    sudo rm "$INSTALLED_HI"
    cecho "Linking $INSTALLED_HI to latest hi.sh... [password required]" "$BLUE"
    sudo ln "$NEW_HI" "$INSTALLED_HI"
  fi
}

function main() {
  config_bashrc
  config_zshrc
  config_fish
  config_hi
  cecho "Generating colors for users and hosts" "$CYAN"
  # shellcheck source=./create_host_colors.sh
  source "$_HI_CREATE_COLORS"  rm -rf "$install_tmpdir"
  cecho "Done!" "$GREEN"
}

main
