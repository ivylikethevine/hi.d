#!/bin/bash

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
  echo
  echo "Checking bashrc ========"
  cat <<'EOF' >> "$_tmp/bashrc"
# hi-config-start
# If not running interactively, exit
[[ $- != *i* ]] && return
source ~/.hi.d/shells/bash.sh
# hi-config-end
EOF
  append "$_tmp"/bashrc ~/.bashrc
}

function zshrc() {
  echo
  echo "Checking zshrc ========"
  cat <<'EOF' >> "$_tmp/zshrc"
# hi-config-start
source ~/.hi.d/shells/zsh.zsh
# hi-config-end
EOF
  append "$_tmp"/zshrc ~/.zshrc
}

function config_fish() {
  echo
  echo "Checking config.fish ========"
  cat <<'EOF' >> "$_tmp/config.fish"
# hi-config-start
if status is-interactive
  source ~/.hi.d/shells/config.fish
end
# hi-config-end
EOF
  append "$_tmp"/config.fish ~/.config/fish/config.fish
}

function config_hi() {
  echo
  echo "Checking hi.sh ========"
  chmod +x ~/.hi.d/hi.sh

  if diff --color=always -w -u ~/.hi.d/hi.sh /usr/bin/hi 2>/dev/null; then
    echo "/usr/bin/hi is same as ~/.hi.d/hi.sh :)"
    return 0
  else
    echo "/usr/bin/hi out of date, updating..."
    sudo rm /usr/bin/hi
    sudo ln ~/.hi.d/hi.sh /usr/bin/hi
  fi
}

function main() {
  bashrc
  zshrc
  config_fish
  config_hi
  rm -rf "$_tmp"
  echo "Done!"
}

main
