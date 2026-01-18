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

sshrc_start="# sshrc-config-start"
sshrc_end="# sshrc-config-end"

minimal=${minimal:-}
sshrc_exclude=${sshrc_exclude:-'--exclude .git --exclude stubs --exclude reports --exclude README.md --exclude tests'}
start=$(date +%s.%N)

cecho() {
  echo -e "$2$1$NC"
}

cecho_n() {
  echo -ne "$2$1$NC"
}

spacer() {
  cecho_n " | " "$NC"
}

timestamp() {
  spacer
  echo -e "$BRBLUE$(date -u "+%a %b %e %H:%M:%S %Z %Y")   $NC|$BRYELLOW   $(date "+%a %b %e %H:%M:%S %Z %Y")$NC"
  spacer
}

configure_file() {
  touch "$1"
  if test -f "$1"; then
    if ! grep -q "$sshrc_start" "$1"; then
      {
        echo "$sshrc_start"
        cat "$SSHHOME/.sshrc.d/$2"
        echo "$sshrc_end"
      } >>"$1"
    fi
  fi
}

clean_file() {
  if test -f "$1"; then
    sed -i "/^$sshrc_start/,/^$sshrc_end/d" -- "$1"
  fi
}

clean_all() {
  clean_file ~/.bashrc
  clean_file ~/.zshrc
  clean_file ~/.nanorc
  clean_file ~/.config/fish/config.fish
  if [ -f ~/.aliasesrc ]; then
    rm -f ~/.aliasesrc
  fi
  if [ -f ~/.hushlogin ]; then
    rm -f ~/.hushlogin
  fi
}

configure_all() {
  if command -v "vim" &>/dev/null; then
    # Will cause errors if we load this with only VI
    export VIMINIT="let \$MYVIMRC='$SSHHOME/.sshrc.d/vim.rc' | source \$MYVIMRC"
  fi
  configure_file ~/.nanorc nano.rc
  configure_file ~/.bashrc bash.sh
  configure_file ~/.zshrc zsh.zsh
  configure_file ~/.aliasesrc aliases.sh
  if command -v "fish" &>/dev/null; then
    # This path won't exist if fish isn't installed
    configure_file ~/.config/fish/config.fish config.fish
  fi
}

system_info() {
  cecho_n "$(uname -s)" "$YELLOW"
  spacer
  cecho_n "$(uname -m)" "$PURPLE"
  spacer
  cecho_n "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')" "$GREEN"
  spacer
  cecho_n "CPUs: $(nproc)" "$BLUE"
  spacer
  cecho "RAM: $(free -h --giga | awk '/^Mem:/ {print $2}GB') " "$CYAN"
}

git_identity() {
  spacer
  if [ -f ~/.gitconfig ]; then
    cecho_n "Git ID: " "$CYAN"
    cecho_n "$(grep email ~/.gitconfig | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }')" "$YELLOW"
  else
    cecho_n "No Git ID Found..." "$YELLOW"
  fi
}

docker_count() {
  spacer
  if command -v "docker" &>/dev/null; then
    cecho_n "Containers: $(docker container ls | wc -l | awk '{ print $1 - 1 }')" "$BLUE"
  else
    cecho_n "No docker :(" "$BRYELLOW"
  fi
}

key_count() {
  spacer
  if [ -f ~/.ssh/authorized_keys ]; then
    cecho_n "Auth: $(wc -l ~/.ssh/authorized_keys | awk '{ print $1 }')" "$RED"
  else
    cecho_n "Auth: 0!" "$RED"
  fi
  spacer
  cecho "Pub: $(find ~/.ssh -type f -name "*.pub" | wc -l)" "$PURPLE"
}

timers() {
  spacer
  cecho_n "load: $(echo "$(date +%s.%N) $start" | awk '{ printf "%.3f\n", $1 - $2 }')s"
  spacer
  copy_time # created by hi.sh to show time to copy over info
}

check_packages() {
  source "$SSHHOME"/.sshrc.d/check.sh
  spacer
  systems
  echo
  spacer
  tools
  echo

  if [ "$minimal" = false ]; then
    spacer
    basics
    echo
    spacer
    installed
    echo
    spacer
    missing
    echo
  fi
}

# TODO: Add tmux support + handle disconnects/reconnects/older sessions
tmuxrc() {
  local TMUXDIR=/tmp/tmuxrc
  if ! [ -d $TMUXDIR ]; then
    rm -rf $TMUXDIR
    mkdir -p $TMUXDIR
  fi
  rm -rf $TMUXDIR/.sshrc.d
  cp -r "$SSHHOME"/.sshrc "$SSHHOME"/bashsshrc "$SSHHOME"/sshrc "$SSHHOME"/.sshrc.d "$TMUXDIR"
  SSHHOME="$TMUXDIR" SHELL="$TMUXDIR"/bashsshrc /usr/bin/tmux -S "$TMUXDIR"/tmuxserver "$@"
}
# export SHELL=`which bash`
# tmuxrc

say_hi() {
  # minimal=false # can also modify in ~/.sshrc

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
  cecho_n "sshrc loaded with... " "$BRCYAN"

  if command -v "fish" &>/dev/null; then
    cecho_n "fish shell! :^)" "$GREEN"
    timers
    fish -C "set fish_greeting ''" -i
  elif command -v "zsh" &>/dev/null; then
    cecho_n "zsh shell! :)" "$PURPLE"
    timers
    zsh -i
  else
    cecho_n "only bash today :(" "$RED"
    timers
    bash -i
  fi

  # sshrc_exclude is appended to load.sh by hi.sh during the transfer
  # can't fix the shellcheck error below
  cecho_n " $(du -sh $sshrc_exclude --apparent-size "$SSHHOME"/.sshrc.d | awk '{ print $1 }') " "$NC"
  cecho '~~~~~~~~~~~~~~~~~~~~~~~ Disconnected! ~~~~~~~~~~~~~~~~~~~~~~~~~~' "$BRRED"
  timestamp
  cecho_n "sshrc closing! " "$BRPURPLE"
  exit 0
}
