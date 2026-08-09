#!/bin/bash
# Sources shells/aliases.sh in a real instance of each target shell and checks
# that a sample of its "required" aliases/vars actually landed - not just that
# the file was found. Skips any shell that isn't installed.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"

# TODO: Make more exhaustive
# a sample from aliases.sh's required block, not exhaustive
_HI_SAMPLE_ALIASES="hi hi_update hi_status hi_install hi_colors hi_info nano vim"
_HI_SAMPLE_VARS="EDITOR EZA_CONFIG_DIR _HI_BAT_OPTS _HI_HUMAN_CENTRIC_DATE"

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

  if ! command -v "$shell" >/dev/null 2>&1; then
    cecho "  $shell -- not installed, skipped" "$YELLOW"
    return 0
  fi

  _hi_test_script "$shell" >"$script"
  output=$("$shell" "$script" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    cecho "  $shell -- aliases.sh loaded OK" "$GREEN"
  else
    cecho "  $shell -- FAILED" "$RED"
    [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
  fi
  return "$exit_code"
}

cecho "~~~~~ testing aliases.sh across shells ~~~~~" "$BRGREEN"
_HI_WORKDIR=$(mktemp -d)
trap 'rm -rfv "$_HI_WORKDIR"' EXIT

_HI_FAILED=0
for _hi_shell in dash bash zsh fish; do
  _hi_test_shell "$_hi_shell" "$_HI_WORKDIR" || _HI_FAILED=1
done

if [ "$_HI_FAILED" -eq 0 ]; then
  cecho "~~~~~ all installed shells loaded aliases.sh cleanly ~~~~~" "$BRGREEN"
else
  cecho "~~~~~ one or more shells FAILED to load aliases.sh ~~~~~" "$BRRED"
fi
exit "$_HI_FAILED"
