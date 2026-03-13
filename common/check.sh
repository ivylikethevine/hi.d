#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./prompt_colors.sh
command -v cecho >/dev/null || source "$_HI_PROMPT_COLORS_PATH"

# Format - package:priority,similar_package:priority
# priority | installed | hidden | color
#    0     |    yes    |   X    |
#    0     |    no     |        | yellow
#    1     |    yes    |        | blue
#    1     |    no     |   X    |
#    2     |    yes    |        | green
#    2     |    no     |        | bright yellow
# highest priority on left

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
  local result=()

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
      result+=("$max_priority_cmd:$max_priority:yes")
    else
      first_cmd="${pairs[0]%:*}"
      first_priority="${pairs[0]#*:}"
      result+=("$first_cmd:$first_priority:no")
    fi
  done

  # Sort by priority (0=low, 1=medium, 2=high)
  printf '%s\n' "${result[@]}" | sort -t':' -k2,2n -k3,3r
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

    case "$priority:$is_installed" in
      "0:yes")
        # Print nothing for priority 0 when installed
        ;;
      "0:no")
        cecho " $cmd ✗" "$YELLOW" 1
        ;;
      "1:yes")
        cecho " $cmd ✓" "$BLUE" 1
        ;;
      "1:no")
        # Print nothing for priority 1 when not installed
        ;;
      "2:yes")
        cecho " $cmd ✓" "$GREEN" 1
        ;;
      "2:no")
        cecho " $cmd ✗" "$BRYELLOW" 1
        ;;
    esac
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
