#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if ! command cecho 2>/dev/null; then
  # shellcheck source=./common/prompt_colors.sh
  source "$SCRIPT_DIR/common/prompt_colors.sh"
fi

export hi_config_start="# hi-config-start"
export hi_config_end="# hi-config-end"
export hi_copy_time=-1

# # # See: hi.sh/say_hi()
# # On local machines, ~/.hi.d has our configs.
# # On remote machines, we need to go to /tmp/.(whoami).hi.XXXX/.hi.d
HI_TMPDIR=${HI_TMPDIR:-~}
HI_ROOT=${HI_TMPDIR:-~}/.hi.d

# required
function spacer() {
  cecho " | " "$NC" 1
}

# required
function timestamp() {
  spacer
  local human_centric_date_format="+%a %b %-e %Y %H:%M:%S %Z"
  echo -e "$BRBLUE$(date -u "$human_centric_date_format")   $NC|$BRYELLOW   $(date "$human_centric_date_format")$NC"
  spacer
}

# required
function configure_file() {
  local target="$1"
  local source="$2"
  touch "$target"
  if test -f "$HI_ROOT/$source"; then
    if ! grep -q "$hi_config_start" "$target"; then
      {
        echo "$hi_config_start"
        cat "$HI_ROOT/$source"
        echo "$hi_config_end"
      } >>"$target"
    fi
  fi
}

# required
function clean_all() {
  local shells=(~/.bashrc ~/.zshrc ~/.config/fish/config.fish)
  for shell in "${shells[@]}"; do
    if test -f "$shell"; then
      sed -i "/^$hi_config_start/,/^$hi_config_end/d" -- "$shell"
    fi
  done
}

# required
function timers() {
  spacer
  cecho "load: $(echo "$(date +%s.%N) $load_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')s | copy: ${hi_copy_time}s"
}

function check_packages() {
  # shellcheck source=./common/check.sh
  source "$HI_ROOT"/common/check.sh
  packages
  basics
  systems
  tools
}

function system_info() {
  cecho "$(uname -s)" "$YELLOW" 1
  spacer
  cecho "$(uname -m)" "$PURPLE" 1
  spacer
  cecho "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')" "$GREEN" 1
  spacer
  cecho "CPUs: $(nproc)" "$BLUE" 1
  spacer
  cecho "RAM: $(free -h --giga | awk '/^Mem:/ {print $2}GB') " "$CYAN"
}

function git_identity() {
  spacer
  if [ -f ~/.gitconfig ]; then
    cecho "Git ID: " "$CYAN" 1
    cecho "$(grep email ~/.gitconfig | tail -n1 | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }')" "$YELLOW" 1
  else
    cecho "No Git ID Found..." "$YELLOW" 1
  fi
}

function docker_count() {
  spacer
  if command -v "docker" &>/dev/null; then
    cecho "Containers: $(docker container ls | wc -l | awk '{ print $1 - 1 }')" "$BLUE" 1
  else
    cecho "No docker :(" "$BRYELLOW" 1
  fi
}

function key_count() {
  spacer
  if [ -f ~/.ssh/authorized_keys ]; then
    cecho "Auth: $(wc -l ~/.ssh/authorized_keys | awk '{ print $1 }')" "$RED" 1
  else
    cecho "Auth: 0!" "$RED" 1
  fi
  spacer
  cecho "Pub: $(find ~/.ssh -type f -name "*.pub" | wc -l)" "$PURPLE"
}

# TODO: Test
# shellcheck disable=SC2329
function tmuxrc() {
  local TMUXDIR="/tmp/tmuxrc"
  if ! [ -d "$TMUXDIR" ]; then
    rm -rf "$TMUXDIR"
    mkdir -p "$TMUXDIR"
  fi
  rm -rf "$TMUXDIR"/.hi.d
  cp -r "$HI_ROOT"/bashrc.hi "$HI_ROOT"/hi "$HI_ROOT"/.hi.d "$TMUXDIR"
  HI_ROOT="$TMUXDIR" SHELL="$TMUXDIR"/bashrc.hi /usr/bin/tmux -S "$TMUXDIR"/tmuxserver "$@"
  SHELL=$(which bash)
  export SHELL
}

# required
function load() {
  local load_start_time
  load_start_time=$(date +%s.%N)

  trap 'clean_all' exit

  local HOST_COLOR
  HOST_COLOR=$(host_color "$(hostname)")
  echo -e "$BRGREEN~~~~~~~~~~~~~~~~~~~ Connected to ${NC}[$HOST_COLOR$(hostname)${NC}]$BRGREEN ~~~~~~~~~~~~~~~~~~~~~~~~$NC"
  timestamp

  # optional header items
  system_info
  git_identity
  docker_count
  key_count
  check_packages

  # back to required configuration
  if command -v "vim" &>/dev/null; then
    # Will cause errors if we load this with only VI
    export VIMINIT="let \$MYVIMRC='$HI_ROOT/misc/vim.rc' | source \$MYVIMRC"
  fi
  configure_file ~/.bashrc shells/bash.sh
  configure_file ~/.zshrc shells/zsh.zsh
  if [ -d ~/.config/fish ]; then
    # This directory won't exist if fish isn't installed
    configure_file ~/.config/fish/config.fish shells/config.fish
  fi

  spacer
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

  cecho " $(du -sh --apparent-size "$HI_ROOT" | awk '{ print $1 }') " "$YELLOW" 1
  echo -e "$BRRED~~~~~~~~~~~~~~~~~ Disconnected from ${NC}[$HOST_COLOR$(hostname)${NC}]$BRRED ~~~~~~~~~~~~~~~~~~~~~$NC"
  timestamp
  cecho "hi closing! " "$BRPURPLE"
  clean_all
  exit 0
}
