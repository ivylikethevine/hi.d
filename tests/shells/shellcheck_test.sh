#!/bin/bash
# The repo's lint gate. shellcheck covers every *.sh file; on top of that, every
# file a non-bash shell parses for itself is run through that shell's own syntax
# checker (`zsh -n` / `fish --no-execute`) - see $_HI_NATIVE_LINT below. Without
# that second half, shells/zsh.zsh and shells/config.fish are checked by nothing
# at all, and the files fish and zsh share with sh are only ever checked as sh.
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# "<file>:<shell>:<flag...>", one per file/shell pair shellcheck's own reading
# doesn't cover. Skipped with a warning when that shell isn't installed: these
# supplement the gate rather than being it, unlike the shellcheck run below,
# whose absence is a hard failure.
# (A comment line here must never *begin* with the word shellcheck - that reads
# as a directive and fails the very lint this file runs.)
#
# Two kinds of entry. shells/zsh.zsh and shells/config.fish are not shell the
# linter can parse at all, so their own shell's syntax checker (`zsh -n` /
# `fish --no-execute`, the same two scripts/install.sh runs against the user's
# rc files) is the only thing checking them.
#
# The rest are files shellcheck *does* read - as sh or bash - that another shell
# also sources for real, so they have to parse in both. shells/aliases.sh and
# common/paths.sh are the two fish sources directly, and the failure mode there
# is silent: a perfectly good `${X:-0}` is a fish parse error that aborts the
# whole file, taking every alias (or every path) with it. zsh reaches
# common/core.sh, common/git_prompt.sh and both of those through shells/zsh.zsh.
_HI_NATIVE_LINT=(
  "shells/zsh.zsh:zsh:-n"
  "shells/config.fish:fish:--no-execute"
  "shells/aliases.sh:fish:--no-execute"
  "common/paths.sh:fish:--no-execute"
  "shells/aliases.sh:zsh:-n"
  "common/paths.sh:zsh:-n"
  "common/core.sh:zsh:-n"
  "common/git_prompt.sh:zsh:-n"
)

# Syntax-check the files above, returning how many failed. Adds its files to
# $_HI_LINT_TOTAL so the suite's reported tally covers everything it checked,
# not just the shellcheck half.
function lint_native() {
  local entry file shell flag out bad=0
  for entry in "${_HI_NATIVE_LINT[@]}"; do
    file="${entry%%:*}"
    shell="${entry#*:}"
    flag="${shell#*:}"
    shell="${shell%%:*}"
    if ! command -v "$shell" >/dev/null 2>&1; then
      _hi_skip " | $file" "no $shell to check it with"
      continue
    fi
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if out="$("$shell" "$flag" "$_HI_ROOT/$file" 2>&1)"; then
      _hi_cecho " | $file ($shell $flag): OK" "$GREEN"
    else
      _hi_cecho " | $file ($shell $flag): FAILED" "$RED"
      printf '%s\n' "$out" | sed 's/^/      /'
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

function run_shellcheck() {
  # deliberately *not* _hi_require: every other suite skips cleanly when its
  # backend is missing, but this one is the lint gate - a missing shellcheck
  # means the check didn't run, which must not read as a pass.
  if ! command -v shellcheck >/dev/null 2>&1; then
    _hi_cecho "shellcheck is not installed" "$RED"
    exit 1
  fi

  mapfile -t _HI_SH_FILES < <(find "$_HI_ROOT" -name '*.sh' -not -path '*/.git/*' | sort)
  _HI_LINT_TOTAL="${#_HI_SH_FILES[@]}"
  _HI_SKIPPED=0

  _hi_h1 "Running shellcheck on ${#_HI_SH_FILES[@]} files"
  _hi_h2 "Version: $(shellcheck --version | awk '/^version:/ {print $2}')"

  _hi_cecho "$(printf ' | %s\n' "${_HI_SH_FILES[@]}")" "$BLUE"

  _hi_workdir shellchecktest
  _HI_SC_LOG="$_HI_WORKDIR/shellcheck.log"

  _HI_T0="$(_hi_now)"

  _HI_SC_FAILED=0
  shellcheck -x -Calways -S style "${_HI_SH_FILES[@]}" | tee "$_HI_SC_LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    # -Calways leaves ANSI codes in $_HI_SC_LOG (needed for the live colorized
    # stream above), so they have to be stripped before "^In " can match
    _HI_SC_FAILED=$(sed 's/\x1b\[[0-9;]*m//g' "$_HI_SC_LOG" | grep -oE '^In .* line [0-9]+:' | sed -E 's/^In (.*) line [0-9]+:/\1/' | sort -u | wc -l)
  fi

  _hi_h2 "Syntax-checking the files shellcheck can't parse"
  _HI_NATIVE_FAILED=0
  lint_native || _HI_NATIVE_FAILED=$?

  _HI_LINT_FAILED=$((_HI_SC_FAILED + _HI_NATIVE_FAILED))
  _hi_report_counts "$_HI_LINT_TOTAL" "$_HI_LINT_FAILED"

  local skipped=""
  [ "$_HI_SKIPPED" -gt 0 ] && skipped=", $_HI_SKIPPED skipped"
  if [ "$_HI_LINT_FAILED" -eq 0 ]; then
    _hi_h1 "Found no issues ($_HI_LINT_TOTAL files$skipped, $(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)"
  else
    _hi_h1 "Found issues: $_HI_LINT_FAILED/$_HI_LINT_TOTAL files$skipped ($(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$RED"
    exit "$_HI_LINT_FAILED"
  fi
}

run_shellcheck
