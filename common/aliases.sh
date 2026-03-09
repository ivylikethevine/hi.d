#!/bin/sh

# colors
export RED='\e[0;31m'
export GREEN='\e[0;32m'
export YELLOW='\e[0;33m'
export BLUE='\e[0;34m'
export PURPLE='\e[0;35m'
export CYAN='\e[0;36m'
export BRRED='\e[1;31m'
export BRGREEN='\e[1;32m'
export BRYELLOW='\e[1;33m'
export BRBLUE='\e[1;34m'
export BRPURPLE='\e[1;35m'
export BRCYAN='\e[1;36m'
export NC='\e[0m'

# ssh custom aliases
alias hii="ssh"
alias hey="hii"

alias newkey='ssh-keygen -t ed25519 -f "/home/$USER/.ssh/$(date -Is)" -P '' -C '''

alias ssh-keys="ls -alhR --color=auto ~/.ssh"
alias ssh-authorized="nano ~/.ssh/authorized_keys"
alias ssh-known="cat ~/.ssh/known_hosts"
alias ssh-config="cat ~/.ssh/config"

# exported here since we have to wrap the bat/batcat call per shell
export bat_opts="-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid,numbers"

# docker
alias dcl="docker container ls && docker compose ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"

# ls
alias ls="ls -lh --color=auto"
alias lsa="ls -lha --color=auto"
alias lsd="ls -lhd .* --color=auto"
alias lsr="ls -lhaR --color=auto"

# grep
alias grep="grep --color=auto"

# git
alias gl="git log -1"
alias gf="git fetch -a"
alias gp="git fetch -a && git pull"
alias gs="git status"
alias gst="git stash"
alias gd="git diff --color=always"
alias gps="echo ' Okay. Where are we going?'"
alias gpsh='git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)'

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
alias yaycc="sudo rm -rf '/var/cache/pacman/pkg/download-*'"

# apt updates
alias aptup="sudo apt update"
alias aptug="sudo apt upgrade"
alias aptupg="sudo apt update && sudo apt upgrade"
alias aptac="sudo apt autoclean && sudo apt autoremove"

# save my fingers
alias sctl="sudo systemctl"

# time
export human_short_date_format="+%b %-e %y %H:%M %Z"
alias now='date $human_short_date_format && date -u $human_short_date_format'

# editing this folder
alias rehi="sudo rm /usr/bin/hi && sudo ln ~/.hi.d/hi.sh /usr/bin/hi"
alias ehi="zed ~/.hi.d"
alias essh="zed ~/.ssh"

# works in bash, fish has a wrapper for sudo in config.fish
alias sudo="command sudo "
# shellcheck disable=SC2139
alias nano="nano --rcfile $HI_ROOT/.hi.d/optional/nano.rc"
# shellcheck disable=SC2139
alias vim="vim -u $HI_ROOT/.hi.d/optional/vim.rc"
