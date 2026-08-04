#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
set -eou pipefail

# shellcheck disable=SC2010
_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"
# shellcheck source=./common/check.sh
source "$_HI_CHECK"
# shellcheck source=./common/header.sh
command -v spacer >/dev/null || source "$_HI_TMPDIR/hi.d/common/header.sh"

export _HI_CONFIG_START="# hi-config-start"
export _HI_CONFIG_END="# hi-config-end"
export _HI_COPY_TIME=-1

# required
function configure_file() {
  local source=${1}
  local target=${2}
  touch "$target"
  if test -f "$source"; then
    if ! grep -q "$_HI_CONFIG_START" "$target"; then
      {
        echo "$_HI_CONFIG_START"
        cat "$source"
        echo "$_HI_CONFIG_END"
      } >>"$target"
    fi
  fi
}

# required
function clean_all() {
  local shells
  if [ -d "$_HI_FISH_DIR" ]; then
    shells=("$_HI_HOME_BASHRC" "$_HI_HOME_ZSHRC" "$_HI_HOME_FISH_CONFIG")
  else
    shells=("$_HI_HOME_BASHRC" "$_HI_HOME_ZSHRC")
  fi
  for shell in "${shells[@]}"; do
    # Double up on sed's just to be sure
    if test -f "$shell"; then
      if [ -f "$_HI_LINUX_PATH" ]; then
        sed -i "/^$_HI_CONFIG_START/,/^$_HI_CONFIG_END/d" -- "$shell"
        sed -i "/^$_HI_CONFIG_START/,/^$_HI_CONFIG_END/d" -- "$shell"
      else
        sed -i '' "/^$_HI_CONFIG_START/,/^$_HI_CONFIG_END/d" "$shell"
        sed -i '' "/^$_HI_CONFIG_START/,/^$_HI_CONFIG_END/d" "$shell"
      fi
    fi
  done
  rm -rfv "$_HI_TMPDIR/hi.d"
}

# required
function timers() {
  spacer
  cecho "load: $(echo "$(perl -MTime::HiRes=time -e 'printf "%.3f", time') $load_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')s | copy: ${_HI_COPY_TIME}s"
}

# required
function load() {
  local load_start_time host_color linux_flags
  load_start_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"

  if [[ -z ${ZSH_VERSION+x} ]]; then
    trap 'clean_all' exit
  else
    # shellcheck disable=SC2329
    TRAPEXIT() { clean_all; }
  fi

  host_color=$(host_color "$(hostname)")
  printf '%b\n' "${BRGREEN} ~~ Connected ${NC}[${host_color}$(hostname)${NC}]${BRGREEN} ~~~~~~~~~~~~~~~~~~~~~~~${NC}"
  timestamp

  system_info_line
  git_keys_docker_line
  printf '%b\n' "$(full_check)"

  spacer
  if command -v "vim" &>/dev/null; then
    # Will cause errors if we load this with only VI
    export VIMINIT="let \$MYVIMRC='$_HI_VIMRC' | source \$MYVIMRC"
  fi
  configure_file "$_HI_BASH_CONFIG" "$_HI_HOME_BASHRC"
  configure_file "$_HI_ZSH_CONFIG" "$_HI_HOME_ZSHRC"
  if [ -d "$_HI_FISH_DIR" ]; then
    # This directory won't exist if fish isn't installed
    configure_file "$_HI_FISH_CONFIG" "$_HI_HOME_FISH_CONFIG"
  fi
  cecho "hi loaded with... " "$BRCYAN" 1

  if command -v "fish" &>/dev/null; then
    cecho "fish shell! :^)" "$GREEN" 1
    timers
    fish -C "set fish_greeting ''" -i
  elif command -v "zsh" &>/dev/null; then
    cecho "zsh shell! :)" "$PURPLE" 1
    timers
    zsh -i
  else
    cecho "only bash today :(" "$RED" 1
    timers
    bash -i
  fi

  if [ -f /etc/os-release ]; then
    linux_flags="--apparent-size"
  fi

  cecho " $(du -sh $linux_flags "$_HI_ROOT" | awk '{ print $1 }') " "$NC" 1
  printf '%b\n' "${BRRED}~~~~~~~~~~~~~~~~~~~~~ Disconnected ${NC}[$host_color$(hostname)${NC}]$BRRED ~~~~~~~~~~~~~~~~~~~~~~~${NC}"
  timestamp
  cecho "hi closing! " "$BRPURPLE"
  exit 0
}
