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

  _hi_h2 "Testing: unlink_hi (skip paths only)"
  _hi_check "Skips a missing link" test_unlink_hi_skips_when_link_missing
  _hi_check "Skips a foreign link" test_unlink_hi_skips_when_link_points_elsewhere

  _hi_suite_end "uninstall.sh logic"
}

run_uninstall_tests
