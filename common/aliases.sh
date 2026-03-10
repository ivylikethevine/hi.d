#!/bin/sh

# === start required variables/aliases ===
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

export human_short_date_format="+%b %-e %y %H:%M %Z"
alias now='date $human_short_date_format && date -u $human_short_date_format'

# shellcheck disable=SC2139
alias bat="$(command -v bat || command -v batcat) -P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid,numbers"

# works in bash, fish has a wrapper for sudo in config.fish
alias sudo="command sudo "
# shellcheck disable=SC2139
alias nano="nano --rcfile $HI_ROOT/.hi.d/optional/nano.rc"
# shellcheck disable=SC2139
alias vim="vim -u $HI_ROOT/.hi.d/optional/vim.rc"

alias hey="ssh"
alias zed="zeditor"
alias view="vew" # here to prevent calling vi
alias vw="vew"
alias vs="version"

alias ehi="zed ~/.hi.d"
alias essh="zed ~/.ssh"
alias hi_colorgen="~/.hi.d/scripts/create_host_colors.sh"
alias hi_reinstall="~/.hi.d/scripts/install.sh"
alias hi_relink="sudo rm /usr/bin/hi && sudo ln ~/.hi.d/hi.sh /usr/bin/hi"
# === end required variables/aliases ===

alias newkey='ssh-keygen -t ed25519 -f "/home/$USER/.ssh/$(hostname)-$USER-$(date -Im)" -P '' -C '''
alias ssh-keys="ls -alhR --color=auto ~/.ssh"
alias ssh-authorized="nano ~/.ssh/authorized_keys"
alias ssh-known="cat ~/.ssh/known_hosts"
alias ssh-config="cat ~/.ssh/config"

alias dcl="docker container ls && docker compose ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"

alias ls="ls -lh --color=auto"
alias lsa="ls -lha --color=auto"
alias lsd="ls -lhd .* --color=auto"
alias lsr="ls -lhaR --color=auto"

alias grep="grep --color=auto"

alias gl="git log -1"
alias gf="git fetch -a"
alias gp="git fetch -a && git pull"
alias gs="git status"
alias gst="git stash"
alias gd="git diff --color=always"
alias gps="echo ' Okay. Where are we going?'"
alias gpsh='git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)'

alias ping="ping -O"
alias ip="ip -color=always"
alias ips="ip -br a"
alias my_ip="ip route get 1.1.1.1"

# prevent mispellings/save my fingers
alias sctl="sudo systemctl"
alias chron="cron"
alias chrontab="crontab"

# pacman/yay updates
alias yayy="yay -Syyu"
alias yayc="yay -Sc"
alias yaycc="sudo rm -rf '/var/cache/pacman/pkg/download-*'"

# apt updates
alias aptup="sudo apt update"
alias aptug="sudo apt upgrade"
alias aptupg="sudo apt update && sudo apt upgrade"
alias aptac="sudo apt autoclean && sudo apt autoremove"
