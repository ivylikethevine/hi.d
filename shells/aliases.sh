#!/bin/sh
# shellcheck disable=SC2155
# shellcheck disable=SC2139

# === start required variables/aliases ===
alias hi_update="git -C $_HI_ROOT pull"
alias hi_status="git -C $_HI_ROOT status"
alias hi_install="$_HI_INSTALL"
alias hi_colorgen="bash -c 'source $_HI_COLORGEN && colorgen'"
alias hi="$_HI_LAUNCHER"

export EDITOR="$(command -v nano || command -v pico || command -v micro || command -v vim || command -v vi)"
alias nano="nano --rcfile $_HI_NANORC"
alias vim="vim -u $_HI_VIMRC"

# nonsense for cat to be bat with options if present, cat otherwise
export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid'
export _HI_BAT_OPTS_NUM="$_HI_BAT_OPTS"',numbers'
alias batcat="$(command -v bat || command -v batcat || command -v cat)"
alias bat="batcat $_HI_BAT_OPTS"
alias batn="batcat $_HI_BAT_OPTS_NUM"
alias cat="batcat"
alias catn="batn"

# works in bash, fish has a wrapper for sudo in config.fish
alias sudo="command sudo "

# helpful time formats
export _HI_HUMAN_CENTRIC_DATE="+%a %b %-e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %-e %y %H:%M %Z"
# time helpers
alias now='echo "LOCAL: $(date $_HI_HUMAN_SHORT_DATE) => UTC: $(date -u $_HI_HUMAN_SHORT_DATE)"'

# for working on this repo quickly
alias hey="ssh"
alias zed="zeditor"
alias ehi="zed ~/hi.d"
alias essh="zed ~/.ssh"
alias elinks="zed ~/projects/links"
# === end required variables/aliases ===

# docker
alias dcl="docker container ls && docker compose ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"

# files/listing/transfer
alias ls="ls -lh --color=auto"
alias lsa="ls -lha --color=auto"
alias lsd="ls -lhd .* --color=auto"
alias lsr="ls -lhaR --color=auto"

# enable color
alias grep="grep --color=auto"

# good safety
alias rm="rm -iv"

# exa (back-compat) improved ls
export _HI_EXA_SHARED_OPTS='-F -1 -l -m --group-directories-first'
export _HI_EXA_OPTS="$_HI_EXA_SHARED_OPTS"' --group --no-filesize'
alias exa="$(command -v exa || command -v eza || command -v ls) $_HI_EXA_OPTS"
alias lr="exa"
alias lra="lr -a"
alias lrt="lr -T -L2"

# eza (newer fork of exa) improved ls
# per https://docs.rs/chrono/latest/chrono/format/strftime/index.html
export _HI_EZA_OPTS="$_HI_EXA_SHARED_OPTS"' --smart-group --time-style="+%b %d %Y %H:%M"'
export _HI_EZA_OPTS_SIZE="$_HI_EZA_OPTS --total-size"
alias eza="$(command -v eza || command -v exa || command -v ls) $_HI_EZA_OPTS"
alias les="eza $_HI_EZA_OPTS_SIZE"
alias lest="eza $_HI_EZA_OPTS_SIZE -T -L2"
alias lesg="eza $_HI_EZA_OPTS_SIZE --git --git-repos-no-status"
alias le="eza --no-filesize"
alias lea="le -a"
alias let="le -T -L2"
alias leg="le --git --git-repos-no-status"

# for bash/zsh (fish enabled by default)
alias ..="cd ../"
alias ...="cd ../../"

# git
alias gl="git log --abbrev-commit --graph"
alias gf="git fetch -a"
alias gp="git fetch -a && git pull"
alias gch="git checkout"
alias gcl="git clone"
alias gs="git status"
alias gst="git stash"
alias gd="git diff --color=always"
alias gps="echo ' Okay. Where are we going?'"
alias gpsh='git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)'

# internet
alias ping="ping -O"
alias pping="prettyping"
alias ip="ip -color=always"
alias ips="ip -br a"
alias my_ip="ip route get 1.1.1.1"

# prevent mispellings/save my fingers
alias sctl="sudo systemctl"
alias chron="cron"
alias chrontab="crontab"

# pacman/yay updates
alias yayy="yay -Syyu"
alias yayc="yay -Sc --noconfirm"
alias yaycc="sudo rm -rf /var/cache/pacman/pkg/download-* >/dev/null"

# apt updates
alias aptup="sudo apt update"
alias aptug="sudo apt upgrade"
alias aptupg="sudo apt update && sudo apt upgrade"
alias aptac="sudo apt autoclean && sudo apt autoremove"

# fwupdmgr
alias fw_check="fwupdmgr get-devices && fwupdmgr get-updates"
alias fw_update="fwupdmgr update"

# file count
alias fc="ls | wc -l"

# make executable
alias mkex="chmod +x"

# tar shortcuts
alias ctar="tar -zcvf"
alias utar="tar -zxvf"

# copy with progress/recursive
alias cp="cp -rv"
alias rsync="rsync -zvhPr --info=progress2"
alias scp="scp -Cr"

# minimal diff-ing
alias mindiff="diff -Bdw"
