#!/bin/bash
set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/bootstrap.sh
source "$_HI_TMPDIR/hi.d/common/bootstrap.sh"

# required
function spacer() {
  echo -n ' | '
}

# required
function timestamp() {
  spacer
  local _HI_HUMAN_CENTRIC_DATE="+%a %b %-e %Y %H:%M:%S %Z"
  printf '%b\n' "${BRBLUE}$(date -u "$_HI_HUMAN_CENTRIC_DATE")   ${NC}|${BRYELLOW}   $(date "$_HI_HUMAN_CENTRIC_DATE")${NC}"
  spacer
}

function system_info_line() {
  local kernel arch uname_out
  uname_out=$(uname -sm)
  kernel=${uname_out%% *}
  arch=${uname_out#* }
  cecho "$kernel" "$YELLOW" 1
  spacer
  cecho "$arch" "$PURPLE" 1
  spacer
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    local key value pretty_name=""
    while IFS='=' read -r key value; do
      if [[ "$key" == "PRETTY_NAME" ]]; then
        pretty_name=${value//\"/}
        break
      fi
    done <"$_HI_LINUX_RELEASE"
    cecho "$pretty_name" "$GREEN" 1
    spacer
    cecho "CPUs: $(nproc)" "$BLUE" 1
    spacer
    local mem_output total="N/A"
    if command -v free &>/dev/null; then
      mem_output=$(free -h --giga)
      if [[ "$mem_output" =~ Mem:[[:space:]]+([0-9.]+[A-Za-z]*) ]]; then
        total="${BASH_REMATCH[1]}"
      fi
    fi
    cecho "RAM: $total " "$CYAN"
  else
    local system_info cores mem
    system_info=$(system_profiler SPHardwareDataType)
    cecho "macOS $(sw_vers -productVersion)" "$BLUE" 1
    spacer
    read -r cores mem < <(awk -F': +' '/Cores/ {cores=$2} /Memory/ {mem=$2} END {print cores, mem}' <<<"$system_info")
    cecho "CPUs: $cores" "$BLUE" 1
    spacer
    cecho "RAM: ${mem%% *}GB" "$CYAN" 1
  fi
}

function git_keys_docker_line() {
  spacer
  if [ -f "$_HI_HOME_GITCONFIG" ]; then
    local line email_line=""
    while IFS=$' ' read -r line; do
      [[ "$line" == *email* ]] && email_line=$line
    done <"$_HI_HOME_GITCONFIG"
    local email=${email_line#*=}
    email=${email// /}
    local user=${email%%@*}
    local domain=${email#*@}
    local bullets=""
    for ((i = 0; i < ${#domain}; i++)); do
      bullets+="●"
    done
    cecho "Git ID: " "$CYAN" 1
    cecho "$user@$bullets" "$YELLOW" 1
  else
    cecho "No Git ID Found..." "$YELLOW" 1
  fi
  spacer
  if command -v "docker" &>/dev/null; then
    cecho "Containers: $(docker container ls -q | wc -l)" "$BLUE" 1
  else
    cecho "No docker :(" "$BRYELLOW" 1
  fi
  spacer
  if [ -f "$_HI_SSH_AUTHORIZED_KEYS" ]; then
    cecho "Auth: $(wc -l <"$_HI_SSH_AUTHORIZED_KEYS")" "$RED" 1
  else
    cecho "Auth: 0!" "$RED" 1
  fi
  spacer
  if [ -f "$_HI_SSH_DIR" ]; then
    cecho "Pub: $(find "$_HI_SSH_DIR" -type f -name "*.pub" | wc -l)" "$PURPLE"
  else
    cecho "Pub: 0!" "$PURPLE"
  fi
}
