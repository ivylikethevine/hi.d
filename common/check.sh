#!/bin/bash
# Reads misc/packages and prints which of them are installed, sorting by priority.
set -euo pipefail

# shellcheck source=./bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

# priority, lowest to highest (more can be added)
# 0 nice-to-haves (netstat, distro tools)
# 1 second line (git, curl, ping)
# 2 first line (sed, awk, bc)
# 3 runtimes (python, node, dotnet)
# 4 favorites (eza, bat)
# 5 workflow-defining (asdf, direnv)
_HI_YES=("$BRBLUE" "$BRBLUE" hide "$GREEN" "$BRGREEN" "$BRGREEN")
_HI_NO=(hide "$BRYELLOW" "$YELLOW" hide hide "$BRRED")

# For each "cmd:priority[,...]", pick the installed package with the
# highest priority (or the first package if none are installed), then apply the
# proper color and mark it as installed or missing (or hide it as per above)
function check_line() {
  local pair cmd priority color best best_priority best_idx=0 idx=0 found=0 symbol rendered
  local -a pairs
  IFS=',' read -ra pairs <<<"$1"
  best="${pairs[0]%:*}"
  best_priority="${pairs[0]#*:}"

  for pair in "${pairs[@]}"; do
    cmd="${pair%:*}"
    priority="${pair#*:}"
    if command -v "$cmd" &>/dev/null && ((found == 0 || priority > best_priority)); then
      best="$cmd"
      best_priority="$priority"
      best_idx=$idx
      found=1
    fi
    ((++idx))
  done

  if ((found)); then
    color="${_HI_YES[best_priority]:-$NC}"
    if ((best_idx == 0)); then symbol="$GREEN✓"; else symbol="$YELLOW~$NC"; fi
  else
    color="${_HI_NO[best_priority]:-$NC}"
    symbol="$RED✗"
  fi
  rendered="$color $best $symbol"
  [[ "$color" == hide ]] || visible+=("$best_priority"$'\x1f'"$((${#best} + 5))"$'\x1f'"$rendered")
}

# print sorted package results limited by _HI_MAX_WIDTH
function full_check() {
  local line priority width_item rendered count=0 width=0
  local -a visible=() # appended to by check_line
  while IFS=$' ' read -r line; do
    [[ "$line" == *#* || -z "$line" ]] || check_line "$line"
  done <"$_HI_PACKAGES"
  ((${#visible[@]})) || return 0

  while IFS=$'\x1f' read -r priority width_item rendered; do
    if ((count == 0)) || ((width + width_item > ${_HI_MAX_WIDTH:-80})); then # start of a row
      ((count == 0)) || printf '\n'
      printf ' '
      width=1
    fi
    printf '%b' "$NC|${rendered} $NC"
    width=$((width + width_item))
    ((++count))
  done < <(printf '%s\n' "${visible[@]}" | sort -t $'\x1f' -k1,1nr -s)
  printf '\n'
}
