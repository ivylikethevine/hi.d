#!/bin/zsh

# === start required configuration ===
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"
source "$_HI_GIT_PROMPT"
source "$_HI_ALIASES"

setopt KSH_ARRAYS # required for sanity & some of the other scripts we run
setopt prompt_subst

# android dev on linux (never last: a false test would make `source` return 1)
[ -d "$HOME/Android/Sdk" ] && export ANDROID_HOME="$HOME/Android/Sdk"

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
[ -r /etc/debian_chroot ] && debian_chroot="($(cat /etc/debian_chroot)) "

if tput setaf 1 >/dev/null 2>&1; then
  export CLICOLOR=1
  export LSCOLORS=gafacadabaegedabagacad
  # %F{} has no bright variants, so brred/brblue/... fall back to their base color
  USER_COLOR="${$(_hi_user_color)//br/}"
  HOST_COLOR="${$(_hi_host_color)//br/}"
  _hi_at_color=plain
  [ -n "${SSH_TTY:-}" ] && _hi_at_color=yellow
  PS1=$' ${debian_chroot:-}%F{$USER_COLOR}%n%f%F{$_hi_at_color}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain}%{$(_hi_git_prompt)%} > '
else
  PS1=$' ${debian_chroot:-}%n@%m %~%{$(_hi_git_prompt)%} > '
fi

# completion: `hi` from the shared target list, `exa` the same way as `eza`
zmodload zsh/complist
autoload -Uz compinit promptinit
compinit
promptinit
_hi() {
  local -a targets descs
  local name kind
  while IFS=$'\t' read -r name kind; do
    targets+=("$name")
    descs+=("$kind - $name")
  done < <(sh "$_HI_TARGETS")
  compadd -d descs -a targets
}
compdef _hi hi
compdef exa=eza
# === end required configuration ===

HISTFILE=~/.zsh_history
HISTSIZE=2000
SAVEHIST=2000

# home/end/delete, plain and ctrl-modified
bindkey "^[OH" beginning-of-line
bindkey "^[[H" beginning-of-line
bindkey "^[[1;5H" backward-word
bindkey "^[[1;5D" backward-word
bindkey "^[OF" end-of-line
bindkey "^[[F" end-of-line
bindkey "^[[1;5F" forward-word
bindkey "^[[1;5C" forward-word
bindkey "^[[3;5~" delete-word

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
