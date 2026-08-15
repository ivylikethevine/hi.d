#!/bin/bash
# Unit tests for scripts/uninstall.sh's reusable logic.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

set -- # install.sh/uninstall.sh read "$@" for their own args; give them none
# shellcheck source=../../scripts/install.sh
source "$_HI_INSTALL" # for config_shell, used to build the round-trip fixture below
# shellcheck source=../../scripts/uninstall.sh
source "$_HI_UNINSTALL"

function test_strip_marker_removes_tagged_lines_only() {
  local target="$_HI_WORKDIR/tagged"
  printf '%s\n' "# a user comment" "alias ll='ls -la'" >"$target"
  config_shell fixture "$target" "hi line one" "hi line two"
  strip_marker test "$target"
  grep -qF "# a user comment" "$target" &&
    grep -qF "alias ll='ls -la'" "$target" &&
    ! grep -qF "$_HI_MARKER" "$target" &&
    ! grep -qF "hi line one" "$target"
}

function test_strip_marker_noop_when_marker_absent() {
  local target="$_HI_WORKDIR/untagged" before after
  printf '%s\n' "just a normal file" >"$target"
  before="$(cat "$target")"
  strip_marker test "$target"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

function test_strip_marker_safe_on_missing_file() {
  strip_marker test "$_HI_WORKDIR/does-not-exist"
}

function test_install_uninstall_round_trip() {
  local target="$_HI_WORKDIR/roundtrip" before after
  printf '%s\n' "# pre-existing line" >"$target"
  before="$(cat "$target")"
  config_shell fixture "$target" "some hi config line"
  grep -qF "some hi config line" "$target" || return 1
  strip_marker fixture "$target"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

# --- strip_settings ---------------------------------------------------------
#
# Install now writes to the overlay, but installs predating it left a
# settings.sh inside the tree - so uninstall has to clear both to stay install's
# exact inverse, the same contract strip_marker has with older rc lines.

# Run strip_settings against a scratch tree + overlay, creating whichever of the
# two settings files were named.
function _hi_settings_fixture() {
  local dir="$_HI_WORKDIR/$1" where
  local _HI_ROOT="$dir/hi.d" _HI_SETTINGS_WRITE="$dir/config/settings.sh"
  shift
  mkdir -p "$_HI_ROOT/misc" "$dir/config"
  for where in "$@"; do
    case "$where" in
    overlay) printf '#!/bin/sh\n' >"$_HI_SETTINGS_WRITE" ;;
    tree) printf '#!/bin/sh\n' >"$_HI_ROOT/misc/settings.sh" ;;
    esac
  done
  strip_settings >/dev/null
}

function test_strip_settings_removes_the_overlay_copy() {
  _hi_settings_fixture overlay overlay
  [ ! -e "$_HI_WORKDIR/overlay/config/settings.sh" ]
}

function test_strip_settings_removes_a_legacy_in_tree_copy() {
  _hi_settings_fixture legacy tree
  [ ! -e "$_HI_WORKDIR/legacy/hi.d/misc/settings.sh" ]
}

function test_strip_settings_removes_both() {
  _hi_settings_fixture both overlay tree
  [ ! -e "$_HI_WORKDIR/both/config/settings.sh" ] &&
    [ ! -e "$_HI_WORKDIR/both/hi.d/misc/settings.sh" ]
}

# colors and packages are the user's own writing, not something install.sh
# produced - uninstall leaves them for the same reason it leaves the checkout
function test_strip_settings_leaves_the_rest_of_the_overlay() {
  local dir="$_HI_WORKDIR/keep"
  mkdir -p "$dir/hi.d/misc" "$dir/config"
  printf 'hostname,foo,brred\n' >"$dir/config/colors"
  (
    _HI_ROOT="$dir/hi.d"
    _HI_SETTINGS_WRITE="$dir/config/settings.sh"
    strip_settings
  ) >/dev/null
  [ -f "$dir/config/colors" ]
}

function test_strip_settings_is_quiet_when_there_is_nothing() {
  _hi_settings_fixture nothing
  return 0
}

function test_unlink_hi_skips_when_link_missing() {
  local link="$_HI_WORKDIR/no-such-link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
}

function test_unlink_hi_skips_when_link_points_elsewhere() {
  local link="$_HI_WORKDIR/elsewhere-link"
  ln -sfn /bin/true "$link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
}

function run_uninstall_tests() {
  _hi_workdir uninstalltest

  _hi_h1 "Testing scripts/uninstall.sh's reusable logic"

  _hi_suite_begin

  _hi_h2 "Testing: strip_marker"
  _hi_check "Removes only tagged lines" test_strip_marker_removes_tagged_lines_only
  _hi_check "No-op when marker absent" test_strip_marker_noop_when_marker_absent
  _hi_check "Safe on a missing file" test_strip_marker_safe_on_missing_file
  _hi_check "Install+uninstall round-trips" test_install_uninstall_round_trip

  _hi_h2 "Testing: strip_settings"
  _hi_check "Removes the overlay copy" test_strip_settings_removes_the_overlay_copy
  _hi_check "Removes a legacy in-tree copy" test_strip_settings_removes_a_legacy_in_tree_copy
  _hi_check "Removes both" test_strip_settings_removes_both
  _hi_check "Leaves the rest of the overlay" test_strip_settings_leaves_the_rest_of_the_overlay
  _hi_check "Quiet when there is nothing" test_strip_settings_is_quiet_when_there_is_nothing

  _hi_h2 "Testing: unlink_hi (skip paths only)"
  _hi_check "Skips a missing link" test_unlink_hi_skips_when_link_missing
  _hi_check "Skips a foreign link" test_unlink_hi_skips_when_link_points_elsewhere

  _hi_suite_end "uninstall.sh logic"
}

run_uninstall_tests
