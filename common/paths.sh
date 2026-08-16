#!/bin/sh
# every path hi uses, in one place. Sourced by fish as well as bash/zsh, so it
# must stay to plain `export NAME=value` lines (plus simple `[ ] && export`
# guards) - no functions, no ${var:-...}.
# $_HI_HOME and $_HI_CONFIG_DIR must already be set (common/core.sh does that
# for bash/zsh); see the note above the user-configurable block below.
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
# shellcheck disable=SC2153 # $_HI_HOME is set by whoever sources this, not here

# hi.d itself
export _HI_ROOT="$_HI_HOME/hi.d"
export _HI_LAUNCHER="$_HI_ROOT/hi.sh"
export _HI_CORE="$_HI_ROOT/common/core.sh"
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
#
# Your own settings, colors and packages live in $_HI_CONFIG_DIR, outside the
# tree, so that configuring hi.d neither dirties the checkout (which would stop
# `hi_update`'s git pull applying cleanly) nor needs the tree to be writable at
# all - a package manager owns /usr/share, not you. hi.sh ships whichever of
# them you have to every target, since $_HI_EXCLUDE only ever carried the
# in-tree copies.
#
# $_HI_CONFIG_DIR itself can't be derived here: it wants
# ${XDG_CONFIG_HOME:-$HOME/.config}/hi.d and fish has no such expansion. Each
# entry point computes it before sourcing this file, knowing its own shell -
# the same three sites listed by the local-only gate at the bottom.
#
# colors and packages are each a *pair*: the default the tree ships, then the
# overlay's copy when the user has made one. Per file, not merged - anything you
# haven't overridden keeps tracking the tree's copy, so `hi_update` still
# delivers new defaults for the rest. settings.sh has no in-tree half:
# scripts/install.sh is the only thing that writes it and it writes here, so the
# path is unguarded - on a fresh machine no `[ -f ]` test could find it yet, and
# install.sh must still know where to put it. It holds every
# _HI_DISABLE_*/_HI_HEADER_*/_HI_MAX_WIDTH choice, and is sourced ahead of this
# file rather than from it - see the local-only gate below.
export _HI_SETTINGS="$_HI_CONFIG_DIR/settings.sh"
export _HI_COLORS="$_HI_ROOT/misc/colors"
[ -f "$_HI_CONFIG_DIR/colors" ] && export _HI_COLORS="$_HI_CONFIG_DIR/colors"
export _HI_PACKAGES="$_HI_ROOT/misc/packages"
[ -f "$_HI_CONFIG_DIR/packages" ] && export _HI_PACKAGES="$_HI_CONFIG_DIR/packages"
export _HI_VIMRC="$_HI_ROOT/misc/vim.rc"
export _HI_NANORC="$_HI_ROOT/misc/nano.rc"
# eza reads its theme from a *directory* (misc/theme.yml), not a file path
export _HI_THEME_DIR="$_HI_ROOT/misc"
export _HI_ALIASES="$_HI_ROOT/shells/aliases.sh"
export _HI_BASHRC="$_HI_ROOT/shells/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/shells/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/shells/config.fish"

# The tag scripts/install.sh writes on every line it owns, and the symlink it
# manages. Here with every other _HI_* constant rather than inside that script,
# so that both halves of it (install and --uninstall) and anything else that
# ever has to recognise hi's lines read the strings from one place.
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

# %e, not %-e: the `-` (no-padding) flag is a GNU strftime extension, and BSD
# strftime - macOS, and every *BSD target - has no such flag, so `%-e` renders
# literally there instead of as the day. %e is POSIX and space-pads instead.
# The formats have to stay self-contained strings rather than growing a helper:
# fish sources this file and shells/aliases.sh's `now` alias, and neither can
# call a bash function.
export _HI_HUMAN_CENTRIC_DATE="+%a %b %e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %e %y %H:%M %Z"

# required helpers/commands.
# hi.sh's $_HI_EXCLUDE strips scripts/, tests/ and .git from the tree copied to
# a target, so these aren't there in a hi session. Each says so rather than
# silently doing nothing, and each tests the *negation* first: `[ -f x ] && cmd
# || echo` would also print the message whenever cmd itself exited non-zero.
# The message expands at alias-definition time like the $_HI_* paths beside it,
# which is what the SC2139 disable at the top is for, so it stays fish-safe.
export _HI_NO_CHECKOUT="needs the full hi.d checkout - not available in a hi session"
# The other reason `git -C $_HI_ROOT pull` can't run: scripts/ is here, so this
# is a real checkout, but there is no .git in it - a package manager laid the
# tree down. One message for both shapes, since the alias below has room for
# exactly one condition and the advice ("update it where it came from") is the
# same either way.
export _HI_NO_GIT="no .git in $_HI_ROOT - if a package manager installed hi.d, update it there; if this is a hi session, update on the machine hi.d lives on"
alias hi="$_HI_LAUNCHER"
alias hi_install="[ ! -f $_HI_INSTALL ] && echo 'hi_install $_HI_NO_CHECKOUT' || $_HI_INSTALL"
alias hi_uninstall="[ ! -f $_HI_UNINSTALL ] && echo 'hi_uninstall $_HI_NO_CHECKOUT' || $_HI_UNINSTALL"
alias hi_configure="[ ! -f $_HI_INSTALL ] && echo 'hi_configure $_HI_NO_CHECKOUT' || $_HI_INSTALL --features-only"
alias hi_check_configs="[ ! -f $_HI_INSTALL ] && echo 'hi_check_configs $_HI_NO_CHECKOUT' || $_HI_INSTALL --check-configs"
# .git rather than a file: $_HI_EXCLUDE strips it, so this is the right test
# here - and it is also absent from a packaged install, which $_HI_NO_GIT covers
alias hi_update="[ ! -d $_HI_ROOT/.git ] && echo 'hi_update: $_HI_NO_GIT' || git -C $_HI_ROOT pull"
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"
alias hi_color_preview="[ ! -f $_HI_COLOR_PREVIEW ] && echo 'hi_color_preview $_HI_NO_CHECKOUT' || $_HI_COLOR_PREVIEW"
# no guard: common/ *is* shipped to targets, so header.sh is always there
alias hi_packages_preview="bash -c 'source \"$_HI_HEADER\" && full_check'"
alias hi_test="[ ! -f $_HI_TEST_RUN ] && echo 'hi_test $_HI_NO_CHECKOUT' || $_HI_TEST_RUN"

# The gate below reads the settings scripts/install.sh writes, so that file is
# sourced ahead of this one rather than from it: no single include line is valid
# in all four shells that source paths.sh (`.` is not fish syntax, `source` is
# not dash's). Each entry point does it instead, knowing its own shell -
# common/core.sh (bash/zsh, and what fish's `bash -c` reaches),
# shells/config.fish, and hi.sh's _hi_fallback_rc. Add a fourth here if a new
# one appears.
#
# Those same three also set $_HI_CONFIG_DIR, for the same reason: this file's
# paths are resolved against it, and ${XDG_CONFIG_HOME:-$HOME/.config} is not
# something fish can expand. They each spell out $_HI_CONFIG_DIR/settings.sh,
# which is the one path they have to derive for themselves - $_HI_SETTINGS
# doesn't exist until this file runs.
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
