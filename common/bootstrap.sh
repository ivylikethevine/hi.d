#!/bin/bash
# shared entry point for scripts
# shellcheck disable=SC2139 # aliases are meant to expand $_HI_* now, not later
: "${_HI_HOME:=$HOME}"
export _HI_HOME
: "${_HI_DISABLE_LOCAL:=0}"
export _HI_DISABLE_LOCAL
: "${_HI_REMOTE_SESSION:=0}"
export _HI_REMOTE_SESSION
# shellcheck source=./paths.sh
source "$_HI_HOME/hi.d/common/paths.sh"
# shellcheck source=./shared.sh
command -v _hi_cecho >/dev/null || source "$_HI_SHARED"
export _HI_HUMAN_CENTRIC_DATE="+%a %b %-e %Y %H:%M:%S %Z"
export _HI_HUMAN_SHORT_DATE="+%b %-e %y %H:%M %Z"

alias hi_install="[ -f $_HI_INSTALL ] && $_HI_INSTALL"
alias hi_uninstall="[ -f $_HI_UNINSTALL ] && $_HI_UNINSTALL"
alias hi_configure="[ -f $_HI_INSTALL ] && $_HI_INSTALL --features-only"
alias hi_check_configs="[ -f $_HI_INSTALL ] && $_HI_INSTALL --check-configs"
alias hi_update="git -C $_HI_ROOT pull"
alias hi_status="git -C $_HI_ROOT status"
alias hi_info="echo ' | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | script: $_HI_LAUNCHER'"
alias hi_color_preview="[ -f $_HI_COLOR_PREVIEW ] && $_HI_COLOR_PREVIEW"
alias hi_check_packages="sh -c 'source \"$_HI_CHECK\" && full_check'"
alias hi_test_aliases="[ -f $_HI_TEST_ALIASES ] && $_HI_TEST_ALIASES"
alias hi_test_ssh="[ -f $_HI_TEST_SSH ] && $_HI_TEST_SSH"
alias hi_test_shellcheck="[ -f $_HI_TEST_SHELLCHECK ] && $_HI_TEST_SHELLCHECK"
alias hi_test_all="hi_test_aliases && hi_test_ssh && hi_test_shellcheck"
