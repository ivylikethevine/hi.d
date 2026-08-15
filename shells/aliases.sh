#!/bin/sh
# Shared by bash, zsh AND fish, so this file must stay to the subset all three
# parse: `alias`, `export`, `&&` chains - no if/then/fi, no $(...) conditionals.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2155
# the following syntax resolves to the first command installed, changing order
# changes preference (for users taste)
# export z="$(command -v a || command -v b || command -v c)"
# This file is an example of my personal setup. Feel free to change it to suit your needs,
# but these are the only patterns that are safe to use, since this file must be
# POSIX+fish compliant.

# The two toggles this file reads, defaulted here so reading them is never an
# error whoever sourced us. No single spelling works: `${_HI_DISABLE_EDITORS-0}`
# is a parse error in fish ("${ is not a valid variable") that aborts the whole
# file, and a bare `$_HI_DISABLE_EDITORS` is fatal in sh/bash/zsh under `set -u`.
# So the defaults sit inside an `eval` string the other shell never parses,
# gated on a builtin every POSIX shell has and fish deliberately doesn't.
# The `-` form, not `:-`, so an intentional empty value isn't quietly turned
# back on. The entry points set these too; this is the backstop for anything
# sourcing this file directly - which is how `hi <target> <command>` broke.
command -v getopts >/dev/null 2>&1 &&
  eval 'export _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS-0}" _HI_DISABLE_ALIASES="${_HI_DISABLE_ALIASES-0}"' || true

# nano, vim, cat, ls, exa and eza are all aliased further down. In zsh, dash and
# POSIX sh (unlike bash/fish), `command -v` returns an *alias's* definition
# rather than the real binary once that alias exists, so every fallthrough chain
# that can reach one of those names has to resolve first. Doing them all here,
# before this file sets any alias, keeps the chains below immune.
export _HI_EDITOR_BIN="$(command -v nano || command -v micro || command -v pico || command -v vim || command -v vi)"
export _HI_BATCAT_BIN="$(command -v bat || command -v batcat || command -v ccat || command -v cat)"
# exa and eza intentionally differ in preference order (exa picks exa first,
# eza/l pick eza first), so each needs its own resolved variable.
export _HI_EXA_BIN="$(command -v exa || command -v eza || command -v ls)"
export _HI_EZA_BIN="$(command -v eza || command -v exa || command -v ls)"

# skipped when _HI_DISABLE_EDITORS=1, leaving nano/vim at their own defaults.
# `|| true` because some sourcers run under `set -e`, where a failed `[ ]` guard
# would abort the whole shell.
[ "$_HI_DISABLE_EDITORS" != 1 ] && alias nano="nano --rcfile $_HI_NANORC" || true
[ "$_HI_DISABLE_EDITORS" != 1 ] && alias vim="$(command -v nvim || command -v vim) -u $_HI_VIMRC" || true

# misc/theme.yml styles eza itself, not any alias hi defines, so it goes above
# the early return: turning personal aliases off shouldn't strip the theme from
# an eza the user runs directly.
export EZA_CONFIG_DIR="$_HI_THEME_DIR"

# everything below is personal preference, freely editable without touching hi's
# own functionality. Skipped wholesale when _HI_DISABLE_ALIASES=1.
[ "$_HI_DISABLE_ALIASES" = 1 ] && return || true

alias sudo="command sudo " # works in bash/zsh, fish has a sudo wrapper in config.fish

# cli text editor defaults with preferential fallthrough
export EDITOR="$_HI_EDITOR_BIN"
alias micro="micro -autoindent=true -colorscheme=darcula -colorcolumn=80 -diffgutter=true -softwrap=true -tabsize=2"
# ide defaults with preferential fallthrough
export IDE="$(command -v zeditor || command -v zed || command -v code || command -v vi)"

# cat is bat with our options when bat exists, plain cat otherwise
export _HI_BAT_OPTS='-P --tabs 2 --theme Monokai\ Extended\ Bright --style changes,grid'
# batcat is batcat on some Linux distros (fallback to ccat)
# ccat is cat with syntax highlighting (fallback to cat)
alias batcat="$_HI_BATCAT_BIN"
alias bat="batcat $_HI_BAT_OPTS"
alias batn="batcat $_HI_BAT_OPTS,numbers"
alias cat="batcat"
alias catn="batn"

alias now='echo "LOCAL: $(date $_HI_HUMAN_SHORT_DATE) => UTC: $(date -u $_HI_HUMAN_SHORT_DATE)"'

# for working on this repo quickly
alias zed="$(command -v zeditor || command -v zed || command -v echo)"
alias ehi="zed $_HI_ROOT"
alias essh="zed $_HI_SSH_DIR"
# TODO: add script/compat for local config changes?
alias elinks="zed ~/projects/links"

# docker compose
alias dcl="docker container ls && docker compose ls"
alias dcu="docker compose up"
alias dcud="docker compose up -d"
alias dcd="docker compose down"
alias dps="dcl"
alias dsp="docker system prune -fa"

# defaults for basics
alias grep="grep --color=auto"
alias ps="ps aux"

# good safety mechanism
alias rm="rm -iv"
alias rmv="rm -rv"

# default recursive copy with progress
alias cp="cp -rv"
alias rsync="rsync -zvhPr --info=progress2"
alias scp="scp -Cr"

# file count + executability
alias fc="ls | wc -l"
alias mkex="chmod +x"

# always forget how tar works
alias ctar="tar -zcvf"
alias utar="tar -zxvf"

# file diffing
# TODO: test out these diffing tools
# alias diff="$(command -v diff-so-fancy || command -v icdiff || command -v diff)"
alias mindiff="diff -Bdw"

# fallthrough aliases for improved basics
# alias du="$(command -v dua || command -v du)" # this breaks du -sh :/
alias df="$(command -v duf || command -v df)"
alias dig="$(command -v dog || command -v dig || command -v echo)"

# directory navigation
alias ..="cd ../"
alias ...="cd ../../"
alias z="zoxide"

# ls basics
alias ls="ls -lh --color=auto"
alias lsa="ls -a"
alias lsr="lsa -R"

# eza/exa (its predecessor) improved ls; time format per
# https://docs.rs/chrono/latest/chrono/format/strftime/index.html
export _HI_EXA_SHARED_OPTS='-F -1 -l -m --group-directories-first'
export _HI_EXA_OPTS="$_HI_EXA_SHARED_OPTS --group --no-filesize"
export _HI_EZA_OPTS="$_HI_EXA_SHARED_OPTS"' --smart-group --time-style="+%b %d %Y %H:%M"'
export _HI_EZA_OPTS_SIZE="$_HI_EZA_OPTS --total-size"
alias exa="$_HI_EXA_BIN $_HI_EXA_OPTS"
alias lr="exa"
alias lsx="lr"
alias lra="lr -a"
alias lrt="lr -T -L2"
alias eza="$_HI_EZA_BIN $_HI_EZA_OPTS"
alias lsz="eza"
alias les="eza $_HI_EZA_OPTS_SIZE"
alias lest="eza $_HI_EZA_OPTS_SIZE -T -L2"
alias lesg="eza $_HI_EZA_OPTS_SIZE --git --git-repos-no-status"
alias le="eza --no-filesize"
alias lea="le -a"
alias let="le -T -L2"
alias leg="le --git --git-repos-no-status"
alias l="$_HI_EZA_BIN -l"

# lsd (another improved ls)
alias lsd="lsd -lh --color=auto"

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
alias yay_list_orphans="pacman -Qdtq"
alias yay_remove_orphans="pacman -Qdtq | sudo pacman -Rns -"

# apt: for debian-likes
alias aptup="sudo apt update"
alias aptug="sudo apt upgrade"
alias aptupg="sudo apt update && sudo apt upgrade"
alias aptac="sudo apt autoclean && sudo apt autoremove"

# fwupdmgr commands (laptops, device drivers, etc.)
alias fw_check="fwupdmgr get-devices && fwupdmgr get-updates"
alias fw_update="fwupdmgr update"

# prevent misspellings/save my fingers
alias sctl="sudo systemctl"
alias chron="cron"
alias chrontab="crontab"
