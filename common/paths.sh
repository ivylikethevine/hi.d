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

# tests - only the two entry points every session needs
export _HI_TEST_LIB="$_HI_ROOT/tests/test_lib.sh"
export _HI_TEST_RUN="$_HI_ROOT/tests/test_runner.sh"

# user configurable
# settings.sh holds every _HI_DISABLE_*/_HI_HEADER_*/_HI_MAX_WIDTH choice
# scripts/install.sh writes. Gitignored, so configuring hi.d doesn't dirty the
# checkout and `hi_update`'s git pull still applies; not in hi.sh's
# $_HI_EXCLUDE, so the choices ride along to every target. See the local-only
# gate below for why it is sourced before this file, not from it.
export _HI_SETTINGS="$_HI_ROOT/misc/settings.sh"
export _HI_COLORS="$_HI_ROOT/misc/colors"
export _HI_PACKAGES="$_HI_ROOT/misc/packages"
export _HI_VIMRC="$_HI_ROOT/misc/vim.rc"
export _HI_NANORC="$_HI_ROOT/misc/nano.rc"
# eza reads its theme from a *directory* (misc/theme.yml), not a file path
export _HI_THEME_DIR="$_HI_ROOT/misc"
export _HI_ALIASES="$_HI_ROOT/shells/aliases.sh"
export _HI_BASHRC="$_HI_ROOT/shells/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/shells/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/shells/config.fish"

# The contract between install.sh and uninstall.sh: the tag install writes on
# every line it owns, and the symlink it manages. Here rather than in either
# script because a marker reworded in one alone would make hi_uninstall a
# silent no-op that still reports success.
export _HI_MARKER="# added by hi during install"
export _HI_LINK="/usr/bin/hi"

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

# required helpers/commands.
# hi.sh's $_HI_EXCLUDE strips scripts/, tests/ and .git from the tree copied to
# a target, so these aren't there in a hi session. Each says so rather than
# silently doing nothing, and each tests the *negation* first: `[ -f x ] && cmd
# || echo` would also print the message whenever cmd itself exited non-zero.
# The message expands at alias-definition time like the $_HI_* paths beside it,
# which is what the SC2139 disable at the top is for, so it stays fish-safe.
export _HI_NO_CHECKOUT="needs the full hi.d checkout - not available in a hi session"
alias hi="$_HI_LAUNCHER"
alias hi_install="[ ! -f $_HI_INSTALL ] && echo 'hi_install $_HI_NO_CHECKOUT' || $_HI_INSTALL"
alias hi_uninstall="[ ! -f $_HI_UNINSTALL ] && echo 'hi_uninstall $_HI_NO_CHECKOUT' || $_HI_UNINSTALL"
alias hi_configure="[ ! -f $_HI_INSTALL ] && echo 'hi_configure $_HI_NO_CHECKOUT' || $_HI_INSTALL --features-only"
alias hi_reconfigure="hi_configure"
alias hi_check_configs="[ ! -f $_HI_INSTALL ] && echo 'hi_check_configs $_HI_NO_CHECKOUT' || $_HI_INSTALL --check-configs"
# .git rather than a file: $_HI_EXCLUDE strips it, so this is the right test here
alias hi_update="[ ! -d $_HI_ROOT/.git ] && echo 'hi_update $_HI_NO_CHECKOUT' || git -C $_HI_ROOT pull"
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"
alias hi_color_preview="[ ! -f $_HI_COLOR_PREVIEW ] && echo 'hi_color_preview $_HI_NO_CHECKOUT' || $_HI_COLOR_PREVIEW"
# no guard: common/ *is* shipped to targets, so check.sh is always there
alias hi_packages_preview="bash -c 'source \"$_HI_CHECK\" && full_check'"
alias hi_test="[ ! -f $_HI_TEST_RUN ] && echo 'hi_test $_HI_NO_CHECKOUT' || $_HI_TEST_RUN"

# The gate below reads the settings scripts/install.sh writes, so $_HI_SETTINGS
# is sourced ahead of this file rather than from it: no single include line is
# valid in all four shells that source paths.sh (`.` is not fish syntax,
# `source` is not dash's). Each entry point does it instead, knowing its own
# shell - common/bootstrap.sh (bash/zsh), common/shared.sh (reached directly by
# fish's `bash -c`), shells/config.fish, and hi.sh's _hi_fallback_rc. Add a
# fifth here if a new one appears.
#
# local-only disable logic. _HI_REMOTE_SESSION is exported by load.sh, which
# every remote path chainloads and the local install's shells never do, so it
# is what tells the two apart.
export _HI_DISABLE_LOCAL
export _HI_REMOTE_SESSION

[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && {
  export _HI_DISABLE_HEADER=1
  export _HI_DISABLE_PROMPT=1
  export _HI_DISABLE_PERSONAL=1
  export _HI_DISABLE_GIT_STATUS=1
  export _HI_DISABLE_EDITORS=1
  export _HI_DISABLE_ALIASES=1
} || true
