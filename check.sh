#!/bin/bash
# TODO: Better divide
# - system (pacman, apt, dnf, nix, etc)
# - commands
# - convenience (bat, tldr, sshm, etc.)
# - add-ons (docker, nomad, etc)
# - tools (jq, yq, zip, tar)

BASICS=(
  sudo
  curl
  wget
  ping
  tar
  zip
  gpg
  git
  htop
  bc
  openssl
  tmux
  screen
  command
  cut
  find
)

PACKAGES=(
  vi
  vim
  nano
  emacs
  micro
  pico
  neovim
  rsync
  netstat
  avahi-daemon
  neofetch
  docker
  python
  node
  nomad
  rustup
  asdf
  direnv
  nmap
  just
)

TOOLS=(
  tldr  # tool
  bat   # improved cat, tool
  cloc  # count lines of code, tool
  sshm  # tool
  sshrc # tool
  ssh-audit
  sshpass
  cosign
  shellcheck
  jq
  yq
)

SYSTEMS=(
  apt        # system
  pacman     # system
  apk        # system
  nix        # system
  dpkg       # system
  rpm        # system
  dnf        # system
  zypper     # tool?
  pkgconf    # tool?
  chocolatey # system
  choco      # system
  wpkg       # ?
  appimage   # ?
  fusermount # ? Surrogate for appimage
  brew       # system
  flatpak    # system
  snap       # system
  # yay # tool? superset of pacman
  # yum # tool? superset of pacman
  # paru # tool? superset of pacman
  make # Is this a system? Idk but it seems useful to know
  # cmake # Is this a system? Idk but it seems useful to know
  systemd   # system
  systemctl # system
)

installed() {
  # TODO: Display important names from groups of commands based on priority?
  for package in "${PACKAGES[@]}"; do
    if command -v "$package" &>/dev/null; then
      cecho_n "$package ✓ " "$GREEN"
    fi
  done
}

missing() {
  for package in "${PACKAGES[@]}"; do
    if ! command -v "$package" &>/dev/null; then
      cecho_n "$package ✗ " "$BRYELLOW"
    fi
  done
}

systems() {
  for system in "${SYSTEMS[@]}"; do
    if command -v "$system" &>/dev/null; then
      cecho_n "$system ✓ " "$BLUE"
    fi
  done
}

tools() {
  for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
      cecho_n "$tool ✓ " "$PURPLE"
    fi
  done
}

basics() {
  for basic in "${BASICS[@]}"; do
    if command -v "$basic" &>/dev/null; then
      cecho_n "$basic ✓ " "$CYAN"
    fi
  done
}
