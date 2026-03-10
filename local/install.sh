#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if ! command cecho 2>/dev/null; then
  # shellcheck source=./../common/prompt_colors.sh
  source "$SCRIPT_DIR/../common/prompt_colors.sh"
fi

_tmp=$(mktemp -d)

function append() {
  local input="$1"
  local output="$2"
  if ! test -f "$input"; then
    touch "$input"
  fi
  cat "$input" | grep -vxF -f "$output" > "$_tmp/append.tmp"
  cat "$output" >> "$_tmp/append.tmp"
  mv "$_tmp/append.tmp" "$2"
}

function bashrc() {
  cecho "Checking bashrc ========" "$CYAN"
  cat <<'EOF' >> "$_tmp/bashrc"
# If not running interactively, exit   # added by hi during install
[[ $- != *i* ]] && return              # added by hi during install
source ~/.hi.d/shells/bash.sh          # added by hi during install
EOF
  append "$_tmp"/bashrc ~/.bashrc
  cecho "local bashrc up to date :)" "$GREEN"
}

function zshrc() {
  cecho "Checking zshrc ========" "$CYAN"
  cat <<'EOF' >> "$_tmp/zshrc"
source ~/.hi.d/shells/zsh.zsh          # added by hi during install
EOF
  append "$_tmp"/zshrc ~/.zshrc
  cecho "local zshrc up to date :)" "$GREEN"
}

function config_fish() {
  cecho "Checking config.fish ========" "$CYAN"
  cat <<'EOF' >> "$_tmp/config.fish"
if status is-interactive               # added by hi during install
  source ~/.hi.d/shells/config.fish    # added by hi during install
end                                    # added by hi during install
EOF
  append "$_tmp"/config.fish ~/.config/fish/config.fish
  cecho "local config.fish up to date :)" "$GREEN"
}

function config_hi() {
  cecho "Checking hi.sh ========" "$CYAN"
  chmod +x ~/.hi.d/hi.sh

  if diff --color=always -w -u ~/.hi.d/hi.sh /usr/bin/hi 2>/dev/null; then
    cecho "/usr/bin/hi is same as ~/.hi.d/hi.sh :)" "$GREEN"
    return 0
  else
    cecho "/usr/bin/hi out of date, updating..." "$YELLOW"
    cecho "Removing old /usr/bin/hi... [password required]" "$BLUE"
    sudo rm /usr/bin/hi
    cecho "Linking /usr/bin/hi to latest hi.sh... [password required]" "$BLUE"
    sudo ln ~/.hi.d/hi.sh /usr/bin/hi
  fi
}

function generate_colors() {
  cecho "Generating colors for users and hosts" "$CYAN"
  sh /home/"$USER"/.hi.d/local/create_host_colors.sh
}

function main() {
  bashrc
  zshrc
  config_fish
  config_hi
  generate_colors
  rm -rf "$_tmp"
  cecho "Done!" "$GREEN"
}

main
