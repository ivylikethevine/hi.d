#!/bin/sh
# requires _HI_TMPDIR be set correctly by any scripts sourcing this file, ${var+x}/${var:-} will not work, since this file is sourced by fish
export _HI_ROOT="$_HI_TMPDIR/hi.d"
export _HI_LAUNCHER="$_HI_ROOT/hi.sh"
export _HI_BOOTSTRAP="$_HI_ROOT/common/bootstrap.sh"
export _HI_COLORS="$_HI_ROOT/common/colors.sh"
export _HI_GIT_PROMPT="$_HI_ROOT/common/git_prompt.sh"
export _HI_CHECK="$_HI_ROOT/common/check.sh"
export _HI_HEADER="$_HI_ROOT/common/header.sh"

# user configurable
export _HI_COLOR_OVERRIDES="$_HI_ROOT/data/color_overrides" # optional; hosts/users with no entry get a deterministic hash-derived color
export _HI_PACKAGES_CONFIG="$_HI_ROOT/data/packages_config"

export _HI_VIMRC="$_HI_ROOT/misc/vim.rc"
export _HI_NANORC="$_HI_ROOT/misc/nano.rc"

export _HI_ALIASES="$_HI_ROOT/shells/aliases.sh"
export _HI_BASH_CONFIG="$_HI_ROOT/shells/bash.sh"
export _HI_ZSH_CONFIG="$_HI_ROOT/shells/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/shells/config.fish"

export _HI_APPEND="$_HI_ROOT/scripts/append.sh"
export _HI_INSTALL="$_HI_ROOT/scripts/install.sh"

export _HI_LINUX_PATH="/etc/os-release"

export _HI_SSH_KEY_DIR="$HOME/.ssh"
export _HI_SSH_CONFIG_FILE="$_HI_SSH_KEY_DIR/config"
export _HI_SSH_AUTHORIZED_KEYS="$_HI_SSH_KEY_DIR/authorized_keys"
export _HI_HOME_GIT_CONFIG="$HOME/.gitconfig"

export _HI_HOME_BASHRC="$HOME/.bashrc"
export _HI_HOME_ZSHRC="$HOME/.zshrc"
export _HI_FISH_DIR="$HOME/.config/fish" # used to check if fish installed before appending config
export _HI_HOME_FISH_CONFIG="$_HI_FISH_DIR/config.fish"
