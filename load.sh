#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# Runs on the target: prints the header, grafts hi's shell configs onto the
# host's rc files, hands over to the best shell available, then undoes it all.
set -euo pipefail

# shellcheck source=./common/bootstrap.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./common/header.sh
source "$_HI_HEADER"

_HI_CONFIG_START="# hi-config-start"
_HI_CONFIG_END="# hi-config-end"

# rc file <- hi config, unless a previous session already added it. Fish only
# gets one if fish is installed (its config dir won't exist otherwise).
_HI_CONFIGS=("$_HI_BASHRC:$_HI_HOME_BASHRC" "$_HI_ZSHRC:$_HI_HOME_ZSHRC" "$_HI_FISH_CONFIG:$_HI_HOME_FISH_CONFIG")

function configure_files() {
  local pair target block
  for pair in "${_HI_CONFIGS[@]}"; do
    target="${pair#*:}"
    [ -d "$(dirname "$target")" ] || continue
    touch "$target"
    grep -q "$_HI_CONFIG_START" "$target" && continue
    block="$_HI_CONFIG_START"$'\n'"$(cat "${pair%:*}")"$'\n'"$_HI_CONFIG_END"
    printf '%s\n' "$block" >>"$target"
  done
}

# strip our block back out of every rc file, then remove hi.d itself
function clean_all() {
  local pair target pattern
  for pair in "${_HI_CONFIGS[@]}"; do
    target="${pair#*:}"
    [ -f "$target" ] || continue
    if grep -q "^$_HI_CONFIG_END" "$target"; then
      pattern="/^$_HI_CONFIG_START/,/^$_HI_CONFIG_END/d"
    else
      pattern="/^$_HI_CONFIG_START/d"
    fi
    # BSD/macOS sed needs an explicit (empty) suffix argument for -i
    if [ -f "$_HI_LINUX_RELEASE" ]; then
      sed -i "$pattern" -- "$target"
    else
      sed -i '' "$pattern" "$target"
    fi
  done
  rm -rfv "$_HI_ROOT"
}

function load() {
  local start
  start="$(_hi_now)"
  _hi_on_exit clean_all

  hi_header Connected "" "${_HI_CONNECT_PREFIX:-}"

  # vim only: setting VIMINIT when all we have is vi breaks it
  command -v vim &>/dev/null && export VIMINIT="let \$MYVIMRC='$_HI_VIMRC' | source \$MYVIMRC"
  configure_files
  cecho " | " "$NC" 1
  cecho "hi loaded with... " "$BRCYAN" 1

  # guard against strict mode leaking into the interactive shell we hand off to
  # (e.g. via an exported SHELLOPTS) - it would close the session on any error
  set +euo pipefail

  local shell=bash greeting="only bash today :(" color="$RED"
  if command -v fish &>/dev/null; then
    shell=fish greeting="fish shell! :^)" color="$GREEN"
  elif command -v zsh &>/dev/null; then
    shell=zsh greeting="zsh shell! :)" color="$PURPLE"
  fi
  cecho "$greeting" "$color" 1
  cecho " | load: $(_hi_elapsed "$start" "$(_hi_now)")s | copy: ${_HI_COPY_TIME:--1}s"

  if [ "$shell" = fish ]; then
    fish -C "set fish_greeting ''" -i # the header above is our greeting
  else
    "$shell" -i
  fi

  local size
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  size="$(du -sh $_HI_LINUX_FLAGS "$_HI_ROOT" | awk '{ print $1 }')"
  cecho " $size " "$NC" 1
  hi_banner Disconnected "$BRRED" " $size "
  timestamp
  cecho " hi closing! " "$BRPURPLE"
  exit 0
}
