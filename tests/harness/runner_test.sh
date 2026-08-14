#!/bin/bash
# Unit tests for tests/test_runner.sh.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

function _hi_fixture() {
  printf '#!/bin/bash\nprintf "ran:%s\\n"\nexit %s\n' "$1" "$2" >"$_HI_FIXTURES/$1.sh"
  chmod +x "$_HI_FIXTURES/$1.sh"
}

function _hi_run_runner() {
  local table="$1" line
  shift
  local -a entries=()
  while IFS= read -r line; do
    [ -n "$line" ] && entries+=("$line")
  done <<<"$table"

  _HI_RUN_EXIT=0
  _HI_RUN_OUT="$(
    _HI_TESTS=("${entries[@]}")
    _HI_TESTS_DIR="$_HI_FIXTURES"
    export _HI_TESTS_DIR
    # shellcheck source=../test_runner.sh
    source "$_HI_TEST_RUN" "$@"
  )" || _HI_RUN_EXIT=$?
}

function test_runs_every_suite_when_given_no_arguments() {
  _hi_run_runner $'a:green.sh\nb:green.sh'
  [[ "$_HI_RUN_OUT" == *"Running 2 test suite(s)"* ]] && [ "$_HI_RUN_EXIT" -eq 0 ]
}

function test_runs_only_the_named_suites() {
  _hi_run_runner $'keep:green.sh\ndrop:red.sh' keep
  [[ "$_HI_RUN_OUT" == *"Running 1 test suite(s)"* ]] &&
    [[ "$_HI_RUN_OUT" == *"keep"* ]] && [[ "$_HI_RUN_OUT" != *"ran:red"* ]]
}

function test_selecting_several_suites_keeps_table_order() {
  local first second
  _hi_run_runner $'one:green.sh\ntwo:green.sh\nthree:green.sh' three one
  first="$(printf '%s\n' "$_HI_RUN_OUT" | grep -n "Running one" | head -1 | cut -d: -f1)"
  second="$(printf '%s\n' "$_HI_RUN_OUT" | grep -n "Running three" | head -1 | cut -d: -f1)"
  [ -n "$first" ] && [ -n "$second" ] && [ "$first" -lt "$second" ]
}

function test_unknown_suite_name_is_an_error() {
  _hi_run_runner $'a:green.sh' nosuchsuite
  [ "$_HI_RUN_EXIT" -eq 1 ] && [[ "$_HI_RUN_OUT" == *"no test suite matches: nosuchsuite"* ]]
}

function test_unknown_suite_name_lists_the_known_ones() {
  _hi_run_runner $'alpha:green.sh\nbeta:green.sh' nosuchsuite
  [[ "$_HI_RUN_OUT" == *"alpha"* && "$_HI_RUN_OUT" == *"beta"* ]]
}

function test_all_passing_exits_zero_with_a_green_summary() {
  _hi_run_runner $'a:green.sh\nb:green.sh'
  [ "$_HI_RUN_EXIT" -eq 0 ] && [[ "$_HI_RUN_OUT" == *"All 2 test suites passed"* ]]
}

function test_a_failing_suite_is_reported_with_its_exit_code() {
  _hi_run_runner $'a:red.sh'
  [[ "$_HI_RUN_OUT" == *"FAILED (3)"* ]]
}

function test_runner_exits_with_the_failed_suite_count() {
  _hi_run_runner $'a:red.sh\nb:amber.sh\nc:green.sh'
  [ "$_HI_RUN_EXIT" -eq 2 ]
}

function test_a_failure_does_not_stop_later_suites() {
  _hi_run_runner $'a:red.sh\nb:green.sh'
  [[ "$_HI_RUN_OUT" == *"ran:red"* && "$_HI_RUN_OUT" == *"ran:green"* ]]
}

function test_failure_summary_counts_failed_over_total() {
  _hi_run_runner $'a:red.sh\nb:green.sh'
  [[ "$_HI_RUN_OUT" == *"1/2 test suites FAILED"* ]]
}

function test_a_missing_script_is_reported_as_missing() {
  _hi_run_runner $'gone:not-a-real-fixture.sh'
  [[ "$_HI_RUN_OUT" == *"script missing"* ]] && [[ "$_HI_RUN_OUT" == *"MISSING"* ]]
}

function test_a_missing_script_counts_as_a_failed_suite() {
  _hi_run_runner $'gone:not-a-real-fixture.sh\nok:green.sh'
  [ "$_HI_RUN_EXIT" -eq 1 ]
}

function test_a_missing_script_does_not_stop_the_run() {
  _hi_run_runner $'gone:not-a-real-fixture.sh\nok:green.sh'
  [[ "$_HI_RUN_OUT" == *"ran:green"* ]]
}

function test_summary_lists_every_suite_with_a_duration() {
  _hi_run_runner $'alpha:green.sh\nbeta:red.sh'
  [[ "$_HI_RUN_OUT" == *"Summary"* ]] &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'alpha .*PASS .*[0-9]+\.[0-9]+s' &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'beta .*FAILED \(3\)'
}

function test_summary_pads_names_to_the_widest() {
  local short_line
  _hi_run_runner $'a:green.sh\nlongername:green.sh'
  short_line="$(printf '%s\n' "$_HI_RUN_OUT" | grep -E '^\s*\S*\s*\| a ' | head -1)"
  # "a" is padded out to "longername"'s width, so PASS starts at the same
  # column on both rows
  [[ "$short_line" == *"a           PASS"* ]]
}

function test_each_suites_own_output_still_streams() {
  _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" == *"ran:green"* ]]
}

function test_shipped_table_still_has_every_suite_name() {
  local name out
  out="$("$_HI_TEST_RUN" definitely-not-a-suite 2>&1)" || true
  for name in aliases alias_fallthrough shellcheck install uninstall check header shared git_prompt \
    test_lib test_runner ssh ssh_disconnect docker podman nomad kube; do
    [[ "$out" == *"$name"* ]] || {
      _hi_cecho " | missing from the table: $name" "$RED"
      return 1
    }
  done
}

function test_every_shipped_suite_script_exists_and_is_executable() {
  local entry path known
  local -a entries=() names=()
  mapfile -t entries < <(grep -oE '^[[:space:]]*"[^":]+:[^"]+\.sh"$' "$_HI_TEST_RUN" | tr -d '" ')
  known="$("$_HI_TEST_RUN" definitely-not-a-suite 2>&1)" || true
  read -r -a names <<<"$(sed 's/.*(known: //; s/).*//' <<<"$known")"

  if [ "${#entries[@]}" -eq 0 ] || [ "${#entries[@]}" -ne "${#names[@]}" ]; then
    _hi_cecho " | parsed ${#entries[@]} table entries out of $_HI_TEST_RUN, runner reports ${#names[@]} suites" "$RED"
    return 1
  fi

  for entry in "${entries[@]}"; do
    path="$_HI_ROOT/tests/${entry#*:}"
    [ -x "$path" ] || {
      _hi_cecho " | not executable: $path" "$RED"
      return 1
    }
  done
}

function run_runner_tests() {
  _hi_workdir runnertest

  _HI_FIXTURES="$_HI_WORKDIR/fixtures"
  mkdir -p "$_HI_FIXTURES"

  _hi_fixture green 0
  _hi_fixture red 3
  _hi_fixture amber 1

  _hi_suite_begin

  _hi_h1 "Testing tests/test_runner.sh"

  _hi_h2 "Testing: suite selection"
  _hi_check "Runs everything with no arguments" test_runs_every_suite_when_given_no_arguments
  _hi_check "Runs only the named suites" test_runs_only_the_named_suites
  _hi_check "Keeps table order regardless of argument order" test_selecting_several_suites_keeps_table_order
  _hi_check "An unknown name is an error" test_unknown_suite_name_is_an_error
  _hi_check "An unknown name lists the known ones" test_unknown_suite_name_lists_the_known_ones

  _hi_h2 "Testing: results and exit codes"
  _hi_check "All passing -> exit 0, green summary" test_all_passing_exits_zero_with_a_green_summary
  _hi_check "A failing suite shows its exit code" test_a_failing_suite_is_reported_with_its_exit_code
  _hi_check "Exits with the failed-suite count" test_runner_exits_with_the_failed_suite_count
  _hi_check "A failure doesn't stop later suites" test_a_failure_does_not_stop_later_suites
  _hi_check "Failure summary counts failed/total" test_failure_summary_counts_failed_over_total

  _hi_h2 "Testing: missing scripts"
  _hi_check "Reported as MISSING" test_a_missing_script_is_reported_as_missing
  _hi_check "Counts as a failed suite" test_a_missing_script_counts_as_a_failed_suite
  _hi_check "Doesn't stop the run" test_a_missing_script_does_not_stop_the_run

  _hi_h2 "Testing: summary table"
  _hi_check "Lists every suite with a duration" test_summary_lists_every_suite_with_a_duration
  _hi_check "Pads names to the widest" test_summary_pads_names_to_the_widest
  _hi_check "Each suite's own output still streams" test_each_suites_own_output_still_streams

  _hi_h2 "Testing: the shipped table"
  _hi_check "Still has every CI and backend suite name" test_shipped_table_still_has_every_suite_name
  _hi_check "Every shipped path exists and is executable" test_every_shipped_suite_script_exists_and_is_executable

  _hi_suite_end "test_runner.sh"
}

run_runner_tests
