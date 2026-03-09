#!/bin/zsh

hi_root=${HI_ROOT:=~}
# shellcheck source=./common/prompt_colors.sh
source "$hi_root/.hi.d/common/prompt_colors.sh"
# shellcheck source=./common/aliases.sh
source "$hi_root/.hi.d/common/aliases.sh"

export bat_opts=${bat_opts:-"--color=always --paging=never"}
# conditionally load since bat is sometimes batcat on debian systems
if [ -f "/usr/bin/bat" ]; then
  alias batcat="bat"
  alias bat="bat $bat_opts"
fi

if [ -f "/usr/bin/batcat" ]; then
  alias bat="batcat"
  alias batcat="batcat $bat_opts"
fi

# Spelled vew to avoid calling vi
vew() {
  local p="${1:-}"

  if [[ -z "$p" ]]; then
    printf 'Usage: %s <file_or_directory>\n' "${FUNCNAME[0]}" >&2
    return 1
  fi

  if [[ -f "$p" ]]; then
    if [ -f "/usr/bin/batcat" -o -f "/usr/bin/bat" ]; then
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

# https://itsfoss.gitlab.io/post/how-to-find-a-package-version-in-linux
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
  if [ "$item" &>/dev/null ]; then
    echo "[$item]: Package/command not installed!"
  fi
  return 1
}

HISTFILE=~/.zsh_history
HISTSIZE=2000
SAVEHIST=2000

autoload -Uz compinit
compinit
compdef hi=ssh

autoload -Uz promptinit
promptinit
# prompt adam1

bindkey -e

# homekey
bindkey "^[OH" beginning-of-line
bindkey "^[[H" beginning-of-line
bindkey "^[[1;5H" backward-word
bindkey "^[[1;5D" backward-word

# endkey
bindkey "^[OF" end-of-line
bindkey "^[[F" end-of-line
bindkey "^[[1;5F" forward-word
bindkey "^[[1;5C" forward-word

# delkey
bindkey "^[[3;5~" delete-word

setopt histignorealldups sharehistory
unsetopt beep

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2

eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

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
  PLAIN_COLOR=$(plain)

  PS1=" ${debian_chroot:+($debian_chroot)}${USER_COLOR}%n${AT_COLOR}@${HOST_COLOR}%m:${PLAIN_COLOR}%1~\$ "
fi
