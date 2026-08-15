#!/bin/bash
# Unit tests for common/header.sh.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../../common/header.sh
source "$_HI_HEADER"

function test_header_row_joins_cells() {
  local out
  out="$(header_row foo bar baz)"
  [[ "$out" == *"| foo"* && "$out" == *"| bar"* && "$out" == *"| baz"* ]]
}

function test_header_row_single_cell() {
  local out
  out="$(header_row solo)"
  [[ "$out" == *"| solo"* ]]
}

function test_banner_includes_label_and_host() {
  local out host
  host="$(_hi_hostname)"
  out="$(banner TestBanner)"
  [[ "$out" == *"TestBanner"* && "$out" == *"$host"* ]]
}

# a longer prefix reserves more of the (already-printed) line, so it should
# shrink - never grow - the tilde padding banner prints for itself
function test_banner_prefix_shrinks_padding() {
  local plain prefixed
  plain="$(banner TestBanner "$BRGREEN" "")"
  prefixed="$(banner TestBanner "$BRGREEN" "$(printf 'x%.0s' {1..50})")"
  [ "${#prefixed}" -lt "${#plain}" ]
}

function test_banner_floors_tildes_on_long_label() {
  local out label
  label="$(printf 'x%.0s' {1..200})" # forces the ((tildes < 4)) floor
  out="$(banner "$label")"
  [[ "$out" == *"$label"* && "$out" == *"~"* ]]
}

function test_banner_narrow_width_does_not_error() {
  local out
  out="$(_HI_MAX_WIDTH=10 banner Narrow)"
  [ -n "$out" ]
}

function test_timestamp_runs_and_has_two_cells() {
  local out
  out="$(timestamp)"
  [ "$(grep -o '|' <<<"$out" | wc -l)" -eq 2 ]
}

function test_system_info_includes_static_labels() {
  local out
  out="$(system_info)"
  [[ "$out" == *"Cores:"* && "$out" == *"RAM:"* && "$out" == *"CPU:"* ]]
}

function test_identity_includes_static_labels() {
  local out
  out="$(identity)"
  [[ "$out" == *"Auth:"* && "$out" == *"Pub:"* ]]
}

function test_banner_disabled_produces_no_output() {
  local out
  out="$(_HI_HEADER_BANNER=0 banner TestBanner)"
  [ -z "$out" ]
}

# guards the default: the toggle is opt-out, so an unset var must still print
function test_banner_prints_when_toggle_unset() {
  local out
  out="$(unset _HI_HEADER_BANNER && banner TestBanner)"
  [[ "$out" == *"TestBanner"* ]]
}

# banner runs twice a session (connect, then load.sh's disconnect) for a change
# count that can't have moved in between, and `git status --short` over the
# checkout is ~10ms a call. The second call has to reuse the first's answer.
# The output goes to a file rather than through $(...): the caching happens in
# a variable, and a command substitution would run banner in a subshell where
# the assignment can't be observed - which is the very thing under test.
function test_banner_change_count_is_computed_once() {
  local first second file
  file="$(mktemp -t hi.banner.XXXXXX)"
  unset _HI_BANNER_CHANGES
  banner TestBanner >"$file"
  first="$(cat "$file")"
  [ -n "${_HI_BANNER_CHANGES+x}" ] || {
    rm -f "$file"
    return 1 # nothing was cached at all
  }
  # a value git could never produce, so a second git call would overwrite it
  _HI_BANNER_CHANGES=4242
  banner TestBanner >"$file"
  second="$(cat "$file")"
  rm -f "$file"
  unset _HI_BANNER_CHANGES
  [ -n "$first" ] && [[ "$second" == *4242* ]]
}

# ...but only when there is a checkout to count. A shipped tree has no .git,
# and the banner there must simply carry no counter rather than a stale one.
function test_banner_omits_the_count_without_a_git_dir() {
  local out dir
  dir="$(mktemp -d -t hi.nogit.XXXXXX)"
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES
    banner TestBanner
  )"
  rm -rf "$dir"
  [[ "$out" == *"TestBanner"* ]] && [[ "$out" != *"↑"* ]]
}

# the regression this toggle exists for: silencing the banner must leave the
# rest of the header alone, unlike _HI_DISABLE_HEADER which kills all of it
function test_hi_header_banner_off_keeps_detail_lines() {
  local out
  out="$(_HI_HEADER_BANNER=0 hi_header Connected)"
  [[ "$out" != *"Connected"* && "$out" == *"Cores:"* && "$out" == *"RAM:"* ]]
}

function test_hi_header_disabled_produces_no_output() {
  local out
  out="$(_HI_DISABLE_HEADER=1 hi_header Connected)"
  [ -z "$out" ]
}

function test_hi_header_enabled_prints_banner() {
  local out
  out="$(_HI_DISABLE_HEADER=0 hi_header Connected)"
  [[ "$out" == *"Connected"* ]]
}

function run_header_tests() {
  _hi_h1 "Testing common/header.sh"

  _hi_suite_begin

  _hi_h2 "Testing: header_row"
  _hi_check "Joins multiple cells" test_header_row_joins_cells
  _hi_check "Handles a single cell" test_header_row_single_cell

  _hi_h2 "Testing: banner"
  _hi_check "Includes label and hostname" test_banner_includes_label_and_host
  _hi_check "A longer prefix shrinks the padding" test_banner_prefix_shrinks_padding
  _hi_check "Floors tilde padding on a pathologically long label" test_banner_floors_tildes_on_long_label
  _hi_check "Survives a narrow _HI_MAX_WIDTH" test_banner_narrow_width_does_not_error
  _hi_check "No output when _HI_HEADER_BANNER=0" test_banner_disabled_produces_no_output
  _hi_check "Still prints when the toggle is unset" test_banner_prints_when_toggle_unset
  _hi_check "Change count is computed once per session" test_banner_change_count_is_computed_once
  _hi_check "No count without a .git dir" test_banner_omits_the_count_without_a_git_dir

  _hi_h2 "Testing: timestamp / system_info / identity (smoke tests)"
  _hi_check "Timestamp prints two cells" test_timestamp_runs_and_has_two_cells
  _hi_check "System_info includes its static labels" test_system_info_includes_static_labels
  _hi_check "Identity includes its static labels" test_identity_includes_static_labels

  _hi_h2 "Testing: hi_header"
  _hi_check "No output when disabled" test_hi_header_disabled_produces_no_output
  _hi_check "Prints the banner when enabled" test_hi_header_enabled_prints_banner
  _hi_check "Banner off still prints the detail lines" test_hi_header_banner_off_keeps_detail_lines

  _hi_suite_end "header.sh"
}

run_header_tests
