#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# Runs on the target: prints the header, grafts hi's shell configs onto the
# host's rc files, hands over to the best shell available, then undoes it all.

# `bash --rcfile` (how hi.sh hands off) skips the normal startup file chain, so
# restore it here - before `set -euo pipefail` below, since arbitrary profile
# scripts on the target aren't guaranteed safe under -e/-u. At source time
# rather than from load(), because the bootloader's other shape (hi.sh's
# $CMDARG) replaces load() and still wants the target's real PATH.
function _hi_restore_profile() {
  if [ -r /etc/profile ]; then source /etc/profile; fi
  # shellcheck disable=SC1090 # target-specific files, no fixed location
  if [ -r ~/.bash_profile ]; then source ~/.bash_profile
  elif [ -r ~/.bash_login ]; then source ~/.bash_login
  elif [ -r ~/.profile ]; then source ~/.profile
  fi
  export PATH="$PATH:$_HI_ROOT"
}

# _HI_LOAD_NO_INIT=1 sources this file for its functions alone, skipping the
# target's profile chain - the same hatch as scripts/install.sh's BASH_SOURCE
# guard, spelled as an env var because this file is only ever sourced, never
# executed.
[ "${_HI_LOAD_NO_INIT:-0}" = 1 ] || _hi_restore_profile

set -euo pipefail

# every remote/container/alloc path chainloads this file and the local
# install's own shells never do, so this is what lets common/paths.sh tell
# "reached via hi" from "the machine hi.d lives on".
export _HI_REMOTE_SESSION=1

# shellcheck source=./common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
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
    block="$_HI_CONFIG_START"$'\n'"$(<"${pair%:*}")"$'\n'"$_HI_CONFIG_END"
    printf '%s\n' "$block" >>"$target"
  done
}

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
  [ -n "${_HI_CLEANUP:-}" ] && rm -rf "$_HI_ROOT"
  return 0
}

function load() {
  local start
  start="$(_hi_now)"
  _hi_on_exit clean_all

  set +euo pipefail

  hi_header Connected "" "${_HI_CONNECT_PREFIX:-}"

  # vim only: setting VIMINIT when all we have is vi breaks it
  command -v vim &>/dev/null && export VIMINIT="let \$MYVIMRC='$_HI_VIMRC' | source \$MYVIMRC"
  configure_files
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi loaded with... " "$BRCYAN" 1

  local shell=bash greeting="only bash today :(" color="$RED"
  if command -v fish &>/dev/null; then
    shell=fish greeting="fish shell! :^)" color="$GREEN"
  elif command -v zsh &>/dev/null; then
    shell=zsh greeting="zsh shell! :)" color="$PURPLE"
  fi
  _hi_cecho "$greeting" "$color" 1
  _hi_cecho " | load: $(_hi_elapsed "$start" "$(_hi_now)")s | copy: ${_HI_COPY_TIME:--1}s"

  # keep the session's own status: `hi <target>` should report a shell that
  # exited non-zero rather than always claiming success
  local shell_ec=0
  if [ "$shell" = fish ]; then
    fish -C "set fish_greeting ''" -i || shell_ec=$? # the header above is our greeting
  else
    "$shell" -i || shell_ec=$?
  fi

  local size
  # no arguments on purpose: the whole shipped tree is measured here, unlike
  # hi.sh's _hi_size, which passes $_HI_EXCLUDE
  # shellcheck disable=SC2119
  size="$(_hi_du_size)"
  _hi_cecho " $size" "$NC" 1
  if [[ "${_HI_DISABLE_HEADER:-0}" != 1 ]]; then
    banner Disconnected "$BRRED" " $size"
    [[ "${_HI_HEADER_TIMESTAMP:-1}" == 0 ]] || timestamp
  fi
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi closing! " "$BRPURPLE"
  exit "$shell_ec"
}
