#!/bin/bash
# Sources shells/aliases.sh in a real instance of each target shell and
# checks that a representative sample of its "required" aliases/vars
# (aliases.sh's start/end required markers) actually landed - not just that
# the file was found. Skips any shell that isn't installed.
set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/bootstrap.sh
source "$_HI_TMPDIR/hi.d/common/bootstrap.sh"

# a sample from aliases.sh's required block (aliases.sh:5-41), not exhaustive
_HI_SAMPLE_ALIASES="hi hi_update hi_status hi_install hi_colors hi_info nano vim"
_HI_SAMPLE_VARS="EDITOR _HI_BAT_OPTS _HI_HUMAN_CENTRIC_DATE"

# shellcheck disable=SC2016
# posix `alias name`/`test -n "${v+x}"` works unmodified in dash/bash/zsh
function _hi_write_posix_test() {
  local out="$1"
  {
    printf '%s\n' '#!/bin/sh' ". \"\$_HI_ALIASES\" || exit 1" "fail=0"
    printf 'for a in %s; do\n' "$_HI_SAMPLE_ALIASES"
    printf '  alias "$a" >/dev/null 2>&1 || { echo "missing alias: $a" >&2; fail=1; }\n'
    printf 'done\n'
    printf 'for v in %s; do\n' "$_HI_SAMPLE_VARS"
    # shellcheck disable=SC2016
    printf '  eval '"'"'test -n "${'"'"'"$v"'"'"'+x}"'"'"' || { echo "missing var: $v" >&2; fail=1; }\n'
    printf 'done\n'
    printf 'exit $fail\n'
  } >"$out"
}

# shellcheck disable=SC2016
# fish has no posix `alias`/`test -n "${v+x}"`; aliases become functions, and
# `set -q` is fish's "is this variable set" check
function _hi_write_fish_test() {
  local out="$1"
  {
    printf '%s\n' '#!/usr/bin/env fish' 'source "$_HI_ALIASES"; or exit 1' 'set fail 0'
    printf 'for a in %s\n' "$_HI_SAMPLE_ALIASES"
    printf '  functions -q -- $a; or begin; echo "missing alias: $a" 1>&2; set fail 1; end\n'
    printf 'end\n'
    printf 'for v in %s\n' "$_HI_SAMPLE_VARS"
    printf '  set -q $v; or begin; echo "missing var: $v" 1>&2; set fail 1; end\n'
    printf 'end\n'
    printf 'exit $fail\n'
  } >"$out"
}

function _hi_test_shell() {
  local shell="$1" tmpdir="$2" script output exit_code=0

  if ! command -v "$shell" >/dev/null 2>&1; then
    cecho "  $shell" "$YELLOW" 1
    cecho " -- not installed, skipped" "$YELLOW"
    return 0
  fi

  script="$tmpdir/$shell.test"
  if [ "$shell" = fish ]; then
    _hi_write_fish_test "$script"
  else
    _hi_write_posix_test "$script"
  fi

  output=$("$shell" "$script" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    cecho "  $shell" "$GREEN" 1
    cecho " -- aliases.sh loaded OK" "$GREEN"
  else
    cecho "  $shell" "$RED" 1
    cecho " -- FAILED" "$RED"
    [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /'
  fi
  return "$exit_code"
}

function main() {
  cecho "~~~~~ testing aliases.sh across shells ~~~~~" "$BRGREEN"

  local tmpdir overall=0
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' exit

  local shell
  for shell in dash bash zsh fish; do
    _hi_test_shell "$shell" "$tmpdir" || overall=1
  done

  if [ "$overall" -eq 0 ]; then
    cecho "~~~~~ all installed shells loaded aliases.sh cleanly ~~~~~" "$BRGREEN"
  else
    cecho "~~~~~ one or more shells FAILED to load aliases.sh ~~~~~" "$BRRED"
  fi
  exit "$overall"
}

main
