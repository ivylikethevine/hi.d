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

# TODO: Test
function tmuxrc() {
  local TMUXDIR="/tmp/tmuxrc"
  if ! [ -d "$TMUXDIR" ]; then
    rm -rf "$TMUXDIR"
    mkdir -p "$TMUXDIR"
  fi
  rm -rf "$TMUXDIR"/hi.d
  cp -r "$_HI_ROOT"/bashrc.hi "$_HI_ROOT"/hi "$_HI_ROOT"/hi.d "$TMUXDIR"
  _HI_ROOT="$TMUXDIR" SHELL="$TMUXDIR"/bashrc.hi /usr/bin/tmux -S "$TMUXDIR"/tmuxserver "$@"
  SHELL=$(which bash)
  export SHELL
}

# required
function load() {
  local load_start_time
  load_start_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  load_packages

  if [[ -z ${ZSH_VERSION+x} ]]; then
    trap 'clean_all' exit
  else
    # shellcheck disable=SC2329
    TRAPEXIT() { clean_all; }
  fi

  local HOST_COLOR
  HOST_COLOR=$(host_color "$(hostname)")
  printf '%b\n' "${BRGREEN} ~~ Connected ${NC}[${HOST_COLOR}$(hostname)${NC}]${BRGREEN} ~~~~~~~~~~~~~~~~~~~~~~~${NC}"
  timestamp

  # optional header items
  system_info_line
  git_keys_docker_line
  printf '%b\n' "$(full_check)"

  # back to required configuration
  spacer
  # Determine if target has hi.d installed, then skip loading copied code if possible
  # shellcheck disable=SC2010
  if [ -d "/home/$USER/hi.d/" ]; then
    cecho "hi on target (native): " "$BRGREEN" 1
  elif [ "$(ls -l /tmp | grep -e "^d.*$USER}hi\." -c)" -gt 1 ]; then
    # export _HI_TMPDIR="/tmp/$USER.hi.*"
    cecho "hi on target (copied): " "$BRGREEN" 1
  else
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
  fi

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

  local linux_flags=""
  if [ -f /etc/os-release ]; then
    linux_flags="--apparent-size"
  fi

  cecho " $(du -sh $linux_flags "$_HI_ROOT" | awk '{ print $1 }') " "$NC" 1
  printf '%b\n' "${BRRED}~~~~~~~~~~~~~~~~~~~~~ Disconnected ${NC}[$HOST_COLOR$(hostname)${NC}]$BRRED ~~~~~~~~~~~~~~~~~~~~~~~${NC}"
  timestamp
  cecho "hi closing! " "$BRPURPLE"
  exit 0
}
