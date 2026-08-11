#!/bin/bash
# colors + the handful of primitives every hi script needs (_hi_cecho, timing,
# hostname). Loaded through common/bootstrap.sh.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# shellcheck source=./paths.sh
source "${_HI_HOME:-$HOME}/hi.d/common/paths.sh"

# color names match fish's set_color vocabulary; greys are skipped, since fish has none.
_HI_COLOR_NAMES=(red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan)

# export _HI_MAX_WIDTH=120

export NC='\e[0m'
export RED='\e[0;31m'
export GREEN='\e[0;32m'
export YELLOW='\e[0;33m'
export BLUE='\e[0;34m'
export PURPLE='\e[0;35m'
export CYAN='\e[0;36m'
export BRRED='\e[1;31m'
export BRGREEN='\e[1;32m'
export BRYELLOW='\e[1;33m'
export BRBLUE='\e[1;34m'
export BRPURPLE='\e[1;35m'
export BRCYAN='\e[1;36m'

# _hi_cecho <text> [color] [no_newline]
function _hi_cecho() {
  local out="${2:-}${1:-}$NC"
  [ $# -ge 3 ] && printf '%b' "$out" || printf '%b\n' "$out"
}

# "= label =", filled with "=" out to _HI_MAX_WIDTH and centered, matching
# banner()'s full-width tilde style in common/header.sh
function _hi_h1() {
  local label=" $1 " width=$((${_HI_MAX_WIDTH:-80} - 1)) total left right
  total=$((width - ${#label}))
  ((total < 0)) && total=0
  left=$((total / 2))
  right=$((total - left))
  _hi_cecho " $(printf '%*s' "$left" '' | tr ' ' '=')$label$(printf '%*s' "$right" '' | tr ' ' '=')" "$BRGREEN"
}

function _hi_h2() {
  _hi_cecho " ======= $1 ========" "$BRBLUE"
}

function _hi_h3() {
  _hi_cecho " ===== $1 =====" "$BRCYAN"
}

# high-res-ish timestamp that falls back to whole seconds on bash <5
function _hi_now() {
  printf '%s' "${EPOCHREALTIME:-$(date +%s)}"
}

function _hi_elapsed() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'
}

# du -sh on $_HI_ROOT with the size column pulled out; "$@" are any extra du
# args (e.g. hi.sh's --exclude list, applied before the copy happens).
# --apparent-size is a GNU-only flag, probed lazily (and cached) on first use
# so plain local shell startups that never call this pay nothing for it.
function _hi_du_size() {
  if [ -z "${_HI_LINUX_FLAGS+x}" ]; then
    _HI_LINUX_FLAGS=""
    du --version 2>/dev/null | grep -q "GNU coreutils" && _HI_LINUX_FLAGS="--apparent-size"
  fi
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  du -sh "$@" $_HI_LINUX_FLAGS "$_HI_ROOT" | awk '{ print $1 }'
}

function _hi_hostname() {
  hostname 2>/dev/null || uname -n
}

# lesspipe (colorized paging for less) plus the debian_chroot prompt label -
# identical bash/zsh interactive-shell setup, shared between shells/bash.sh
# and shells/zsh.zsh. Sets $debian_chroot in the caller's scope.
function _hi_interactive_extras() {
  [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
  # shellcheck disable=SC2034 # read by shells/bash.sh and shells/zsh.zsh's PS1
  [ -r /etc/debian_chroot ] && debian_chroot="($(</etc/debian_chroot)) "
}

function _hi_sanitize() {
  local out="${1//[[:cntrl:]]/}"
  printf '%s' "${out//\\/}"
}

# zsh's `trap ... EXIT` doesn't fire the way bash's does; it has TRAPEXIT instead
function _hi_on_exit() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "TRAPEXIT() { $1; }"
  else
    # shellcheck disable=SC2064 # $1 is the command we want stored, expanded now
    trap "$1" EXIT
  fi
}

# the "@" between user and host is yellow when the session came in over ssh
function _hi_at_color() {
  [ -n "${SSH_TTY:-}" ] && printf '%b' "$YELLOW" || printf '%b' "$NC"
}

# the ANSI escape for a palette name (see _HI_COLOR_NAMES); unknown names reset
function _hi_color_escape() {
  local i=0 name
  for name in "${_HI_COLOR_NAMES[@]}"; do
    [ "$name" = "$1" ] && {
      printf '\e[%d;3%dm' "$((i / 6))" "$((i % 6 + 1))"
      return
    }
    i=$((i + 1))
  done
  printf '%b' "$NC"
}

# deterministic name -> palette bucket, so the same host/username always gets
# the same color without any generated/cached state to go stale or go missing
function _hi_hash_color() {
  local name="$1" sum=0 i ord
  for ((i = 0; i < ${#name}; i++)); do
    printf -v ord '%d' "'${name:i:1}"
    sum=$((sum + ord))
  done
  printf '%s\n' "${_HI_COLOR_NAMES[sum % ${#_HI_COLOR_NAMES[@]}]}"
}

# the user/host of the machine hi.d is installed on - i.e. where you started
# from, not whatever you've since ssh'd into. hi.sh ships these ahead as
# _HI_LOCAL_USER/_HI_LOCAL_HOSTNAME (see hi.sh's _hi_remote_preamble) so a
# freshly-shipped remote copy of hi.d still knows the origin's identity
# instead of just seeing its own; a plain local shell has neither set, so
# these fall back to the current user/host, i.e. themselves.
function _hi_local_username() { printf '%s\n' "${_HI_LOCAL_USER:-$(whoami)}"; }
function _hi_local_hostname() { printf '%s\n' "${_HI_LOCAL_HOSTNAME:-$(_hi_hostname)}"; }

# look up an exact "<type>,<name>,<color>" override
# most names won't have an override and will return 1.
# exact matches always win; only once none exist does a "username,LOCALUSER,…"
# or "hostname,LOCALHOSTNAME,…" line get a shot, and only when $2 is the local
# machine's own user/host (see _hi_local_username/_hi_local_hostname above) -
# e.g. LOCALUSER lets "the same username as home" get colored consistently
# across every machine you ssh into, without hardcoding that username.
function _hi_override_color() {
  local cur_type cur_name color special=""
  [[ -f "$_HI_COLORS" ]] || return 1
  while IFS=',' read -r cur_type cur_name color; do
    if [[ "$cur_type" = "$1" && "$cur_name" = "$2" ]]; then
      printf '%s\n' "$color"
      return 0
    fi
  done <"$_HI_COLORS"

  case "$1" in
  username) [[ "$2" = "$(_hi_local_username)" ]] && special="LOCALUSER" ;;
  hostname) [[ "$2" = "$(_hi_local_hostname)" ]] && special="LOCALHOSTNAME" ;;
  esac
  [[ -n "$special" ]] || return 1

  while IFS=',' read -r cur_type cur_name color; do
    if [[ "$cur_type" = "$1" && "$cur_name" = "$special" ]]; then
      printf '%s\n' "$color"
      return 0
    fi
  done <"$_HI_COLORS"
  return 1
}

# grab the "# Tags: a, b" comment sitting directly above
# a "Host <alias>" line in ~/.ssh/config. an unknown host will return 1
function _hi_ssh_host_tag() {
  local line tag=""
  [[ -f "$_HI_SSH_CONFIG" ]] || return 1
  while IFS=$' ' read -r line; do
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*[Tt]ags[:=][[:space:]]*(.+)$ ]]; then
      tag=${BASH_REMATCH[1]%%[,[:space:]]*}
    elif [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+([^#]+) ]]; then
      local alias
      for alias in ${BASH_REMATCH[1]}; do
        [[ "$alias" = "$1" ]] || continue
        [[ -n "$tag" ]] && printf '%s\n' "$tag" && return 0
        return 1
      done
      tag=""
    elif [[ -n "$line" ]]; then
      tag=""
    fi
  done <"$_HI_SSH_CONFIG"
  return 1
}

function _hi_ssh_tag_color() {
  local tag
  tag=$(_hi_ssh_host_tag "$1") && _hi_override_color hosttag "$tag" && return
  return 1
}

# type is "hostname" or "username"; tag is only meaningful for "username" -
# it's the hosttag of whatever host the user is currently on (see
# _HI_TARGET_TAG below), letting a "usertag,<tag>,<color>" entry color every
# user on a tagged host, unless that user also has its own exact override
function _hi_resolve_color() {
  local type="$1" name="$2" tag="${3:-}"
  _hi_override_color "$type" "$name" && return
  case "$type" in
  hostname) _hi_ssh_tag_color "$name" && return ;;
  username) [[ -n "$tag" ]] && _hi_override_color usertag "$tag" && return ;;
  esac
  _hi_hash_color "$name"
}

# *_color -> a palette name (fish set_color / zsh %F{} vocabulary)
# *_escape -> the same color as a raw ANSI escape, for bash prompts & printf
# hi.sh pre-resolves this over ssh (using the alias connected with, plus the
# *local* misc/colors and ~/.ssh/config Tags - the only place both are
# available) and ships the result as _HI_TARGET_COLOR, so this matches what
# hi_colors previews instead of re-deriving from the target's own `hostname`
# output against its own (usually unrelated) ssh config
function _hi_host_color() { printf '%s\n' "${_HI_TARGET_COLOR:-$(_hi_resolve_color hostname "$(_hi_hostname)")}"; }
# _HI_TARGET_TAG is the connected-to host's tag, pre-resolved locally the same
# way as _HI_TARGET_COLOR; unset on a plain local shell, since there's no
# ssh alias/Tags comment for the machine you're already sitting at
function _hi_user_color() { _hi_resolve_color username "$(whoami)" "${_HI_TARGET_TAG:-}"; }
function _hi_host_escape() { _hi_color_escape "$(_hi_host_color)"; }
function _hi_user_escape() { _hi_color_escape "$(_hi_user_color)"; }

set +euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)
