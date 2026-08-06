#!/bin/bash
# shared bash/zsh git-status prompt segment, styled to match the fish prompt's
# fish_vcs_prompt output (see shells/config.fish's __fish_git_prompt_* settings)
# requires colors.sh to already be sourced (NC, RED, YELLOW, BRGREEN, BRBLUE, BRPURPLE)
# set -eou pipefail # fails when enabled

_hi_git_prompt() {
  # NB: LANG=C is a command-prefix assignment (not a variable holding "git"),
  # so this expands safely under both bash and zsh's differing word-splitting rules
  LANG=C git rev-parse --is-inside-work-tree &>/dev/null || return

  local git_dir
  git_dir=$(LANG=C git rev-parse --git-dir 2>/dev/null)

  local ref detached=0
  ref=$(LANG=C git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -z "$ref" ]]; then
    detached=1
    ref=$(LANG=C git describe --tags --contains HEAD 2>/dev/null)
    [[ -z "$ref" ]] && ref=$(LANG=C git describe --tags HEAD 2>/dev/null)
    [[ -z "$ref" ]] && ref="($(LANG=C git rev-parse --short=8 HEAD 2>/dev/null))"
  fi
  [[ -n "$ref" ]] || return

  # in-progress operation (rebase/merge/cherry-pick/revert/bisect), mirroring
  # the labels fish_vcs_prompt shows in the same slot
  local state=""
  if [[ -d "$git_dir/rebase-merge" ]]; then
    local step total
    step=$(cat "$git_dir/rebase-merge/msgnum" 2>/dev/null)
    total=$(cat "$git_dir/rebase-merge/end" 2>/dev/null)
    if [[ -f "$git_dir/rebase-merge/interactive" ]]; then
      state="REBASE-i $step/$total"
    else
      state="REBASE-m $step/$total"
    fi
    [[ -f "$git_dir/rebase-merge/head-name" ]] && ref=$(sed 's#^refs/heads/##' "$git_dir/rebase-merge/head-name") && detached=0
  elif [[ -d "$git_dir/rebase-apply" ]]; then
    local step total
    step=$(cat "$git_dir/rebase-apply/next" 2>/dev/null)
    total=$(cat "$git_dir/rebase-apply/last" 2>/dev/null)
    if [[ -f "$git_dir/rebase-apply/rebasing" ]]; then
      state="REBASE $step/$total"
    elif [[ -f "$git_dir/rebase-apply/applying" ]]; then
      state="AM $step/$total"
    else
      state="AM/REBASE $step/$total"
    fi
    [[ -f "$git_dir/rebase-apply/head-name" ]] && ref=$(sed 's#^refs/heads/##' "$git_dir/rebase-apply/head-name") && detached=0
  elif [[ -f "$git_dir/MERGE_HEAD" ]]; then
    state="MERGING"
  elif [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
    state="CHERRY-PICKING"
  elif [[ -f "$git_dir/REVERT_HEAD" ]]; then
    state="REVERTING"
  elif [[ -f "$git_dir/BISECT_LOG" ]]; then
    state="BISECTING"
  fi

  # shorten_branch_len 32, matching config.fish
  if ((${#ref} > 32)); then
    ref="${ref:0:31}…"
  fi

  # ahead/behind vs upstream; "informative" style shows nothing when equal or unset
  local upstream="" ahead behind
  ahead=$(LANG=C git rev-list --count '@{upstream}..HEAD' 2>/dev/null)
  behind=$(LANG=C git rev-list --count 'HEAD..@{upstream}' 2>/dev/null)
  if [[ -n "$ahead" && -n "$behind" ]]; then
    ((ahead > 0)) && upstream+="↑${ahead}"
    ((behind > 0)) && upstream+="↓${behind}"
  fi

  # dirty/staged/conflicted/untracked counts
  local staged=0 dirty=0 invalid=0 untracked=0
  local line x y
  while IFS=$' ' read -r line; do
    [[ -z "$line" ]] && continue
    x=${line:0:1}
    y=${line:1:1}
    if [[ "$x" == "U" || "$y" == "U" || "$x$y" == "AA" || "$x$y" == "DD" ]]; then
      ((invalid++))
    elif [[ "$x" == "?" && "$y" == "?" ]]; then
      ((untracked++))
    else
      [[ "$x" != " " ]] && ((staged++))
      [[ "$y" != " " ]] && ((dirty++))
    fi
  done < <(LANG=C git status --porcelain=v1 2>/dev/null)

  local stash
  stash=$(LANG=C git rev-list --walk-reflogs --count refs/stash 2>/dev/null)
  stash=${stash:-0}

  local flags=""
  ((staged > 0)) && flags+="${YELLOW}●${staged}${NC}"
  ((dirty > 0)) && flags+="${RED}✚${dirty}${NC}"
  ((invalid > 0)) && flags+="${RED}✖${invalid}${NC}"
  ((untracked > 0)) && flags+="${BRBLUE}…${untracked}${NC}"
  ((stash > 0)) && flags+="${BRBLUE}⚑${stash}${NC}"
  [[ -z "$flags" ]] && flags="${BRGREEN}✔${NC}"

  local branch_color="$BRPURPLE"
  ((detached)) && branch_color="$RED"

  local out="(${branch_color}${ref}${NC}"
  [[ -n "$state" ]] && out+="|${state}"
  [[ -n "$upstream" ]] && out+="|${upstream}"
  out+="|${flags})"

  printf ' %b' "$out"
}
