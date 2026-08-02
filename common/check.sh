#!/bin/bash
set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

package_commands=()
basic_commands=()
tool_commands=()

declare -a color_yes
declare -a color_no

load_packages() {
  while read -r line; do
    if [[ "$line" =~ ^packages ]]; then
      package_commands+=("$line")
    elif [[ "$line" =~ ^basics ]]; then
      basic_commands+=("$line")
    elif [[ "$line" =~ ^tools ]]; then
      tool_commands+=("$line")
    elif [[ "$line" =~ ^[0-9] ]]; then
      priority=${line%%,*}
      inner=${line#*,}
      color_yes["$priority"]="${inner%%,*}"
      color_no["$priority"]="${line##*,}"
    fi
  done < "$_HI_PACKAGES_CONFIG"
}

function sort_commands() {
  local cmd_list=("$@")
  local result=()

  for item in "${cmd_list[@]}"; do
    if [[ -z ${ZSH_VERSION+x} ]]; then
      IFS=',' read -ra pairs <<< "$item"
    else
      IFS=',' read -rA pairs <<< "$item"
    fi

    local max_priority=-1
    local max_cmd
    local is_installed=0
    local first_cmd
    local first_priority
    for pair in "${pairs[@]}"; do
      local cmd="${pair%:*}"
      local current_priority="${pair#*:}"

      if command -v "$cmd" &>/dev/null; then
        if (( current_priority > max_priority )); then
          max_priority=$current_priority
          max_cmd=$cmd
          is_installed=1
        fi
      fi

      if [[ -z ${first_cmd:-} ]]; then
        first_cmd=$cmd
        first_priority=$current_priority
      fi
    done

    if (( is_installed )); then
      result+=("$max_cmd:$max_priority:yes")
    else
      result+=("$first_cmd:$first_priority:no")
    fi
  done

  printf '%s\n' "${result[@]}"
}

function check_commands() {
  local -a cmd_list
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    return
  fi

  if [[ -z ${ZSH_VERSION+x} ]]; then
    IFS=',' read -ra cmd_list <<< "$raw"
  else
    IFS=',' read -rA cmd_list <<< "$raw"
  fi

  cmd_list=("${cmd_list[@]:1}") # remove the grouping

  # shellcheck disable=SC2207
  local sorted_cmd_list=($(sort_commands "${cmd_list[@]}"))

  if (( ${#sorted_cmd_list[@]} == 0 )); then
    return
  fi

  local symbol
  local color
  local cmd
  local item
  local found=0
  for item in "${sorted_cmd_list[@]}"; do
    symbol="$GREEN✓"
    color="$NC"
    cmd="${item%:*:*}"
    inner="${item#*:}"
    priority="${inner%:*}"
    is_installed="${item##*:}"

    if [[ "$is_installed" == "yes" ]]; then
      color="${color_yes[priority]}"
    else
      color="${color_no[priority]}"
      symbol="$RED✗"
    fi

    if [[ -n "$color" && "$color" != "hide" ]]; then
      found=1
      break
    fi
  done

  if (( found == 0 )); then
    return
  fi

  printf '%b %b %b%b' "$color" "$cmd" "$symbol" "$NC"
}

function process_commands() {
  echo -ne "$NC|"
  for line in "$@"; do
    check_commands "$line"
  done
}


function full_check() {
  echo -ne " "
  process_commands "${package_commands[@]}"
  echo -ne "\n "
  process_commands "${basic_commands[@]}"
  echo -ne "\n "
  process_commands "${tool_commands[@]}"
  echo -ne "\n"
}

function full_check_fish {
  load_packages
  process_commands "${package_commands[@]}"
  echo -n "newline"
  process_commands "${basic_commands[@]}"
  echo -n "newline"
  process_commands "${tool_commands[@]}"
}
