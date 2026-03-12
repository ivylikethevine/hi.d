#!/bin/sh
# requires HI_TMPDIR be set correctly by any scripts sourcing this file
export HI_ROOT="$HI_TMPDIR/hi.d"
export _HI_PROMPT_COLORS_PATH="$HI_ROOT/common/prompt_colors.sh"
export _HI_ALIASES_PATH="$HI_ROOT/common/aliases.sh"
export _HI_CHECK_PATH="$HI_ROOT/common/check.sh"
export _HI_HOST_COLOR_FILE="$HI_ROOT/data/host_colors"
export _HI_USER_COLOR_FILE="$HI_ROOT/data/user_colors"
export _HI_GROUP_COLORS="$HI_ROOT/data/group_colors"
export _HI_TRAVEL_CONFIG="$HI_ROOT/data/travel_config"

export _HI_VIMRC="$HI_ROOT/misc/vim.rc"
export _HI_BASHRC="$HI_ROOT/shells/bash.sh"
export _HI_ZSHRC="$HI_ROOT/shells/zsh.zsh"
export _HI_FISH_CONFIG="$HI_ROOT/shells/config.fish"

export _HI_CREATE_COLORS="$HI_ROOT/scripts/create_host_colors.sh"

export _HI_SSH_KEY_DIR="$HOME/.ssh"
export _HI_SSH_CONFIG_FILE="$_HI_SSH_KEY_DIR/config"
export _HI_SSH_AUTHORIZED_KEYS="$_HI_SSH_KEY_DIR/authorized_keys"
export _HI_GIT_CONFIG_PATH="$HOME/.gitconfig"
export _HI_FISH_DIR="$HOME/.config/fish"
export _HI_HOME_BASHRC="$HOME/.bashrc"
export _HI_HOME_ZSHRC="$HOME/.zshrc"
export _HI_HOME_FISH_CONFIG="$HOME/.config/fish/config.fish"
