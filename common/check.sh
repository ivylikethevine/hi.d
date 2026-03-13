#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

package_commands=()
basic_commands=()
system_commands=()
tool_commands=()

while IFS= read -r line; do
  if [[ "$line" =~ ^packages ]]; then
    package_commands+=("$line")
  elif [[ "$line" =~ ^basics ]]; then
    basic_commands+=("$line")
  elif [[ "$line" =~ ^systems ]]; then
    system_commands+=("$line")
  elif [[ "$line" =~ ^tools ]]; then
    tool_commands+=("$line")
  fi
done < "$_HI_CHECK_PACKAGES"

function sort_commands() {
 local cmd_list=("$@")
 local result=()

 # Cache command existence to avoid repeated command -v lookups
 declare -g -A _HI_CMD_CACHE 2>/dev/null
 if [[ -z ${_HI_CMD_CACHE+x} ]]; then
  declare -g -A _HI_CMD_CACHE
 fi

 for item in "${cmd_list[@]}"; do
  IFS=',' read -ra pairs <<< "$item"

  local max_priority=-1
  local max_cmd
  local is_installed=0
  local first_cmd
  local first_priority

  for pair in "${pairs[@]}"; do
   local cmd="${pair%:*}"
   local priority="${pair#*:}"

   if [[ -z ${_HI_CMD_CACHE[$cmd]+_} ]]; then
    if command -v "$cmd" &>/dev/null; then
     _HI_CMD_CACHE["$cmd"]=1
    else
     _HI_CMD_CACHE["$cmd"]=0
    fi
   fi

   if [[ ${_HI_CMD_CACHE[$cmd]} -eq 1 ]]; then
    if (( priority > max_priority )); then
     max_priority=$priority
     max_cmd=$cmd
     is_installed=1
    fi
   fi

   if [[ -z $first_cmd ]]; then
    first_cmd=$cmd
    first_priority=$priority
   fi
  done

  if (( is_installed )); then
   result+=("$max_cmd:$max_priority:yes")
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

  declare -A color_yes
  declare -A color_no

  while IFS=',' read -r priority yescol nocol; do
    [[ -z "$priority" ]] && continue
    [[ "$priority" =~ ^[0-9] ]] || continue
    color_yes["$priority"]="$yescol"
    color_no["$priority"]="$nocol"
  done < "$_HI_CHECK_PACKAGES"

  # shellcheck disable=SC2207
  local sorted_cmd_list=($(sort_commands "${cmd_list[@]}"))

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

    # Skip if color is empty or set to "hide"
    if [[ -z "$color" || "$color" == "hide" ]]; then
      continue
    fi

    local symbol
    if [[ "$is_installed" == "yes" ]]; then
      symbol="✓"
    else
      symbol="✗"
    fi

    printf '%b' "$color $cmd $symbol$NC"
  done
}

function process_commands() {
  echo -ne "$NC|"
  local -n arr=$1
  for line in "${arr[@]}"; do
    check_commands "$line"
  done
}

function packages() {
  process_commands package_commands
}

function basics() {
  process_commands basic_commands
}

function systems() {
  process_commands system_commands
}

function tools() {
  process_commands tool_commands
}

function full_check_fish {
  packages
  echo -n "newline"

  basics
  echo -n "newline"

  systems
  echo -n "newline"

  tools
  echo -n "newline"
}
