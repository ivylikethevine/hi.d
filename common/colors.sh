#!/bin/bash
# set -eou pipefail # cannot be enabled (this script is part of the interactive shell - any error would cause the shell session to close)

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"

## Shell Color Mapping Chart
# Notes - greys are skipped, as they don't exist in fish
#       - sometimes yellow vs bright-yellow is yellow/orange...
#  number  |    bash    |      zsh       |     fish
# ---------------------------------------------------------
#   0      | '\e[0m'    | default/plain  | normal
#   1      | '\e[0;31m' | red            | red
#   2      | '\e[0;32m' | green          | green
#   3      | '\e[0;33m' | yellow*        | yellow*
#   4      | '\e[0;34m' | blue           | blue
#   5      | '\e[0;35m' | magenta        | magenta
#   6      | '\e[0;36m' | cyan           | cyan
#   7      | '\e[0;37m' | white          | white
#   8      | '\e[1;31m' | bright-red     | brred
#   9      | '\e[1;32m' | bright-green   | brgreen
#   10     | '\e[1;33m' | bright-yellow* | bryellow*
#   11     | '\e[1;34m' | bright-blue    | brblue
#   12     | '\e[1;35m' | bright-magenta | brmagenta
#   13     | '\e[1;36m' | bright-cyan    | brcyan
#   14     | '\e[1;37m' | bright-white   | brwhite

# required
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

# canonical color names usable in data/color_overrides and as the hash-derived
# palette for host_color/user_color; names match fish's set_color vocabulary
_HI_COLOR_NAMES=(red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan)
declare -A _HI_COLOR_ESCAPES=(
  [red]="$RED" [green]="$GREEN" [yellow]="$YELLOW" [blue]="$BLUE" [magenta]="$PURPLE" [cyan]="$CYAN"
  [brred]="$BRRED" [brgreen]="$BRGREEN" [bryellow]="$BRYELLOW" [brblue]="$BRBLUE" [brmagenta]="$BRPURPLE" [brcyan]="$BRCYAN"
)

# GNU coreutils' du supports --apparent-size; busybox/bsd du (Alpine, macOS,
# *BSD, etc.) don't support this GNU-only flag
_HI_LINUX_FLAGS=""
if du --version >/dev/null 2>&1 && du --version | grep -q "GNU coreutils"; then
  _HI_LINUX_FLAGS="--apparent-size"
fi
export _HI_LINUX_FLAGS

# high-res-ish timestamp without shelling out to perl (not guaranteed to exist
# on minimal/embedded targets); falls back to whole-second precision on bash <5
function _hi_now() {
  if [[ -n ${EPOCHREALTIME+x} ]]; then
    printf '%s' "$EPOCHREALTIME"
  else
    date +%s
  fi
}

# `hostname` isn't guaranteed to exist on minimal/container images; uname -n is
function _hi_hostname() {
  hostname 2>/dev/null || uname -n
}

function cecho() {
  local text=${1:-}
  local color=${2:-}

  local formatted_text="$color$text$NC"
  if [[ -z ${3+x} ]]; then
    printf '%b\n' "$formatted_text"
  else
    printf '%b' "$formatted_text"
  fi
}

function at_color() {
  if [[ -v SSH_TTY ]]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$NC"
  fi
}

# deterministic name -> color bucket, so the same host/username always gets
# the same color without any generated/cached state to go stale or go missing
function _hi_hash_color() {
  local name="$1" sum=0 i ord
  for ((i = 0; i < ${#name}; i++)); do
    printf -v ord '%d' "'${name:i:1}"
    sum=$((sum + ord))
  done
  printf '%s' "${_HI_COLOR_NAMES[sum % ${#_HI_COLOR_NAMES[@]}]}"
}

# look up an exact (type,name) pin from $_HI_COLOR_OVERRIDES, e.g.:
#   username,root,red
#   hostname,prod-db,yellow
#   hosttag,desktop,green
# missing file/no match is expected (most names are unpinned) - just returns 1
function _hi_override_color() {
  local type="$1" name="$2"
  [[ -f "$_HI_COLOR_OVERRIDES" ]] || return 1

  local cur_type cur_name color
  while IFS=',' read -r cur_type cur_name color; do
    [[ "$cur_type" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cur_type" ]] && continue
    if [[ "$cur_type" = "$type" && "$cur_name" = "$name" ]]; then
      printf '%s' "$color"
      return 0
    fi
  done <"$_HI_COLOR_OVERRIDES"
  return 1
}

# find the leftmost "# Tags: a, b" comment directly above a matching
# "Host <alias>" line in ~/.ssh/config, and resolve that tag as a hosttag
# override; missing ssh config/no tag/untagged host is expected, returns 1
function _hi_ssh_tag_color() {
  local host="$1"
  [[ -f "$_HI_SSH_CONFIG" ]] || return 1

  local line tag=""
  while IFS=$' ' read -r line; do
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*[Tt]ags[:=][[:space:]]*(.+)$ ]]; then
      tag=${BASH_REMATCH[1]%%[,[:space:]]*}
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+([^#]+) ]]; then
      local alias
      for alias in ${BASH_REMATCH[1]}; do
        if [[ "$alias" = "$host" ]]; then
          [[ -n "$tag" ]] && _hi_override_color hosttag "$tag" && return 0
          return 1
        fi
      done
      tag=""
    elif [[ -n "$line" ]]; then
      tag=""
    fi
  done <"$_HI_SSH_CONFIG"
  return 1
}

# resolution order: explicit pin in $_HI_COLOR_OVERRIDES, then (hostnames
# only) an ssh config hosttag, then a deterministic hash - always succeeds
function _hi_resolve_color() {
  local type="$1" name="$2" color

  color=$(_hi_override_color "$type" "$name") && {
    printf '%s' "$color"
    return
  }

  if [[ "$type" = hostname ]]; then
    color=$(_hi_ssh_tag_color "$name") && {
      printf '%s' "$color"
      return
    }
  fi

  _hi_hash_color "$name"
}

# no third arg -> the color's name (fish set_color / zsh %F{} vocabulary);
# third arg present -> the raw bash/zsh ANSI escape for that color
function _hi_emit_color() {
  local color_name="${1:-}" want_escape="${2:-}"
  if [[ -z $want_escape ]]; then
    printf '%s\n' "$color_name"
  elif [[ -z ${ZSH_VERSION+x} ]]; then
    printf '%b' "${_HI_COLOR_ESCAPES[$color_name]}"
  else
    printf '%b\n' "${_HI_COLOR_ESCAPES[$color_name]}"
  fi
}

function host_color() {
  _hi_emit_color "$(_hi_resolve_color hostname "$(_hi_hostname)")" ${1+x}
}

function user_color() {
  _hi_emit_color "$(_hi_resolve_color username "$(whoami)")" ${1+x}
}

# preview what color each ssh host & the current user resolve to, rendered in
# that actual color - handy when tuning data/color_overrides. Run via `hi_colors`.
function list_colors() {
  cecho "~~~~~ hi.sh color preview ~~~~~" "$BRGREEN"

  cecho "=== user ===" "$YELLOW"
  local ucolor
  ucolor=$(_hi_resolve_color username "$(whoami)")
  cecho "$(whoami)  ->  $ucolor" "${_HI_COLOR_ESCAPES[$ucolor]}"

  cecho "=== ssh hosts ===" "$YELLOW"
  if [[ -f "$_HI_SSH_CONFIG" ]]; then
    local line host hcolor
    while IFS=$' ' read -r line; do
      [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+([^#]+) ]] || continue
      for host in ${BASH_REMATCH[1]}; do
        [[ "$host" == *[*?]* ]] && continue
        hcolor=$(_hi_resolve_color hostname "$host")
        cecho "$host  ->  $hcolor" "${_HI_COLOR_ESCAPES[$hcolor]}"
      done
    done <"$_HI_SSH_CONFIG"
  else
    cecho "No ssh config found at $_HI_SSH_CONFIG" "$RED"
  fi
}
