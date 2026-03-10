#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if ! command cecho 2>/dev/null; then
  # shellcheck source=./common/prompt_colors.sh
  source "$SCRIPT_DIR/common/prompt_colors.sh"
fi

hi_start="# hi-config-start"
hi_end="# hi-config-end"
copy_time=-1

# # # See: hi.sh/say_hi()
# # On local machines, ~/.hi.d has our configs.
# # On remote machines, we need to go to /tmp/.(whoami).hi.XXXX/.hi.d
hi_root=${HI_ROOT:-~/.hi.d}

# required
spacer() {
  cecho " | " "$NC" 1
}

# required
timestamp() {
  spacer
  local human_centric_date_format="+%a %b %-e %Y %H:%M:%S %Z"
  echo -e "$BRBLUE$(date -u "$human_centric_date_format")   $NC|$BRYELLOW   $(date "$human_centric_date_format")$NC"
  spacer
}

# required
configure_file() {
  local target="$1"
  local source="$2"
  touch "$target"
  if test -f "$hi_root/.hi.d/$source"; then
    if ! grep -q "$hi_start" "$target"; then
      {
        echo "$hi_start"
        cat "$hi_root/.hi.d/$source"
        echo "$hi_end"
      } >>"$target"
    fi
  fi
}

# required
clean_all() {
  shells=(~/.bashrc ~/.zshrc ~/.config/fish/config.fish)
  for shell in "${shells[@]}"; do
    if test -f "$shell"; then
      sed -i "/^$hi_start/,/^$hi_end/d" -- "$shell"
    fi
  done
}

# required
configure_all() {
  if command -v "vim" &>/dev/null; then
    # Will cause errors if we load this with only VI
    export VIMINIT="let \$MYVIMRC='$hi_root/.hi.d/misc/vim.rc' | source \$MYVIMRC"
  fi
  configure_file ~/.bashrc shells/bash.sh
  configure_file ~/.zshrc shells/zsh.zsh
  if [ -d ~/.config/fish ]; then
    # This directory won't exist if fish isn't installed
    configure_file ~/.config/fish/config.fish shells/config.fish
  fi
}

# required
timers() {
  spacer
  cecho "load: $(echo "$(date +%s.%N) $load_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')s | copy: ${copy_time}s"
}

check_packages() {
  # shellcheck source=./common/check.sh
  source "$hi_root"/.hi.d/common/check.sh
  packages
  basics
  systems
  tools
}

system_info() {
  cecho "$(uname -s)" "$YELLOW" 1
  spacer
  cecho "$(uname -m)" "$PURPLE" 1
  spacer
  cecho "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')" "$GREEN" 1
  spacer
  cecho "CPUs: $(nproc)" "$BLUE" 1
  spacer
  cecho "RAM: $(free -h --giga | awk '/^Mem:/ {print $2}GB') " "$CYAN"
}

git_identity() {
  spacer
  if [ -f ~/.gitconfig ]; then
    cecho "Git ID: " "$CYAN" 1
    cecho "$(grep email ~/.gitconfig | tail -n1 | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }')" "$YELLOW" 1
  else
    cecho "No Git ID Found..." "$YELLOW" 1
  fi
}

docker_count() {
  spacer
  if command -v "docker" &>/dev/null; then
    cecho "Containers: $(docker container ls | wc -l | awk '{ print $1 - 1 }')" "$BLUE" 1
  else
    cecho "No docker :(" "$BRYELLOW" 1
  fi
}

key_count() {
  spacer
  if [ -f ~/.ssh/authorized_keys ]; then
    cecho "Auth: $(wc -l ~/.ssh/authorized_keys | awk '{ print $1 }')" "$RED" 1
  else
    cecho "Auth: 0!" "$RED" 1
  fi
  spacer
  cecho "Pub: $(find ~/.ssh -type f -name "*.pub" | wc -l)" "$PURPLE"
}

# TODO: Test
# shellcheck disable=SC2329
tmuxrc() {
  local TMUXDIR="/tmp/tmuxrc"
  if ! [ -d "$TMUXDIR" ]; then
    rm -rf "$TMUXDIR"
    mkdir -p "$TMUXDIR"
  fi
  rm -rf "$TMUXDIR"/.hi.d
  cp -r "$hi_root"/bashrc.hi "$hi_root"/hi "$hi_root"/.hi.d "$TMUXDIR"
  hi_root="$TMUXDIR" SHELL="$TMUXDIR"/bashrc.hi /usr/bin/tmux -S "$TMUXDIR"/tmuxserver "$@"
  SHELL=$(which bash)
  export SHELL
}

# required
load() {
  load_start_time=$(date +%s.%N)

  trap 'clean_all' exit

  HOST_COLOR=$(host_color "$(hostname)")
  echo -e "$BRGREEN~~~~~~~~~~~~~~~~~~~ Connected to ${NC}[$HOST_COLOR$(hostname)${NC}]$BRGREEN ~~~~~~~~~~~~~~~~~~~~~~~~$NC"
  timestamp

  # optional header items
  system_info
  git_identity
  docker_count
  key_count
  check_packages
  configure_all

  spacer
  cecho "hi loaded with... " "$BRCYAN" 1

  if command -v "fish" &>/dev/null; then
    cecho "fish shell! :^)" "$GREEN" 1
    timers
    fish -C "set fish_greeting ''" -i
  elif command -v "zsh" &>/dev/null; then
    cecho "zsh shell! :)" "$PURPLE" 1
    timers
    zsh -i
  else
    cecho "only bash today :(" "$RED" 1
    timers
    bash -i
  fi

  cecho " $(du -sh --apparent-size "$HI_ROOT"/.hi.d | awk '{ print $1 }') " "$NC" 1
  echo -e "$BRRED~~~~~~~~~~~~~~~~~ Disconnected from ${NC}[$HOST_COLOR$(hostname)${NC}]$BRRED ~~~~~~~~~~~~~~~~~~~~~$NC"
  timestamp
  cecho "hi closing! " "$BRPURPLE"
  clean_all
  exit 0
}
