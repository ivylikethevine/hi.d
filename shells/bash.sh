#!/bin/bash
# set -euo pipefail # cannot be enabled: an interactive shell would exit on the first error

# === start required configuration ===
# shellcheck source=../common/bootstrap.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../common/git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=./aliases.sh
source "$_HI_ALIASES"

_hi_interactive_extras
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

if tput setaf 1 >/dev/null 2>&1; then
  HI_PS1=" ${debian_chroot:-}$(_hi_user_escape)\u$(_hi_at_color)@$(_hi_host_escape)\h$NC $BRBLUE\w$NC"
else
  HI_PS1=" ${debian_chroot:-}\u@\h:\w"
fi

if ! shopt -oq posix; then
  # shellcheck disable=SC1091
  source /usr/share/bash-completion/bash_completion 2>/dev/null ||
    source /etc/bash_completion 2>/dev/null
fi

# complete `hi` from the same target list zsh/fish use, and make `exa` complete
# exactly the way `eza` does, whatever bash-completion bound to it
function _hi_complete() {
  mapfile -t COMPREPLY < <(compgen -W "$(sh "$_HI_TARGETS" | cut -f1)" -- "${COMP_WORDS[COMP_CWORD]}")
}
complete -F _hi_complete hi
command -v _completion_loader &>/dev/null && _completion_loader eza &>/dev/null
_hi_eza_spec=$(complete -p eza 2>/dev/null) && eval "${_hi_eza_spec% eza} exa"
unset _hi_eza_spec

# modified from: https://github.com/riobard/bash-powerline/blob/master/bash-powerline.sh
function ps1() {
  # Bash expands the content of PS1 unless promptvars is disabled, so the git
  # info goes through another layer of reference - expanding user provided
  # strings would be a security issue. POC: https://github.com/njhartwell/pw3nage
  if shopt -q promptvars; then
    __powerline_git_info="$(_hi_git_prompt)"
    PS1="$HI_PS1\${__powerline_git_info}$NC \$ "
  else
    PS1="$HI_PS1$(_hi_git_prompt)$NC \$ "
  fi
}
PROMPT_COMMAND="ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
# === end required configuration ===

HISTSIZE=2000
HISTFILESIZE=2000
HISTCONTROL="erasedups:ignoreboth"
export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"
PROMPT_DIRTRIM=2

shopt -s histappend checkwinsize globstar cmdhist

bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set show-all-if-ambiguous on"
bind "set mark-symlinked-directories on"

bind Space:magic-space
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\e[C": forward-char'
bind '"\e[D": backward-char'
