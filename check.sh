#!/bin/bash
# # [0] -> display only if missing (yellow)
# # [1] -> display only if installed (blue)
# # [2] -> display for either of above (purple/green)

# TODO: Priority grouping

PACKAGES=(
  vim:2
  docker:2

  vi:1
  node:1
  nomad:1
  rustup:1
  rust:1
  asdf:1
  direnv:1
  nmap:1
  just:1
)

BASICS=(
  nano:0
  emacs:0
  micro:0
  pico:0
  neovim:0
  rsync:0
  netstat:0
  avahi-daemon:0
  neofetch:0
  python:0
  sponge:0
  sudo:0
  curl:0
  wget:0
  ping:0
  tar:0
  zip:0
  gpg:0
  git:0
  htop:0
  openssl:0
  screen:0
  command:0
  cut:0
  find:0
)

TOOLS=(
  ssh-audit:1
  sshpass:1
  yq:1
  bc:1
  tmux:1
  bat:2

  cat:0
  tldr:0
  cloc:0
  sshm:0
  cosign:0
  shellcheck:0
  jq:0
)

SYSTEMS=(
  choco:2
  apt:2
  yay:2
  apk:2
  nix:2
  dpkg:2
  rpm:2
  dnf:2
  zypper:2
  pkgconf:2
  wpkg:2
  appimage:2
  fusermount:2
  brew:2
  flatpak:2
  snap:2
  make:2
  systemctl:2

  systemd:1

  pacman:1
  paru:1
  chocolatey:1
)

check_commands() {
  local cmd_list=("$@")
  echo -ne " $NC|"

  for item in "${cmd_list[@]}"; do
    cmd="${item%:*}"
    value="${item#*:}"

    if command -v "$cmd" &>/dev/null; then
      if [[ "$value" == "1" ]]; then
        echo -ne " $BLUE$cmd ✓$NC"
      elif [[ "$value" == "2" ]]; then
        echo -ne " $GREEN$cmd ✓$NC"
      fi
    else
      if [[ "$value" == "0" ]]; then
        echo -ne " $BRYELLOW$cmd ✗$NC"
      elif [[ "$value" == "2" ]]; then
        echo -ne " $BRPURPLE$cmd ✗$NC"
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
