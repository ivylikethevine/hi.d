#!/bin/bash
# Sources shells/aliases.sh in a real instance of each target shell and checks
# that every alias/var it unconditionally defines actually landed - not just
# that the file was found. Skips any shell that isn't installed.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# derived straight from aliases.sh so this test can't drift out of sync with
# it; only unconditional top-of-line `alias name=`/`export name=` are picked
# up, so conditionally-set vars (e.g. ANDROID_HOME) are correctly skipped
_HI_SAMPLE_ALIASES=$(grep -oE '^alias +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ALIASES" | sed -E 's/^alias +//; s/=$//' | tr '\n' ' ')
_HI_SAMPLE_VARS=$(grep -oE '^export +[A-Za-z_][A-Za-z0-9_]*=' "$_HI_ALIASES" | sed -E 's/^export +//; s/=$//' | tr '\n' ' ')

# posix `alias name` / `test -n "${v+x}"` work unmodified in dash, bash and zsh;
# fish has neither - aliases are functions there, and `set -q` is its "is set"
# shellcheck disable=SC2016 # these are the scripts we write out, not code to run here
function _hi_test_script() {
  if [ "$1" = fish ]; then
    printf '%s\n' 'source "$_HI_ALIASES"; or exit 1' 'set fail 0' \
      "for a in $_HI_SAMPLE_ALIASES" '  functions -q -- $a; or begin; echo "missing alias: $a" >&2; set fail 1; end' 'end' \
      "for v in $_HI_SAMPLE_VARS" '  set -q $v; or begin; echo "missing var: $v" >&2; set fail 1; end' 'end' \
      'exit $fail'
  else
    printf '%s\n' '. "$_HI_ALIASES" || exit 1' 'fail=0' \
      "for a in $_HI_SAMPLE_ALIASES; do" '  alias "$a" >/dev/null 2>&1 || { echo "missing alias: $a" >&2; fail=1; }' 'done' \
      "for v in $_HI_SAMPLE_VARS; do" '  eval "test -n \"\${$v+x}\"" || { echo "missing var: $v" >&2; fail=1; }' 'done' \
      'exit $fail'
  fi
}

function _hi_test_shell() {
  local shell="$1" script="$2/$1.test" output exit_code=0 t0 t1
  _hi_h2 "Starting: [$shell]"
  t0="$(_hi_now)"

  _hi_cecho "  [$shell] -- Writing test script..."
  _hi_test_script "$shell" >"$script"
  _hi_cecho "  [$shell] -- Running: $script"
  output=$("$shell" "$script" 2>&1) || exit_code=$?
  t1="$(_hi_now)"

  if [ "$exit_code" -eq 0 ]; then
    _hi_h3 "[$shell] -- Loaded aliases.sh OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
  else
    _hi_h3 "[$shell] -- FAILED ($(_hi_elapsed "$t0" "$t1")s)" "$RED"
    [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
  fi
  return "$exit_code"
}

# aliases.sh reads _HI_DISABLE_EDITORS/_HI_DISABLE_ALIASES, and neither can be
# written as ${X:-0} because fish sources this file and cannot parse that. So
# the file defaults them itself, and this is what proves it: source it with
# both scrubbed from the environment, under `set -u` where an unset variable is
# fatal rather than empty. That is the shape `hi <target> <command>` runs in,
# and it is how the ssh suite broke.
function _hi_test_shell_strict() {
  local shell="$1" script="$2/$1.strict" output exit_code=0
  _hi_h2 "Starting: [$shell] (toggles unset, strict mode)"
  _hi_test_script "$shell" >"$script"

  if [ "$shell" = fish ]; then
    # fish has no `set -u` - unset is always empty there - so what matters is
    # that the defaulting line doesn't break parsing
    output=$(env -u _HI_DISABLE_EDITORS -u _HI_DISABLE_ALIASES "$shell" "$script" 2>&1) || exit_code=$?
  else
    output=$(env -u _HI_DISABLE_EDITORS -u _HI_DISABLE_ALIASES "$shell" -u "$script" 2>&1) || exit_code=$?
  fi

  if [ "$exit_code" -eq 0 ]; then
    _hi_h3 "[$shell] -- Loaded with the toggles unset OK" "$GREEN"
  else
    _hi_h3 "[$shell] -- FAILED with the toggles unset" "$RED"
    [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
  fi
  return "$exit_code"
}

function run_alias_test() {
  _hi_h1 "Testing aliases.sh across shells"
  _hi_h2 "Sampled $(wc -w <<<"$_HI_SAMPLE_ALIASES") aliases and $(wc -w <<<"$_HI_SAMPLE_VARS") variables"

  _hi_workdir aliases

  _hi_suite_begin
  for _hi_shell in dash bash zsh fish; do
    if ! command -v "$_hi_shell" >/dev/null 2>&1; then
      _hi_h2 "$_hi_shell -- not installed, skipped"
      continue
    fi
    _hi_case _hi_test_shell "$_hi_shell" "$_HI_WORKDIR"
    _hi_case _hi_test_shell_strict "$_hi_shell" "$_HI_WORKDIR"
  done

  _hi_suite_end "" \
    "All installed shells loaded aliases.sh cleanly ($_HI_TOTAL shells)" \
    "One or more shells FAILED to load aliases.sh: $_HI_FAILED/$_HI_TOTAL"
}

run_alias_test
