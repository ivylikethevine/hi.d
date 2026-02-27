#!/bin/bash

PACKAGES=(
  top:0,btop:2,htop:2
  openssl:2
  git:2
  vi:0,vim:1,nvim:2
  cat:1,bat:2
  man:1,tldr:2
  tar:0,zip:2
  bc:1
  jq:1,yq:1
  gpg:0
  sudo:0
  ping:0
) # 12

BASICS=(
  nmap:2
  just:2
  hi:2
  screen:1,tmux:2
  nano:1,pico:1,micro:1
  emacs:1
  scp:1,rsync:1
  python:1
  ssh-audit:1
  sshpass:1
  sponge:0
  netstat:0
  neofetch:0
) # 13

TOOLS=(
  node:1,npx:2,npm:2
  nomad:2
  asdf:2
  rust:1,rustc:1,rustup:2
  cmake:2,make:1
  sshm:1,sshrc:2
  cloc:1
  cosign:1
  shellcheck:1
  systemctl:1
  curl:0
  wget:0
) # 12

SYSTEMS=(
  snap:2
  apk:2,nix:2
  apt:1,pacman:1,dnf:1,rpm:1,zypper:1,brew:1
  paru:1,yay:1
  dpkg:1,wpkg:1
  chocolatey:1,choco:1
  pkgconf:1
  appimage:1
  fusermount:1
  flatpak:1
  docker:0
  direnv:0
) # 12

command_exists() {
  command -v "$1" &>/dev/null
}

# Sort commands by existence and priority
sort_commands() {
  local cmd_list=("$@")
  local installed=()
  local not_installed=()
  local priority_zero_installed=()
  local priority_zero_not_installed=()

  for item in "${cmd_list[@]}"; do
    # Handle multiple pairs in one entry (comma-separated)
    IFS=',' read -ra pairs <<< "$item"
    local highest_priority_cmd=""
    local highest_priority=0
    local found_installed=false

    # Find the highest priority installed command
    for pair in "${pairs[@]}"; do
      cmd="${pair%:*}"
      priority="${pair#*:}"

      if command_exists "$cmd"; then
        if [[ "$priority" -gt "$highest_priority" ]] || [[ "$highest_priority" -eq 0 ]]; then
          highest_priority=$priority
          highest_priority_cmd=$cmd
          found_installed=true
        fi
      fi
    done

    # If we found an installed command, add it to installed list
    if [[ "$found_installed" == true ]]; then
      if [[ "$highest_priority" -eq 0 ]]; then
        # Add to priority_zero_installed list if priority is 0
        priority_zero_installed+=("$highest_priority_cmd:$highest_priority:installed")
      else
        installed+=("$highest_priority_cmd:$highest_priority:installed")
      fi
    else
      # If no installed command found, add the first one in the list
      first_cmd="${pairs[0]%:*}"
      first_priority="${pairs[0]#*:}"
      if [[ "$first_priority" -eq 0 ]]; then
        # Add to priority_zero_not_installed list if priority is 0
        priority_zero_not_installed+=("$first_cmd:$first_priority:not_installed")
      else
        not_installed+=("$first_cmd:$first_priority:not_installed")
      fi
    fi
  done

  # Combine lists with priority 0 commands first (both installed and not installed),
  # then installed commands, then not installed commands
  local sorted=("${priority_zero_installed[@]}" "${priority_zero_not_installed[@]}" "${installed[@]}" "${not_installed[@]}")
  printf '%s\n' "${sorted[@]}"
}

check_commands() {
  local cmd_list=("$@")
  echo -ne " $NC|"

  local sorted_cmd_list=($(sort_commands "${cmd_list[@]}"))

  for item in "${sorted_cmd_list[@]}"; do
    cmd="${item%:*:*}"
    inner="${item#*:}"
    priority="${inner%:*}"
    status="${item##*:}"
    if [[ "$status" == "installed" ]]; then
      if [[ "$priority" == "1" ]]; then
        echo -ne " $BLUE$cmd ✓$NC"
      elif [[ "$priority" == "2" ]]; then
        echo -ne " $GREEN$cmd ✓$NC"
      fi
    else
      if [[ "$priority" == "0" ]]; then
        echo -ne " $YELLOW$cmd ✗$NC"
      elif [[ "$priority" == "2" ]]; then
        echo -ne " $BRYELLOW$cmd ✗$NC"
      fi
    fi
  done
  echo
}

packages() {
  check_commands "${PACKAGES[@]}"
}

basics() {
  check_commands "${BASICS[@]}"
}

systems() {
  check_commands "${SYSTEMS[@]}"
}

tools() {
  check_commands "${TOOLS[@]}"
}

header() {
  local full="$1"
  if [[ "$full" -eq 1 ]]; then
    packages
    basics
    systems
    tools
  else
    systems
    tools
  fi
}
