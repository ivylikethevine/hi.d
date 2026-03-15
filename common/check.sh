#!/bin/bash
# set -eou pipefail

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

package_commands=()
basic_commands=()
system_commands=()
tool_commands=()

declare -A color_yes
declare -A color_no

load_packages() {
  while read -r line; do
    if [[ "$line" =~ ^packages ]]; then
      package_commands+=("$line")
    elif [[ "$line" =~ ^basics ]]; then
      basic_commands+=("$line")
    elif [[ "$line" =~ ^systems ]]; then
      system_commands+=("$line")
    elif [[ "$line" =~ ^tools ]]; then
      tool_commands+=("$line")
    elif [[ "$line" =~ ^[0-9] ]]; then
      priority=${line%%,*}
      inner=${line#*,}
      yescol=${inner%%,*}
      nocol=${line##*,}
      color_yes["$priority"]="$yescol"
      color_no["$priority"]="$nocol"
    fi
  done < "$_HI_PACKAGES_CONFIG"
}

function sort_commands() {
  local cmd_list=("$@")
  local result=()

  for item in "${cmd_list[@]}"; do
    IFS=',' read -ra pairs <<< "$item"

    local max=-1
    local max_cmd
    local is_installed=0
    local first_cmd
    local first_priority

    for pair in "${pairs[@]}"; do
      local cmd="${pair%:*}"
      local current="${pair#*:}"

      if command -v "$cmd" &>/dev/null; then
        if (( current > max )); then
          max=$current
          max_cmd=$cmd
          is_installed=1
        fi
      fi

      if [[ -z ${first_cmd+x} ]]; then
        first_cmd=$cmd
        first_priority=$current
      fi
    done

    if (( is_installed )); then
      result+=("$max_cmd:$max:yes")
    else
      result+=("$first_cmd:$first_priority:no")
    fi
  done

  printf '%s\n' "${result[@]}" | sort -t':' -k2,2n -k3,3r
}

function check_commands() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    return
  fi
  IFS=',' read -ra cmd_list <<< "$raw"
  cmd_list=("${cmd_list[@]:1}") # remove the grouping

  # shellcheck disable=SC2207
  local sorted_cmd_list=($(sort_commands "${cmd_list[@]}"))
  if (( ${#sorted_cmd_list[@]} == 0 )); then
    return
  fi

  # Find the first command whose color is not empty and not "hide".
  local item
  local found=0
  for item in "${sorted_cmd_list[@]}"; do
    cmd="${item%:*:*}"
    inner="${item#*:}"
    priority="${inner%:*}"
    is_installed="${item##*:}"

    local color
    if [[ "$is_installed" == "yes" ]]; then
      color="${color_yes[$priority]}"
    else
      color="${color_no[$priority]}"
    fi

    if [[ -n "$color" && "$color" != "hide" ]]; then
      found=1
      break
    fi
  done

  if (( found == 0 )); then
    return
  fi

  local symbol
  if [[ "$is_installed" == "yes" ]]; then
    symbol="✓"
  else
    symbol="✗"
  fi

  printf '%b' "$color $cmd $symbol$NC"
}

function process_commands() {
  echo -ne "$NC|"
  local -n arr=$1
  for line in "${arr[@]}"; do
    check_commands "$line"
  done
}

function full_check() {
  echo -ne " "
  process_commands package_commands
  echo -ne "\n "
  process_commands basic_commands
  echo -ne "\n "
  process_commands system_commands
  echo -ne "\n "
  process_commands tool_commands
  echo -ne "\n"
}

function full_check_fish {
  load_packages
  process_commands package_commands
  echo -n "newline"
  process_commands basic_commands
  echo -n "newline"
  process_commands system_commands
  echo -n "newline"
  process_commands tool_commands
}
