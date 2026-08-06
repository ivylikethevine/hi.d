#!/bin/zsh

# === start required configuration ===
_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/bootstrap.sh
source "$_HI_TMPDIR/hi.d/common/bootstrap.sh"
# shellcheck source=./common/git_prompt.sh
source "$_HI_GIT_PROMPT"
# shellcheck source=./shells/aliases.sh
source "$_HI_ALIASES"

if [ -d "$HOME"/Android ] && [ -d "$HOME"/Android/Sdk ]; then
  export ANDROID_HOME="$HOME"/Android/Sdk # for android dev on linux
fi

export EZA_CONFIG_DIR="$_HI_TMPDIR"/hi.d/misc # for eza theme customization at misc/theme.yml

# required for sanity & some of the other scripts we run
setopt KSH_ARRAYS

# header/coloring
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
  color_prompt=yes
else
  color_prompt=
fi

setopt prompt_subst

if [ "$color_prompt" = yes ]; then
  export CLICOLOR=1
  export LSCOLORS=gafacadabaegedabagacad
  USER_COLOR=$(user_color)
  USER_COLOR="${USER_COLOR//br/}"
  HOST_COLOR=$(host_color)
  HOST_COLOR="${HOST_COLOR//br/}"
  AT_COLOR=plain
  if [[ -v SSH_TTY ]]; then
    AT_COLOR=yellow
  fi
  PS1=$' ${debian_chroot:+($debian_chroot)}%F{$USER_COLOR}%n%f%F{$AT_COLOR}@%f%F{$HOST_COLOR}%m%f%F{cyan} %~%f%F{plain}%{$(_hi_git_prompt)%} > '
else
  PS1=$' ${debian_chroot:+($debian_chroot)}%n@%m %~%{$(_hi_git_prompt)%} > '
fi
# === end required configuration ===

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
_hi() {
  local -a hosts descs
  local cfg="${_HI_SSH_CONFIG_FILE:-$HOME/.ssh/config}"
  if [[ -f $cfg ]]; then
    local line h
    while IFS=$' ' read -r line; do
      local -a words=(${=line})
      ((${#words} >= 2)) || continue
      [[ ${(L)words[1]} == host ]] || continue
      for h in ${words[2,-1]}; do
        [[ $h == *[*?]* ]] && continue
        hosts+=("$h")
        descs+=("ssh - $h")
      done
    done <"$cfg"
  fi

  if (($+commands[docker])); then
    local name
    for name in ${(f)"$(docker ps --format '{{.Names}}' 2>/dev/null)"}; do
      [[ -z $name ]] && continue
      hosts+=("$name")
      descs+=("docker - $name")
    done
  fi

  if (($+commands[nomad])); then
    local job id
    for job in ${(f)"$(nomad job status 2>/dev/null | tail -n +2 | awk '{print $1}')"}; do
      [[ -z $job ]] && continue
      for id in ${(f)"$(nomad job allocs -t '{{range .}}{{if eq .ClientStatus "running"}}{{printf "%.8s" .ID}}{{"\n"}}{{end}}{{end}}' "$job" 2>/dev/null)"}; do
        [[ -z $id ]] && continue
        hosts+=("$id")
        descs+=("nomad - $id")
      done
    done
  fi

  compadd -d descs -a hosts
}
compdef _hi hi
compdef exa=eza
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
