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

# ssh custom aliases
alias hii="ssh"
alias hey="hii"
alias ssh-keys="ls -alhR --color=auto ~/.ssh"
alias ssh-authorized="nano ~/.ssh/authorized_keys"
alias ssh-known="cat ~/.ssh/known_hosts"
alias ssh-config="cat ~/.ssh/config"
alias newkey='ssh-keygen -t ed25519 -f "/home/$USER/.ssh/$(date -Is)" -P '' -C '''
# user customization goes below =============

# exported here since we have to wrap the bat/batcat call per shell
export bat_opts="-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid,numbers"

# docker
alias dcl="docker container ls && docker compose ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"

# ls
alias ls="ls -lh --color=auto"
alias lsa="ls -alh --color=auto"
alias lsd="ls -ld .* --color=auto"

# grep
alias grep="grep --color=auto"

# git
alias gi="git"
alias gp="git pull"
alias gf="git fetch -a"
alias gs="git status"
alias gst="git stash"
alias gps="git fetch && git pull && git status"
alias gd="git diff --color=always"
alias gps="echo where are we going?"

# ping
alias ping="ping -O"

# ip
alias ip="ip -color=always"
alias ips="ip -br a"
alias myip="ip route get 1.1.1.1"

# prevent mispellings
alias chron="cron"
alias chrontab="crontab"
alias zed="zeditor"
alias view="vew" # here to prevent calling vi
alias vs="version"

# pacman/yay updates
alias yayy="yay -Syyu"
alias yayc="yay -Sc"
alias yayc="sudo rm -rf /var/cache/pacman/pkg/download-*"

# apt updates
alias aptu="sudo apt update"
alias aptup="sudo apt upgrade"
alias aptuc="sudo apt update && sudo apt upgrade"
alias aptac="sudo apt autoclean && sudo apt autoremove"

# save my fingers
alias sctl="sudo systemctl"

# time
export human_short_date_format="+%b %-e %y %H:%M %Z"
alias now='date $human_short_date_format && date -u $human_short_date_format'

# editing this folder
alias ehi="zed ~/.hi.d"
