#!/bin/bash
# set -euo pipefail # cannot be enabled: an interactive shell would exit on the first error

# === start required configuration ===
# shellcheck source=../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../common/git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=./aliases.sh
source "$_HI_ALIASES"

_hi_interactive_extras
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

if [[ "${_HI_DISABLE_PROMPT:-0}" != 1 ]]; then
  _hi_prime_identity
  # the character this prompt ends with (`\$` here, which bash renders as $ for
  # a user and # for root) - see _hi_prompt_end in common/core.sh
  HI_PS1_END="$(_hi_prompt_end BASH '\$')"
  if _hi_has_color; then
    HI_PS1=" ${debian_chroot:-}$(_hi_user_escape)\u$(_hi_at_color)@$(_hi_host_escape)\h$NC $BRBLUE\w$NC"
  else
    HI_PS1=" ${debian_chroot:-}\u@\h:\w"
  fi
fi

if ! shopt -oq posix; then
  # shellcheck disable=SC1091
  source /usr/share/bash-completion/bash_completion 2>/dev/null ||
    source /etc/bash_completion 2>/dev/null
fi

# complete `hi` from the same target list zsh/fish use, and make `exa` complete
# exactly the way `eza` does, whatever bash-completion bound to it
function _hi_complete() {
  local -a rows=()
  _hi_read_lines rows < <(sh "$_HI_TARGETS")
  # names are field 1; the tab strip is a builtin, sparing a `cut` per TAB
  _hi_read_lines COMPREPLY < <(compgen -W "${rows[*]%%$'\t'*}" -- "${COMP_WORDS[COMP_CWORD]}")
}
complete -F _hi_complete hi

# Deferred to the first TAB after `exa`: loading eza's completion at startup
# parses a multi-KB file in every shell for something most sessions never use.
# Returns 124, bash-completion's "retry with the new spec".
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
  function ps1() {
    # Bash expands the content of PS1 unless promptvars is disabled, so the git
    # info goes through another layer of reference - expanding user provided
    # strings would be a security issue. POC: https://github.com/njhartwell/pw3nage
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
