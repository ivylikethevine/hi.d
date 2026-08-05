#!/bin/zsh

# === start required configuration ===
_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
source "$_HI_COLORS"
# shellcheck source=./shells/aliases.sh
source "$_HI_ALIASES"

if [ -d "$HOME"/Android ] && [ -d "$HOME"/Android/Sdk ]; then
  export ANDROID_HOME="$HOME"/Android/Sdk # for android dev on linux
fi

export EZA_CONFIG_DIR="$_HI_TMPDIR"/hi.d/misc # for eza theme customization at misc/theme.yml

# required for sanity & some of the other scripts we run
setopt KSH_ARRAYS

# header/coloring
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
  color_prompt=yes
else
  color_prompt=
fi

# git status
autoload -Uz vcs_info
setopt prompt_subst

zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '*'
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' formats '%b%c%u%m'
zstyle ':vcs_info:git+set-message:*' hooks git-aheadbehind

# adds " ↑<n> ↓<n>" (commits ahead/behind the upstream) to vcs_info's %m,
# mirroring the ahead/behind markers bash.sh's __git_info shows
+vi-git-aheadbehind() {
  local ahead behind
  local -a marks

  ahead=$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null)
  behind=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null)

  (( ${ahead:-0} > 0 )) && marks+=("↑${ahead}")
  (( ${behind:-0} > 0 )) && marks+=("↓${behind}")

  (( $#marks )) && hook_com[misc]=" ${(j: :)marks}"
}

precmd() { vcs_info }

if [ "$color_prompt" = yes ]; then
  export CLICOLOR=1
  export LSCOLORS=gafacadabaegedabagacad
  USER_COLOR=$(user_color)
  USER_COLOR="${USER_COLOR//br/}"
  HOST_COLOR=$(host_color)
  HOST_COLOR="${HOST_COLOR//br/}"
  AT_COLOR=plain
  if [[ -v SSH_TTY ]]; then
    AT_COLOR=yellow
  fi
  PS1=$' ${debian_chroot:+($debian_chroot)}%F{$USER_COLOR}%n%f%F{$AT_COLOR}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain} $vcs_info_msg_0_| '
else
  PS1=$' ${debian_chroot:+($debian_chroot)}%n@%m %~ $vcs_info_msg_0_| '
fi
# === end required configuration ===

HISTFILE=~/.zsh_history
HISTSIZE=2000
SAVEHIST=2000

# homekey
bindkey "^[OH" beginning-of-line
bindkey "^[[H" beginning-of-line
bindkey "^[[1;5H" backward-word
bindkey "^[[1;5D" backward-word

# endkey
bindkey "^[OF" end-of-line
bindkey "^[[F" end-of-line
bindkey "^[[1;5F" forward-word
bindkey "^[[1;5C" forward-word

# delkey
bindkey "^[[3;5~" delete-word

# completion configuration
zmodload zsh/complist
autoload -Uz compinit
autoload -Uz promptinit
compinit
compdef hi=ssh
compdef exa=eza
promptinit

# configuration
setopt LIST_PACKED
setopt histignorealldups sharehistory
unsetopt beep
bindkey -e

zstyle ':completion:*' menu yes select
zstyle ':completion:*' completer _extensions _expand _complete _correct _approximate
zstyle ':completion:*' file-list all
zstyle ':completion:*' verbose yes
zstyle ':completion:*' use-cache on
zstyle ':completion:*' rehash true
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/.zcompcache"
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' complete-options true
zstyle ':completion:*' group-name ''

zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:*:-command-:*:*' group-order alias builtins functions commands

zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
