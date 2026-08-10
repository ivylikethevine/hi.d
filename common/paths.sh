#!/bin/sh
# every path hi uses, in one place. Sourced by fish as well as bash/zsh, so it
# must stay to plain `export NAME=value` lines - no functions, no ${var:-...}.
# $_HI_TMPDIR must already be set (common/bootstrap.sh does that for bash/zsh).

# hi.d itself
export _HI_ROOT="$_HI_TMPDIR/hi.d"
export _HI_LAUNCHER="$_HI_ROOT/hi.sh"
export _HI_SHARED="$_HI_ROOT/common/shared.sh"
export _HI_CHECK="$_HI_ROOT/common/check.sh"
export _HI_HEADER="$_HI_ROOT/common/header.sh"
export _HI_GIT_PROMPT="$_HI_ROOT/common/git_prompt.sh"
export _HI_TARGETS="$_HI_ROOT/common/targets.sh"
export _HI_INSTALL="$_HI_ROOT/scripts/install.sh"
export _HI_TEST_ALIASES="$_HI_ROOT/scripts/aliastest.sh"
export _HI_TEST_COLORS="$_HI_ROOT/scripts/colortest.sh"
export _HI_TEST_SSH="$_HI_ROOT/scripts/sshtest.sh"

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
