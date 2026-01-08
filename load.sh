#!/bin/sh
start=$(date +%s.%N)
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
BLUE='\e[0;34m'
PURPLE='\e[0;35m'
CYAN='\e[0;36m'
BRRED='\e[1;31m'
BRGREEN='\e[1;32m'
BRYELLOW='\e[1;33m'
BRBLUE='\e[1;34m'
BRPURPLE='\e[1;35m'
BRCYAN='\e[1;36m'
NC='\e[0m'

sshrc_start="# sshrc-config-start"
sshrc_end="# sshrc-config-end"

cecho() {
  echo -e "$2$1$NC"
}

cecho_n() {
  echo -ne "$2$1$NC"
}

spacer() {
  cecho_n " | " $NC
}

timestamp() {
  spacer
  echo -e "$BRBLUE$(date -u "+%a %b %e %H:%M:%S %Z %Y")   $NC|$BRYELLOW   $(date "+%a %b %e %H:%M:%S %Z %Y")$NC"
  spacer
}

configure_file() {
  touch $1
  if ! grep -q "$sshrc_start" $1; then
    echo "$sshrc_start" >>$1
    cat "$SSHHOME/.sshrc.d/$2" >>$1
    echo "$sshrc_end" >>$1
  fi
}

clean_file() {
  if test -f $1; then
    sed -i "/^$sshrc_start/,/^$sshrc_end/d" -- $1
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
  configure_file ~/.bashrc bash.rc
  configure_file ~/.zshrc zsh.rc
  configure_file ~/.aliasesrc aliases.rc
  if command -v "fish" &>/dev/null; then
    # This path won't exist if fish isn't installed
    configure_file ~/.config/fish/config.fish config.fish
  fi
}

system_info() {
  cecho_n "$(uname -s)" $YELLOW
  spacer
  cecho_n "$(uname -m)" $PURPLE
  spacer
  cecho_n "$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')" $GREEN
  spacer
  cecho_n "CPUs: $(nproc)" $BLUE
  spacer
  cecho "RAM: $(free -h --giga | awk '/^Mem:/ {print $2}GB') " $CYAN
}

git_identity() {
  spacer
  if [ -f ~/.gitconfig ]; then
    cecho_n "Git Identity: " $CYAN
    cecho_n "$(cat ~/.gitconfig | grep email | cut -d= -f2 | tr -d ' ' | awk -F@ '{for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c=""}')" $YELLOW
  else
    cecho_n "No Git Identity Found..." $YELLOW
  fi
}

docker_count() {
  spacer
  if command -v "docker" &>/dev/null; then
    cecho_n "Containers: $(docker container ls | wc -l | awk '{print $1 - 1}')" $BLUE
  else
    cecho_n "No docker :(" $BRYELLOW
  fi
}

key_count() {
  spacer
  cecho_n "Auth: $(ls ~/.ssh | grep authorized_keys | wc -l)" $RED
  spacer
  cecho "Pub: $(ls ~/.ssh | grep .pub | wc -l)" $PURPLE
}

timers() {
  spacer
  cecho_n "load: $(echo "$(date +%s.%N) - $start" | bc -l | awk '{printf "%.3f\n", $1}')s"
  spacer
  copy_time # created by hi.sh to show time to copy over info
}

check_packages() {
  source $SSHHOME/.sshrc.d/check.rc
  spacer
  installed
  spacer
  systems
  cecho_n "| " $NC
  missing
}

say_hi() {
  minimal=false # can also modify in ~/.sshrc

  trap 'clean_all' EXIT
  cecho '~~~~~~~~~~~~~~~~~~~~~~~~ Connected! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~' $BRGREEN
  timestamp
  system_info
  if [ "$minimal" = false ]; then
    git_identity
    docker_count
    key_count
    check_packages
  fi
  configure_all
  spacer
  cecho_n "sshrc loaded with... " $PURPLE

  if command -v "fish" &>/dev/null; then
    cecho_n "fish shell! :^)" $GREEN
    timers
    fish -C "source $SSHHOME/.sshrc.d/aliases.rc && set fish_greeting ''" -i
  elif command -v "zsh" &>/dev/null; then
    cecho_n "zsh shell! :)" $PURPLE
    timers
    zsh -i
  else
    cecho_n "only bash today :(" $RED
    timers
    bash -i
  fi

  # sshrc_exclude is adding to load.sh by hi.sh
  cecho_n " $(du -sh $sshrc_exclude --apparent-size $SSHHOME/.sshrc.d | awk '{ print $1 }') " $NC
  cecho '~~~~~~~~~~~~~~~~~~~~~~~ Disconnected! ~~~~~~~~~~~~~~~~~~~~~~~~~~' $BRRED
  timestamp
  cecho_n "sshrc closing! " $BRPURPLE
  exit 0
}
