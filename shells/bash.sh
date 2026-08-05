#!/bin/bash
# set -eou pipefail # this will cause an interactive shell to exit on first error

# === start required configuration ===
# shellcheck disable=SC2010
_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
source "$_HI_COLORS"
# shellcheck source=./common/git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=./shells/aliases.sh
source "$_HI_ALIASES"

if [ -d "$HOME"/Android ] && [ -d "$HOME"/Android/Sdk ]; then
  export ANDROID_HOME="$HOME"/Android/Sdk # for android dev on linux
fi

export EZA_CONFIG_DIR="$_HI_TMPDIR"/hi.d/misc # for eza theme customization at misc/theme.yml

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
  color_prompt=yes
else
  color_prompt=
fi

if [ "$color_prompt" = yes ]; then
  USER_COLOR=$(user_color "$(whoami)")
  HOST_COLOR=$(host_color "$(_hi_hostname)")
  AT_COLOR=$(at_color)

  HI_PS1=" ${debian_chroot:+($debian_chroot)}${USER_COLOR}\u${AT_COLOR}@${HOST_COLOR}\h${NC} ${BRBLUE}\w${NC}"
else
  HI_PS1=" ${debian_chroot:+($debian_chroot)}\u@\h:\w"
fi

unset color_prompt

if ! shopt -oq posix; then
  if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    . /usr/share/bash-completion/bash_completion
  elif [[ -f /etc/bash_completion ]]; then
    # shellcheck disable=SC1091
    . /etc/bash_completion
  fi
fi

# make `hi`/`exa` complete exactly the way `ssh`/`eza` do, whatever function bash-completion bound to them
_hi_mirror_completion() {
  local target="$1" source_cmd="$2" spec
  if ! complete -p "$source_cmd" &>/dev/null; then
    command -v _completion_loader &>/dev/null && _completion_loader "$source_cmd" &>/dev/null
  fi
  spec=$(complete -p "$source_cmd" 2>/dev/null) || return 0
  eval "${spec% "$source_cmd"} $target"
}
_hi_mirror_completion hi ssh
_hi_mirror_completion exa eza
unset -f _hi_mirror_completion

# modified from: https://github.com/riobard/bash-powerline/blob/master/bash-powerline.sh |
ps1() {
  local symbol="$WHITE \$ $NC"

  # Bash by default expands the content of PS1 unless promptvars is disabled.
  # We must use another layer of reference to prevent expanding any user
  # provided strings, which would cause security issues.
  # POC: https://github.com/njhartwell/pw3nage
  if shopt -q promptvars; then
    __powerline_git_info="$(_hi_git_prompt)"
    local git="\${__powerline_git_info}"
  else
    local git
    git="$(_hi_git_prompt)"
  fi

  PS1="$HI_PS1$git$symbol"
}

PROMPT_COMMAND="ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
# end from: https://github.com/riobard/bash-powerline/blob/master/bash-powerline.sh |
# === end required configuration ===

HISTCONTROL=ignoreboth
HISTSIZE=2000
HISTFILESIZE=2000

PROMPT_DIRTRIM=2
HISTCONTROL="erasedups:ignoreboth"
export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"

shopt -s histappend
shopt -s checkwinsize
shopt -s globstar
shopt -s cmdhist

bind "set completion-ignore-case on"
bind "set completion-map-case on"
bind "set show-all-if-ambiguous on"
bind "set mark-symlinked-directories on"

bind Space:magic-space
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\e[C": forward-char'
bind '"\e[D": backward-char'
