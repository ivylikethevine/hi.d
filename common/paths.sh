#!/bin/sh
# requires _HI_TMPDIR be set correctly by any scripts sourcing this file
# ${var+x}/${var:-} will not work, since this file is sourced by fish

# base paths for other scripts to use
export _HI_ROOT="$_HI_TMPDIR/hi.d"
export _HI_LAUNCHER="$_HI_ROOT/hi.sh"
export _HI_BOOTSTRAP="$_HI_ROOT/common/bootstrap.sh"
export _HI_GIT_PROMPT="$_HI_ROOT/common/git_prompt.sh"
export _HI_CHECK="$_HI_ROOT/common/check.sh"
export _HI_HEADER="$_HI_ROOT/common/header.sh"
export _HI_COLORS="$_HI_ROOT/common/colors.sh"

# user configurable
export _HI_COLOR_OVERRIDES="$_HI_ROOT/data/color_overrides"
export _HI_PACKAGES="$_HI_ROOT/data/packages"
export _HI_VIMRC="$_HI_ROOT/misc/vim.rc"
export _HI_NANORC="$_HI_ROOT/misc/nano.rc"
export _HI_ALIASES="$_HI_ROOT/shells/aliases.sh"
export _HI_BASHRC="$_HI_ROOT/shells/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/shells/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/shells/config.fish"

# scripts
export _HI_INSTALL="$_HI_ROOT/scripts/install.sh"
export _HI_TEST_ALIASES="$_HI_ROOT/scripts/test_aliases.sh"

# re-used in other scripts
export _HI_LINUX_RELEASE="/etc/os-release"
export _HI_SSH_DIR="$HOME/.ssh"
export _HI_SSH_CONFIG="$_HI_SSH_DIR/config"
export _HI_SSH_AUTHORIZED_KEYS="$_HI_SSH_DIR/authorized_keys"
export _HI_HOME_GITCONFIG="$HOME/.gitconfig"
export _HI_HOME_BASHRC="$HOME/.bashrc"
export _HI_HOME_ZSHRC="$HOME/.zshrc"
export _HI_HOME_FISH_DIR="$HOME/.config/fish" # used to check if fish installed before appending config
export _HI_HOME_FISH_CONFIG="$_HI_HOME_FISH_DIR/config.fish"
