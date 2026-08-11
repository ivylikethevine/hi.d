#!/bin/bash
# Unit tests for common/check.sh: check_line's found/missing/fallback/hide
# logic per priority bucket (see the priority table atop check.sh) and
# full_check's packages-file parsing (comment/blank skipping, row wrapping,
# fully-hidden output). Runs against scratch packages files plus one
# guaranteed-present command (sh) and one guaranteed-absent one - nothing in
# the real misc/packages is read except by the dedicated fixture test at the
# end.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../common/check.sh
source "$_HI_CHECK"

_HI_WORKDIR="$(mktemp -d -t hi.checktest.XXXXXX)"
# shellcheck disable=SC2016 # $_HI_WORKDIR is resolved when the trap fires
_hi_on_exit 'rm -rf "$_HI_WORKDIR"'

# shellcheck disable=SC2209 # the literal command name "sh" is intentional, not a botched `sh` invocation
_HI_REAL_CMD=sh
_HI_FAKE_CMD=definitely-not-a-real-hi-test-command-xyz

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

# ---- check_line -----------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_line_found_primary_is_visible_checked() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  [[ "${visible[0]}" == *"$_HI_REAL_CMD"* && "${visible[0]}" == *"✓"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_line_found_priority2_is_hidden() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:2"
  [ "${#visible[@]}" -eq 0 ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_line_missing_priority0_is_hidden() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:0"
  [ "${#visible[@]}" -eq 0 ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_line_missing_priority5_is_visible_crossed() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  [[ "${visible[0]}" == *"$_HI_FAKE_CMD"* && "${visible[0]}" == *"✗"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_line_fallback_uses_second_alternative() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:0,$_HI_REAL_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  [[ "${visible[0]}" == *"$_HI_REAL_CMD"* && "${visible[0]}" == *"~"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_line_picks_highest_priority_installed() {
  command -v bash >/dev/null 2>&1 || return 0 # nothing to assert without bash
  local -a visible=()
  check_line "$_HI_REAL_CMD:1,bash:5"
  [[ "${visible[0]}" == *"bash"* ]]
}

# ---- full_check -------------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_full_check_skips_comments_and_blanks() {
  local pkgfile="$_HI_WORKDIR/comments"
  printf '# a comment\n\n%s:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  (
    _HI_PACKAGES="$pkgfile"
    full_check
  ) | grep -qF "$_HI_REAL_CMD"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_full_check_empty_when_everything_hidden() {
  local pkgfile="$_HI_WORKDIR/hidden" out
  printf '%s:0\n' "$_HI_FAKE_CMD" >"$pkgfile" # missing + priority 0 == hide
  out="$(
    _HI_PACKAGES="$pkgfile"
    full_check
  )"
  [ -z "$out" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_full_check_wraps_at_max_width() {
  command -v bash >/dev/null 2>&1 || return 0
  local pkgfile="$_HI_WORKDIR/wrap" out lines
  printf '%s:5\nbash:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    _HI_MAX_WIDTH=1
    full_check
  )"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$lines" -ge 2 ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_full_check_reads_real_packages_file_without_erroring() {
  full_check >/dev/null
}

function run_check_tests() {
  _hi_h1 "Testing common/check.sh"

  _HI_FAILED=0
  _HI_TOTAL=0

  _hi_h2 "check_line"
  _hi_case _hi_assert "found primary -> visible, checked" test_check_line_found_primary_is_visible_checked
  _hi_case _hi_assert "found priority 2 -> hidden" test_check_line_found_priority2_is_hidden
  _hi_case _hi_assert "missing priority 0 -> hidden" test_check_line_missing_priority0_is_hidden
  _hi_case _hi_assert "missing priority 5 -> visible, crossed" test_check_line_missing_priority5_is_visible_crossed
  _hi_case _hi_assert "fallback alternative used" test_check_line_fallback_uses_second_alternative
  _hi_case _hi_assert "picks the highest-priority installed alternative" test_check_line_picks_highest_priority_installed

  _hi_h2 "full_check"
  _hi_case _hi_assert "skips comment/blank lines" test_full_check_skips_comments_and_blanks
  _hi_case _hi_assert "empty output when everything is hidden" test_full_check_empty_when_everything_hidden
  _hi_case _hi_assert "wraps rows at _HI_MAX_WIDTH" test_full_check_wraps_at_max_width
  _hi_case _hi_assert "real misc/packages file parses cleanly" test_full_check_reads_real_packages_file_without_erroring

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "All check.sh checks passed ($_HI_TOTAL cases)"
  else
    _hi_h1 "$_HI_FAILED/$_HI_TOTAL check.sh checks FAILED" "$RED"
  fi
  exit "$_HI_FAILED"
}

run_check_tests
