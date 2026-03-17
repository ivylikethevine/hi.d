#!/bin/bash
# set -eou pipefail

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"

# required
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
export NC='\e[0m'

# required
cecho() {
  local text=${1:-}
  local color=${2:-}

  local formatted_text="$color$text$NC"
  if [[ -z ${3+x}  ]]; then
    printf '%b\n' "$formatted_text";
  else
    printf '%b' "$formatted_text";
  fi
  return
}

# required
function at_color() {
  local ssh_tty=${1+x}
  if [[ -z $ssh_tty ]]; then
    printf '%b' "$YELLOW"
  else
    printf '%b' "$NC"
  fi
}

# required
function read_color_file() {
  local search_val=${1:-}
  local color_file=${2:-}
  local is_fish=${3+x}

  local -a dataArray
  local line
  while IFS=$' ' read -r line; do
    if [[ -z ${ZSH_VERSION+x} ]]; then
      IFS=',' read -ra dataArray <<< "$line"
    else
      IFS=',' read -rA dataArray <<< "$line"
    fi
    current_val="${dataArray[0]}"
    [[ "$current_val" =~ ^[[:space:]]*# ]] && continue
    [[ -z ${current_val+x} ]] && continue

    if [ "$search_val" = "$current_val" ]; then
      if [[ -z $is_fish ]]; then
        printf '%b\n' "${dataArray[2]}"
      else
        printf '%b\n' "${dataArray[1]}"
      fi
      return
    fi
  done < "$color_file"
  if [[ -z $is_fish ]]; then
    printf '%s\n' "brgreen"
  else
    printf '%s\n' "\e[0;32m"
  fi
}

# required
function host_color() {
  read_color_file "$(hostname)" "$_HI_HOST_COLORS" ${1+x}
}

# required
function user_color() {
  read_color_file "$(whoami)" "$_HI_USER_COLORS"  ${1+x}
}
