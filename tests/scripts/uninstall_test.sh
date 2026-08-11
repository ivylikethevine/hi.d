#!/bin/bash
# Unit tests for scripts/uninstall.sh's reusable logic: strip_marker (the
# exact inverse of install.sh's config_shell - both are exercised together
# here to prove they round-trip) and unlink_hi's detection of whether
# /usr/bin/hi (or a scratch stand-in for it, in these tests) actually points
# at this hi.d before touching it. Everything runs against scratch files -
# the real /usr/bin/hi is never read or written, and the one code path that
# would call `sudo rm` is deliberately never exercised here (it's a one-line
# passthrough with nothing to unit test; what's actually error-prone is the
# skip/detection logic around it, which these do cover - see
# install_test.sh's matching config_hi coverage for the same reasoning).
#
# uninstall.sh's own BASH_SOURCE guard (see its comment right above its main
# flow) is what makes sourcing it here safe.
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

_HI_WORKDIR="$(mktemp -d -t hi.uninstalltest.XXXXXX)"
# shellcheck disable=SC2016 # $_HI_WORKDIR is resolved when the trap fires
_hi_on_exit 'rm -rf "$_HI_WORKDIR"'

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function _hi_assert() {
  local label="$1"
  shift
  if "$@"; then
    _hi_cecho " | $label: OK" "$GREEN"
  else
    _hi_cecho " | $label: FAILED" "$RED"
    return 1
  fi
}

# ---- strip_marker -----------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
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

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_strip_marker_noop_when_marker_absent() {
  local target="$_HI_WORKDIR/untagged" before after
  printf '%s\n' "just a normal file" >"$target"
  before="$(cat "$target")"
  strip_marker test "$target"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_strip_marker_safe_on_missing_file() {
  strip_marker test "$_HI_WORKDIR/does-not-exist"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
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

# ---- unlink_hi (skip paths only - the sudo-affecting match is out of scope) --

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_unlink_hi_skips_when_link_missing() {
  local link="$_HI_WORKDIR/no-such-link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_unlink_hi_skips_when_link_points_elsewhere() {
  local link="$_HI_WORKDIR/elsewhere-link"
  ln -sfn /bin/true "$link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
}

function run_uninstall_tests() {
  _hi_h1 "Testing scripts/uninstall.sh's reusable logic"

  _HI_FAILED=0
  _HI_TOTAL=0

  _hi_h2 "strip_marker"
  _hi_case _hi_assert "removes only tagged lines" test_strip_marker_removes_tagged_lines_only
  _hi_case _hi_assert "no-op when marker absent" test_strip_marker_noop_when_marker_absent
  _hi_case _hi_assert "safe on a missing file" test_strip_marker_safe_on_missing_file
  _hi_case _hi_assert "install+uninstall round-trips" test_install_uninstall_round_trip

  _hi_h2 "unlink_hi (skip paths only)"
  _hi_case _hi_assert "skips a missing link" test_unlink_hi_skips_when_link_missing
  _hi_case _hi_assert "skips a foreign link" test_unlink_hi_skips_when_link_points_elsewhere

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "All uninstall.sh logic checks passed ($_HI_TOTAL cases)"
  else
    _hi_h1 "$_HI_FAILED/$_HI_TOTAL uninstall.sh logic checks FAILED" "$RED"
  fi
  exit "$_HI_FAILED"
}

run_uninstall_tests
