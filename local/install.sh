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
# If not running interactively, exit   # added by hi during install
[[ $- != *i* ]] && return              # added by hi during install
source ~/.hi.d/shells/bash.sh          # added by hi during install
EOF
  append "$_tmp"/bashrc ~/.bashrc
}

function zshrc() {
  echo
  echo "Checking zshrc ========"
  cat <<'EOF' >> "$_tmp/zshrc"
source ~/.hi.d/shells/zsh.zsh          # added by hi during install
EOF
  append "$_tmp"/zshrc ~/.zshrc
}

function config_fish() {
  echo
  echo "Checking config.fish ========"
  cat <<'EOF' >> "$_tmp/config.fish"
if status is-interactive               # added by hi during install
  source ~/.hi.d/shells/config.fish    # added by hi during install
end                                    # added by hi during install
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
    echo "Removing old /usr/bin/hi... [password required]"
    sudo rm /usr/bin/hi
    echo "Linking /usr/bin/hi to latest hi.sh... [password required]"
    sudo ln ~/.hi.d/hi.sh /usr/bin/hi
  fi
}

function generate_colors() {
  echo "Generating colors for users and hosts"
  sh /home/"$USER"/.hi.d/local/create_host_colors.sh
}

function main() {
  bashrc
  zshrc
  config_fish
  config_hi
  generate_colors
  rm -rf "$_tmp"
  echo "Done!"
}

main
