#!/bin/bash
# Unified test runner - runs every test in tests/ (or a chosen subset), times
# each one, and prints a colored pass/fail summary table at the end, instead
# of the old hi_test_all `&&` chain, which stopped at the first failure
# rather than reporting the full picture. Each test's own output still
# streams live exactly as it would running that test directly - this only
# adds timing and a final summary around it. Every test here already reports
# its own sub-case failure count (e.g. "3/4 shells FAILED") in its own red
# banner when it has more than one case; this runner's summary just shows
# each suite's overall pass/fail and duration.
#
# Usage: tests/run.sh [name ...]
#   no args     - run every test suite
#   name ...    - run only the named suite(s), e.g. `tests/run.sh docker kube`
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

# name:path, in the order they run - fast local checks first, the
# docker/kind/nomad-backed end-to-end tests after
_HI_TESTS=(
  "aliases:$_HI_TEST_ALIASES"
  "alias_fallthrough:$_HI_TEST_ALIAS_FALLTHROUGH"
  "shellcheck:$_HI_TEST_SHELLCHECK"
  "ssh:$_HI_TEST_SSH"
  "docker:$_HI_TEST_DOCKER"
  "podman:$_HI_TEST_PODMAN"
  "nomad:$_HI_TEST_NOMAD"
  "kube:$_HI_TEST_KUBE"
)

declare -a _HI_SELECTED=()
if [ "$#" -eq 0 ]; then
  _HI_SELECTED=("${_HI_TESTS[@]}")
else
  for _hi_t in "${_HI_TESTS[@]}"; do
    for _hi_arg in "$@"; do
      [ "${_hi_t%%:*}" = "$_hi_arg" ] && _HI_SELECTED+=("$_hi_t")
    done
  done
  if [ "${#_HI_SELECTED[@]}" -eq 0 ]; then
    _hi_cecho "no test suite matches: $* (known: $(printf '%s ' "${_HI_TESTS[@]%%:*}"))" "$RED"
    exit 1
  fi
fi

_hi_h1 "Running ${#_HI_SELECTED[@]} test suite(s)"

declare -a _HI_NAMES=() _HI_STATUSES=() _HI_DURATIONS=()
_HI_SUITE_FAILED=0
_HI_RUN_T0="$(_hi_now)"

for _hi_t in "${_HI_SELECTED[@]}"; do
  _hi_name="${_hi_t%%:*}"
  _hi_path="${_hi_t#*:}"

  if [ ! -f "$_hi_path" ]; then
    _hi_cecho " | $_hi_name: script missing ($_hi_path), skipping" "$YELLOW"
    _HI_NAMES+=("$_hi_name")
    _HI_STATUSES+=("MISSING")
    _HI_DURATIONS+=("-")
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
    continue
  fi

  _hi_h2 "Running $_hi_name ($_hi_path)"
  _hi_t0="$(_hi_now)"
  if "$_hi_path"; then
    _hi_code=0
  else
    _hi_code=$?
  fi
  _hi_dur="$(_hi_elapsed "$_hi_t0" "$(_hi_now)")s"

  _HI_NAMES+=("$_hi_name")
  _HI_DURATIONS+=("$_hi_dur")
  if [ "$_hi_code" -eq 0 ]; then
    _HI_STATUSES+=("PASS")
  else
    _HI_STATUSES+=("FAILED ($_hi_code)")
    _HI_SUITE_FAILED=$((_HI_SUITE_FAILED + 1))
  fi
done

# ---- summary table -----------------------------------------------------
_hi_h1 "Summary"
_hi_width=0
for _hi_name in "${_HI_NAMES[@]}"; do
  ((${#_hi_name} > _hi_width)) && _hi_width=${#_hi_name}
done

for _hi_i in "${!_HI_NAMES[@]}"; do
  _hi_color="$GREEN"
  [ "${_HI_STATUSES[_hi_i]}" = PASS ] || _hi_color="$RED"
  # shellcheck disable=SC2059 # _hi_width is a computed field-width, not user data
  _hi_cecho "$(printf " | %-${_hi_width}s  %-14s  %s" "${_HI_NAMES[_hi_i]}" "${_HI_STATUSES[_hi_i]}" "${_HI_DURATIONS[_hi_i]}")" "$_hi_color"
done

_HI_TOTAL_DUR="$(_hi_elapsed "$_HI_RUN_T0" "$(_hi_now)")s"
if [ "$_HI_SUITE_FAILED" -eq 0 ]; then
  _hi_h1 "All ${#_HI_SELECTED[@]} test suites passed ($_HI_TOTAL_DUR)"
else
  _hi_h1 "$_HI_SUITE_FAILED/${#_HI_SELECTED[@]} test suites FAILED ($_HI_TOTAL_DUR)" "$RED"
fi

exit "$_HI_SUITE_FAILED"
