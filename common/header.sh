#!/bin/bash
set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

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
  cecho "$(uname -s)" "$YELLOW" 1
  spacer
  cecho "$(uname -m)" "$PURPLE" 1
  spacer
  if [ -f "$_HI_LINUX_PATH" ]; then
    cecho "$(grep PRETTY_NAME "$_HI_LINUX_PATH" | cut -d= -f2 | tr -d '"')" "$GREEN" 1
    spacer
    cecho "CPUs: $(nproc)" "$BLUE" 1
    spacer
    cecho "RAM: $(free -h --giga | awk '/^Mem:/ {print $2}GB') " "$CYAN"
  else
    local system_info
    system_info=$(system_profiler SPHardwareDataType)
    cecho "macOS $(sw_vers -productVersion)" "$BLUE" 1
    spacer
    cecho "CPUs: $(echo "$system_info" | grep -e Cores | awk '{ print $5 }')" "$BLUE" 1
    spacer
    cecho "RAM: $(echo "$system_info" | grep -e Memory | awk '{ print $2 }')GB" "$CYAN"
  fi
}

function git_keys_docker_line() {
  spacer
  if [ -f "$_HI_HOME_GIT_CONFIG" ]; then
    cecho "Git ID: " "$CYAN" 1
    cecho "$(grep email "$_HI_HOME_GIT_CONFIG" | tail -n1 | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }')" "$YELLOW" 1
  else
    cecho "No Git ID Found..." "$YELLOW" 1
  fi
  spacer
  if command -v "docker" &>/dev/null; then
    cecho "Containers: $(docker container ls | wc -l | awk '{ print $1 - 1 }')" "$BLUE" 1
  else
    cecho "No docker :(" "$BRYELLOW" 1
  fi
  spacer
  if [ -f "$_HI_SSH_AUTHORIZED_KEYS" ]; then
    cecho "Auth: $(wc -l "$_HI_SSH_AUTHORIZED_KEYS" | awk '{ print $1 }')" "$RED" 1
  else
    cecho "Auth: 0!" "$RED" 1
  fi
  spacer
  cecho "Pub: $(find "$_HI_SSH_KEY_DIR" -type f -name "*.pub" | wc -l | awk '{ print $1 }')" "$PURPLE"
}
