#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/aliases.sh

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
  local formatted_text="$2$1$NC"
  local disable_newline="${3}"

  if [[ -n "$disable_newline" ]]; then
    echo -e -n "$formatted_text";
  else
    echo -e "$formatted_text";
  fi
}

# required
function at_color() {
  local ssh_tty="$1"
  if [[ $ssh_tty ]]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$NC"
  fi
}

# required
function read_color_file() {
  local search_val="$1"
  local color_file="$2"
  local is_fish="$3"

  while IFS=$',' read -r -a dataArray; do
      current_val="${dataArray[0]}"
      [[ "$current_val" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$current_val" ]] && continue

      if [ "$search_val" = "$current_val" ]; then
        if [[ -z "$is_fish" ]]; then
          echo "${dataArray[2]}"
        else
          echo "${dataArray[1]}"
        fi
        return 0
      fi
  done < "$color_file"
  if [[ -z "$is_fish" ]]; then
    printf '%s' "brgreen"
  else
    printf '%s' "\e[0;32m"
  fi
  return 1
}

# required
function host_color() {
  read_color_file "$(hostname)" "$_HI_HOST_COLORS" "${1:-}"
}

# required
function user_color() {
  read_color_file "$(whoami)" "$_HI_USER_COLORS"  "${1:-}"
}
