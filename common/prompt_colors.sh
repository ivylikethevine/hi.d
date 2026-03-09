#!/bin/bash

at_color() {
  local AT_COLOR=$NC
  if [[ $1 ]]; then
    AT_COLOR=$YELLOW
  fi
  echo "$AT_COLOR"
}

read_color_file() {
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
    echo "brgreen"
  else
    # shellcheck disable=SC2028
    echo "\e[0;32m"
  fi
  return 1
}

host_color() {
  local hi_root=${HI_ROOT:-~}
  local is_fish="$1"
  read_color_file "$(hostname)" "$hi_root/.hi.d/common/host_colors" "$is_fish"
}

user_color() {
  local hi_root=${HI_ROOT:-~}
  local is_fish="$1"
  read_color_file "$(whoami)" "$hi_root/.hi.d/common/user_colors" "$is_fish"
}
