#!/bin/zsh

# === start required configuration ===
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
source "$_HI_GIT_PROMPT"
source "$_HI_ALIASES"

# NOT setopt KSH_ARRAYS: it is global, hi's block runs *after* oh-my-zsh's,
# and their code assumes zsh's 1-based arrays - core.sh counts instead.
setopt prompt_subst

_hi_interactive_extras

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  if _hi_wants_starship; then
    # deference, chosen in settings.sh - see _hi_wants_starship in core.sh
    eval "$(starship init zsh)"
  else
    _hi_prime_identity
    # git info through a precmd out-var reference, never a $( ) in PS1: the
    # same fork-free, pw3nage-safe form bash.sh's ps1() uses (prompt_subst
    # expands the reference at render time)
    __hi_git_precmd() { _hi_git_prompt __hi_git_info; }
    precmd_functions+=(__hi_git_precmd)
    # concatenated onto the $'...' strings, not interpolated - those stay
    # literal so zsh's prompt expansion happens at render time, not assignment
    HI_PS1_END="$(_hi_prompt_end ZSH '>')"
    if _hi_has_color; then
      export CLICOLOR=1
      export LSCOLORS=gafacadabaegedabagacad
      # %F{} has no bright variants, so brred/brblue/... fall back to their base color
      USER_COLOR="${$(_hi_user_color)//br/}"
      HOST_COLOR="${$(_hi_host_color)//br/}"
      _hi_at_color=plain
      [ -n "${SSH_TTY:-}" ] && _hi_at_color=yellow
      PS1=$' ${debian_chroot:-}%F{$USER_COLOR}%n%f%F{$_hi_at_color}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain}%{${__hi_git_info}%} '"$HI_PS1_END"' '
    else
      PS1=$' ${debian_chroot:-}%n@%m %~%{${__hi_git_info}%} '"$HI_PS1_END"' '
    fi
  fi
fi

# completion: `hi` from the shared target list, `exa` the same way as `eza`
zmodload zsh/complist
autoload -Uz compinit promptinit
# bare `compinit` costs 50-150ms per start; full check once a day, -C in
# between. (#qN.mh+24): N tolerates a missing dump, .mh+24 = older than 24h.
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
  # compinit leaves an unchanged dump's mtime alone, which would make this
  # branch permanent once the dump turns a day old - touch restarts the clock
  touch "${ZDOTDIR:-$HOME}/.zcompdump" 2>/dev/null || true
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
