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

# _hi_fixture <name> <exit> [counts-line] - a stand-in suite: announces itself
# as "ran:<name>", optionally writes <counts-line> to $_HI_COUNTS_FILE the way
# _hi_report_counts/_hi_report_skip do, and exits <exit>. One writer rather
# than three near-copies of the same hand-escaped printf format.
function _hi_fixture() {
  {
    printf '#!/bin/bash\nprintf "ran:%s\\n"\n' "$1"
    # shellcheck disable=SC2016 # $_HI_COUNTS_FILE is resolved when the fixture runs
    [ -n "${3:-}" ] && printf 'printf "%%s\\n" "%s" >"$_HI_COUNTS_FILE"\n' "$3"
    printf 'exit %s\n' "$2"
  } >"$_HI_FIXTURES/$1.sh"
  chmod +x "$_HI_FIXTURES/$1.sh"
}

# A suite reporting a case tally: "<total> <failed>", exiting with the fail count.
function _hi_counting_fixture() {
  _hi_fixture "$1" "$3" "$2 $3"
}

# a suite that stood down without running anything - what _hi_require does
# when its backend is missing. Exits 0 like a passing suite, so only the SKIP
# line in $_HI_COUNTS_FILE tells the runner the two apart.
function _hi_skipping_fixture() {
  _hi_fixture "$1" 0 "SKIP ${2:-no backend}"
}

function _hi_run_runner() {
  local table="$1" line
  shift
  local -a entries=()
  # Fixtures are written "<name>:<path>" - the group is what the real table
  # carries for CI's sake and no case here is about, so a two-field row gets
  # the default one rather than every call site restating it.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
    *:*:*) entries+=("$line") ;;
    *) entries+=("fast:$line") ;;
    esac
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
  [ "$_HI_RUN_EXIT" -eq 0 ] && [[ "$_HI_RUN_OUT" == *"2/2 test suites passed"* ]]
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

# The summary rows carry color, so every measurement below strips the escapes
# first and then reads the row whose name cell is $1 - "SUITE" for the header
# and "TOTAL" for the totals row, both of which sit in the same column.
function _hi_summary_field() {
  printf '%s\n' "$_HI_RUN_OUT" | sed 's/\x1b\[[0-9;]*m//g' |
    awk -v n="$1" -v what="$2" '$1 == "|" && $2 == n {
      print (what == "len" ? length($0) : index($0, "PASS")); exit
    }'
}

function test_summary_pads_names_to_the_widest() {
  local short long
  _hi_run_runner $'a:green.sh\nlongername:green.sh'
  # a short name is padded out to the column width, so the STATUS cell starts
  # at the same offset on every row
  short="$(_hi_summary_field a col)"
  long="$(_hi_summary_field longername col)"
  [ -n "$short" ] && [ "$short" != 0 ] && [ "$short" = "$long" ]
}

# the table is sized like every other banner hi prints - see common/shared.sh's
# _HI_MAX_WIDTH, which the _hi_h1 rules above and below the table already use
function test_summary_rows_span_hi_max_width() {
  local row
  export _HI_MAX_WIDTH=72
  _hi_run_runner $'a:green.sh\nlongername:green.sh'
  unset _HI_MAX_WIDTH
  for row in SUITE a longername TOTAL; do
    [ "$(_hi_summary_field "$row" len)" = 72 ] || {
      _hi_cecho " | row '$row' is $(_hi_summary_field "$row" len) wide, expected 72" "$RED"
      return 1
    }
  done
}

function test_summary_tracks_a_wider_hi_max_width() {
  export _HI_MAX_WIDTH=110
  _hi_run_runner $'a:green.sh'
  unset _HI_MAX_WIDTH
  [ "$(_hi_summary_field TOTAL len)" = 110 ]
}

# too narrow to fit the names, the column keeps its natural size and the row
# overflows - a truncated suite name would be worse than a long line
function test_summary_narrow_width_does_not_truncate_names() {
  export _HI_MAX_WIDTH=20
  _hi_run_runner $'averylongsuitename:green.sh'
  unset _HI_MAX_WIDTH
  [ -n "$(_hi_summary_field averylongsuitename len)" ]
}

function test_summary_has_a_column_header() {
  _hi_run_runner $'a:green.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'SUITE .*STATUS .*PASS .*FAIL .*TIME'
}

# 7 cases, 2 of them failing, must render as 5 passed / 2 failed
function test_summary_shows_each_suites_case_counts() {
  _hi_counting_fixture counted 7 2
  _hi_run_runner $'counted:counted.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'counted .*FAILED \(2\) +5 +2 '
}

# a suite that never reported (no _hi_suite_end - a backend skip, or a bare
# script) must read as "-", not as a silent 0
function test_summary_shows_dashes_when_no_counts_were_reported() {
  _hi_run_runner $'a:green.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'a +PASS +- +- '
}

# the totals row sums subtests across suites: (6-1) + (4-0) passed, 1 + 0 failed
function test_summary_totals_sum_every_suites_cases() {
  _hi_counting_fixture six 6 1
  _hi_counting_fixture four 4 0
  _hi_run_runner $'six:six.sh\nfour:four.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'TOTAL +2 suite\(s\) +9 +1 '
}

# suites that reported nothing must not drag the totals to "-" or crash the sum
function test_summary_totals_ignore_suites_without_counts() {
  _hi_counting_fixture three 3 0
  _hi_run_runner $'three:three.sh\nplain:green.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'TOTAL +2 suite\(s\) +3 +0 '
}

# The honest half of the summary: a suite that ran nothing exits 0, so
# without a status of its own it would render as a green PASS and a run could
# report every suite passing while several never executed a case.
function test_a_skipping_suite_is_reported_as_skipped() {
  _hi_skipping_fixture stood_down "no docker"
  _hi_run_runner $'stood_down:stood_down.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'stood_down +SKIPPED'
}

function test_a_skipping_suite_is_not_a_failure() {
  _hi_skipping_fixture stood_down2
  _hi_run_runner $'stood_down2:stood_down2.sh'
  [ "$_HI_RUN_EXIT" -eq 0 ]
}

function test_a_skipping_suite_is_not_counted_as_passed() {
  _hi_skipping_fixture stood_down3
  _hi_run_runner $'stood_down3:stood_down3.sh\nok:green.sh'
  [[ "$_HI_RUN_OUT" == *"1/2 test suites passed"* ]] && [[ "$_HI_RUN_OUT" == *"1 skipped"* ]]
}

# a skip contributes no cases, so it must not add a 0 to the totals either
function test_a_skipping_suite_contributes_no_cases() {
  _hi_counting_fixture five 5 0
  _hi_skipping_fixture stood_down4
  _hi_run_runner $'five:five.sh\nstood_down4:stood_down4.sh'
  printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'TOTAL +2 suite\(s\) +5 +0 ' &&
    printf '%s\n' "$_HI_RUN_OUT" | grep -qE 'stood_down4 +SKIPPED +- +- '
}

function test_each_suites_own_output_still_streams() {
  _hi_run_runner $'a:green.sh'
  [[ "$_HI_RUN_OUT" == *"ran:green"* ]]
}

# The shipped table, straight from --list: "<group> <name>" per suite. This
# used to be a hardcoded name list here plus a `sed` over the runner's own
# error message - parsing a UI string as an API. The hardcoded copy had already
# drifted: paths, color_preview and kube were in the table and not in the list,
# so the test meant to catch drift was silently ignoring three suites.
function _hi_runner_list() {
  "$_HI_TEST_RUN" --list 2>/dev/null
}

function test_shipped_table_lists_a_group_and_name_per_suite() {
  local group name count=0
  while read -r group name; do
    [ -n "$group" ] && [ -n "$name" ] || {
      _hi_cecho " | malformed --list row: $group $name" "$RED"
      return 1
    }
    count=$((count + 1))
  done < <(_hi_runner_list)
  [ "$count" -gt 0 ] || {
    _hi_cecho " | --list returned nothing" "$RED"
    return 1
  }
}

# Every suite has to be in a group CI actually runs, or it never runs on a push
# and nothing says so - which is what happened to the `hi` suite. CI invokes
# groups by name now (see ci.yml's `--group fast`/`e2e`/`backends`), so this
# checks the workflow runs every group the table uses rather than every suite.
function test_ci_runs_every_group_in_the_table() {
  local workflow="$_HI_ROOT/.github/workflows/ci.yml" group name missing=""
  local -a groups=()
  [ -f "$workflow" ] || return 0 # a shipped tree has no .github
  while read -r group name; do
    [[ " ${groups[*]} " == *" $group "* ]] || groups+=("$group")
  done < <(_hi_runner_list)
  [ "${#groups[@]}" -gt 0 ] || {
    _hi_cecho " | couldn't read the suite table back out of the runner" "$RED"
    return 1
  }
  for group in "${groups[@]}"; do
    grep -qF -- "--group $group" "$workflow" || missing+=" $group"
  done
  [ -z "$missing" ] || {
    _hi_cecho " | groups in the runner but not run by CI:$missing" "$RED"
    return 1
  }
}

# Each suite selectable on its own, and every group non-empty: together these
# are what makes `--group` a safe thing for CI to depend on.
# --group is what ci.yml invokes, so every group the table uses has to select
# at least one suite - and only suites of that group
function test_every_group_selects_only_its_own_suites() {
  local group rows
  while read -r group; do
    rows="$("$_HI_TEST_RUN" --group "$group" --list 2>/dev/null)"
    [ -n "$rows" ] || {
      _hi_cecho " | group selects nothing: $group" "$RED"
      return 1
    }
    [ -z "$(printf '%s\n' "$rows" | awk -v g="$group" '$1 != g')" ] || {
      _hi_cecho " | --group $group returned another group's suites" "$RED"
      return 1
    }
  done < <(_hi_runner_list | awk '!seen[$1]++ {print $1}')
}

function test_every_shipped_suite_script_exists_and_is_executable() {
  local entry path count=0
  local -a entries=()
  mapfile -t entries < <(grep -oE '^[[:space:]]*"[^":]+:[^":]+:[^"]+\.sh"$' "$_HI_TEST_RUN" | tr -d '" ')
  while read -r _ _; do count=$((count + 1)); done < <(_hi_runner_list)

  if [ "${#entries[@]}" -eq 0 ] || [ "${#entries[@]}" -ne "$count" ]; then
    _hi_cecho " | parsed ${#entries[@]} table entries out of $_HI_TEST_RUN, runner reports $count suites" "$RED"
    return 1
  fi

  for entry in "${entries[@]}"; do
    path="$_HI_ROOT/tests/${entry##*:}"
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
  _hi_check "Rows span _HI_MAX_WIDTH" test_summary_rows_span_hi_max_width
  _hi_check "Tracks a wider _HI_MAX_WIDTH" test_summary_tracks_a_wider_hi_max_width
  _hi_check "A narrow width doesn't truncate names" test_summary_narrow_width_does_not_truncate_names
  _hi_check "Each suite's own output still streams" test_each_suites_own_output_still_streams

  _hi_h2 "Testing: summary case counts"
  _hi_check "Has a column header" test_summary_has_a_column_header
  _hi_check "Shows each suite's pass/fail counts" test_summary_shows_each_suites_case_counts
  _hi_check "Shows - when a suite reported no counts" test_summary_shows_dashes_when_no_counts_were_reported
  _hi_check "Totals sum every suite's cases" test_summary_totals_sum_every_suites_cases
  _hi_check "Totals ignore suites without counts" test_summary_totals_ignore_suites_without_counts

  _hi_h2 "Testing: skipped suites"
  _hi_check "Reported as SKIPPED, not PASS" test_a_skipping_suite_is_reported_as_skipped
  _hi_check "Not a failure" test_a_skipping_suite_is_not_a_failure
  _hi_check "Not counted as passed" test_a_skipping_suite_is_not_counted_as_passed
  _hi_check "Contributes no cases" test_a_skipping_suite_contributes_no_cases

  _hi_h2 "Testing: the shipped table"
  _hi_check "Lists a group and name per suite" test_shipped_table_lists_a_group_and_name_per_suite
  _hi_check "Every shipped path exists and is executable" test_every_shipped_suite_script_exists_and_is_executable
  _hi_check "CI runs every group in the table" test_ci_runs_every_group_in_the_table
  _hi_check "Each group selects only its own" test_every_group_selects_only_its_own_suites

  _hi_suite_end "test_runner.sh"
}

run_runner_tests
