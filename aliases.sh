#!/bin/sh
# colors
export RED='\e[0;31m'      # 1
export GREEN='\e[0;32m'    # 2
export YELLOW='\e[0;33m'   # 3
export BLUE='\e[0;34m'     # 4
export PURPLE='\e[0;35m'   # 5
export CYAN='\e[0;36m'     # 6
export BRRED='\e[1;31m'    # 7
export BRGREEN='\e[1;32m'  # 8
export BRYELLOW='\e[1;33m' # 9
export BRBLUE='\e[1;34m'   # 10
export BRPURPLE='\e[1;35m' # 11
export BRCYAN='\e[1;36m'   # 12
export NC='\e[0m'          # 13

# exported here since we have to wrap the bat/batcat call per shell
export bat_opts="-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid,numbers"

# docker
alias dcl="docker container ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"

# ls
alias ls="ls -lh --color=auto"
alias lsa="ls -alh --color=auto"

# grep
alias grep="grep --color=auto"

# git
alias gi="git"
alias gp="git pull"
alias gf="git fetch -a"
alias gs="git status"
alias gd="git diff --color=always"

# for timestamping
alias now="date -u '+%a %b %e %H:%M:%S %Z %Y'; date '+%a %b %e %H:%M:%S %Z %Y'; date +%s"

# prevent mispellings
alias chron="cron"
alias chrontab="crontab"
alias zed="zeditor"
alias view="vew" # here to prevent calling vi

# hi/sshrc custom aliases
alias hi="sshrc" # wraps our override function
alias hii="ssh"
alias hey="hii"
alias vs="version"

# pacman/yay updates
alias yayy="yay -Syyu"
alias yayc="yay -Sc"

# editing this folder
alias esshrc="zed ~/.sshrc.d"

# status of a node (currently in trial on multiple machines)
alias glance="glances --fetch"

# in trial
alias nollama='docker compose -f /home/$USER/projects/csd-selfhost/ollama/compose.yml down'
alias yollama='docker compose -f /home/$USER/projects/csd-selfhost/ollama/compose.yml up -d'
alias zy="yollama && zed"
alias zn="nollama && killall zed-editor"
