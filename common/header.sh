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
  kernel=$(_hi_sanitize "$kernel")
  arch=$(_hi_sanitize "$arch")
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    # also covers WSL - it's a real Linux kernel with its own /etc/os-release
    os=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' "$_HI_LINUX_RELEASE")
    cpus=$(nproc 2>/dev/null)
    ram=$(free -h --giga 2>/dev/null | awk '$1 == "Mem:" { print $2 }')
  elif [[ "$kernel" == MINGW* || "$kernel" == MSYS* || "$kernel" == CYGWIN* ]]; then
    # git-bash/MSYS2/Cygwin on native Windows - no /etc/os-release, no sysctl
    os="Windows ($kernel)"
    cpus="${NUMBER_OF_PROCESSORS:-?}"
    ram=$(wmic ComputerSystem get TotalPhysicalMemory 2>/dev/null |
      awk 'NR==2 && $1 ~ /^[0-9]+$/ { printf "%.0fG", $1 / 1073741824 }')
  else
    os="macOS $(sw_vers -productVersion 2>/dev/null)"
    cpus=$(sysctl -n hw.ncpu 2>/dev/null)
    ram=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%.0fG", $1 / 1073741824 }')
  fi
  os=$(_hi_sanitize "$os")
  _hi_row "$YELLOW$kernel" "$PURPLE$arch" "$GREEN$os" "${BLUE}CPUs: ${cpus:-?}" "${CYAN}RAM: ${ram:-?}"
}

# git identity (domain masked), running containers, and ssh key counts
function identity_line() {
  local email="" domain user_part bullets containers="No docker :(" authorized=0 public=0
  local -a lines
  command -v git &>/dev/null && email=$(git config --get user.email 2>/dev/null || true)
  email=$(_hi_sanitize "$email")
  if [ -n "$email" ]; then
    domain=${email#*@}
    printf -v bullets '%*s' "${#domain}" ''
    user_part="${CYAN}Git ID: $YELLOW${email%%@*}@${bullets// /●}"
  else
    user_part="${YELLOW}No Git ID Found..."
  fi
  if command -v docker &>/dev/null; then
    mapfile -t lines < <(docker container ls -q)
    containers="Containers: ${#lines[@]}"
  fi
  [ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && mapfile -t lines <"$_HI_SSH_AUTHORIZED_KEYS" && authorized=${#lines[@]}
  [ -d "$_HI_SSH_DIR" ] && mapfile -t lines < <(find "$_HI_SSH_DIR" -type f -name "*.pub") && public=${#lines[@]}
  _hi_row "$user_part" "$BLUE$containers" "${RED}Auth: $authorized" "${PURPLE}Pub: $public"
}

# "~~~ <label> [host] ~~~", prefixed with hi.d's local change count
# this whole line is always _HI_MAX_WIDTH columns, regardless of other factors
function hi_banner() {
  local label="$1" color="${2:-$BRGREEN}" prefix="${3:-}" changes_plain="" changes=""
  if [ -d "$_HI_ROOT/.git" ]; then
    local -a lines
    mapfile -t lines < <(git -C "$_HI_ROOT" status --short)
    changes_plain="${#lines[@]} ↑ "
    changes="$BRYELLOW$changes_plain"
  fi
  local host tildes start_len end_len start_tildes end_tildes width left core
  host="$(_hi_sanitize "$(_hi_hostname)")"
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
