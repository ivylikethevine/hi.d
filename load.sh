#!/bin/bash
RED='\e[0;31m'      # 1
GREEN='\e[0;32m'    # 2
YELLOW='\e[0;33m'   # 3
BLUE='\e[0;34m'     # 4
PURPLE='\e[0;35m'   # 5
CYAN='\e[0;36m'     # 6
BRRED='\e[1;31m'    # 7
BRGREEN='\e[1;32m'  # 8
BRYELLOW='\e[1;33m' # 9
BRBLUE='\e[1;34m'   # 10
BRPURPLE='\e[1;35m' # 11
BRCYAN='\e[1;36m'   # 12
NC='\e[0m'          # 13

hi_start="# hi-config-start"
hi_end="# hi-config-end"

minimal=${minimal:-}

HI_HOME=${HI_HOME:-$HOME/.hi.d}
hi_exclude=${hi_exclude:-'--exclude .git --exclude .gitignore --exclude README.md --exclude stubs --exclude reports --exclude scripts'}
start=$(date +%s.%N)
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
INSTALL_PATH="$(readlink -f "$SCRIPT_DIR/../")"
export INSTALL_PATH

export human_centric_date_format="+%a %b %-e %Y %H:%M:%S %Z"
export human_short_date_format="+%b %-e %y %H:%M %Z"
export human_precise_date_format="+%a %b %-e %Y %H:%M:%S.%3N %Z"
export file_short_date_format="+%m-%d-%Y-%H:%M-%Z"
export file_verbose_date_format="+%a-%m-%d-%Y-%H:%M:%S-%Z"
export file_precise_date_format="+%a-%m-%d-%Y-%H:%M:%S.%3N-%Z"

copy_time=-1

cecho() {
  local formatted_text="$2$1$NC"
  local disable_newline="$3"

  if [[ -n "$disable_newline" ]]; then
    echo -e -n "$formatted_text";
  else
    echo -e "$formatted_text";
  fi
}

spacer() {
  cecho " | " "$NC" 1
}

timestamp() {
  spacer
  echo -e "$BRBLUE$(date -u "$human_centric_date_format")   $NC|$BRYELLOW   $(date "$human_centric_date_format")$NC"
  spacer
}

configure_file() {
  touch "$1"
  if test -f "$1"; then
    if test -f "$HI_HOME/.hi.d/$2"; then
      if ! grep -q "$hi_start" "$1"; then
        {
          echo "$hi_start"
          cat "$HI_HOME/.hi.d/$2"
          echo "$hi_end"
        } >>"$1"
      fi
    fi
  fi
}

# false positive?
# shellcheck disable=SC2329
clean_file() {
  if test -f "$1"; then
    sed -i "/^$hi_start/,/^$hi_end/d" -- "$1"
  fi
}

# false positive?
# shellcheck disable=SC2329
clean_all() {
  clean_file ~/.bashrc
  clean_file ~/.zshrc
  clean_file ~/.nanorc
  clean_file ~/.config/fish/config.fish
}

# TODO: Support /etc/profile + similar for root accounts (only when logging in as root)
configure_all() {
  if command -v "vim" &>/dev/null; then
    # Will cause errors if we load this with only VI
    export VIMINIT="let \$MYVIMRC='$HI_HOME/.hi.d/vim.rc' | source \$MYVIMRC"
  fi
  configure_file ~/.nanorc nano.rc
  configure_file ~/.bashrc bash.sh
  configure_file ~/.zshrc zsh.zsh
  if [ -f ~/.config/fish/config.fish ]; then
    # This path won't exist if fish isn't installed
    configure_file ~/.config/fish/config.fish config.fish
  fi
}

system_info() {
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

git_identity() {
  spacer
  if [ -f ~/.gitconfig ]; then
    cecho "Git ID: " "$CYAN" 1
    cecho "$(grep email ~/.gitconfig | tail -n1 | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }')" "$YELLOW" 1
  else
    cecho "No Git ID Found..." "$YELLOW" 1
  fi
}

docker_count() {
  spacer
  if command -v "docker" &>/dev/null; then
    cecho "Containers: $(docker container ls | wc -l | awk '{ print $1 - 1 }')" "$BLUE" 1
  else
    cecho "No docker :(" "$BRYELLOW" 1
  fi
}

key_count() {
  spacer
  if [ -f ~/.ssh/authorized_keys ]; then
    cecho "Auth: $(wc -l ~/.ssh/authorized_keys | awk '{ print $1 }')" "$RED" 1
  else
    cecho "Auth: 0!" "$RED" 1
  fi
  spacer
  cecho "Pub: $(find ~/.ssh -type f -name "*.pub" | wc -l)" "$PURPLE"
}

timers() {
  spacer
  cecho "load: $(echo "$(date +%s.%N) $start" | awk '{ printf "%.3f\n", $1 - $2 }')s | copy: ${copy_time}s"
}

check_packages() {
  # shellcheck source=./check.sh
  source "$HI_HOME"/.hi.d/check.sh
  if [ "$minimal" = false ]; then
    packages
    basics
  fi
  systems
  tools
}

# TODO: Add tmux support + handle disconnects/reconnects/older sessions
# shellcheck disable=SC2329
tmuxrc() {
  local TMUXDIR="/tmp/tmuxrc"
  if ! [ -d "$TMUXDIR" ]; then
    rm -rf "$TMUXDIR"
    mkdir -p "$TMUXDIR"
  fi
  rm -rf "$TMUXDIR"/.hi.d
  cp -r "$HI_HOME"/.hi "$HI_HOME"/bashhi "$HI_HOME"/hi "$HI_HOME"/.hi.d "$TMUXDIR"
  HI_HOME="$TMUXDIR" SHELL="$TMUXDIR"/bashhi /usr/bin/tmux -S "$TMUXDIR"/tmuxserver "$@"
  # export SHELL=`which bash`
  # tmuxrc
}

load() {
  minimal=false

  trap 'clean_all' exit
  cecho '~~~~~~~~~~~~~~~~~~~~~~~~ Connected! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~' "$BRGREEN"
  timestamp
  system_info
  if [ "$minimal" = false ]; then
    git_identity
    docker_count
    key_count
  fi
  check_packages
  configure_all
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

  # hi_exclude is appended to load.sh by hi.sh during the transfer
  # shellcheck disable=SC2086
  cecho " $(du -sh $hi_exclude --apparent-size "$HI_HOME"/.hi.d | awk '{ print $1 }') " "$NC" 1
  cecho '~~~~~~~~~~~~~~~~~~~~~~~ Disconnected! ~~~~~~~~~~~~~~~~~~~~~~~~~~' "$BRRED"
  timestamp
  cecho "hi closing! " "$BRPURPLE" 1
  exit 0
}
