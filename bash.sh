#!/bin/bash

# shellcheck disable=SC1090
# shellcheck disable=SC1091
if [ -f "$SSHHOME/.sshrc.d/aliases.sh" ]; then
  source "$SSHHOME/.sshrc.d/aliases.sh"
elif [ -f ~/.sshrc.d/aliases.sh ]; then
  source ~/.sshrc.d/aliases.sh
fi

if [ -f "$SSHHOME/.sshrc.d/prompt_colors.sh" ]; then
  source "$SSHHOME/.sshrc.d/prompt_colors.sh"
elif [ -f ~/.sshrc.d/prompt_colors.sh ]; then
  source ~/.sshrc.d/prompt_colors.sh
fi

bat_opts=${bat_opts:-"--color=always --paging=never"}
# conditionally load since bat is sometimes batcat on debian systems
if [ -f "/usr/bin/bat" ]; then
  alias batcat="bat"
  alias bat='bat $bat_opts'
fi

if [ -f "/usr/bin/batcat" ]; then
  alias bat="batcat"
  alias batcat='batcat $bat_opts'
fi

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

# TODO:
# - add "item -v" fallback
# - fix alias detection in fish shell
# - follow aliases and tell version if possible
# https://itsfoss.gitlab.io/post/how-to-find-a-package-version-in-linux
version() {
  # 'Check if a package/command is installed, then display its version'
  local item="${1:-}"

  if command -v "$item" &>/dev/null; then
    echo -n "[$(command -v "$item")]: "
    if not which "$item" &>/dev/null; then
      echo "script/alias, no version found!"
    else
      if command -v "dpkg" &>/dev/null; then
        dpkg -s "$item" | grep Version | awk '{ print $2 }';
      elif command -v "pacman" &>/dev/null; then
        pacman -Qi "$item" | grep Version | awk '{ print $3 }';
      elif command -v "dnf" &>/dev/null; then
        dnf info "$item" | grep Version;
      elif command -v "rpm" &>/dev/null; then
        rpm -qi "$item" | grep Version;
      elif command -v "zypper" &>/dev/null; then
        zypper info "$item" | grep Version;
      elif command -v "apk" &>/dev/null; then
        apk info "$item" | grep Version;
      fi
    fi
    return 0
  fi

  echo "Error: '$item' is not a command or program."
  return 1
}

HISTCONTROL=ignoreboth
HISTSIZE=2000
HISTFILESIZE=2000

shopt -s histappend
shopt -s checkwinsize
shopt -s globstar

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
  AT_COLOR=$(at_color "${SSH_TTY}")

  PS1=" ${debian_chroot:+($debian_chroot)}${USER_COLOR}\u${AT_COLOR}@${HOST_COLOR}\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
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
    . /etc/bash_completion
  fi
fi
