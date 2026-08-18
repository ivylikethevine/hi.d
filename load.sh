#!/bin/bash
# The target half (forked from sshrc): header, rc grafts, shell handoff, undo.

# `bash --rcfile` skips the startup chain; restore it before strict mode
# (profile scripts aren't -e/-u safe), at source time ($CMDARG needs PATH too).
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

# only hi's remote paths chainload this file - it is how common/paths.sh
# tells "reached via hi" from "the machine hi.d lives on"
export _HI_REMOTE_SESSION=1

# shellcheck source=./common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=./common/header.sh
source "$_HI_HEADER"

_HI_CONFIG_START="# hi-config-start"
_HI_CONFIG_END="# hi-config-end"

# rc file <- hi config; fish/nu only when installed (no config dir otherwise).
# The pairs come from core.sh's _HI_SHELL_TABLE, filtered to the rows flagged
# `graft` - the same roster scripts/install.sh reads for its local half
_HI_CONFIGS=()
while IFS='|' read -r _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags; do
  _HI_CONFIGS+=("$_hi_tree_rc:$_hi_home_rc")
done < <(_hi_shell_rows graft)
unset _hi_shell _hi_label _hi_tree_rc _hi_home_rc _hi_check _hi_flags

function configure_files() {
  local pair target src open body
  # nu makes its config dir on first run, not install - so a fresh nu would dodge the loop's dir gate
  command -v nu >/dev/null 2>&1 && mkdir -p "$_HI_HOME_NU_DIR"
  for pair in "${_HI_CONFIGS[@]}"; do
    target="${pair#*:}"
    src="${pair%:*}"
    [ -d "${target%/*}" ] || continue # targets are absolute; no dirname fork
    touch "$target"
    grep -q "$_HI_CONFIG_START" "$target" && continue
    # GLOSSARY: graft crash guard - why every graft wraps, and nu's exception
    # shellcheck disable=SC2016 # single quotes are the point: the guard expands at shell start, not graft time
    case "$src" in
    *.fish)
      open='set -l _hi_tree $HOME'$'\n''test -n "$_HI_HOME"; and set _hi_tree $_HI_HOME'$'\n''if test -f $_hi_tree/hi.d/common/core.sh'
      body="$open"$'\n'"$(<"$src")"$'\n'"end"
      ;;
    *.nu) body="$(<"$src")" ;;
    *)
      open='if [ -f "${_HI_HOME:-$HOME}/hi.d/common/core.sh" ]; then'
      body="$open"$'\n'"$(<"$src")"$'\n'"fi"
      ;;
    esac
    printf '%s\n' "$_HI_CONFIG_START"$'\n'"$body"$'\n'"$_HI_CONFIG_END" >>"$target"
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

function _hi_login_shell() {
  local shell="${SHELL:-}" user
  if [ -z "$shell" ]; then
    user="$(_hi_whoami)" # memoized in core.sh; this path forked `id` twice
    shell="$(getent passwd "$user" 2>/dev/null | awk -F: '{ print $NF }')"
    [ -n "$shell" ] || shell="$(awk -F: -v u="$user" '$1 == u { print $NF }' /etc/passwd 2>/dev/null)"
  fi
  printf '%s' "${shell##*/}"
}

# GLOSSARY: session-shell ranking - login-first, and nu's allow-list-only seat
function _hi_session_shell() {
  local want
  for want in ${_HI_SHELL_PREFERENCE:-login fish zsh bash} fish zsh bash; do
    [ "$want" = login ] && want="$(_hi_login_shell)"
    case "$want" in
    bash | zsh | fish | nu) command -v "$want" >/dev/null 2>&1 && {
      printf '%s' "$want"
      return 0
    } ;;
    esac
  done
  printf 'bash'
}

# True when this session should run inside a named tmux (`hi --tmux` /
# _HI_TMUX_ATTACH=1). Both refusals print and carry on: a disposable tree
# would outlive a detached tmux, and the client can't know if tmux exists.
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

  local shell greeting color
  shell="$(_hi_session_shell)"
  case "$shell" in
  fish) greeting="fish shell! :^)" color="$GREEN" ;;
  zsh) greeting="zsh shell! :)" color="$PURPLE" ;;
  nu) greeting="nushell! :o)" color="$BRCYAN" ;;
  *) greeting="only bash today :(" color="$RED" ;;
  esac
  _hi_cecho "$greeting" "$color" 1
  _hi_cecho " | load: $(_hi_elapsed "$start" "$(_hi_now)")s | copy: ${_HI_COPY_TIME:--1}s"

  # keep the session's own status
  local shell_ec=0
  local -a shell_cmd=("$shell" -i)
  # the header above is our greeting
  [ "$shell" = fish ] && shell_cmd=(fish -C "set fish_greeting ''" -i)
  if _hi_tmux_wanted; then
    # -A: attach-or-create, the answer that never loses work; separate args so
    # fish's -C survives unquoted. GLOSSARY: tmux server-start rules
    tmux -f "$_HI_TMUXCONF" new-session -A -s "${_HI_TMUX_SESSION:-hi}" \
      "${shell_cmd[@]}" || shell_ec=$?
  else
    "${shell_cmd[@]}" || shell_ec=$?
  fi

  local size
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
