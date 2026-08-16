#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# Runs on the target: prints the header, grafts hi's shell configs onto the
# host's rc files, hands over to the best shell available, then undoes it all.

# `bash --rcfile` skips the startup chain, so restore it - before the strict
# mode below (profile scripts aren't -e/-u safe), and at source time, since
# the $CMDARG bootloader shape replaces load() but still wants the real PATH.
function _hi_restore_profile() {
  if [ -r /etc/profile ]; then source /etc/profile; fi
  # shellcheck disable=SC1090 # target-specific files, no fixed location
  if [ -r ~/.bash_profile ]; then
    source ~/.bash_profile
  elif [ -r ~/.bash_login ]; then
    source ~/.bash_login
  elif [ -r ~/.profile ]; then
    source ~/.profile
  fi
  export PATH="$PATH:$_HI_ROOT"
}

# _HI_LOAD_NO_INIT=1: functions only, no profile chain - install.sh's source
# guard as an env var, since this file is only ever sourced
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
    [ -d "${target%/*}" ] || continue # targets are absolute; no dirname fork
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

# True when this session should run inside a named tmux (`hi --tmux`, or
# _HI_TMUX_ATTACH=1), so a dropped connection detaches instead of losing the
# work. Both refusals print and carry on rather than dropping the connection: a
# disposable tree ($_HI_CLEANUP) is deleted when the session ends and a detached
# tmux would outlive it - the same test shells/aliases.sh makes - and whether
# there is a tmux here at all is not something the client can know.
function _hi_tmux_wanted() {
  [ "${_HI_TMUX_ATTACH:-0}" = 1 ] || return 1
  if [ -n "${_HI_CLEANUP:-}" ]; then
    _hi_cecho " --tmux needs a permanent hi.d here (scripts/install.sh) - this tree is disposable, so a detached session would outlive it. Continuing without tmux." "$YELLOW"
    return 1
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    _hi_cecho " --tmux asked for, but there is no tmux on this host. Continuing without it." "$YELLOW"
    return 1
  fi
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
  local -a shell_cmd=("$shell" -i)
  # the header above is our greeting
  [ "$shell" = fish ] && shell_cmd=(fish -C "set fish_greeting ''" -i)
  if _hi_tmux_wanted; then
    # -A: attach if the session exists, create it if not - the one answer that
    # never loses work. The command goes as separate arguments so fish's -C
    # survives unquoted; tmux ignores it when attaching. -f is read only when
    # the server starts (see misc/tmux.conf).
    tmux -f "$_HI_TMUXCONF" new-session -A -s "${_HI_TMUX_SESSION:-hi}" \
      "${shell_cmd[@]}" || shell_ec=$?
  else
    "${shell_cmd[@]}" || shell_ec=$?
  fi

  local size
  # the whole unpacked tree, unlike hi.sh's _hi_size (client tree has extras)
  size="$(_hi_du_size "$_HI_ROOT")"
  _hi_cecho " $size" "$NC" 1
  if [[ "${_HI_DISABLE_HEADER:-0}" != 1 ]]; then
    banner Disconnected "$BRRED" " $size"
    [[ "${_HI_HEADER_TIMESTAMP:-1}" == 0 ]] || timestamp
  fi
  _hi_cecho " | " "$NC" 1
  _hi_cecho "hi closing! " "$BRPURPLE"
  exit "$shell_ec"
}
