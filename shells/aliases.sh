#!/bin/sh
# Shared by bash, zsh AND fish, so this file must stay to the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155

# # === start required variables/aliases ===
alias hi="$_HI_LAUNCHER"
alias hi_colors="bash -c 'source $_HI_SHARED && list_colors'"
alias hi_install="$_HI_INSTALL"
alias hi_test_aliases="$_HI_TEST_ALIASES"
alias hi_update="git -C $_HI_ROOT pull"
alias hi_status="git -C $_HI_ROOT status"
alias hi_info="echo 'tmpdir: $_HI_TMPDIR | root: $_HI_ROOT | script: $_HI_LAUNCHER'"
alias sudo="command sudo " # works in bash/zsh, fish has a sudo wrapper in config.fish
# # === end required variables/aliases ===

# editor defaults with preferential fallthrough
export EDITOR="$(command -v nano || command -v pico || command -v micro || command -v vim || command -v vi)"
alias micro="micro -autoindent=true -colorscheme=darcula -colorcolumn=80 -diffgutter=true -softwrap=true -tabsize=2"
alias nano="nano --rcfile $_HI_NANORC"
alias vim="vim -u $_HI_VIMRC"

# cat is bat with our options when bat exists, plain cat otherwise
export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid'
# batcat is batcat on some Linux distros (fallback to cat)
alias batcat="$(command -v bat || command -v batcat || command -v cat)"
alias bat="batcat $_HI_BAT_OPTS"
alias batn="batcat $_HI_BAT_OPTS,numbers"
alias cat="batcat"
alias catn="batn"

# time helpers
export _HI_HUMAN_CENTRIC_DATE="+%a %b %-e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %-e %y %H:%M %Z"
alias now='echo "LOCAL: $(date $_HI_HUMAN_SHORT_DATE) => UTC: $(date -u $_HI_HUMAN_SHORT_DATE)"'

# for working on this repo quickly
alias hey="ssh"
alias zed="zeditor"
alias ehi="zed $_HI_ROOT"
alias essh="zed $_HI_SSH_DIR"

# TODO: add script/compat for local config changes?
alias elinks="zed ~/projects/links"

# docker
alias dcl="docker container ls && docker compose ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"
alias dps="dcl"

# copying and general safety
alias grep="grep --color=auto"
alias rm="rm -iv"
alias cp="cp -rv"
alias rsync="rsync -zvhPr --info=progress2"
alias scp="scp -Cr"
alias fc="ls | wc -l"
alias mkex="chmod +x"
alias ctar="tar -zcvf"
alias utar="tar -zxvf"
alias mindiff="diff -Bdw"
alias ..="cd ../"
alias ...="cd ../../"

# ls basics
alias ls="ls -lh --color=auto"
alias lsa="ls -a"
alias lsd="ls -d .*"
alias lsr="lsa -R"

# fallthrough aliases for improved basics
alias du="$(command -v dua || command -v du)"
alias df="$(command -v duf || command -v df)"
alias dig="$(command -v dog || command -v dig)"

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html
export EZA_CONFIG_DIR="$_HI_ROOT/misc" # eza theme customization, misc/theme.yml
export _HI_EXA_SHARED_OPTS='-F -1 -l -m --group-directories-first'
export _HI_EXA_OPTS="$_HI_EXA_SHARED_OPTS --group --no-filesize"
export _HI_EZA_OPTS="$_HI_EXA_SHARED_OPTS"' --smart-group --time-style="+%b %d %Y %H:%M"'
export _HI_EZA_OPTS_SIZE="$_HI_EZA_OPTS --total-size"
alias exa="$(command -v exa || command -v eza || command -v ls) $_HI_EXA_OPTS"
alias lr="exa"
alias lra="lr -a"
alias lrt="lr -T -L2"
alias eza="$(command -v eza || command -v exa || command -v ls) $_HI_EZA_OPTS"
alias les="eza $_HI_EZA_OPTS_SIZE"
alias lest="eza $_HI_EZA_OPTS_SIZE -T -L2"
alias lesg="eza $_HI_EZA_OPTS_SIZE --git --git-repos-no-status"
alias le="eza --no-filesize"
alias lea="le -a"
alias let="le -T -L2"
alias leg="le --git --git-repos-no-status"

# git
alias gl="git log --abbrev-commit --graph"
alias gf="git fetch -a"
alias gp="git fetch -a && git pull"
alias gch="git checkout"
alias gcl="git clone"
alias gs="git status"
alias gst="git stash"
alias gss="git stash show"
alias gsl="git stash list"
alias gsa="git stash apply"
alias gsd="git stash drop"
alias gsda="git stash drop --all"
alias gd="git diff --color=always"
alias gps="echo ' Okay. Where are we going?'"
alias gpsh='git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)'

# internet
alias ping="ping -O"
alias pping="prettyping"
alias ip="ip -color=always"
alias ips="ip -br a"
alias my_ip="ip route get 1.1.1.1"

# pacman: for arch-likes
alias yayy="yay -Syyu"
alias yayc="yay -Sc --noconfirm"
alias yaycc="sudo rm -rfv /var/cache/pacman/pkg/download-* >/dev/null"
alias yay_remove_orphans="pacman -Qdtq | sudo pacman -Rns -"

# apt: for debian-likes
alias aptup="sudo apt update"
alias aptug="sudo apt upgrade"
alias aptupg="sudo apt update && sudo apt upgrade"
alias aptac="sudo apt autoclean && sudo apt autoremove"

# fwupdmgr commands (laptops, device drivers, etc.)
alias fw_check="fwupdmgr get-devices && fwupdmgr get-updates"
alias fw_update="fwupdmgr update"

# android dev on linux (never last: a false test would make `source` return 1)
[ -d "$HOME/Android/Sdk" ] && export ANDROID_HOME="$HOME/Android/Sdk"

# prevent misspellings/save my fingers
alias sctl="sudo systemctl"
alias chron="cron"
alias chrontab="crontab"
