#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

function sort_commands() {
  local cmd_list=("$@")

  local result=()

  for item in "${cmd_list[@]}"; do
    IFS=',' read -ra pairs <<< "$item"

    local max_priority_cmd=""
    local max_priority=0
    local is_installed=false

    for pair in "${pairs[@]}"; do
      cmd="${pair%:*}"
      priority="${pair#*:}"

      if command -v "$cmd" &>/dev/null; then
        if [[ "$priority" -gt "$max_priority" ]] || [[ "$max_priority" -eq 0 ]]; then
          max_priority=$priority
          max_priority_cmd=$cmd
          is_installed=true
        fi
      fi
    done

    if [[ "$is_installed" == true ]]; then
      result+=("$max_priority_cmd:$max_priority:yes")
    else
      first_cmd="${pairs[0]%:*}"
      first_priority="${pairs[0]#*:}"
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

  echo -ne "$NC"

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

    cecho " $cmd $symbol" "$color" 1
  done
}

function packages() {
  echo -ne " $NC|"

  local package_commands
  package_commands=$(grep -E '^packages' "$_HI_CHECK_PACKAGES")
  [[ -z $package_commands ]] && return 1
  package_commands=${package_commands#packages:}
  local -a cmd_arr
  readarray -t cmd_arr <<< "$package_commands"
  for line in "${cmd_arr[@]}"; do
    check_commands "$line"
  done
}

function basics() {
  echo -ne " $NC|"

  local basic_commands
  basic_commands=$(grep -E '^basics' "$_HI_CHECK_PACKAGES")
  [[ -z $basic_commands ]] && return 1
  basic_commands=${basic_commands#basics:}
  local -a cmd_arr
  readarray -t cmd_arr <<< "$basic_commands"
  for line in "${cmd_arr[@]}"; do
    check_commands "$line"
  done
}

function systems() {
  echo -ne " $NC|"

  local system_commands
  system_commands=$(grep -E '^systems' "$_HI_CHECK_PACKAGES")
  [[ -z $system_commands ]] && return 1
  system_commands=${system_commands#systems:}
  local -a cmd_arr
  readarray -t cmd_arr <<< "$system_commands"
  for line in "${cmd_arr[@]}"; do
    check_commands "$line"
  done
}

function tools() {
  echo -ne " $NC|"

  local tool_commands
  tool_commands=$(grep -E '^tools' "$_HI_CHECK_PACKAGES")
  [[ -z $tool_commands ]] && return 1
  tool_commands=${tool_commands#tools:}
  local -a cmd_arr
  readarray -t cmd_arr <<< "$tool_commands"
  for line in "${cmd_arr[@]}"; do
    check_commands "$line"
  done
}
