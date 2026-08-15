#!/bin/bash
# Shared bash/zsh git status prompt segment, styled to match what fish's
# built-in fish_vcs_prompt produces (see the __fish_git_prompt_* settings in
# shells/config.fish). Requires colors.sh to already be sourced.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

_hi_git_prompt() {
  [[ "${_HI_DISABLE_GIT_STATUS:-0}" == 1 ]] && return

  # --no-optional-locks on both git calls: without it `git status` refreshes and
  # *rewrites* .git/index every prompt - real I/O and lock contention per
  # keystroke-to-prompt cycle, tens to hundreds of ms on a large checkout. The
  # output is identical. rev-parse exits non-zero outside a repo without
  # --is-inside-work-tree too, whose answer was read and discarded.
  local git_dir ref="" detached=0
  git_dir=$(LANG=C git --no-optional-locks rev-parse --git-dir 2>/dev/null) || return

  local ahead=0 behind=0 staged=0 dirty=0 invalid=0 untracked=0 line
  while IFS= read -r line; do
    case "$line" in
    "# branch.head "*)
      ref="${line#"# branch.head "}"
      [[ "$ref" == "(detached)" || "$ref" == "(unknown)" ]] && ref=""
      ;;
    "# branch.ab "*)
      local ab="${line#"# branch.ab "}" # "+<ahead> -<behind>"
      ahead="${ab%% *}" ahead="${ahead#+}"
      behind="${ab##* }" behind="${behind#-}"
      ;;
    "1 "* | "2 "*)
      [[ "${line:2:1}" != "." ]] && ((staged++))
      [[ "${line:3:1}" != "." ]] && ((dirty++))
      ;;
    "u "*) ((invalid++)) ;;
    "? "*) ((untracked++)) ;;
    esac
  done < <(LANG=C git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)

  if [[ -z "$ref" ]]; then
    detached=1
    ref=$(LANG=C git describe --tags --contains HEAD 2>/dev/null)
    [[ -z "$ref" ]] && ref=$(LANG=C git describe --tags HEAD 2>/dev/null)
    [[ -z "$ref" ]] && ref="($(LANG=C git rev-parse --short=8 HEAD 2>/dev/null))"
  fi
  [[ -n "$ref" ]] || return

  # in-progress operation (rebase/merge/cherry-pick/revert/bisect), using the
  # same labels fish_vcs_prompt shows in the same slot
  local state="" dir="" step total
  if [[ -d "$git_dir/rebase-merge" ]]; then
    dir="$git_dir/rebase-merge"
    read -r step <"$dir/msgnum" && read -r total <"$dir/end"
    [[ -f "$dir/interactive" ]] && state="REBASE-i" || state="REBASE-m"
  elif [[ -d "$git_dir/rebase-apply" ]]; then
    dir="$git_dir/rebase-apply"
    read -r step <"$dir/next" && read -r total <"$dir/last"
    if [[ -f "$dir/rebasing" ]]; then
      state="REBASE"
    elif [[ -f "$dir/applying" ]]; then
      state="AM"
    else
      state="AM/REBASE"
    fi
  elif [[ -f "$git_dir/MERGE_HEAD" ]]; then
    state="MERGING"
  elif [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
    state="CHERRY-PICKING"
  elif [[ -f "$git_dir/REVERT_HEAD" ]]; then
    state="REVERTING"
  elif [[ -f "$git_dir/BISECT_LOG" ]]; then
    state="BISECTING"
  fi
  if [[ -n "$dir" ]]; then
    state+=" ${step:-?}/${total:-?}"
    # a rebase knows the branch it started from, so show that instead of HEAD
    [[ -f "$dir/head-name" ]] && ref=$(sed 's#^refs/heads/##' "$dir/head-name") && detached=0
  fi

  # shorten_branch_len 32, matching config.fish
  ((${#ref} > 32)) && ref="${ref:0:31}…"

  local upstream=""
  ((ahead > 0)) && upstream+="↑${ahead}"
  ((behind > 0)) && upstream+="↓${behind}"

  # one line per stash push/apply, same count `rev-list --walk-reflogs` gives
  local stash=0 stash_line
  if [[ -f "$git_dir/logs/refs/stash" ]]; then
    while IFS= read -r stash_line || [[ -n "$stash_line" ]]; do
      ((stash++))
    done <"$git_dir/logs/refs/stash"
  fi

  local flags=""
  ((staged > 0)) && flags+="${YELLOW}●${staged}${NC}"
  ((dirty > 0)) && flags+="${RED}✚${dirty}${NC}"
  ((invalid > 0)) && flags+="${RED}✖${invalid}${NC}"
  ((untracked > 0)) && flags+="${BRBLUE}…${untracked}${NC}"
  ((${stash:-0} > 0)) && flags+="${BRBLUE}⚑${stash}${NC}"
  [[ -z "$flags" ]] && flags="${BRGREEN}✔${NC}"

  local branch_color="$BRPURPLE"
  ((detached)) && branch_color="$RED"

  local out="(${branch_color}${ref}${NC}"
  [[ -n "$state" ]] && out+="|${state}"
  [[ -n "$upstream" ]] && out+="|${upstream}"
  printf ' %b' "$out|${flags})"
}

set +euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)
