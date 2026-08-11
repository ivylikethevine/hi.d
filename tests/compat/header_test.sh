#!/bin/bash
# Unit tests for common/header.sh: header_row's cell-joining, banner's label/
# host embedding, its prefix-reserves-width behavior (the prefix text itself
# is never printed by banner - see the comment on it below - only its length
# shrinks the tilde padding, since the caller already printed it earlier on
# the same terminal line), and the floor that keeps its tilde math from going
# negative on a pathologically long label/narrow width. timestamp/system_info/
# identity are host-dependent, so they only get smoke-tested: assert the
# static labels they always print show up and nothing errors. hi_header's
# _HI_DISABLE_HEADER gate rounds it out.
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../../common/header.sh
source "$_HI_HEADER"

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

# ---- header_row -------------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_header_row_joins_cells() {
  local out
  out="$(header_row foo bar baz)"
  [[ "$out" == *"| foo"* && "$out" == *"| bar"* && "$out" == *"| baz"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_header_row_single_cell() {
  local out
  out="$(header_row solo)"
  [[ "$out" == *"| solo"* ]]
}

# ---- banner -------------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_banner_includes_label_and_host() {
  local out host
  host="$(_hi_hostname)"
  out="$(banner TestBanner)"
  [[ "$out" == *"TestBanner"* && "$out" == *"$host"* ]]
}

# a longer prefix reserves more of the (already-printed) line, so it should
# shrink - never grow - the tilde padding banner prints for itself
# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_banner_prefix_shrinks_padding() {
  local plain prefixed
  plain="$(banner TestBanner "$BRGREEN" "")"
  prefixed="$(banner TestBanner "$BRGREEN" "$(printf 'x%.0s' {1..50})")"
  [ "${#prefixed}" -lt "${#plain}" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_banner_floors_tildes_on_long_label() {
  local out label
  label="$(printf 'x%.0s' {1..200})" # forces the ((tildes < 4)) floor
  out="$(banner "$label")"
  [[ "$out" == *"$label"* && "$out" == *"~"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_banner_narrow_width_does_not_error() {
  local out
  out="$(_HI_MAX_WIDTH=10 banner Narrow)"
  [ -n "$out" ]
}

# ---- timestamp / system_info / identity (smoke tests) -----------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_timestamp_runs_and_has_two_cells() {
  local out
  out="$(timestamp)"
  [ "$(grep -o '|' <<<"$out" | wc -l)" -eq 2 ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_system_info_includes_static_labels() {
  local out
  out="$(system_info)"
  [[ "$out" == *"Cores:"* && "$out" == *"RAM:"* && "$out" == *"CPU:"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_identity_includes_static_labels() {
  local out
  out="$(identity)"
  [[ "$out" == *"Auth:"* && "$out" == *"Pub:"* ]]
}

# ---- hi_header ----------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_hi_header_disabled_produces_no_output() {
  local out
  out="$(_HI_DISABLE_HEADER=1 hi_header Connected)"
  [ -z "$out" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_hi_header_enabled_prints_banner() {
  local out
  out="$(_HI_DISABLE_HEADER=0 hi_header Connected)"
  [[ "$out" == *"Connected"* ]]
}

function run_header_tests() {
  _hi_h1 "Testing common/header.sh"

  _HI_FAILED=0
  _HI_TOTAL=0

  _hi_h2 "Testing: header_row"
  _hi_case _hi_assert "Joins multiple cells" test_header_row_joins_cells
  _hi_case _hi_assert "Handles a single cell" test_header_row_single_cell

  _hi_h2 "Testing: banner"
  _hi_case _hi_assert "Includes label and hostname" test_banner_includes_label_and_host
  _hi_case _hi_assert "A longer prefix shrinks the padding" test_banner_prefix_shrinks_padding
  _hi_case _hi_assert "Floors tilde padding on a pathologically long label" test_banner_floors_tildes_on_long_label
  _hi_case _hi_assert "Survives a narrow _HI_MAX_WIDTH" test_banner_narrow_width_does_not_error

  _hi_h2 "Testing: timestamp / system_info / identity (smoke tests)"
  _hi_case _hi_assert "Timestamp prints two cells" test_timestamp_runs_and_has_two_cells
  _hi_case _hi_assert "System_info includes its static labels" test_system_info_includes_static_labels
  _hi_case _hi_assert "Identity includes its static labels" test_identity_includes_static_labels

  _hi_h2 "Testing: hi_header"
  _hi_case _hi_assert "No output when disabled" test_hi_header_disabled_produces_no_output
  _hi_case _hi_assert "Prints the banner when enabled" test_hi_header_enabled_prints_banner

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "All header.sh checks passed ($_HI_TOTAL cases)"
  else
    _hi_h1 "$_HI_FAILED/$_HI_TOTAL header.sh checks FAILED" "$RED"
  fi
  exit "$_HI_FAILED"
}

run_header_tests
