#!/bin/bash
# Runs shellcheck over every *.sh file in the repo (zsh/fish configs are
# skipped - shellcheck doesn't support their syntax) and reports the total.
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

if ! command -v shellcheck >/dev/null 2>&1; then
  _hi_cecho "shellcheck is not installed" "$RED"
  exit 1
fi


mapfile -t _HI_SH_FILES < <(find "$_HI_ROOT" -name '*.sh' -not -path '*/.git/*' | sort)

_hi_h1 "Running shellcheck on ${#_HI_SH_FILES[@]} files"
_hi_h2 "Version: $(shellcheck --version | awk '/^version:/ {print $2}')"

_hi_cecho "$(printf ' | %s\n' "${_HI_SH_FILES[@]}")" "$BLUE"

_HI_SC_LOG="$(mktemp -t hi.shellcheck.XXXXXX)"
# shellcheck disable=SC2064 # $_HI_SC_LOG is resolved now, not when the trap fires
_hi_on_exit "rm -f '$_HI_SC_LOG'"

_HI_T0="$(_hi_now)"
# common/shared.sh (sourced via bootstrap.sh above) turns pipefail back off
# once it's done loading (deliberately - it's also sourced by interactive
# shells, which must never die from a stray error), so `$?` after a pipe
# can't be trusted here; PIPESTATUS isn't affected by that and always
# reflects shellcheck's own exit code, letting the colorized stream still
# land live via tee while the per-file failure count below is pulled from
# the same run
shellcheck -x -Calways -S style "${_HI_SH_FILES[@]}" | tee "$_HI_SC_LOG"
_HI_SC_EXIT="${PIPESTATUS[0]}"
if [ "$_HI_SC_EXIT" -eq 0 ]; then
  _hi_h1 "Found no issues (${#_HI_SH_FILES[@]} files, $(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)"
else
  # -Calways leaves ANSI codes in $_HI_SC_LOG (needed for the live colorized
  # stream above), so they have to be stripped before "^In " can match
  _HI_SC_FAILED=$(sed 's/\x1b\[[0-9;]*m//g' "$_HI_SC_LOG" | grep -oE '^In .* line [0-9]+:' | sed -E 's/^In (.*) line [0-9]+:/\1/' | sort -u | wc -l)
  _hi_h1 "Found issues: $_HI_SC_FAILED/${#_HI_SH_FILES[@]} files ($(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$RED"
  exit "$_HI_SC_FAILED"
fi
