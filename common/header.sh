#!/bin/bash
# The banner hi prints on connect/disconnect, and the fish greeting prints
# locally - one implementation for every shell (fish shells out to bash here).
set -euo pipefail

# shellcheck source=./bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./check.sh
source "$_HI_CHECK"

# export _HI_HEADER_TIMESTAMP=0
# export _HI_HEADER_SYSINFO=0
# export _HI_HEADER_IDENTITY=0
# export _HI_HEADER_CHECK=0

function header_row() {
  local cell out=""
  for cell in "$@"; do out+="$NC | $cell"; done
  printf '%b\n' "$out$NC"
}

function timestamp() {
  local fmt="+%a %b %-e %Y %H:%M:%S %Z"
  header_row "$BRBLUE$(date -u "$fmt")  " "  $BRYELLOW$(date "$fmt")"
}

function system_info() {
  local kernel arch os cpus ram base_mhz boost_mhz
  read -r kernel arch <<<"$(uname -sm)"
  kernel=$(_hi_sanitize "$kernel")
  arch=$(_hi_sanitize "$arch")
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    # also covers WSL - it's a real Linux kernel with its own /etc/os-release
    os=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' "$_HI_LINUX_RELEASE")
    cpus=$(nproc 2>/dev/null)
    ram=$(free -h --giga 2>/dev/null | awk '$1 == "Mem:" { print $2 }')
    # base clock: try the model name first (eg "... @ 2.80GHz") - AMD chips (Ryzen/EPYC) don't
    # print one, so fall back to cpufreq's base_frequency (Intel P-State / amd-pstate only)
    base_mhz=$(awk -F'@ *' '/model name/ && NF>1 { gsub(/GHz.*/, "", $2); printf "%.0f", $2 * 1000; exit }' /proc/cpuinfo 2>/dev/null)
    if [ -z "$base_mhz" ]; then
      base_mhz=$(($(cat /sys/devices/system/cpu/cpu0/cpufreq/base_frequency 2>/dev/null || echo 0) / 1000))
      ((base_mhz)) || base_mhz=""
    fi
    # boost/max clock: cpufreq first (works for any driver that exposes it), falling back to lscpu
    boost_mhz=$(($(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null ||
      cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo 0) / 1000))
    ((boost_mhz)) || boost_mhz=$(lscpu 2>/dev/null | awk -F: '/CPU max MHz/ { gsub(/ /, "", $2); printf "%.0f", $2 }' || true)
  elif [[ "$kernel" == MINGW* || "$kernel" == MSYS* || "$kernel" == CYGWIN* ]]; then
    # git-bash/MSYS2/Cygwin on native Windows - no /etc/os-release, no sysctl
    os="Windows ($kernel)"
    cpus="${NUMBER_OF_PROCESSORS:-?}"
    ram=$(wmic ComputerSystem get TotalPhysicalMemory 2>/dev/null |
      awk 'NR==2 && $1 ~ /^[0-9]+$/ { printf "%.0fG", $1 / 1073741824 }')
    # wmic only exposes the rated (base) clock; turbo/boost isn't queryable this way
    base_mhz=$(wmic cpu get MaxClockSpeed 2>/dev/null | awk 'NR==2 && $1 ~ /^[0-9]+$/ { print $1 }')
  else
    os="macOS $(sw_vers -productVersion 2>/dev/null)"
    cpus=$(sysctl -n hw.ncpu 2>/dev/null)
    ram=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%.0fG", $1 / 1073741824 }')
    # Apple Silicon doesn't expose either clock via sysctl; only Intel Macs get a value here
    base_mhz=$(sysctl -n hw.cpufrequency 2>/dev/null | awk '{ printf "%.0f", $1 / 1000000 }')
  fi
  os=$(_hi_sanitize "$os")
  header_row "$PURPLE$arch" "$GREEN$os" "${YELLOW}Cores: ${cpus:-?}" \
    "${CYAN}RAM: ${ram:-?}" "${BRBLUE}CPU: ${base_mhz:-?}/${boost_mhz:-?} MHz"
}

# git identity (domain masked), running containers, nomad jobs, and ssh key counts
function identity() {
  local email="" domain user_part bullets containers="No docker :(" jobs="" authorized=0 public=0
  local -a lines cells
  command -v git &>/dev/null && email=$(git config --get user.email 2>/dev/null || true)
  email=$(_hi_sanitize "$email")
  if [ -n "$email" ]; then
    domain=${email#*@}
    printf -v bullets '%*s' "${#domain}" ''
    user_part="$YELLOW${email%%@*}@${bullets// /●}"
  else
    user_part="${YELLOW}No Git ID Found..."
  fi
  if command -v docker &>/dev/null; then
    mapfile -t lines < <(docker container ls -q)
    containers="Containers: ${#lines[@]}"
  fi
  if command -v nomad &>/dev/null; then
    mapfile -t lines < <(nomad job status 2>/dev/null | tail -n +2)
    jobs="Jobs: ${#lines[@]}"
  fi
  [ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && mapfile -t lines <"$_HI_SSH_AUTHORIZED_KEYS" && authorized=${#lines[@]}
  [ -d "$_HI_SSH_DIR" ] && mapfile -t lines < <(find "$_HI_SSH_DIR" -type f -name "*.pub") && public=${#lines[@]}
  cells=("$user_part" "$BLUE$containers")
  [ -n "$jobs" ] && cells+=("$CYAN$jobs")
  cells+=("${RED}Auth: $authorized" "${PURPLE}Pub: $public")
  header_row "${cells[@]}"
}

# "~~~ <label> [host] ~~~", prefixed with hi.d's local change count
# this whole line is always _HI_MAX_WIDTH columns, regardless of other factors
function banner() {
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
  printf '%b\n' " $changes$color$start_tildes $label ${NC}[$(_hi_host_escape)$host$NC]$color $end_tildes$NC"
}

function hi_header() {
  banner "$@"
  [[ "${_HI_HEADER_TIMESTAMP:-1}" == 0 ]] || timestamp
  [[ "${_HI_HEADER_SYSINFO:-1}" == 0 ]] || system_info
  [[ "${_HI_HEADER_IDENTITY:-1}" == 0 ]] || identity
  [[ "${_HI_HEADER_CHECK:-1}" == 0 ]] || full_check
}
