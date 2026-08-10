#!/bin/bash
# Sources shells/aliases.sh in a real instance of each target shell and checks
# that every alias/var it unconditionally defines actually landed - not just
# that the file was found. Skips any shell that isn't installed.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

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
  local shell="$1" script="$2/$1.test" output exit_code=0
  _hi_h2 "$shell -- starting"

  if ! command -v "$shell" >/dev/null 2>&1; then
    _hi_h3 "$shell -- not installed, skipped"
    return 0
  fi

  _hi_cecho " | $shell -- writing test script to $script"
  _hi_test_script "$shell" >"$script"
  _hi_cecho " | $shell -- running: $shell $script"
  output=$("$shell" "$script" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    _hi_h3 "$shell -- aliases.sh loaded OK"
  else
    _hi_h3 "$shell -- FAILED"
    [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
  fi
  return "$exit_code"
}

function run_alias_test() {
  _hi_h1 "Testing aliases.sh across shells"
  _hi_h2 "Sampled $(wc -w <<<"$_HI_SAMPLE_ALIASES") aliases and $(wc -w <<<"$_HI_SAMPLE_VARS") variables"

  _HI_WORKDIR=$(mktemp -d -t hi.aliases.XXXXXX)
  trap 'rm -rf "$_HI_WORKDIR"' EXIT

  _HI_FAILED=0
  for _hi_shell in dash bash zsh fish; do
    _hi_test_shell "$_hi_shell" "$_HI_WORKDIR" || _HI_FAILED=1
  done

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "All installed shells loaded aliases.sh cleanly"
  else
    _hi_h1 "One or more shells FAILED to load aliases.sh"
  fi
  exit "$_HI_FAILED"
}

run_alias_test
