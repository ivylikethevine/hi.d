#!/bin/bash
# Unit tests for common/header.sh - the banner and its detail lines, plus the
# packages check (check_line/full_check) that lives at the bottom of that file.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
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
#
# The hostname is pinned rather than taken from the machine. banner budgets a
# fixed width between the change count, the label, the host and the prefix, and
# floors the tildes at 4 once that budget is gone - so on a host whose name runs
# past ~54 characters *both* calls floor, the two lines come out the same length
# and this reads as a failure of the padding logic when it is really a failure
# to control the fixture. That is what it did on the macOS CI runner.
function test_banner_prefix_shrinks_padding() {
  local plain prefixed _HI_HOSTNAME_CACHE="pinned-host"
  plain="$(banner TestBanner "$BRGREEN" "")"
  prefixed="$(banner TestBanner "$BRGREEN" "$(printf 'x%.0s' {1..50})")"
  [ "${#prefixed}" -lt "${#plain}" ]
}

# ...and the floor itself, which the test above used to reach by accident on a
# long-hostname machine. Here it is on purpose, with the hostname pinned long.
function test_banner_floors_padding_on_a_long_hostname() {
  local out _HI_HOSTNAME_CACHE
  printf -v _HI_HOSTNAME_CACHE 'h%.0s' {1..60}
  out="$(banner TestBanner)"
  [[ "$out" == *"$_HI_HOSTNAME_CACHE"* && "$out" == *"~"* ]]
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

# A tiny checkout for the branch-indicator cases: one commit on main, so HEAD
# can be moved to a working branch or detached per case.
function _hi_banner_repo() {
  local dir
  dir="$(mktemp -d "$_HI_WORKDIR/branch.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Test"
  git -C "$dir" commit -q --allow-empty -m initial
  printf '%s' "$dir"
}

# the roadmap contract: the Online banner on a working branch names it, in
# parentheses, right after the change count
function test_banner_online_names_an_off_main_branch() {
  local dir out
  dir="$(_hi_banner_repo)"
  git -C "$dir" checkout -qb feature-x
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  [[ "$out" == *"(feature-x)"* ]]
}

# ...but main is the expected state and earns no callout
function test_banner_online_stays_quiet_on_main() {
  local dir out
  dir="$(_hi_banner_repo)"
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# ...nor does a detached HEAD, which is what a release-tag checkout is
function test_banner_online_stays_quiet_when_detached() {
  local dir out
  dir="$(_hi_banner_repo)"
  git -C "$dir" checkout -q --detach
  out="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  [[ "$out" == *"↑"* && "$out" != *"("* ]]
}

# Online only: the same branch stays out of the Connected and Disconnected
# banners a session prints
function test_banner_branch_stays_out_of_remote_banners() {
  local dir out label
  dir="$(_hi_banner_repo)"
  git -C "$dir" checkout -qb feature-x
  for label in Connected Disconnected; do
    out="$(
      _HI_ROOT="$dir"
      unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
      banner "$label"
    )"
    [[ "$out" == *"↑"* && "$out" != *"("* ]] || return 1
  done
}

# the branch spends the tilde budget, not line width: same label, same repo,
# fewer tildes once the indicator is on the line
function test_banner_branch_shrinks_padding() {
  local dir plain branched _HI_HOSTNAME_CACHE="pinned-host"
  dir="$(_hi_banner_repo)"
  plain="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  git -C "$dir" checkout -qb feature-x
  branched="$(
    _HI_ROOT="$dir"
    unset _HI_BANNER_CHANGES _HI_BANNER_BRANCH
    banner Online
  )"
  [ "$(tr -dc '~' <<<"$branched" | wc -c)" -lt "$(tr -dc '~' <<<"$plain" | wc -c)" ]
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

# --- the packages check -----------------------------------------------------

# shellcheck disable=SC2209 # the literal command name "sh" is intentional, not a botched `sh` invocation
_HI_REAL_CMD=sh
_HI_FAKE_CMD=definitely-not-a-real-hi-test-command-xyz

# Does $1 contain the bytes of $2? A byte-exact `grep -F` under LC_ALL=C rather
# than `[[ $1 == *"$2"* ]]`, because two of the three marks are multibyte and
# bash's pattern engine consults the locale to decide what a character even is.
# The macOS runner failed exactly the two cases that looked for ✓ and ✗ while
# passing the one that looked for the ASCII ~, which is that difference and
# nothing else. Bytes are bytes in every locale.
#
# The needle always comes from header.sh's own $_HI_MARK_* rather than a second
# literal here, so this compares the shipped glyph against itself.
function _hi_contains() {
  printf '%s' "$1" | LC_ALL=C grep -qF -- "$2"
}

# _hi_contains with the mismatch printed, so a failure on a machine this suite
# cannot be run on interactively still says what it actually got.
function _hi_assert_contains() {
  _hi_contains "$1" "$2" && return 0
  _hi_cecho "   expected to find: $(printf '%s' "$2" | od -An -tx1 | tr -d ' \n')" "$RED"
  _hi_cecho "   in: $(printf '%s' "$1" | od -An -tx1 | tr -d ' \n')" "$RED"
  return 1
}

function test_check_line_found_primary_is_visible_checked() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  _hi_contains "${visible[0]}" "$_HI_REAL_CMD" &&
    _hi_assert_contains "${visible[0]}" "$_HI_MARK_OK"
}

function test_check_line_found_priority2_is_hidden() {
  local -a visible=()
  check_line "$_HI_REAL_CMD:2"
  [ "${#visible[@]}" -eq 0 ]
}

function test_check_line_missing_priority0_is_hidden() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:0"
  [ "${#visible[@]}" -eq 0 ]
}

function test_check_line_missing_priority5_is_visible_crossed() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  _hi_contains "${visible[0]}" "$_HI_FAKE_CMD" &&
    _hi_assert_contains "${visible[0]}" "$_HI_MARK_NO"
}

function test_check_line_fallback_uses_second_alternative() {
  local -a visible=()
  check_line "$_HI_FAKE_CMD:0,$_HI_REAL_CMD:5"
  [ "${#visible[@]}" -eq 1 ] || return 1
  _hi_contains "${visible[0]}" "$_HI_REAL_CMD" &&
    _hi_assert_contains "${visible[0]}" "$_HI_MARK_ALT"
}

function test_check_line_picks_highest_priority_installed() {
  command -v bash >/dev/null 2>&1 || return 0 # nothing to assert without bash
  local -a visible=()
  check_line "$_HI_REAL_CMD:1,bash:5"
  _hi_contains "${visible[0]}" bash
}

function test_full_check_skips_comments_and_blanks() {
  local pkgfile="$_HI_WORKDIR/comments"
  printf '# a comment\n\n%s:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  (
    _HI_PACKAGES="$pkgfile"
    full_check
  ) | grep -qF "$_HI_REAL_CMD"
}

function test_full_check_empty_when_everything_hidden() {
  local pkgfile="$_HI_WORKDIR/hidden" out
  printf '%s:0\n' "$_HI_FAKE_CMD" >"$pkgfile" # missing + priority 0 == hide
  out="$(
    _HI_PACKAGES="$pkgfile"
    full_check
  )"
  [ -z "$out" ]
}

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

function test_full_check_reads_real_packages_file_without_erroring() {
  full_check >/dev/null
}

# The assertion that would have caught the BSD-sort bug where it happened. That
# sort ran under the ambient locale, and on macOS it exited with "Illegal byte
# sequence" and printed nothing - so full_check rendered an empty check while
# still exiting 0, and only the downstream output assertions noticed. stderr is
# the direct signal; everything else is a symptom.
function test_full_check_is_silent_on_stderr() {
  local err
  err="$({ full_check >/dev/null; } 2>&1)"
  [ -z "$err" ]
}

# ...and the other half of that failure mode: sorting produced no rows at all.
# A visible package must actually reach the output, not just fail to error.
function test_full_check_emits_a_row_for_an_installed_package() {
  local pkgfile="$_HI_WORKDIR/emits" out
  printf '%s:5\n' "$_HI_REAL_CMD" >"$pkgfile"
  out="$(
    _HI_PACKAGES="$pkgfile"
    full_check
  )"
  [[ "$out" == *"$_HI_REAL_CMD"* ]]
}

function run_header_tests() {
  _hi_workdir headertest

  _hi_h1 "Testing common/header.sh"

  _hi_suite_begin

  _hi_h2 "Testing: header_row"
  _hi_check "Joins multiple cells" test_header_row_joins_cells
  _hi_check "Handles a single cell" test_header_row_single_cell

  _hi_h2 "Testing: banner"
  _hi_check "Includes label and hostname" test_banner_includes_label_and_host
  _hi_check "A longer prefix shrinks the padding" test_banner_prefix_shrinks_padding
  _hi_check "Floors padding on a long hostname" test_banner_floors_padding_on_a_long_hostname
  _hi_check "Floors tilde padding on a pathologically long label" test_banner_floors_tildes_on_long_label
  _hi_check "Survives a narrow _HI_MAX_WIDTH" test_banner_narrow_width_does_not_error
  _hi_check "No output when _HI_HEADER_BANNER=0" test_banner_disabled_produces_no_output
  _hi_check "Still prints when the toggle is unset" test_banner_prints_when_toggle_unset
  _hi_check "Change count is computed once per session" test_banner_change_count_is_computed_once
  _hi_check "No count without a .git dir" test_banner_omits_the_count_without_a_git_dir
  _hi_check "Online names an off-main branch" test_banner_online_names_an_off_main_branch
  _hi_check "Online stays quiet on main" test_banner_online_stays_quiet_on_main
  _hi_check "Online stays quiet when detached" test_banner_online_stays_quiet_when_detached
  _hi_check "Branch stays out of Connected/Disconnected" test_banner_branch_stays_out_of_remote_banners
  _hi_check "Branch spends tilde budget, not width" test_banner_branch_shrinks_padding

  _hi_h2 "Testing: timestamp / system_info / identity (smoke tests)"
  _hi_check "Timestamp prints two cells" test_timestamp_runs_and_has_two_cells
  _hi_check "System_info includes its static labels" test_system_info_includes_static_labels
  _hi_check "Identity includes its static labels" test_identity_includes_static_labels

  _hi_h2 "Testing: hi_header"
  _hi_check "No output when disabled" test_hi_header_disabled_produces_no_output
  _hi_check "Prints the banner when enabled" test_hi_header_enabled_prints_banner
  _hi_check "Banner off still prints the detail lines" test_hi_header_banner_off_keeps_detail_lines

  _hi_h2 "Testing: check_line"
  _hi_check "Found primary -> visible, checked" test_check_line_found_primary_is_visible_checked
  _hi_check "Found priority 2 -> hidden" test_check_line_found_priority2_is_hidden
  _hi_check "Missing priority 0 -> hidden" test_check_line_missing_priority0_is_hidden
  _hi_check "Missing priority 5 -> visible, crossed" test_check_line_missing_priority5_is_visible_crossed
  _hi_check "Fallback alternative used" test_check_line_fallback_uses_second_alternative
  _hi_check "Picks the highest-priority installed alternative" test_check_line_picks_highest_priority_installed

  _hi_h2 "Testing: full_check"
  _hi_check "Skips comment/blank lines" test_full_check_skips_comments_and_blanks
  _hi_check "Empty output when everything is hidden" test_full_check_empty_when_everything_hidden
  _hi_check "Wraps rows at _HI_MAX_WIDTH" test_full_check_wraps_at_max_width
  _hi_check "Real misc/packages file parses cleanly" test_full_check_reads_real_packages_file_without_erroring
  _hi_check "Writes nothing to stderr" test_full_check_is_silent_on_stderr
  _hi_check "Emits a row for an installed package" test_full_check_emits_a_row_for_an_installed_package

  _hi_suite_end "header.sh"
}

run_header_tests
