#!/bin/bash
set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

declare -a color_yes
declare -a color_no
# bright blue if we have, ignore if we don't (ex: nice-to-haves, such netstat + distro specific tools)
color_yes[0]="$BRBLUE"
color_no[0]="hide"

# bright blue if we have, yellow if we don't (ex. 2nd line tools, such as git, curl, ping)
color_yes[1]="$BRBLUE"
color_no[1]="$YELLOW"

# hide if we have, bright red if we don't (ex: 1st line tools, such as sed, awk, bc)
color_yes[2]="hide"
color_no[2]="$BRRED"

# green if we have, hide if we don't (ex: tools/languages such as python, node, docker, dotnet)
color_yes[3]="$GREEN"
color_no[3]="hide"

# bright green if we have, hide if we don't (ex: favorites & complex tools such as eza/exa)
color_yes[4]="$BRGREEN"
color_no[4]="hide"

# bright green if we have, bright red if we don't (ex: things that majorly change work such as asdf, direnv)
color_yes[5]="$BRGREEN"
color_no[5]="$BRRED"

commands=()

load_packages() {
  while read -r line; do
    if ! [[ "$line" =~ '#' ]]; then
      commands+=("$line")
    fi
  done <"$_HI_PACKAGES_CONFIG"
}

function sort_commands() {
  local cmd_list=("$@")
  local result=()
  local color

  for item in "${cmd_list[@]}"; do
    if [[ -z ${ZSH_VERSION+x} ]]; then
      IFS=',' read -ra pairs <<<"$item"
    else
      IFS=',' read -rA pairs <<<"$item"
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
        if ((current_priority > max_priority)); then
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

    if ((is_installed)); then
      color="${color_yes[max_priority]}"
      result+=("$max_cmd:$GREEN✓:$color")
    else
      color="${color_no[first_priority]}"
      result+=("$first_cmd:$RED✗:$color")
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
    IFS=',' read -ra cmd_list <<<"$raw"
  else
    IFS=',' read -rA cmd_list <<<"$raw"
  fi

  # shellcheck disable=SC2207
  local sorted_cmd_list=($(sort_commands "${cmd_list[@]}"))

  if ((${#sorted_cmd_list[@]} == 0)); then
    return
  fi

  local symbol
  local color
  local cmd
  local item
  local found=0
  for item in "${sorted_cmd_list[@]}"; do
    color="$NC"
    cmd="${item%:*:*}"
    inner="${item#*:}"
    symbol="${inner%:*}"
    color="${item##*:}"

    if [[ -n "$color" && "$color" != "hide" ]]; then
      found=1
      break
    fi
  done

  if ((found == 0)); then
    return
  fi

  printf '%b %b %b%b' "$color" "$cmd" "$symbol" "$NC"
}

function process_commands() {
  local is_fish="${1:-0}"
  local length
  local breakpoint
  local rows=3
  length="${#commands[@]}"
  breakpoint=$(((length + (rows - 1)) / rows))

  echo -ne "$NC|"
  local count=0
  for line in "${commands[@]}"; do
    check_commands "$line"
    if ((count % breakpoint == 0)) && ((count != 0)); then
      if [[ $is_fish -eq 1 ]]; then
        echo -n "newline"
      else
        echo -ne "\n "
      fi
      echo -ne "$NC|"
    fi
    ((count += 1))
  done
}

function full_check() {
  echo -ne " "
  process_commands 2
}

function full_check_fish {
  load_packages
  process_commands 1
}
