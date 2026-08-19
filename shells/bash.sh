#!/bin/bash
# set -euo pipefail # cannot be enabled: an interactive shell would exit on the first error

# === start required configuration ===
# shellcheck source=../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../common/git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=../misc/aliases.sh
source "$_HI_ALIASES"

_hi_interactive_extras
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]] && ! _hi_wants_starship; then
  _hi_prime_identity
  # the character this prompt ends with (`\$` here, which bash renders as $ for
  # a user and # for root) - see _hi_prompt_end in common/core.sh
  HI_PS1_END="$(_hi_prompt_end BASH)"
  if _hi_has_color; then
    # the *_var forms, not $( ): _hi_prime_identity above already resolved both
    # escapes in this shell, and a command substitution would pay for them
    # again. Spelled empty first so shellcheck sees the `printf -v` assignment
    # (SC2154) - these are file scope, where `local` is not available.
    _hi_ps1_u="" _hi_ps1_h=""
    _hi_user_escape_var _hi_ps1_u
    _hi_host_escape_var _hi_ps1_h
    HI_PS1=" ${debian_chroot:-}$_hi_ps1_u\u$(_hi_at_color)@$_hi_ps1_h\h$NC $BRBLUE\w$NC"
    unset _hi_ps1_u _hi_ps1_h
  else
    HI_PS1=" ${debian_chroot:-}\u@\h:\w"
  fi
fi

if ! shopt -oq posix; then
  # $BASH_COMPLETION_VERSINFO is the loader's own sentinel: the host's stock
  # rc (Debian's skeleton, notably) often sourced it before hi's grafted
  # block runs, and re-parsing the ~2000-line script costs every shell start
  # 20-50ms for nothing
  # shellcheck disable=SC1091
  [ -n "${BASH_COMPLETION_VERSINFO-}" ] ||
    source /usr/share/bash-completion/bash_completion 2>/dev/null ||
    source /etc/bash_completion 2>/dev/null
fi

# complete `hi` from the same target list zsh/fish use, and make `exa` complete
# exactly the way `eza` does, whatever bash-completion bound to it.
#
# targets.sh file-caches its answer for $_HI_TARGETS_TTL seconds, so a repeat
# TAB is cheap - but finding that out is still a fork and an exec. Holding the
# names in the shell for the same window makes it free, and means the same
# thing: a container started inside the window was already invisible until the
# file cache turned over. $SECONDS is the stamp because it is a builtin (a
# `date +%s` would cost the fork it saves); -1 is "never filled", and a TTL of
# 0 refreshes every time, the "no cache wanted" targets.sh reads it as.
# GLOSSARY: completion probe knobs
_HI_TARGET_NAMES=""
_HI_TARGET_NAMES_AT=-1

function _hi_target_names() {
  local -a rows=()
  if [ "$_HI_TARGET_NAMES_AT" -ge 0 ] &&
    [ "$((SECONDS - _HI_TARGET_NAMES_AT))" -lt "${_HI_TARGETS_TTL:-5}" ]; then
    return 0
  fi
  _hi_read_lines rows < <(sh "$_HI_TARGETS")
  # names are field 1; the tab strip is a builtin, sparing a `cut` per TAB
  _HI_TARGET_NAMES="${rows[*]%%$'\t'*}"
  _HI_TARGET_NAMES_AT="$SECONDS"
}

# On a warm cache _hi_target_names returns without doing anything, and then
# `compgen` through a process substitution cost a fork plus one `eval` per
# candidate (core.sh's _hi_read_lines) on every single TAB. Matching in-shell
# costs neither. targets.sh already drops names carrying `*` or `?`, so `set -f`
# is belt to that: a stored name is matched, never globbed.
function _hi_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}" n
  _hi_target_names
  COMPREPLY=()
  set -f
  for n in $_HI_TARGET_NAMES; do
    case "$n" in "$cur"*) COMPREPLY+=("$n") ;; esac
  done
  set +f
}
complete -F _hi_complete hi

# Deferred to the first TAB after `exa` - startup shouldn't parse a multi-KB
# spec most sessions never use. 124 is bash-completion's "retry".
function _hi_load_exa_completion() {
  local spec
  command -v _completion_loader &>/dev/null && _completion_loader eza &>/dev/null
  spec=$(complete -p eza 2>/dev/null) || return 1
  eval "${spec% eza} exa"
  return 124
}
complete -F _hi_load_exa_completion exa

# modified from: https://github.com/riobard/bash-powerline/blob/master/bash-powerline.sh
if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  if _hi_wants_starship; then
    # deference, chosen in settings.sh - see _hi_wants_starship in core.sh
    eval "$(starship init bash)"
  else
    function ps1() {
      # git info through a reference, never expanded into PS1 - expanding user
      # strings is the pw3nage class of bug (github.com/njhartwell/pw3nage)
      if shopt -q promptvars; then
        _hi_git_prompt __powerline_git_info # out-var form: no $( ) fork per prompt
        # shellcheck disable=SC2154 # assigned by the printf -v one line up
        PS1="$HI_PS1\${__powerline_git_info}$NC $HI_PS1_END "
      else
        PS1="$HI_PS1$(_hi_git_prompt)$NC $HI_PS1_END "
      fi
    }
    PROMPT_COMMAND="ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
  fi
fi
# === end required configuration ===

if [[ "${_HI_DISABLE_PERSONAL:-0}" != 1 ]]; then
  HISTSIZE=2000
  HISTFILESIZE=2000
  HISTCONTROL="erasedups:ignoreboth"
  export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
  PROMPT_DIRTRIM=2

  shopt -s histappend checkwinsize cmdhist
  # globstar is bash 4; on bash 3.2 (macOS) `shopt -s` on an unknown option is an
  # error, which under an rc file that keeps going is just noise on every prompt
  shopt -s globstar 2>/dev/null || true

  bind "set completion-ignore-case on"
  bind "set completion-map-case on"
  bind "set show-all-if-ambiguous on"
  bind "set mark-symlinked-directories on"

  bind Space:magic-space
  bind '"\e[A": history-search-backward'
  bind '"\e[B": history-search-forward'
  bind '"\e[C": forward-char'
  bind '"\e[D": backward-char'
fi
