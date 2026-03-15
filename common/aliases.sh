#!/bin/sh

# === start required variables/aliases ===
# TODO: Hide/shadow these aliases when on a remote device...
alias hi_colorgen="sh -c 'source ~/hi.d/scripts/colorgen.sh && colorgen'"
alias hi_reinstall="~/hi.d/scripts/install.sh"
alias hi_relink="sudo rm /usr/bin/hi && sudo ln ~/hi.d/hi.sh /usr/bin/hi"

# works in bash, fish has a wrapper for sudo in config.fish
alias sudo="command sudo "
# shellcheck disable=SC2139
alias nano="nano --rcfile $HI_TMPDIR/hi.d/misc/nano.rc"
# shellcheck disable=SC2139
alias vim="vim -u $HI_TMPDIR/hi.d/misc/vim.rc"

# shellcheck disable=SC2139
alias bat="$(command -v bat || command -v batcat) -P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid,numbers"
# === end required variables/aliases ===

export human_short_date_format="+%b %-e %y %H:%M %Z"
alias now='date $human_short_date_format && date -u $human_short_date_format'

alias hey="ssh"
alias zed="zeditor"
alias ehi="zed ~/hi.d"
alias essh="zed ~/.ssh"
alias view="vew" # here to prevent calling vi
alias vw="vew"
alias vs="version"
alias newkey='ssh-keygen -t ed25519 -f "/home/$USER/.ssh/$(hostname)-$USER-$(date -Im)" -P '' -C '''

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
alias yaycc="sudo rm -rf /var/cache/pacman/pkg/download-*"

# apt updates
alias aptup="sudo apt update"
alias aptug="sudo apt upgrade"
alias aptupg="sudo apt update && sudo apt upgrade"
alias aptac="sudo apt autoclean && sudo apt autoremove"


# fwupdmgr
alias fw_check="fwupdmgr get-devices && fwupdmgr get-updates"
alias fw_update="fwupdmgr update"
