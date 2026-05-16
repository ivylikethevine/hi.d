#!/bin/sh

# === start required variables/aliases ===
alias hi_colorgen="sh -c 'source ~/hi.d/scripts/colorgen.sh && colorgen'"
alias hi_newhost="~/hi.d/scripts/newhost.sh"
alias hi_update="cd ~/hi.d && git pull"
alias hi_install="~/hi.d/scripts/install.sh"

# shellcheck disable=SC2139
alias hi="$HI_TMPDIR/hi.d/hi.sh"

# shellcheck disable=SC2139,SC2155
export EDITOR="$(command -v pico || command -v nano || command -v micro || command -v vim || command -v vi)"
# shellcheck disable=SC2139
alias nano="nano --rcfile $HI_TMPDIR/hi.d/misc/nano.rc"
# shellcheck disable=SC2139
alias vim="vim -u $HI_TMPDIR/hi.d/misc/vim.rc"

# nonsense for cat to be bat with options if present, cat otherwise
export BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid'
export BAT_OPTS_NUM="$BAT_OPTS"',numbers'
# shellcheck disable=SC2139
alias batcat="$(command -v bat || command -v batcat || command -v cat)"
# shellcheck disable=SC2139
alias bat="batcat $BAT_OPTS"
# shellcheck disable=SC2139
alias batn="batcat $BAT_OPTS_NUM"
alias cat="batcat"

# works in bash, fish has a wrapper for sudo in config.fish
alias sudo="command sudo "

export human_centric_date_format="+%a %b %-e %Y %H:%M:%S %Z" # used in fish
export human_short_date_format="+%b %-e %y %H:%M %Z"         # used for 'now' alias
# time helpers
alias now='echo "LOCAL: $(date $human_short_date_format) => UTC: $(date -u $human_short_date_format)"'

# for working on this repo quickly
alias hey="ssh"
alias zed="zeditor"
alias ehi="zed ~/hi.d"
alias essh="zed ~/.ssh"
alias elinks="zed ~/projects/links"
# === end required variables/aliases ===
# in trial
alias list_pkgs="pacman -Qe > ~/projects/links/explicitly-installed.txt && pacman -Qd > ~/projects/links/dependencies-installed.txt"

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

alias grep="grep --color=auto"
alias rm="rm -iv"
# alias rsync="rsync -zvhPra --info=progress2" #  the -a flag might not work on all systems...
alias rsync="rsync -zvhPr --info=progress2"
alias scp="scp -Cr"

# exa (back-compat) improved ls
export EXA_SHARED_OPTS='-F -1 -l -m --group-directories-first'
export EXA_OPTS="$EXA_SHARED_OPTS"' --group --no-filesize'
# shellcheck disable=SC2139
alias eza="$(command -v eza || command -v exa || command -v ls)"
# shellcheck disable=SC2139
alias exa="exa $EXA_OPTS"
# shellcheck disable=SC2139
alias lr="exa"
alias lra="lr -a"
alias lrt="lr -T -L2"

# eza (newer fork of exa) improved ls
# per https://docs.rs/chrono/latest/chrono/format/strftime/index.html
export EZA_OPTS="$EXA_SHARED_OPTS"' --smart-group --time-style="+%b %d %Y %H:%M"'
export EZA_OPTS_SIZE="$EZA_OPTS --total-size"
# shellcheck disable=SC2139
alias eza="eza $EZA_OPTS"
# shellcheck disable=SC2139
alias les="eza $EZA_OPTS_SIZE"
# shellcheck disable=SC2139
alias lest="eza $EZA_OPTS_SIZE -T -L2"
# shellcheck disable=SC2139
alias lesg="eza $EZA_OPTS_SIZE --git --git-repos-no-status"
# shellcheck disable=SC2139
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

alias fc="ls | wc -l"
alias mkex="chmod +x"

alias ctar="tar -zcvf"
alias utar="tar -zxvf"

alias cp="cp -rv"
