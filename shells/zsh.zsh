#!/bin/zsh

# === start required configuration ===
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
source "$_HI_GIT_PROMPT"
source "$_HI_ALIASES"

setopt KSH_ARRAYS # required for sanity & some of the other scripts we run
setopt prompt_subst

_hi_interactive_extras

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  _hi_prime_identity
  if _hi_has_color; then
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
fi

# completion: `hi` from the shared target list, `exa` the same way as `eza`
zmodload zsh/complist
autoload -Uz compinit promptinit
# A bare `compinit` re-scans and security-checks all of $fpath on every zsh
# start - typically 50-150ms. Full check once a day, trust the dump in between
# (-C). (#qN.mh+24): N so a missing dump isn't an error, .mh+24 for "older
# than 24 hours".
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi
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

if [[ "${_HI_DISABLE_PERSONAL:-0}" != 1 ]]; then
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
  # XDG_CACHE_HOME is unset on most targets, which would leave this pointing at
  # an unwritable /zsh/.zcompcache - fall back to the spec's own default
  zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/.zcompcache"
  zstyle ':completion:*' squeeze-slashes true
  zstyle ':completion:*' complete-options true
  zstyle ':completion:*' group-name ''

  zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
  zstyle ':completion:*:*:-command-:*:*' group-order alias builtins functions commands

  zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
  zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
fi
