#!/bin/bash
set -eou pipefail

# === start required configuration ===
HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
source "$_HI_COLORS"
# shellcheck source=./../common/aliases.sh
source "$_HI_ALIASES"

# header/coloring
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac
force_color_prompt=yes
if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    color_prompt=yes
  else
    color_prompt=
  fi
fi
if [ "$color_prompt" = yes ]; then
  USER_COLOR=$(user_color "$(whoami)")
  HOST_COLOR=$(host_color "$(hostname)")
  AT_COLOR=$(at_color)

  PS1=" ${debian_chroot:+($debian_chroot)}${USER_COLOR}\u${AT_COLOR}@${HOST_COLOR}\h\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$ "
else
  PS1=" ${debian_chroot:+($debian_chroot)}\u@\h:\w\$ "
fi
unset color_prompt force_color_prompt
case "$TERM" in
xterm* | rxvt*)
  PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
  ;;
*) ;;
esac
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
if ! shopt -oq posix; then
  if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    . /usr/share/bash-completion/bash_completion
  elif [[ -f /etc/bash_completion ]]; then
    # shellcheck disable=SC1091
    . /etc/bash_completion
  fi
fi
# === end required configuration ===


# Spelled vew to avoid calling vi
vew() {
  local p="${1:-}"

  if [[ -z "$p" ]]; then
    printf 'Usage: %s <file_or_directory>\n' "${FUNCNAME[0]}" >&2
    return 1
  fi

  if [[ -f "$p" ]]; then
    if [ -f "/usr/bin/batcat" ] || [ -f "/usr/bin/bat" ]; then
      bat "$@"
    else
      cat -- "$p"
    fi
  elif [[ -d "$p" ]]; then
    ls "$@"
  else
    printf 'Error: %s is not a regular file or directory.\n' "$p" >&2
    return 2
  fi
}

version() {
  # 'Check if a package/command is installed, then display its version'
  local item="${1:-}"

  if command -v "$item" &>/dev/null; then
    echo -n "[$(command -v "$item")]: "
    if command -v "dpkg" &>/dev/null; then
      if dpkg -s "$item" &>/dev/null; then
        dpkg -s "$item" | grep Version | awk '{ print $2 }';
        return 0;
      fi
    elif command -v "pacman" &>/dev/null; then
      if pacman -Qi "$item" &>/dev/null; then
        pacman -Qi "$item" | grep Version | awk '{ print $3 }';
        return 0;
      fi
    elif command -v "dnf" &>/dev/null; then
      if dnf info "$item" &>/dev/null; then
        dnf info "$item" | grep Version;
        return 0;
      fi
    elif command -v "rpm" &>/dev/null; then
      if rpm -qi "$item" &>/dev/null; then
        rpm -qi "$item" | grep Version;
        return 0;
      fi
    elif command -v "zypper" &>/dev/null; then
      if zypper info "$item" &>/dev/null; then
        zypper info "$item" | grep Version;
        return 0;
      fi
    elif command -v "apk" &>/dev/null; then
      if apk info "$item" &>/dev/null; then
        apk info "$item" | grep Version;
        return 0;
      fi
    fi
    if "$item" --version &>/dev/null; then
      echo -n "$("$item" --version)"
      return 0;
    elif "$item" -V &>/dev/null; then
      echo -n "$("$item" -V)"
      return 0;
    fi
    echo "Local function/alias, version unknowable..."
    return 0
  fi
  if "$item" &>/dev/null; then
    echo "[$item]: Package/command not installed!"
  fi
  return 1
}

HISTCONTROL=ignoreboth
HISTSIZE=2000
HISTFILESIZE=2000

PROMPT_DIRTRIM=2
PROMPT_COMMAND='history -a'
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
