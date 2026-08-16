#!/bin/bash
# Unit tests for load.sh - the target-side half of hi: the marker-delimited
# block it grafts onto the host's rc files, and the cleanup that takes it
# (and, only when the tree is disposable, hi.d itself) back out again.
#
# load.sh is sourced here with _HI_LOAD_NO_INIT=1, which skips its profile
# restoration and leaves just the functions - the same hatch install.sh gets
# from its BASH_SOURCE guard. Everything it touches is
# redirected into the scratch dir by reassigning _HI_CONFIGS (built from
# $_HI_BASHRC/$_HI_HOME_BASHRC at source time) and _HI_ROOT.
#
# SAFETY: clean_all ends in `rm -rf "$_HI_ROOT"`, so no case below may call it
# directly - every call goes through _hi_clean_all, which shadows _HI_ROOT with
# a scratch path. Calling the real thing with the real _HI_ROOT would delete
# this checkout. The canary case at the end of the suite proves none did.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_LOAD_NO_INIT=1
# shellcheck source=../../load.sh
source "$_HI_ROOT/load.sh"

_HI_USER_LINE='# a line the user put here themselves'
_HI_FAKE_HOME=""

function _hi_fake_rcs() {
  local name
  _HI_FAKE_HOME="$_HI_WORKDIR/$1"
  rm -rf "$_HI_FAKE_HOME"
  mkdir -p "$_HI_FAKE_HOME"
  for name in bashrc zshrc fishconf; do
    printf 'source-for-%s\n' "$name" >"$_HI_FAKE_HOME/src.$name"
  done
  printf '%s\n' "$_HI_USER_LINE" >"$_HI_FAKE_HOME/.bashrc"
  printf '%s\n' "$_HI_USER_LINE" >"$_HI_FAKE_HOME/.zshrc"
  _HI_CONFIGS=(
    "$_HI_FAKE_HOME/src.bashrc:$_HI_FAKE_HOME/.bashrc"
    "$_HI_FAKE_HOME/src.zshrc:$_HI_FAKE_HOME/.zshrc"
    "$_HI_FAKE_HOME/src.fishconf:$_HI_FAKE_HOME/.config/fish/config.fish"
  )
}

function _hi_clean_all() {
  local _HI_ROOT="${1:-$_HI_WORKDIR/unused-root}" _HI_CLEANUP="${2:-}"
  clean_all
}

function _hi_clean_only_root() {
  local -a _HI_CONFIGS=("$_HI_WORKDIR/no.src:$_HI_WORKDIR/no.such.rc")
  _hi_clean_all "$@"
}

function _hi_block_count() {
  grep -c "^$_HI_CONFIG_START\$" "$1" 2>/dev/null || true
}

function test_configure_files_appends_block() {
  _hi_fake_rcs append
  configure_files
  [ "$(_hi_block_count "$_HI_FAKE_HOME/.bashrc")" -eq 1 ] || return 1
  grep -q '^source-for-bashrc$' "$_HI_FAKE_HOME/.bashrc" || return 1
  grep -q "^$_HI_CONFIG_END\$" "$_HI_FAKE_HOME/.bashrc" || return 1
  grep -q '^source-for-zshrc$' "$_HI_FAKE_HOME/.zshrc"
}

function test_configure_files_is_idempotent() {
  _hi_fake_rcs idempotent
  configure_files
  configure_files
  [ "$(_hi_block_count "$_HI_FAKE_HOME/.bashrc")" -eq 1 ]
}

function test_configure_files_skips_absent_fish_dir() {
  _hi_fake_rcs nofish
  configure_files
  [ ! -e "$_HI_FAKE_HOME/.config/fish/config.fish" ]
}

function test_configure_files_creates_missing_rc_file() {
  _hi_fake_rcs missingrc
  rm -f "$_HI_FAKE_HOME/.zshrc"
  configure_files
  [ -f "$_HI_FAKE_HOME/.zshrc" ] && grep -q '^source-for-zshrc$' "$_HI_FAKE_HOME/.zshrc"
}

function test_configure_files_grafts_fish_when_dir_exists() {
  _hi_fake_rcs withfish
  mkdir -p "$_HI_FAKE_HOME/.config/fish"
  configure_files
  grep -q '^source-for-fishconf$' "$_HI_FAKE_HOME/.config/fish/config.fish"
}

function test_clean_all_strips_block_and_keeps_user_lines() {
  _hi_fake_rcs strip
  configure_files
  _hi_clean_all
  [ "$(cat "$_HI_FAKE_HOME/.bashrc")" = "$_HI_USER_LINE" ] || return 1
  [ "$(cat "$_HI_FAKE_HOME/.zshrc")" = "$_HI_USER_LINE" ]
}

function test_clean_all_removes_lone_start_marker() {
  _hi_fake_rcs lonemarker
  printf '%s\n%s\n' "$_HI_CONFIG_START" 'orphaned line' >>"$_HI_FAKE_HOME/.bashrc"
  _hi_clean_all
  ! grep -q "$_HI_CONFIG_START" "$_HI_FAKE_HOME/.bashrc" || return 1
  grep -q '^orphaned line$' "$_HI_FAKE_HOME/.bashrc"
}

function test_clean_all_keeps_permanent_install() {
  local root="$_HI_WORKDIR/permanent"
  mkdir -p "$root"
  printf 'colors\n' >"$root/keepme"
  _hi_clean_only_root "$root"
  [ -f "$root/keepme" ]
}

function test_clean_all_removes_disposable_copy() {
  local root="$_HI_WORKDIR/disposable"
  mkdir -p "$root"
  printf 'copied\n' >"$root/keepme"
  _hi_clean_only_root "$root" "$_HI_WORKDIR"
  [ ! -e "$root" ]
}

function test_clean_all_succeeds_with_nothing_to_do() {
  _hi_clean_only_root "$_HI_WORKDIR/never-created"
}

function _hi_source_load() {
  local home="$1" guard="$2"
  _HI_LOAD_NO_INIT="$guard" HOME="$home" bash -c \
    'source "$1/load.sh"; printf "%s|%s" "${HI_LOAD_TEST_PROFILE:-}" "$PATH"' _ "$_HI_ROOT"
}

function test_source_restores_profile_and_path() {
  local home="$_HI_WORKDIR/profilehome" out
  mkdir -p "$home"
  printf 'export HI_LOAD_TEST_PROFILE=1\n' >"$home/.profile"
  out="$(_hi_source_load "$home" 0)"
  [[ "${out%%|*}" == 1 ]] || return 1
  [[ "${out#*|}" == *"$_HI_ROOT"* ]]
}

function test_no_init_guard_skips_profile_and_path() {
  local home="$_HI_WORKDIR/profilehome" out
  mkdir -p "$home"
  printf 'export HI_LOAD_TEST_PROFILE=1\n' >"$home/.profile"
  out="$(_hi_source_load "$home" 1)"
  [[ -z "${out%%|*}" ]] || return 1
  [[ "${out#*|}" != *"$_HI_ROOT"* ]]
}

function test_this_checkout_was_never_touched() {
  [ -f "$_HI_ROOT/load.sh" ] && [ -f "$_HI_ROOT/hi.sh" ] && [ -d "$_HI_ROOT/common" ]
}

# --- _hi_tmux_wanted ----------------------------------------------------------
#
# The gate in front of `hi --tmux`. Every "no" here has to be a *loud* no that
# still lets the session happen - refusing to connect because a host has no
# tmux would be a worse answer than connecting without it.

# _hi_tmux_answer <NAME=VALUE ...> - "yes"/"no", plus whatever it printed
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function _hi_tmux_answer() {
  local out rc=0
  out="$(env "$@" bash -c '
    _HI_LOAD_NO_INIT=1
    source "$_HI_HOME/hi.d/common/core.sh"
    source "$_HI_HOME/hi.d/load.sh"
    if _hi_tmux_wanted; then echo yes; else echo no; fi' 2>&1)" || rc=$?
  printf '%s' "$out"
  return "$rc"
}

function test_tmux_wanted_off_by_default() {
  [ "$(_hi_tmux_answer _HI_HOME="$_HI_HOME" PATH="$PATH")" = no ]
}

function test_tmux_wanted_on_when_asked_for() {
  [ "$(_hi_tmux_answer _HI_HOME="$_HI_HOME" PATH="$PATH" _HI_TMUX_ATTACH=1)" = yes ]
}

# a disposable tree is deleted when this session ends; a tmux that outlived it
# would be reading a directory that is gone - the same test shells/aliases.sh
# makes before defining the `tmux` alias
function test_tmux_wanted_refuses_a_disposable_tree() {
  local out
  out="$(_hi_tmux_answer _HI_HOME="$_HI_HOME" PATH="$PATH" _HI_TMUX_ATTACH=1 _HI_CLEANUP=/tmp/x.hi)"
  case "$out" in
  *permanent*no) return 0 ;;
  esac
  return 1
}

function run_load_tests() {
  _hi_workdir loadtest

  _hi_h1 "Testing load.sh"

  _hi_suite_begin

  _hi_h2 "Testing: configure_files"
  _hi_check "Appends the marked block" test_configure_files_appends_block
  _hi_check "Second call doesn't duplicate it" test_configure_files_is_idempotent
  _hi_check "Skips fish when its config dir is absent" test_configure_files_skips_absent_fish_dir
  _hi_check "Grafts fish when its config dir exists" test_configure_files_grafts_fish_when_dir_exists
  _hi_check "Creates an rc file that doesn't exist yet" test_configure_files_creates_missing_rc_file

  _hi_h2 "Testing: clean_all"
  _hi_check "Strips the block, keeps user lines" test_clean_all_strips_block_and_keeps_user_lines
  _hi_check "Removes a start marker with no end marker" test_clean_all_removes_lone_start_marker
  _hi_check "Keeps \$_HI_ROOT when _HI_CLEANUP is unset" test_clean_all_keeps_permanent_install
  _hi_check "Removes \$_HI_ROOT when _HI_CLEANUP is set" test_clean_all_removes_disposable_copy
  _hi_check "Succeeds with nothing to clean" test_clean_all_succeeds_with_nothing_to_do

  _hi_h2 "Testing: profile restoration"
  _hi_check "Sourcing restores the profile chain and PATH" test_source_restores_profile_and_path
  _hi_check "_HI_LOAD_NO_INIT=1 skips both" test_no_init_guard_skips_profile_and_path

  _hi_h2 "Testing: _hi_tmux_wanted"
  _hi_check "Off by default" test_tmux_wanted_off_by_default
  _hi_check_requires tmux "On when asked for" test_tmux_wanted_on_when_asked_for
  _hi_check_requires tmux "Refuses a disposable tree, loudly" test_tmux_wanted_refuses_a_disposable_tree

  _hi_h2 "Testing: this checkout"
  _hi_check "Still intact after every clean_all above" test_this_checkout_was_never_touched

  _hi_suite_end "load.sh"
}

run_load_tests
