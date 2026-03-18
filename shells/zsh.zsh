#!/bin/zsh

# === start required configuration ===
HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
source "$_HI_COLORS"
# shellcheck source=./common/aliases.sh
source "$_HI_ALIASES"

# required for sanity & some of the other scripts we run
setopt KSH_ARRAYS

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


# git status
autoload -Uz vcs_info
precmd() { vcs_info }
setopt prompt_subst
zstyle ':vcs_info:git:*' formats '%b'

if [ "$color_prompt" = yes ]; then
  export CLICOLOR=1
  export LSCOLORS=gafacadabaegedabagacad
  # TODO: Improve this conversion from fish colors to zsh colors
  USER_COLOR=$(user_color)
  if [[ "$USER_COLOR" = "bryellow" ]]; then
    USER_COLOR=yellow
  fi
  HOST_COLOR=$(host_color)
  if [[ "$HOST_COLOR" = "bryellow" ]]; then
    HOST_COLOR=yellow
  fi
  AT_COLOR=plain
  if [[ ! -z ${SSH_TTY+x} ]]; then
    AT_COLOR=yellow
  fi
  PS1=$' ${debian_chroot:+($debian_chroot)}%F{$USER_COLOR}%n%f%F{$AT_COLOR}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain} $vcs_info_msg_0_| '
else
  PS1=$' ${debian_chroot:+($debian_chroot)}%n@%m %~ $vcs_info_msg_0_| '
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

# completion configuration
zmodload zsh/complist
autoload -Uz compinit
autoload -Uz promptinit
compinit
compdef hi=ssh
promptinit

# configuration
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
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/.zcompcache"
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' complete-options true
zstyle ':completion:*' group-name ''

zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:*:-command-:*:*' group-order alias builtins functions commands

zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
