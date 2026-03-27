#!/bin/bash
# set -eou pipefail # this will cause an interactive shell to exit on first error

# === start required configuration ===
HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
source "$_HI_COLORS"
# shellcheck source=./../common/aliases.sh
source "$_HI_ALIASES"

# TODO: Test autocomplete for hi, exa, etc.
complete -C hi ssh
complete -C exa eza

if [ -d "$HOME"/Android ] && [ -d "$HOME"/Android/Sdk ]; then
  export ANDROID_HOME="$HOME"/Android/Sdk # for android dev on linux
fi

export EZA_CONFIG_DIR="$HI_TMPDIR"/hi.d/misc # for eza theme customization at misc/theme.yml

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

case "$TERM" in
xterm* | rxvt*)
  HI_PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*) ;;
esac

case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
  color_prompt=yes
else
  color_prompt=
fi

if [ "$color_prompt" = yes ]; then
  USER_COLOR=$(user_color "$(whoami)")
  HOST_COLOR=$(host_color "$(hostname)")
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

# modified from: https://github.com/riobard/bash-powerline/blob/master/bash-powerline.sh |
__git_info() {
  local git_eng="env LANG=C git"

  local ref
  ref=$($git_eng symbolic-ref --short HEAD 2>/dev/null)

  if [[ ! -n "$ref" ]]; then
    ref=$($git_eng describe --tags --always 2>/dev/null)
  fi

  [[ -n "$ref" ]] || return

  local marks

  # TODO: Modify to list number of locally modified files + commits behind
  # scan first two lines of output from `git status`
  while IFS= read -r line; do
    if [[ $line =~ ^## ]]; then # header line
      [[ $line =~ ahead\ ([0-9]+) ]] && marks+=" ↑${BASH_REMATCH[1]}"
      [[ $line =~ behind\ ([0-9]+) ]] && marks+=" ↓${BASH_REMATCH[1]}"
    else # branch is modified if output contains more lines after the header line
      marks="*$marks"
      break
    fi
  done < <($git_eng status --porcelain --branch 2>/dev/null) # note the space between the two <

  printf " ($BRPURPLE%s%s$NC)" "$ref" "$marks"
}

ps1() {
  if [ $? -eq 0 ]; then
    local symbol="$GREEN \$ $NC"
  else
    local symbol="$RED \$ $NC"
  fi

  # Bash by default expands the content of PS1 unless promptvars is disabled.
  # We must use another layer of reference to prevent expanding any user
  # provided strings, which would cause security issues.
  # POC: https://github.com/njhartwell/pw3nage
  if shopt -q promptvars; then
    __powerline_git_info="$(__git_info)"
    local git="$WHITE\${__powerline_git_info}$NC"
  else
    local git
    git="$WHITE$(__git_info)$NC"
  fi

  PS1="$HI_PS1$git$symbol"
}

hash git 2>/dev/null || {
  PS1="$HI_PS1 \$"
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

# TODO: Determine best way to switch this/configure on install
# # If we are in bash and there is no fish shell running
# # drop from bash into fish (for interactive, login shells).
# # source: https://wiki.archlinux.org/title/Fish#Modify_.bashrc_to_drop_into_fish
# if grep -qv 'fish' /proc/$PPID/comm && [[ ${SHLVL} == [1,2] ]]; then
#  	shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=''
#  	exec fish "$LOGIN_OPTION"
# fi
