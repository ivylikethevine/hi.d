#!/bin/bash
# Unit tests for common/git_prompt.sh's _hi_git_prompt: the no-repo/disabled
# early-outs, the porcelain=v2 status-flag counting (staged/dirty/untracked/
# unmerged), ahead/behind arrows against an upstream, detached HEAD (short
# sha + red branch color), the 32-char branch name truncation, every
# in-progress operation state (REBASE via the apply backend, REBASE-i via the
# sequencer, MERGING, CHERRY-PICKING, REVERTING, BISECTING - including that a
# rebase shows the branch it started from, not a raw sha), and the stash
# flag count. Every conflict scenario below replaces the same single line
# with different content on two diverging histories, which reliably
# conflicts regardless of git's merge heuristics (a content append often
# doesn't). Runs against real throwaway git repos under a scratch dir -
# nothing outside that dir is ever touched.
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../../common/git_prompt.sh
source "$_HI_GIT_PROMPT"

command -v git >/dev/null 2>&1 || { _hi_cecho "git not installed, skipping" "$YELLOW"; exit 0; }

_HI_WORKDIR="$(mktemp -d -t hi.gitprompttest.XXXXXX)"
# shellcheck disable=SC2016 # $_HI_WORKDIR is resolved when the trap fires
_hi_on_exit 'rm -rf "$_HI_WORKDIR"'

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function _hi_assert() {
  local label="$1"
  shift
  if "$@"; then
    _hi_cecho " | $label: OK" "$GREEN"
  else
    _hi_cecho " | $label: FAILED" "$RED"
    return 1
  fi
}

# fresh repo, one commit, always on a branch literally named "main" -
# forced via symbolic-ref before the first commit, so this doesn't depend on
# git version/config defaults for the initial branch name
# shellcheck disable=SC2329 # invoked from the test_* functions below
function _hi_git_new_repo() {
  local dir
  dir="$(mktemp -d "$_HI_WORKDIR/repo.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Test"
  printf 'one\n' >"$dir/file.txt"
  git -C "$dir" add file.txt
  git -C "$dir" commit -q -m initial
  printf '%s' "$dir"
}

# ---- no repo / disabled -----------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_outside_a_repo_produces_no_output() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/plain.XXXXXX")"
  out="$(cd "$dir" && _hi_git_prompt)"
  [ -z "$out" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_disabled_flag_produces_no_output() {
  local dir out
  dir="$(_hi_git_new_repo)"
  out="$(cd "$dir" && _HI_DISABLE_GIT_STATUS=1 _hi_git_prompt)"
  [ -z "$out" ]
}

# ---- clean status -------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_clean_repo_shows_branch_and_checkmark() {
  local dir out expected
  dir="$(_hi_git_new_repo)"
  out="$(cd "$dir" && _hi_git_prompt)"
  printf -v expected '%b' "${BRGREEN}✔${NC}"
  [[ "$out" == *"main"* && "$out" == *"$expected"* ]]
}

# ---- working tree flags -------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_staged_change_shows_bullet_count() {
  local dir out expected
  dir="$(_hi_git_new_repo)"
  printf 'two\n' >"$dir/staged.txt"
  git -C "$dir" add staged.txt
  out="$(cd "$dir" && _hi_git_prompt)"
  printf -v expected '%b' "${YELLOW}●1${NC}"
  [[ "$out" == *"$expected"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_dirty_change_shows_plus_count() {
  local dir out expected
  dir="$(_hi_git_new_repo)"
  printf 'modified\n' >"$dir/file.txt"
  out="$(cd "$dir" && _hi_git_prompt)"
  printf -v expected '%b' "${RED}✚1${NC}"
  [[ "$out" == *"$expected"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_untracked_file_shows_ellipsis_count() {
  local dir out expected
  dir="$(_hi_git_new_repo)"
  printf 'x\n' >"$dir/untracked.txt"
  out="$(cd "$dir" && _hi_git_prompt)"
  printf -v expected '%b' "${BRBLUE}…1${NC}"
  [[ "$out" == *"$expected"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_merge_conflict_shows_invalid_and_merging() {
  local dir out expected
  dir="$(_hi_git_new_repo)"
  git -C "$dir" checkout -q -b other
  printf 'other-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam other-change
  git -C "$dir" checkout -q main
  printf 'main-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam main-change
  git -C "$dir" merge -q other >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  printf -v expected '%b' "${RED}✖1${NC}"
  [[ "$out" == *"$expected"* && "$out" == *"|MERGING"* ]]
}

# ---- ahead/behind ---------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_ahead_and_behind_show_arrows() {
  local dir out
  dir="$(_hi_git_new_repo)"
  git -C "$dir" checkout -q -b feature
  git -C "$dir" branch -q --set-upstream-to=main feature
  printf 'f1\n' >>"$dir/file.txt"
  git -C "$dir" commit -qam f1
  printf 'f2\n' >>"$dir/file.txt"
  git -C "$dir" commit -qam f2
  git -C "$dir" checkout -q main
  printf 'm1\n' >>"$dir/file.txt"
  git -C "$dir" commit -qam m1
  git -C "$dir" checkout -q feature
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"↑2"* && "$out" == *"↓1"* ]]
}

# ---- detached HEAD ------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_detached_head_shows_short_sha_and_red() {
  local dir sha out expected_red
  dir="$(_hi_git_new_repo)"
  sha="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" -c advice.detachedHead=false checkout -q "$sha"
  out="$(cd "$dir" && _hi_git_prompt)"
  printf -v expected_red '%b' "$RED"
  [[ "$out" == *"${sha:0:8}"* && "$out" == *"$expected_red"* ]]
}

# ---- long branch names ----------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_long_branch_name_is_truncated() {
  local dir long_name out
  dir="$(_hi_git_new_repo)"
  long_name="$(printf 'x%.0s' {1..40})"
  git -C "$dir" checkout -q -b "$long_name"
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"${long_name:0:31}…"* ]]
}

# ---- in-progress operations -----------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_rebase_apply_backend_shows_state_and_source_branch() {
  local dir out
  dir="$(_hi_git_new_repo)"
  git -C "$dir" checkout -q -b rebase-branch
  printf 'branch-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam branch-change
  git -C "$dir" checkout -q main
  printf 'main-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam main-change
  git -C "$dir" checkout -q rebase-branch
  git -C "$dir" rebase --apply main >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"REBASE 1/1"* && "$out" == *"rebase-branch"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_rebase_interactive_shows_state() {
  local dir out
  dir="$(_hi_git_new_repo)"
  git -C "$dir" checkout -q -b interactive-branch
  printf 'branch-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam branch-change
  git -C "$dir" checkout -q main
  printf 'main-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam main-change
  git -C "$dir" checkout -q interactive-branch
  GIT_SEQUENCE_EDITOR=true git -C "$dir" rebase -i main >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"REBASE-i 1/1"* && "$out" == *"interactive-branch"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_cherry_pick_conflict_shows_state() {
  local dir out target_sha
  dir="$(_hi_git_new_repo)"
  git -C "$dir" checkout -q -b source-branch
  printf 'source-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam source-change
  target_sha="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" checkout -q main
  printf 'main-value\n' >"$dir/file.txt"
  git -C "$dir" commit -qam main-change
  git -C "$dir" cherry-pick "$target_sha" >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"|CHERRY-PICKING"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_revert_conflict_shows_state() {
  local dir out commit_a
  dir="$(_hi_git_new_repo)"
  printf 'A\n' >"$dir/file.txt"
  git -C "$dir" commit -qam commit-A
  commit_a="$(git -C "$dir" rev-parse HEAD)"
  printf 'B\n' >"$dir/file.txt"
  git -C "$dir" commit -qam commit-B
  git -C "$dir" revert --no-edit "$commit_a" >/dev/null 2>&1 || true
  out="$(cd "$dir" && _hi_git_prompt)"
  [[ "$out" == *"|REVERTING"* ]]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_bisect_shows_state() {
  local dir old_sha out
  dir="$(_hi_git_new_repo)"
  old_sha="$(git -C "$dir" rev-parse HEAD)"
  printf 'two\n' >"$dir/file.txt"
  git -C "$dir" commit -qam second
  git -C "$dir" bisect start >/dev/null 2>&1
  git -C "$dir" bisect bad >/dev/null 2>&1
  git -C "$dir" bisect good "$old_sha" >/dev/null 2>&1
  out="$(cd "$dir" && _hi_git_prompt)"
  git -C "$dir" bisect reset >/dev/null 2>&1 || true
  [[ "$out" == *"|BISECTING"* ]]
}

# ---- stash ----------------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_stash_shows_flag_count() {
  local dir out expected
  dir="$(_hi_git_new_repo)"
  printf 'stashed-change\n' >"$dir/file.txt"
  git -C "$dir" stash push -q -m teststash >/dev/null 2>&1
  out="$(cd "$dir" && _hi_git_prompt)"
  printf -v expected '%b' "${BRBLUE}⚑1${NC}"
  [[ "$out" == *"$expected"* ]]
}

function run_git_prompt_tests() {
  _hi_h1 "Testing common/git_prompt.sh"

  _HI_FAILED=0
  _HI_TOTAL=0

  _hi_h2 "no repo / disabled"
  _hi_case _hi_assert "outside a repo -> no output" test_outside_a_repo_produces_no_output
  _hi_case _hi_assert "_HI_DISABLE_GIT_STATUS=1 -> no output" test_disabled_flag_produces_no_output

  _hi_h2 "clean status"
  _hi_case _hi_assert "shows branch and checkmark" test_clean_repo_shows_branch_and_checkmark

  _hi_h2 "working tree flags"
  _hi_case _hi_assert "staged change -> bullet count" test_staged_change_shows_bullet_count
  _hi_case _hi_assert "dirty change -> plus count" test_dirty_change_shows_plus_count
  _hi_case _hi_assert "untracked file -> ellipsis count" test_untracked_file_shows_ellipsis_count
  _hi_case _hi_assert "merge conflict -> invalid count + MERGING" test_merge_conflict_shows_invalid_and_merging

  _hi_h2 "ahead/behind"
  _hi_case _hi_assert "ahead and behind arrows" test_ahead_and_behind_show_arrows

  _hi_h2 "detached HEAD"
  _hi_case _hi_assert "short sha + red branch color" test_detached_head_shows_short_sha_and_red

  _hi_h2 "long branch names"
  _hi_case _hi_assert "truncated at 31 chars + ellipsis" test_long_branch_name_is_truncated

  _hi_h2 "in-progress operations"
  _hi_case _hi_assert "rebase (apply backend) + source branch" test_rebase_apply_backend_shows_state_and_source_branch
  _hi_case _hi_assert "rebase (interactive)" test_rebase_interactive_shows_state
  _hi_case _hi_assert "cherry-pick conflict" test_cherry_pick_conflict_shows_state
  _hi_case _hi_assert "revert conflict" test_revert_conflict_shows_state
  _hi_case _hi_assert "bisect" test_bisect_shows_state

  _hi_h2 "stash"
  _hi_case _hi_assert "stash -> flag count" test_stash_shows_flag_count

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "All git_prompt.sh checks passed ($_HI_TOTAL cases)"
  else
    _hi_h1 "$_HI_FAILED/$_HI_TOTAL git_prompt.sh checks FAILED" "$RED"
  fi
  exit "$_HI_FAILED"
}

run_git_prompt_tests
