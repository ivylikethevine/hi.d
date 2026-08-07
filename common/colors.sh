#!/bin/bash
# colors + the handful of primitives every hi script needs (cecho, timing,
# hostname). Loaded through common/bootstrap.sh.
set -eou pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# shellcheck source=./paths.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/paths.sh"

# color names match fish's set_color vocabulary; greys are skipped, since fish has none.
_HI_COLOR_NAMES=(red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan)
export _HI_MAX_WIDTH=80

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

# --apparent-size is a GNU-only flag
_HI_LINUX_FLAGS=""
du --version 2>/dev/null | grep -q "GNU coreutils" && _HI_LINUX_FLAGS="--apparent-size"
export _HI_LINUX_FLAGS

# high-res-ish timestamp that falls back to whole seconds on bash <5
function _hi_now() {
  printf '%s' "${EPOCHREALTIME:-$(date +%s)}"
}

function _hi_elapsed() {
  echo "$1 $2" | awk '{ printf "%.3f", $2 - $1 }'
}

function _hi_hostname() {
  hostname 2>/dev/null || uname -n
}

function _hi_sanitize() {
  # shellcheck disable=SC1003
  printf '%s' "$1" | tr -d '[:cntrl:]\\'
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

# cecho <text> [color] [no_newline]
function cecho() {
  local out="${2:-}${1:-}$NC"
  [ $# -ge 3 ] && printf '%b' "$out" || printf '%b\n' "$out"
}

# the "@" between user and host is yellow when the session came in over ssh
function at_color() {
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

# look up an exact "<type>,<name>,<color>" override
# most names won't have an override and will return 1.
function _hi_override_color() {
  local cur_type cur_name color
  [[ -f "$_HI_COLOR_OVERRIDES" ]] || return 1
  while IFS=',' read -r cur_type cur_name color; do
    if [[ "$cur_type" = "$1" && "$cur_name" = "$2" ]]; then
      printf '%s\n' "$color"
      return 0
    fi
  done <"$_HI_COLOR_OVERRIDES"
  return 1
}

# grab the "# Tags: a, b" comment sitting directly above
# a "Host <alias>" line in ~/.ssh/config. an unknown host will return 1
function _hi_ssh_tag_color() {
  local line tag=""
  [[ -f "$_HI_SSH_CONFIG" ]] || return 1
  while IFS=$' ' read -r line; do
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*[Tt]ags[:=][[:space:]]*(.+)$ ]]; then
      tag=${BASH_REMATCH[1]%%[,[:space:]]*}
    elif [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+([^#]+) ]]; then
      local alias
      for alias in ${BASH_REMATCH[1]}; do
        [[ "$alias" = "$1" ]] || continue
        [[ -n "$tag" ]] && _hi_override_color hosttag "$tag" && return 0
        return 1
      done
      tag=""
    elif [[ -n "$line" ]]; then
      tag=""
    fi
  done <"$_HI_SSH_CONFIG"
  return 1
}

function _hi_resolve_color() {
  _hi_override_color "$1" "$2" && return
  [[ "$1" = hostname ]] && _hi_ssh_tag_color "$2" && return
  _hi_hash_color "$2"
}

# *_color -> a palette name (fish set_color / zsh %F{} vocabulary)
# *_escape -> the same color as a raw ANSI escape, for bash prompts & printf
function host_color() { _hi_resolve_color hostname "$(_hi_hostname)"; }
function user_color() { _hi_resolve_color username "$(whoami)"; }
function host_escape() { _hi_color_escape "$(host_color)"; }
function user_escape() { _hi_color_escape "$(user_color)"; }

# preview what every ssh host & the current user resolve to, rendered in that
# actual color - handy when tuning data/color_overrides. Run via `hi_colors`.
function list_colors() {
  local name color
  cecho "~~~~~ hi.sh color preview ~~~~~" "$BRGREEN"

  cecho "=== user ===" "$YELLOW"
  color=$(user_color)
  cecho "$(whoami)  ->  $color" "$(_hi_color_escape "$color")"

  cecho "=== ssh hosts ===" "$YELLOW"
  if [[ ! -f "$_HI_SSH_CONFIG" ]]; then
    cecho "No ssh config found at $_HI_SSH_CONFIG" "$RED"
    return
  fi
  while IFS=$'\t' read -r name _; do
    color=$(_hi_resolve_color hostname "$name")
    cecho "$name  ->  $color" "$(_hi_color_escape "$color")"
  done < <(sh "$_HI_TARGETS" ssh)
}

set +eou pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)
