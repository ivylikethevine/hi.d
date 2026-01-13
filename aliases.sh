#!/bin/sh

alias dcl="docker container ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"

alias ls="ls -lh --color=auto"
alias lsa="ls -alh --color=auto"
alias grep="grep --color=auto"

alias gi="git"
alias gp="git pull"
alias gf="git fetch -a"
alias gs="git status"
alias gd="git diff --color=always"

# end sh-compatible aliases

# exported here since we have to wrap the bat/batcat call per shell
export bat_opts="-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid,numbers"

alias chron="cron"
alias chrontab="crontab"
alias view="vew" # here to avoid calling vi (and each shell has their own vew functions)
alias hi="sshrc" # wraps our override function
alias hii="ssh"
alias hey="hii"
alias zed="zeditor"

alias nollama='docker compose -f /home/$USER/projects/csd-selfhost/ollama/compose.yml down'
alias yollama='docker compose -f /home/$USER/projects/csd-selfhost/ollama/compose.yml up -d'
alias zy="yollama && zed"
alias zn="nollama && killall zed-editor"

alias yayy="yay -Syyu"
alias yayc="yay -Sc"

alias esshrc="zed ~/.sshrc.d"

export RED='\e[0;31m' # 1
export GREEN='\e[0;32m' # 2
export YELLOW='\e[0;33m' # 3
export BLUE='\e[0;34m' # 4
export PURPLE='\e[0;35m' # 5
export CYAN='\e[0;36m' # 6
export BRRED='\e[1;31m' # 7
export BRGREEN='\e[1;32m' # 8
export BRYELLOW='\e[1;33m' # 9
export BRBLUE='\e[1;34m' # 10
export BRPURPLE='\e[1;35m' # 11
export BRCYAN='\e[1;36m' # 12
export NC='\e[0m' # 13
