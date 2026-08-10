#!/bin/sh
# every path hi uses, in one place. Sourced by fish as well as bash/zsh, so it
# must stay to plain `export NAME=value` lines (plus simple `[ ] && export`
# guards) - no functions, no ${var:-...}.
# $_HI_HOME must already be set (common/bootstrap.sh does that for bash/zsh).
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later

# hi.d itself
export _HI_ROOT="$_HI_HOME/hi.d"
export _HI_LAUNCHER="$_HI_ROOT/hi.sh"
export _HI_SHARED="$_HI_ROOT/common/shared.sh"
export _HI_CHECK="$_HI_ROOT/common/check.sh"
export _HI_HEADER="$_HI_ROOT/common/header.sh"
export _HI_GIT_PROMPT="$_HI_ROOT/common/git_prompt.sh"
export _HI_TARGETS="$_HI_ROOT/common/targets.sh"
export _HI_INSTALL="$_HI_ROOT/scripts/install.sh"
export _HI_UNINSTALL="$_HI_ROOT/scripts/uninstall.sh"
export _HI_COLOR_PREVIEW="$_HI_ROOT/scripts/color_preview.sh"
export _HI_TEST_ALIASES="$_HI_ROOT/scripts/alias_test.sh"
export _HI_TEST_SSH="$_HI_ROOT/scripts/ssh_test.sh"
export _HI_TEST_DOCKER="$_HI_ROOT/scripts/docker_test.sh"
export _HI_TEST_SHELLCHECK="$_HI_ROOT/scripts/shellcheck_test.sh"

# user configurable
export _HI_COLORS="$_HI_ROOT/misc/colors"
export _HI_PACKAGES="$_HI_ROOT/misc/packages"
export _HI_VIMRC="$_HI_ROOT/misc/vim.rc"
export _HI_NANORC="$_HI_ROOT/misc/nano.rc"
export _HI_ALIASES="$_HI_ROOT/shells/aliases.sh"
export _HI_BASHRC="$_HI_ROOT/shells/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/shells/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/shells/config.fish"

# host paths hi reads or appends to
export _HI_LINUX_RELEASE="/etc/os-release"
export _HI_SSH_DIR="$HOME/.ssh"
export _HI_SSH_CONFIG="$HOME/.ssh/config"
export _HI_SSH_AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"
export _HI_HOME_BASHRC="$HOME/.bashrc"
export _HI_HOME_ZSHRC="$HOME/.zshrc"
export _HI_HOME_FISH_DIR="$HOME/.config/fish" # absent unless fish is installed
export _HI_HOME_FISH_CONFIG="$HOME/.config/fish/config.fish"

export _HI_HUMAN_CENTRIC_DATE="+%a %b %-e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %-e %y %H:%M %Z"

# required helpers/commands
alias hi_install="[ -f $_HI_INSTALL ] && $_HI_INSTALL"
alias hi_uninstall="[ -f $_HI_UNINSTALL ] && $_HI_UNINSTALL"
alias hi_configure="[ -f $_HI_INSTALL ] && $_HI_INSTALL --features-only"
alias hi_reconfigure="hi_configure"
alias hi_check_configs="[ -f $_HI_INSTALL ] && $_HI_INSTALL --check-configs"
alias hi_update="git -C $_HI_ROOT pull"
alias hi_status="git -C $_HI_ROOT status"
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"
alias hi_color_preview="[ -f $_HI_COLOR_PREVIEW ] && $_HI_COLOR_PREVIEW"
alias hi_packages_preview="sh -c 'source \"$_HI_CHECK\" && full_check'"
alias hi_test_aliases="[ -f $_HI_TEST_ALIASES ] && $_HI_TEST_ALIASES"
alias hi_test_ssh="[ -f $_HI_TEST_SSH ] && $_HI_TEST_SSH"
alias hi_test_docker="[ -f $_HI_TEST_DOCKER ] && $_HI_TEST_DOCKER"
alias hi_test_shellcheck="[ -f $_HI_TEST_SHELLCHECK ] && $_HI_TEST_SHELLCHECK"
alias hi_test_all="hi_test_aliases && hi_test_ssh && hi_test_docker && hi_test_shellcheck"

# android dev on linux; `|| true` since paths.sh is sourced under callers'
# `set -e` (bootstrap.sh et al) and a false test here would otherwise abort them
[ -d "$HOME/Android/Sdk" ] && export ANDROID_HOME="$HOME/Android/Sdk" || true

# feature toggles - set any of these to 1 to turn that piece of hi's shell
# config off everywhere (locally and on every host you `hi` to, since hi.d is
# copied as-is). scripts/install.sh asks about these and writes the lines
# below the marker for you; uncomment by hand instead if you'd rather skip
# the prompts.
# export _HI_DISABLE_HEADER=1   # common/header.sh's connect/disconnect banner
# export _HI_DISABLE_PROMPT=1   # the colored user@host:cwd prompt
# export _HI_DISABLE_PERSONAL=1 # history size, keybindings, completion tweaks
# export _HI_DISABLE_GIT_STATUS=1 # git status in the prompt
# export _HI_DISABLE_EDITORS=1  # the vim/nano aliases pointing at misc/vim.rc, misc/nano.rc
# export _HI_DISABLE_ALIASES=1  # the personal aliases in shells/aliases.sh (sudo, cat/eza, git, docker, pacman/apt, etc) - hi's own essentials in common/bootstrap.sh always load regardless

# local-only disable - set to 1 to turn off every toggle above on the machine
# hi.d is installed on, while still applying them when hi is used to reach a
# remote host/container/alloc. _HI_REMOTE_SESSION is exported by load.sh, the
# chainload entry point every remote path goes through and the local
# install's own shells never do, so it's what tells the two apart.
export _HI_DISABLE_LOCAL

[ -z "$_HI_DISABLE_LOCAL" ] && [ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && {
  export _HI_DISABLE_HEADER=1
  export _HI_DISABLE_PROMPT=1
  export _HI_DISABLE_PERSONAL=1
  export _HI_DISABLE_GIT_STATUS=1
  export _HI_DISABLE_EDITORS=1
  export _HI_DISABLE_ALIASES=1
} || true
