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
export _HI_BENCH_RUN="$_HI_ROOT/tests/bench/bench.sh"

# user configurable
# settings.sh is where scripts/install.sh writes every _HI_DISABLE_*/
# _HI_HEADER_*/_HI_MAX_WIDTH choice. It is gitignored, so configuring hi.d
# no longer dirties the checkout and `hi_update`'s git pull still applies
# cleanly. It is *not* in hi.sh's $_HI_EXCLUDE, so the choices ride along to
# every target. See the note by the local-only gate at the bottom of this
# file for why it is sourced before this one, not from it.
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
# hi.sh's $_HI_EXCLUDE strips scripts/, tests/ and .git from the tree it
# copies to a target, so the helpers below simply aren't there in a hi
# session. Each one says so instead of silently doing nothing - and each
# tests the *negation* first, because `[ -f x ] && cmd || echo` would also
# print the message whenever cmd itself exited non-zero.
alias hi="$_HI_LAUNCHER"
alias hi_install="[ ! -f $_HI_INSTALL ] && echo 'hi_install needs the full hi.d checkout - not available in a hi session' || $_HI_INSTALL"
alias hi_uninstall="[ ! -f $_HI_UNINSTALL ] && echo 'hi_uninstall needs the full hi.d checkout - not available in a hi session' || $_HI_UNINSTALL"
alias hi_configure="[ ! -f $_HI_INSTALL ] && echo 'hi_configure needs the full hi.d checkout - not available in a hi session' || $_HI_INSTALL --features-only"
alias hi_reconfigure="hi_configure"
alias hi_check_configs="[ ! -f $_HI_INSTALL ] && echo 'hi_check_configs needs the full hi.d checkout - not available in a hi session' || $_HI_INSTALL --check-configs"
alias hi_update="[ ! -d $_HI_ROOT/.git ] && echo 'hi_update needs the full hi.d checkout - not available in a hi session' || git -C $_HI_ROOT pull"
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"
alias hi_color_preview="[ ! -f $_HI_COLOR_PREVIEW ] && echo 'hi_color_preview needs the full hi.d checkout - not available in a hi session' || $_HI_COLOR_PREVIEW"
alias hi_packages_preview="bash -c 'source \"$_HI_CHECK\" && full_check'"
alias hi_test="[ ! -f $_HI_TEST_RUN ] && echo 'hi_test needs the full hi.d checkout - not available in a hi session' || $_HI_TEST_RUN"
alias hi_bench="[ ! -f $_HI_BENCH_RUN ] && echo 'hi_bench needs the full hi.d checkout - not available in a hi session' || $_HI_BENCH_RUN"

# The gate below *reads* the settings scripts/install.sh writes, so they have
# to be set before this file runs - which is why $_HI_SETTINGS is sourced
# ahead of this file rather than from it. There is no single include line
# valid in all four shells that source paths.sh: `.` is not fish syntax and
# `source` is not dash's. So each entry point, which already knows its own
# shell, does it instead - common/bootstrap.sh (bash/zsh), common/shared.sh
# (reached directly by fish's `bash -c`), shells/config.fish, and hi.sh's
# _hi_fallback_rc (the no-bash target). Add a fifth here if a new one appears.
#
# local-only disable logic. _HI_REMOTE_SESSION is exported by load.sh, the
# chainload entry point every remote path goes through and the local
# install's own shells never do, so it's what tells the two apart.
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
