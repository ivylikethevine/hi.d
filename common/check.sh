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
color_no[1]="$BRYELLOW"

# hide if we have, bright red if we don't (ex: 1st line tools, such as sed, awk, bc)
color_yes[2]="hide"
color_no[2]="$YELLOW"

# green if we have, hide if we don't (ex: tools/languages such as python, node, docker, dotnet)
color_yes[3]="$GREEN"
color_no[3]="hide"

# bright green if we have, hide if we don't (ex: favorites & complex tools such as eza/exa)
color_yes[4]="$BRGREEN"
color_no[4]="hide"

# bright green if we have, bright red if we don't (ex: things that majorly change work such as asdf, direnv)
color_yes[5]="$BRGREEN"
color_no[5]="$BRRED"

# for a single "cmd:priority[,cmd:priority...]" line, pick the installed
# pair with the highest priority (falling back to the first pair if none
# are installed), then emit it unless its priority maps to "hide"
function check_line() {
  local line="$1"
  local -a pairs
  if [[ -z ${ZSH_VERSION+x} ]]; then
    IFS=',' read -ra pairs <<<"$line"
  else
    IFS=',' read -rA pairs <<<"$line"
  fi

  local pair cmd priority
  local max_priority=-1
  local max_cmd=""
  local is_installed=0
  local first_cmd=""
  local first_priority=""

  for pair in "${pairs[@]}"; do
    cmd="${pair%:*}"
    priority="${pair#*:}"

    if [[ -z "$first_cmd" ]]; then
      first_cmd="$cmd"
      first_priority="$priority"
    fi

    if command -v "$cmd" &>/dev/null && ((priority > max_priority)); then
      max_priority=$priority
      max_cmd=$cmd
      is_installed=1
    fi
  done

  local color cmd_out symbol priority_out
  if ((is_installed)); then
    color="${color_yes[max_priority]}"
    cmd_out="$max_cmd"
    symbol="$GREEN✓"
    priority_out="$max_priority"
  else
    color="${color_no[first_priority]}"
    cmd_out="$first_cmd"
    symbol="$RED✗"
    priority_out="$first_priority"
  fi

  [[ "$color" == "hide" ]] && return

  printf '%s\x1f%b %b %b\n' "$priority_out" "$color" "$cmd_out" "$symbol"
}

function process_commands() {
  local is_fish="${1:-0}"
  local columns=8

  local -a visible_output=()
  local line item
  while IFS=$'\n' read -r line; do
    [[ "$line" == *#* ]] && continue
    item="$(check_line "$line")"
    [[ -n "$item" ]] && visible_output+=("$item")
  done <"$_HI_PACKAGES_CONFIG"

  # sort the visible (non-"hide") entries by their priority, highest first,
  # ties keep file order, then drop the priority prefix used only for sorting
  local -a checked_output=()
  if ((${#visible_output[@]} > 0)); then
    while IFS=$' ' read -r item; do
      checked_output+=("${item#*$'\x1f'}")
    done < <(printf '%s\n' "${visible_output[@]}" | sort -t $'\x1f' -k1,1nr -s)
  fi

  local count=1
  for item in "${checked_output[@]}"; do
    echo -ne "$NC|$item $NC"
    if ((count % columns == 0)); then
      if [[ $is_fish -eq 1 ]]; then
        echo -n "newline"
      else
        echo -ne "\n "
      fi
    fi
    ((count += 1))
  done
}

function full_check() {
  echo -ne " "
  process_commands 0
}

function full_check_fish {
  process_commands 1
}
