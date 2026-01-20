#!/bin/zsh
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

# TODO: zsh header
# user customization goes below =============

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
    if not which "$item" &>/dev/null; then
      echo "script/alias, no version found!"
    else
      if command -v "dpkg" &>/dev/null; then
        if dpkg -s "$item" &>/dev/null; then
          dpkg -s "$item" | grep Version | awk '{ print $2 }';
        else
          if "$item" --version &>/dev/null; then
            echo -n "$("$item" --version)"
          elif "$item" -V &>/dev/null; then
            echo -n "$("$item" -V)"
          fi
        fi
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

  echo "[$item]: not a command or program."
  return 1
}

HISTFILE=~/.zsh_history
HISTSIZE=2000
SAVEHIST=2000

autoload -Uz compinit
compinit
compdef sshrc=ssh

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
