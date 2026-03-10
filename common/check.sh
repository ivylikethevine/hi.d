#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if ! command cecho 2>/dev/null; then
  # shellcheck source=./prompt_colors.sh
  source "$SCRIPT_DIR/prompt_colors.sh"
fi

# # Format - package:priority,similar_package
# # Sort highest priorities to top of each list

# shellcheck disable=SC2054
PACKAGES=(
  top:0,btop:2,htop:2
  openssl:2
  git:2
  vi:0,vim:1,nvim:2,nano:2,pico:1,micro:1
  cat:1,bat:2
  man:1,tldr:2
  tar:0,zip:2
  bc:1
  jq:1,yq:1
  gpg:0
  sudo:0
)

# shellcheck disable=SC2054
BASICS=(
  nmap:2
  just:2
  screen:1,tmux:2
  emacs:1
  scp:1,rsync:1
  python:1
  ssh-audit:1
  sshpass:1
  sponge:0
  netstat:0
  ping:0
)

# shellcheck disable=SC2054
TOOLS=(
  node:1,npx:2,npm:2
  nomad:1
  asdf:2
  cmake:2,make:1
  sshm:1,sshrc:2,hi:2
  rust:1,rustc:1,rustup:2
  cosign:1
  shellcheck:1
  systemctl:0
  curl:0
  wget:0
)

# shellcheck disable=SC2054
SYSTEMS=(
  snap:1
  apt:1,pacman:1,dnf:1,rpm:1,zypper:1,brew:1,apk:2,nix:2
  paru:1,yay:1
  dpkg:1,wpkg:1
  chocolatey:1,choco:1
  pkgconf:1
  appimage:1
  fusermount:1
  flatpak:1
  docker:0
  direnv:0
)

function sort_commands() {
  local cmd_list=("$@")
  local present=()
  local absent=()
  local priority_zero_present=()
  local priority_zero_absent=()

  for item in "${cmd_list[@]}"; do
    IFS=',' read -ra pairs <<< "$item"
    local max_priority_cmd=""
    local max_priority=0
    local is_installed=false
    for pair in "${pairs[@]}"; do
      cmd="${pair%:*}"
      priority="${pair#*:}"
      if command -v "$cmd" &>/dev/null; then
        if [[ "$priority" -gt "$max_priority" ]] || [[ "$max_priority" -eq 0 ]]; then
          max_priority=$priority
          max_priority_cmd=$cmd
          is_installed=true
        fi
      fi
    done
    if [[ "$is_installed" == true ]]; then
      if [[ "$max_priority" -eq 0 ]]; then
        priority_zero_present+=("$max_priority_cmd:$max_priority:yes")
      else
        present+=("$max_priority_cmd:$max_priority:yes")
      fi
    else
      first_cmd="${pairs[0]%:*}"
      first_priority="${pairs[0]#*:}"
      if [[ "$first_priority" -eq 0 ]]; then
        priority_zero_absent+=("$first_cmd:$first_priority:no")
      else
        absent+=("$first_cmd:$first_priority:no")
      fi
    fi
  done
  local sorted=("${priority_zero_present[@]}" "${priority_zero_absent[@]}" "${present[@]}" "${absent[@]}")
  printf '%s\n' "${sorted[@]}"
}

function check_commands() {
  local cmd_list=("$@")
  echo -ne " $NC|"
  # shellcheck disable=SC2207
  local sorted_cmd_list=($(sort_commands "${cmd_list[@]}"))
  for item in "${sorted_cmd_list[@]}"; do
    cmd="${item%:*:*}"
    inner="${item#*:}"
    priority="${inner%:*}"
    is_installed="${item##*:}"
    if [[ "$priority" == "0" ]]; then
      if [[ "$is_installed" == "yes" ]]; then
        echo -ne ""
      else
        echo -ne " $YELLOW$cmd ✗$NC"
      fi
    elif [[ "$priority" == "1" ]]; then
      if [[ "$is_installed" == "yes" ]]; then
        echo -ne " $BLUE$cmd ✓$NC"
      else
        echo -ne ""
      fi
    elif [[ "$priority" == "2" ]]; then
      if [[ "$is_installed" == "yes" ]]; then
        echo -ne " $GREEN$cmd ✓$NC"
      else
        echo -ne " $BRYELLOW$cmd ✗$NC"
      fi
    fi
  done
  echo
}

function packages() {
  check_commands "${PACKAGES[@]}"
}

function basics() {
  check_commands "${BASICS[@]}"
}

function systems() {
  check_commands "${SYSTEMS[@]}"
}

function tools() {
  check_commands "${TOOLS[@]}"
}
