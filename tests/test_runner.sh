#!/bin/bash
# Unified test runner - runs every test in tests/ (or a chosen subset), times
# each one, and prints a colored pass/fail summary table at the end.
#
# Usage: tests/test_runner.sh [name ...]
#   no args     - run every test suite
#   name ...    - run only the named suite(s), e.g. `tests/test_runner.sh docker kube`
set -euo pipefail

# shellcheck source=../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"

# group:name:path (relative to this directory), in the order they run - fast
# local checks first, the docker/kind/nomad-backed end-to-end tests after.
#
# The group is here rather than in .github/workflows/ci.yml because CI used to
# spell out which suites were fast and which were e2e, and a suite added to
# this table but missed there silently never ran on a push (which is what
# happened to the `hi` suite). `--group fast` is now the only list, so the two
# cannot disagree.
if ! declare -p _HI_TESTS >/dev/null 2>&1; then
  _HI_TESTS=(
    "fast:aliases:shells/alias_test.sh"
    "fast:alias_fallthrough:shells/alias_fallthrough_test.sh"
    "fast:shellcheck:shells/shellcheck_test.sh"
    "fast:install:scripts/install_test.sh"
    "fast:hi:shells/hi_test.sh"
    "fast:header:common/header_test.sh"
    "fast:core:common/core_test.sh"
    "fast:git_prompt:common/git_prompt_test.sh"
    "fast:targets:common/targets_test.sh"
    "fast:paths:common/paths_test.sh"
    "fast:color_preview:scripts/color_preview_test.sh"
    "fast:load:shells/load_test.sh"
    "fast:test_lib:harness/lib_test.sh"
    "fast:test_runner:harness/runner_test.sh"
    "e2e:ssh:targets/ssh_test.sh"
    "e2e:ssh_disconnect:targets/ssh_disconnect_test.sh"
    "e2e:docker:targets/docker_test.sh"
    "backends:podman:targets/podman_test.sh"
    "backends:nomad:targets/nomad_test.sh"
    "backends:kube:targets/kube_test.sh"
  )
fi

# <group>:<name>:<path> -> the parts every consumer below wants. Kept as
# accessors so nothing else has to know the field order.
function _hi_test_group() { printf '%s' "${1%%:*}"; }
function _hi_test_name() {
  local rest="${1#*:}"
  printf '%s' "${rest%%:*}"
}
function _hi_test_path() { printf '%s' "${1##*:}"; }

function _hi_test_names() {
  local t
  for t in "${_HI_TESTS[@]}"; do _hi_test_name "$t"; printf ' '; done
}

function _hi_test_groups() {
  local t
  for t in "${_HI_TESTS[@]}"; do _hi_test_group "$t"; printf '\n'; done | awk '!seen[$0]++' | tr '\n' ' '
}

# "  <group>  <name>" per suite, for --help
function _hi_test_listing() {
  local t
  for t in "${_HI_TESTS[@]}"; do
    printf '  %-10s %s\n' "$(_hi_test_group "$t")" "$(_hi_test_name "$t")"
  done
}

_HI_TESTS_DIR="${_HI_TESTS_DIR:-$_HI_ROOT/tests}"

# Checked before suite matching so `--help` can't be mistaken for a suite name
# and rejected as unknown. The suite list comes from $_HI_TESTS rather than
# being spelled out again, so it can't drift.
_HI_GROUP=""
_HI_LIST=0
declare -a _HI_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
  -h | --help)
    cat <<EOF
Usage: test_runner.sh [--group <group>] [suite ...]

Runs every test suite, or just the named ones, timing each and printing a
pass/fail summary table at the end. Exits with the number of failed suites.

A suite that stands down because its backend isn't installed reports SKIPPED
rather than PASS, so a green run can't overstate what actually ran.

  suite ...        one or more of the names below (default: all of them)
  --group <group>  every suite in one group: $(_hi_test_groups)
  --list           print "<group> <name>" per suite and exit
  -h, --help       this text

Suites, in the order they run:
$(_hi_test_listing)

Needs \$_HI_HOME pointing at the parent of your hi.d checkout.
EOF
    exit 0
    ;;
  # handled after selection below, so `--group X --list` lists that group
  --list) _HI_LIST=1 ;;
  --group)
    [ "$#" -ge 2 ] || {
      _hi_cecho "test_runner.sh: --group needs a value" "$RED" >&2
      exit 1
    }
    _HI_GROUP="$2"
    shift
    ;;
  --group=*) _HI_GROUP="${1#--group=}" ;;
  *) _HI_ARGS+=("$1") ;;
  esac
  shift
done

declare -a _HI_SELECTED=()
if [ -n "$_HI_GROUP" ]; then
  for _hi_t in "${_HI_TESTS[@]}"; do
    [ "$(_hi_test_group "$_hi_t")" = "$_HI_GROUP" ] && _HI_SELECTED+=("$_hi_t")
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test group matches: $_HI_GROUP (known: $(_hi_test_groups))" "$RED"
    exit 1
  fi
elif [ "${#_HI_ARGS[@]}" -eq 0 ]; then
  _HI_SELECTED=("${_HI_TESTS[@]}")
else
  for _hi_t in "${_HI_TESTS[@]}"; do
    for _hi_arg in "${_HI_ARGS[@]}"; do
      [ "$(_hi_test_name "$_hi_t")" = "$_hi_arg" ] && _HI_SELECTED+=("$_hi_t")
    done
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test suite matches: ${_HI_ARGS[*]} (known: $(_hi_test_names))" "$RED"
    exit 1
  fi
fi

# "<group> <name>" per selected suite - the machine-readable view of the table,
# which tests/harness/runner_test.sh reads instead of parsing an error message
if [ "$_HI_LIST" = 1 ]; then
  for _hi_t in "${_HI_SELECTED[@]}"; do
    printf '%s %s\n' "$(_hi_test_group "$_hi_t")" "$(_hi_test_name "$_hi_t")"
  done
  exit 0
fi

_hi_h1 "Running ${#_HI_SELECTED[@]} test suite(s)"

# An e2e suite that drives a pty (ssh_disconnect, ssh, ...) can hand a real
# `ssh -t` our terminal and then kill it before it restores the terminal modes
# it changed, leaving every later suite's output staircased. The suites are
# responsible for not doing that, but one slip shouldn't corrupt the rest of
# the run - so snapshot the terminal here and put it back after every suite.
_HI_TTY_STATE=""
if [ -t 0 ] && command -v stty >/dev/null 2>&1; then
  _HI_TTY_STATE="$(stty -g </dev/tty 2>/dev/null || true)"
fi

function _hi_restore_tty() {
  [ -n "$_HI_TTY_STATE" ] || return 0
  stty "$_HI_TTY_STATE" </dev/tty 2>/dev/null || true
}

# Each suite runs as its own process, so its case tally can't come back in a
# variable - _hi_suite_end writes "<total> <failed>" here instead. Assigned
# unconditionally (never defaulted from the environment) so that a runner
# nested inside another run - which is exactly what harness/runner_test.sh
# does - gets its own file and can't clobber its parent's.
_HI_COUNTS_FILE="$(mktemp -t hi.counts.XXXXXX)"
export _HI_COUNTS_FILE

# shellcheck disable=SC2064 # _HI_COUNTS_FILE is fixed by now; expand it here
trap "_hi_restore_tty; rm -f '$_HI_COUNTS_FILE'" EXIT

# One row per suite, tab-joined: <name>\t<status>\t<pass>\t<fail>\t<duration>.
# Five arrays appended in lockstep from two places meant a missed append in one
# of them silently shifted every later row's data.
declare -a _HI_ROWS=()
_HI_SUITE_FAILED=0
_HI_SUITE_SKIPPED=0
_HI_CASES_PASSED=0
_HI_CASES_FAILED=0
_HI_RUN_T0="$(_hi_now)"

for _hi_t in "${_HI_SELECTED[@]}"; do
  _hi_name="$(_hi_test_name "$_hi_t")"
  _hi_path="$_HI_TESTS_DIR/$(_hi_test_path "$_hi_t")"

  if [ ! -f "$_hi_path" ]; then
    _hi_cecho " | $_hi_name: script missing ($_hi_path), skipping" "$YELLOW"
    _HI_ROWS+=("$_hi_name"$'\t'MISSING$'\t'-$'\t'-$'\t'-)
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
    continue
  fi

  _hi_h2 "Running $_hi_name ($_hi_path)"
  : >"$_HI_COUNTS_FILE"
  _hi_t0="$(_hi_now)"
  if "$_hi_path"; then
    _hi_code=0
  else
    _hi_code=$?
  fi
  _hi_dur="$(_hi_elapsed "$_hi_t0" "$(_hi_now)")s"
  _hi_restore_tty

  # empty unless the suite reached _hi_suite_end - a suite that reports its own
  # way contributes no cases. A leading SKIP instead of a tally is _hi_require's
  # doing: the suite stood down (no backend, no binary) without running a case,
  # and exits 0 doing it, so only this tells the two apart from a real pass.
  _hi_pass="-"
  _hi_fail="-"
  _hi_skip=""
  if [ -s "$_HI_COUNTS_FILE" ]; then
    read -r _hi_cases _hi_bad <"$_HI_COUNTS_FILE"
    if [ "$_hi_cases" = SKIP ]; then
      _hi_skip="${_hi_bad:-skipped}"
    else
      _hi_pass=$((_hi_cases - _hi_bad))
      _hi_fail="$_hi_bad"
      _HI_CASES_PASSED=$((_HI_CASES_PASSED + _hi_pass))
      _HI_CASES_FAILED=$((_HI_CASES_FAILED + _hi_bad))
    fi
  fi

  if [ -n "$_hi_skip" ]; then
    _hi_status="SKIPPED"
    _HI_SUITE_SKIPPED=$((_HI_SUITE_SKIPPED + 1))
  elif [ "$_hi_code" -eq 0 ]; then
    _hi_status="PASS"
  else
    _hi_status="FAILED ($_hi_code)"
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
  fi
  _HI_ROWS+=("$_hi_name"$'\t'"$_hi_status"$'\t'"$_hi_pass"$'\t'"$_hi_fail"$'\t'"$_hi_dur")
done

_hi_h1 "Summary"
_hi_width=5 # "TOTAL" is the widest the name column can need on its own
for _hi_row in "${_HI_ROWS[@]}"; do
  _hi_name="${_hi_row%%$'\t'*}"
  ((${#_hi_name} > _hi_width)) && _hi_width=${#_hi_name}
done

# Stretch the name column so a row spans exactly _HI_MAX_WIDTH, lining the
# table up with the _hi_h1 rules above and below it. 47 is everything a row
# spends outside that column: the " | " prefix (3), the four fixed columns
# (14 + 6 + 6 + 10) and the two-space gap between each pair (8). A width too
# narrow to fit the names leaves the column at its natural size and lets the
# row overflow, rather than truncating a suite name into ambiguity.
_HI_SUMMARY_FIXED=47
_hi_avail=$((${_HI_MAX_WIDTH:-80} - _HI_SUMMARY_FIXED))
((_hi_avail > _hi_width)) && _hi_width=$_hi_avail

# one format for the header, every suite row, and the totals row, so the
# columns can't drift apart; cases are right-aligned to read as numbers
# shellcheck disable=SC2059 # _hi_width is a computed field-width, not user data
function _hi_summary_row() {
  printf " | %-${_hi_width}s  %-14s  %6s  %6s  %10s" "$1" "$2" "$3" "$4" "$5"
}

_hi_cecho "$(_hi_summary_row SUITE STATUS PASS FAIL TIME)" "$BRBLUE"

for _hi_row in "${_HI_ROWS[@]}"; do
  IFS=$'\t' read -r _hi_name _hi_status _hi_pass _hi_fail _hi_dur <<<"$_hi_row"
  case "$_hi_status" in
  PASS) _hi_color="$GREEN" ;;
  SKIPPED) _hi_color="$YELLOW" ;; # ran nothing: neither a pass nor a failure
  *) _hi_color="$RED" ;;
  esac
  _hi_cecho "$(_hi_summary_row "$_hi_name" "$_hi_status" "$_hi_pass" "$_hi_fail" "$_hi_dur")" "$_hi_color"
done

_HI_TOTAL_DUR="$(_hi_elapsed "$_HI_RUN_T0" "$(_hi_now)")s"

# totals row: suites across the status column, summed cases across pass/fail
_hi_cecho "$(_hi_summary_row TOTAL "${#_HI_SELECTED[@]} suite(s)" \
  "$_HI_CASES_PASSED" "$_HI_CASES_FAILED" "$_HI_TOTAL_DUR")" "$BRBLUE"

_HI_SKIP_NOTE=""
[ "$_HI_SUITE_SKIPPED" -gt 0 ] && _HI_SKIP_NOTE=", $_HI_SUITE_SKIPPED skipped"

if [ "$_HI_SUITE_FAILED" -eq 0 ]; then
  # never claim the skipped ones passed - that's the whole point of the status
  _hi_h1 "$((${#_HI_SELECTED[@]} - _HI_SUITE_SKIPPED))/${#_HI_SELECTED[@]} test suites passed ($_HI_TOTAL_DUR$_HI_SKIP_NOTE)"
else
  _hi_h1 "$_HI_SUITE_FAILED/${#_HI_SELECTED[@]} test suites FAILED ($_HI_TOTAL_DUR$_HI_SKIP_NOTE)" "$RED"
fi

exit "$_HI_SUITE_FAILED"
