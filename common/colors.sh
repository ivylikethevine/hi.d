#!/bin/bash
# set -eou pipefail

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

# required
# high-res-ish timestamp without shelling out to perl (not guaranteed to exist
# on minimal/embedded targets); falls back to whole-second precision on bash <5
function _hi_now() {
  if [[ -n ${EPOCHREALTIME+x} ]]; then
    printf '%s' "$EPOCHREALTIME"
  else
    date +%s
  fi
}

# required
# `hostname` isn't guaranteed to exist on minimal/container images; uname -n is
function _hi_hostname() {
  hostname 2>/dev/null || uname -n
}

# required
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

# required
function at_color() {
  if [[ -v SSH_TTY ]]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$NC"
  fi
}

# required
function read_color_file() {
  local search_val=${1:-}
  local color_file=${2:-}
  local is_fish=${3+x}

  local current_val color_bash color_fish
  while IFS=',' read -r current_val color_bash color_fish; do
    [[ "$current_val" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$current_val" ]] && continue

    if [ "$search_val" = "$current_val" ]; then
      if [[ -z $is_fish ]]; then
        printf '%b\n' "$color_fish"
      elif [[ -z ${ZSH_VERSION+x} ]]; then
        printf '%b' "$color_bash"
      else
        printf '%b\n' "$color_bash"
      fi
      return
    fi
  done <"$color_file"
  if [[ -z $is_fish ]]; then
    printf '%s\n' "brgreen"
  elif [[ -z ${ZSH_VERSION+x} ]]; then
    printf '%s' "$GREEN"
  else
    printf '%s\n' "$GREEN"
  fi
}

# required
function host_color() {
  read_color_file "$(_hi_hostname)" "$_HI_HOST_COLORS" ${1+x}
}

# required
function user_color() {
  read_color_file "$(whoami)" "$_HI_USER_COLORS" ${1+x}
}
