#!/bin/sh
# every path hi uses, in one place. Fish sources this too, so plain `export
# NAME=value` lines only (plus `[ ] && export` guards) - no functions, no
# ${var:-...}. $_HI_HOME and $_HI_CONFIG_DIR must already be set.
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
export _HI_PACKAGES_PREVIEW="$_HI_ROOT/scripts/packages_preview.sh"
export _HI_DOCTOR="$_HI_ROOT/scripts/doctor.sh"

# tests - only the two entry points every session needs
export _HI_TEST_LIB="$_HI_ROOT/tests/test_lib.sh"
export _HI_TEST_RUN="$_HI_ROOT/tests/test_runner.sh"

# User config lives in $_HI_CONFIG_DIR, outside the tree (no dirty checkout,
# no writable-tree need); each entry point sets the var itself. Overridden
# per file - unoverridden ones keep tracking the tree copy; settings.sh has
# no in-tree half, so its path is unguarded.
export _HI_SETTINGS="$_HI_CONFIG_DIR/settings.sh"
export _HI_COLORS="$_HI_ROOT/misc/colors"
[ -f "$_HI_CONFIG_DIR/colors" ] && export _HI_COLORS="$_HI_CONFIG_DIR/colors"
export _HI_PACKAGES="$_HI_ROOT/misc/packages"
[ -f "$_HI_CONFIG_DIR/packages" ] && export _HI_PACKAGES="$_HI_CONFIG_DIR/packages"
export _HI_VIMRC="$_HI_ROOT/misc/vim.rc"
export _HI_NANORC="$_HI_ROOT/misc/nano.rc"
export _HI_TMUXCONF="$_HI_ROOT/misc/tmux.conf"
[ -f "$_HI_CONFIG_DIR/tmux.conf" ] && export _HI_TMUXCONF="$_HI_CONFIG_DIR/tmux.conf"
# eza reads its theme from a *directory* (misc/theme.yml), not a file path
export _HI_THEME_DIR="$_HI_ROOT/misc"
export _HI_ALIASES="$_HI_ROOT/misc/aliases.sh"
export _HI_OSC52="$_HI_ROOT/shells/osc52.sh"
export _HI_BASHRC="$_HI_ROOT/shells/bash.sh"
export _HI_ZSHRC="$_HI_ROOT/shells/zsh.zsh"
export _HI_FISH_CONFIG="$_HI_ROOT/shells/config.fish"

# install.sh's line tag and managed symlink - here so install, --uninstall
# and anyone else recognising hi's lines read one string
export _HI_MARKER="# added by hi during install"
export _HI_LINK="/usr/bin/hi"

# host paths hi reads or appends to
export _HI_LINUX_RELEASE="/etc/os-release"
export _HI_SSH_DIR="$HOME/.ssh"
export _HI_SSH_CONFIG="$HOME/.ssh/config"
export _HI_SSH_AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"
export _HI_HOME_BASHRC="$HOME/.bashrc"
export _HI_HOME_ZSHRC="$HOME/.zshrc"
export _HI_HOME_FISH_CONFIG="$HOME/.config/fish/config.fish"

# GLOSSARY: strftime %e over %-e. Self-contained strings - fish sources this
# and can't call a bash helper.
export _HI_HUMAN_CENTRIC_DATE="+%a %b %e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %e %y %H:%M %Z"

# Helper aliases; the payload ships no scripts/tests/.git, so each says so on
# a target. Negation first: `[ -f ] && cmd || echo` would print on cmd failure.
export _HI_NO_CHECKOUT="needs the full hi.d checkout - not available in a hi session"
# one message for both no-.git shapes (hi session, packaged install) - the
# alias has room for one condition and the advice is the same
export _HI_NO_GIT="no .git in $_HI_ROOT - if a package manager installed hi.d, update it there; if this is a hi session, update on the machine hi.d lives on"
alias hi="$_HI_LAUNCHER"
alias hi_install="[ ! -f $_HI_INSTALL ] && echo 'hi_install $_HI_NO_CHECKOUT' || $_HI_INSTALL"
alias hi_uninstall="[ ! -f $_HI_UNINSTALL ] && echo 'hi_uninstall $_HI_NO_CHECKOUT' || $_HI_UNINSTALL"
alias hi_configure="[ ! -f $_HI_INSTALL ] && echo 'hi_configure $_HI_NO_CHECKOUT' || $_HI_INSTALL --features-only"
alias hi_check_configs="[ ! -f $_HI_INSTALL ] && echo 'hi_check_configs $_HI_NO_CHECKOUT' || $_HI_INSTALL --check-configs"
alias hi_overlay_init="[ ! -f $_HI_INSTALL ] && echo 'hi_overlay_init $_HI_NO_CHECKOUT' || $_HI_INSTALL --overlay-init"
# .git as the test: absent from payloads and packaged installs alike
alias hi_update="[ ! -d $_HI_ROOT/.git ] && echo 'hi_update: $_HI_NO_GIT' || git -C $_HI_ROOT pull"
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"
alias hi_color_preview="[ ! -f $_HI_COLOR_PREVIEW ] && echo 'hi_color_preview $_HI_NO_CHECKOUT' || $_HI_COLOR_PREVIEW"
alias hi_doctor="[ ! -f $_HI_DOCTOR ] && echo 'hi_doctor $_HI_NO_CHECKOUT' || $_HI_DOCTOR"
# The full preview - priorities, their colors, examples - lives in scripts/,
# which targets do not get. There the alias falls back to what it has always
# run: the check itself, out of the shipped common/header.sh.
alias hi_packages_preview="[ ! -f $_HI_PACKAGES_PREVIEW ] && bash -c 'source \"$_HI_HEADER\" && full_check' || $_HI_PACKAGES_PREVIEW"
alias hi_test="[ ! -f $_HI_TEST_RUN ] && echo 'hi_test $_HI_NO_CHECKOUT' || $_HI_TEST_RUN"

# Local-only gate, reading settings each entry point sourced *ahead* of this
# file (no include line parses in all four shells - new entry points source
# them there, not here); _HI_REMOTE_SESSION is what tells local from remote.
export _HI_DISABLE_LOCAL
export _HI_REMOTE_SESSION

# The list below is core.sh's _HI_TOGGLES minus the gate's own two inputs,
# spelled out because this dialect can't loop; paths_test.sh pins the two
# lists together (OSC52 and TMUX had already gone missing here once).
[ "$_HI_DISABLE_LOCAL" = 1 ] && [ "$_HI_REMOTE_SESSION" != 1 ] && {
  export _HI_DISABLE_HEADER=1
  export _HI_DISABLE_PROMPT=1
  export _HI_DISABLE_PERSONAL=1
  export _HI_DISABLE_GIT_STATUS=1
  export _HI_DISABLE_EDITORS=1
  export _HI_DISABLE_ALIASES=1
  export _HI_DISABLE_OSC52=1
  export _HI_DISABLE_TMUX=1
} || true
