#!/bin/bash
# Shared bash/zsh git status prompt segment, styled to match what fish's
# built-in fish_vcs_prompt produces (see the __fish_git_prompt_* settings in
# shells/config.fish). Requires colors.sh to already be sourced.
# set -eou pipefail # cannot be enabled (this file is part of the interactive shell - any error would close the session)

# NB: LANG=C below is a command-prefix assignment (not a variable holding
# "git"), so it expands safely under both bash's and zsh's word-splitting rules
_hi_git_prompt() {
  LANG=C git rev-parse --is-inside-work-tree &>/dev/null || return

  local git_dir ref detached=0
  git_dir=$(LANG=C git rev-parse --git-dir 2>/dev/null)

  ref=$(LANG=C git symbolic-ref --short HEAD 2>/dev/null)
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

  # ahead/behind vs upstream; "informative" style shows nothing when equal/unset
  local upstream="" ahead behind
  ahead=$(LANG=C git rev-list --count '@{upstream}..HEAD' 2>/dev/null)
  behind=$(LANG=C git rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
  ((${ahead:-0} > 0)) && upstream+="↑${ahead}"
  ((${behind:-0} > 0)) && upstream+="↓${behind}"

  # staged/dirty/conflicted/untracked counts, from the two porcelain columns
  # (IFS= matters: leading spaces are significant here)
  local staged=0 dirty=0 invalid=0 untracked=0 line x y
  while IFS= read -r line; do
    x=${line:0:1}
    y=${line:1:1}
    if [[ "$x" == "U" || "$y" == "U" || "$x$y" == "AA" || "$x$y" == "DD" ]]; then
      ((invalid++))
    elif [[ "$x$y" == "??" ]]; then
      ((untracked++))
    else
      [[ "$x" != " " ]] && ((staged++))
      [[ "$y" != " " ]] && ((dirty++))
    fi
  done < <(LANG=C git status --porcelain=v1 2>/dev/null)

  local stash
  stash=$(LANG=C git rev-list --walk-reflogs --count refs/stash 2>/dev/null)

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
