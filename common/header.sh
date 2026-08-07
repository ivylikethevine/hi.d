#!/bin/bash
# The banner hi prints on connect/disconnect, and the fish greeting prints
# locally - one implementation for every shell (fish shells out to bash here).
set -eou pipefail

# shellcheck source=./bootstrap.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./check.sh
source "$_HI_CHECK"

function _hi_row() {
  local cell out=""
  for cell in "$@"; do out+="$NC | $cell"; done
  printf '%b\n' "$out$NC"
}

function timestamp() {
  local fmt="+%a %b %-e %Y %H:%M:%S %Z"
  _hi_row "$BRBLUE$(date -u "$fmt")  " "  $BRYELLOW$(date "$fmt")"
}

function system_info_line() {
  local kernel arch os cpus ram
  read -r kernel arch <<<"$(uname -sm)"
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    os=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' "$_HI_LINUX_RELEASE")
    cpus=$(nproc 2>/dev/null)
    ram=$(free -h --giga 2>/dev/null | awk '$1 == "Mem:" { print $2 }')
  else
    os="macOS $(sw_vers -productVersion 2>/dev/null)"
    cpus=$(sysctl -n hw.ncpu 2>/dev/null)
    ram=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%.0fG", $1 / 1073741824 }')
  fi
  _hi_row "$YELLOW$kernel" "$PURPLE$arch" "$GREEN$os" "${BLUE}CPUs: ${cpus:-?}" "${CYAN}RAM: ${ram:-?}"
}

# git identity (domain masked), running containers, and ssh key counts
function identity_line() {
  local email="" domain user_part bullets containers="No docker :(" authorized=0 public=0
  command -v git &>/dev/null && email=$(git config --get user.email 2>/dev/null || true)
  if [ -n "$email" ]; then
    domain=${email#*@}
    bullets=$(printf "%*s" "${#domain}" "" | sed 's/ /●/g')
    user_part="${CYAN}Git ID: $YELLOW${email%%@*}@$bullets"
  else
    user_part="${YELLOW}No Git ID Found..."
  fi
  command -v docker &>/dev/null && containers="Containers: $(docker container ls -q | wc -l)"
  [ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && authorized=$(wc -l <"$_HI_SSH_AUTHORIZED_KEYS")
  [ -d "$_HI_SSH_DIR" ] && public=$(find "$_HI_SSH_DIR" -type f -name "*.pub" | wc -l)
  _hi_row "$user_part" "$BLUE$containers" "${RED}Auth: $authorized" "${PURPLE}Pub: $public"
}

# "~~~ <label> [host] ~~~", prefixed with hi.d's local change count
# this whole line is always _HI_MAX_WIDTH columns, regardless of other factors
function hi_banner() {
  local label="$1" color="${2:-$BRGREEN}" prefix="${3:-}" changes_plain="" changes=""
  if [ -d "$_HI_ROOT/.git" ]; then
    changes_plain="$(git -C "$_HI_ROOT" status --short | wc -l) ↑ "
    changes="$BRYELLOW$changes_plain"
  fi
  local host tildes start_len end_len start_tildes end_tildes width left core
  host="$(_hi_hostname)"
  width=${_HI_MAX_WIDTH:-80}
  tildes=$((width - 6 - ${#changes_plain} - ${#label} - ${#host} - ${#prefix}))
  ((tildes < 4)) && tildes=4
  # split so "label [host]" lands at the center with at least 1 tilde on the left
  left=$((${#prefix} + 1 + ${#changes_plain}))
  core=$((${#label} + ${#host} + 4))
  start_len=$((width / 2 - left - core / 2))
  ((start_len < 1)) && start_len=1
  ((start_len > tildes - 1)) && start_len=$((tildes - 1))
  end_len=$((tildes - start_len))
  start_tildes=$(printf '%*s' "$start_len" '' | tr ' ' '~')
  end_tildes=$(printf '%*s' "$end_len" '' | tr ' ' '~')
  printf '%b\n' " $changes$color$start_tildes $label ${NC}[$(host_escape)$host$NC]$color $end_tildes$NC"
}

function hi_header() {
  hi_banner "$@"
  timestamp
  system_info_line
  identity_line
  full_check
}
