#!/bin/ksh
# shellcheck shell=ksh
# The git segment for the bash-less ksh/mksh tier, and the only part of hi's
# prompt that has to be recomputed on every line.
#
# Why this file exists at all. Where bash is present, common/git_prompt.sh does
# this job and shells/config.fish reaches it by shelling out to `bash -c`. This
# tier is defined by bash being absent, so neither is available: the segment has
# to be written again, in POSIX shell, or ksh users get the static user@host
# prompt hi.sh's _hi_fallback_prompt bakes in and nothing else.
#
# Why only ksh and mksh get it. The segment is live - `$(...)` inside PS1,
# stored single-quoted so it is expanded when the prompt is *printed* rather
# than when it is assigned. ksh93 and mksh both do that expansion. busybox ash
# does not do command substitution in PS1 at all, which is exactly why
# _hi_fallback_prompt bakes everything in and leaves one escape behind, so the
# sh/dash/ash tier keeps that prompt untouched.
#
# What this deliberately does NOT do is the header. That needs common/header.sh,
# which needs bash - see the compatibility tables in the README, where the ksh
# row says so.

# Colors and glyphs, copied rather than shared: common/core.sh defines both, and
# it is bash. tests/shells/hi_test.sh asserts these agree with core.sh's, so a
# palette change there fails there rather than silently drifting here.
_HI_KSH_NC='\033[0m'
_HI_KSH_RED='\033[0;31m'
_HI_KSH_YELLOW='\033[0;33m'
_HI_KSH_BRGREEN='\033[1;32m'
_HI_KSH_BRBLUE='\033[1;34m'
_HI_KSH_BRPURPLE='\033[1;35m'

# _HI_ASCII is the client's verdict about the terminal, shipped by hi.sh's
# _hi_remote_preamble - the same flag core.sh's _hi_choose_glyphs reads, so both
# tiers agree about whether this session can draw multibyte glyphs.
if [ "${_HI_ASCII:-0}" = 1 ]; then
  _HI_KSH_AHEAD='^' _HI_KSH_BEHIND='v' _HI_KSH_STAGED='*'
  _HI_KSH_DIRTY='+' _HI_KSH_INVALID='x' _HI_KSH_UNTRACKED='?'
  _HI_KSH_STASH='$' _HI_KSH_CLEAN='ok' _HI_KSH_ELLIPSIS='..'
else
  _HI_KSH_AHEAD='↑' _HI_KSH_BEHIND='↓' _HI_KSH_STAGED='●'
  _HI_KSH_DIRTY='✚' _HI_KSH_INVALID='✖' _HI_KSH_UNTRACKED='…'
  _HI_KSH_STASH='⚑' _HI_KSH_CLEAN='✔' _HI_KSH_ELLIPSIS='…'
fi

# _hi_ksh_git - the segment, printed to stdout, empty outside a repo.
#
# Two git calls per prompt and no more, the same budget common/git_prompt.sh
# keeps: --no-optional-locks because a plain `git status` rewrites .git/index
# every time it runs, which on a large checkout is real I/O per keystroke for
# identical output.
_hi_ksh_git() {
  [ "${_HI_DISABLE_GIT_STATUS:-0}" = 1 ] && return 0

  _hi_kg_dir=$(LANG=C git --no-optional-locks rev-parse --git-dir 2>/dev/null) || return 0

  _hi_kg_ref=""
  _hi_kg_ahead=0 _hi_kg_behind=0 _hi_kg_staged=0 _hi_kg_dirty=0
  _hi_kg_invalid=0 _hi_kg_untracked=0 _hi_kg_detached=0

  # porcelain=v2 is a stable, parseable contract; the fields read here are the
  # same ones git_prompt.sh reads, in the same order
  while IFS= read -r _hi_kg_line; do
    case "$_hi_kg_line" in
    "# branch.head "*)
      _hi_kg_ref="${_hi_kg_line#\# branch.head }"
      case "$_hi_kg_ref" in
      "(detached)" | "(unknown)") _hi_kg_ref="" ;;
      esac
      ;;
    "# branch.ab "*)
      _hi_kg_ab="${_hi_kg_line#\# branch.ab }" # "+<ahead> -<behind>"
      _hi_kg_ahead="${_hi_kg_ab%% *}"
      _hi_kg_ahead="${_hi_kg_ahead#+}"
      _hi_kg_behind="${_hi_kg_ab##* }"
      _hi_kg_behind="${_hi_kg_behind#-}"
      ;;
    # "1 XY ..." / "2 XY ..." - X is the staged column, Y the worktree one,
    # "." meaning unchanged. Cut with substring removal rather than ${line:2:1},
    # which is not POSIX.
    "1 "* | "2 "*)
      _hi_kg_xy="${_hi_kg_line#? }"
      case "$_hi_kg_xy" in
      .*) ;;
      *) _hi_kg_staged=$((_hi_kg_staged + 1)) ;;
      esac
      case "${_hi_kg_xy#?}" in
      .*) ;;
      *) _hi_kg_dirty=$((_hi_kg_dirty + 1)) ;;
      esac
      ;;
    "u "*) _hi_kg_invalid=$((_hi_kg_invalid + 1)) ;;
    "? "*) _hi_kg_untracked=$((_hi_kg_untracked + 1)) ;;
    esac
  done <<EOF
$(LANG=C git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
EOF

  # detached: name the nearest tag, else the short sha in parentheses, which is
  # the ladder git_prompt.sh walks
  if [ -z "$_hi_kg_ref" ]; then
    _hi_kg_detached=1
    _hi_kg_ref=$(LANG=C git describe --tags --contains HEAD 2>/dev/null) ||
      _hi_kg_ref=$(LANG=C git describe --tags HEAD 2>/dev/null) ||
      _hi_kg_ref="($(LANG=C git rev-parse --short=8 HEAD 2>/dev/null))"
  fi
  [ -n "$_hi_kg_ref" ] || return 0

  # in-progress operation, in the slot fish_vcs_prompt uses. File tests only -
  # no step/total, which would cost two more reads per prompt for a line that
  # is already telling you to look.
  _hi_kg_state=""
  if [ -d "$_hi_kg_dir/rebase-merge" ] || [ -d "$_hi_kg_dir/rebase-apply" ]; then
    _hi_kg_state="REBASE"
  elif [ -f "$_hi_kg_dir/MERGE_HEAD" ]; then
    _hi_kg_state="MERGING"
  elif [ -f "$_hi_kg_dir/CHERRY_PICK_HEAD" ]; then
    _hi_kg_state="CHERRY-PICKING"
  elif [ -f "$_hi_kg_dir/REVERT_HEAD" ]; then
    _hi_kg_state="REVERTING"
  elif [ -f "$_hi_kg_dir/BISECT_LOG" ]; then
    _hi_kg_state="BISECTING"
  fi

  # shorten_branch_len 32, matching config.fish and git_prompt.sh
  if [ "${#_hi_kg_ref}" -gt 32 ]; then
    _hi_kg_cut=$(printf '%.31s' "$_hi_kg_ref")
    _hi_kg_ref="$_hi_kg_cut$_HI_KSH_ELLIPSIS"
  fi

  _hi_kg_up=""
  [ "$_hi_kg_ahead" -gt 0 ] 2>/dev/null && _hi_kg_up="$_hi_kg_up$_HI_KSH_AHEAD$_hi_kg_ahead"
  [ "$_hi_kg_behind" -gt 0 ] 2>/dev/null && _hi_kg_up="$_hi_kg_up$_HI_KSH_BEHIND$_hi_kg_behind"

  # one line per stash push/apply, the count `rev-list --walk-reflogs` gives
  _hi_kg_stash=0
  [ -f "$_hi_kg_dir/logs/refs/stash" ] &&
    _hi_kg_stash=$(wc -l <"$_hi_kg_dir/logs/refs/stash" 2>/dev/null | tr -d ' ')

  _hi_kg_flags=""
  [ "$_hi_kg_staged" -gt 0 ] &&
    _hi_kg_flags="$_hi_kg_flags$_HI_KSH_YELLOW$_HI_KSH_STAGED$_hi_kg_staged$_HI_KSH_NC"
  [ "$_hi_kg_dirty" -gt 0 ] &&
    _hi_kg_flags="$_hi_kg_flags$_HI_KSH_RED$_HI_KSH_DIRTY$_hi_kg_dirty$_HI_KSH_NC"
  [ "$_hi_kg_invalid" -gt 0 ] &&
    _hi_kg_flags="$_hi_kg_flags$_HI_KSH_RED$_HI_KSH_INVALID$_hi_kg_invalid$_HI_KSH_NC"
  [ "$_hi_kg_untracked" -gt 0 ] &&
    _hi_kg_flags="$_hi_kg_flags$_HI_KSH_BRBLUE$_HI_KSH_UNTRACKED$_hi_kg_untracked$_HI_KSH_NC"
  [ "${_hi_kg_stash:-0}" -gt 0 ] 2>/dev/null &&
    _hi_kg_flags="$_hi_kg_flags$_HI_KSH_BRBLUE$_HI_KSH_STASH$_hi_kg_stash$_HI_KSH_NC"
  [ -n "$_hi_kg_flags" ] ||
    _hi_kg_flags="$_HI_KSH_BRGREEN$_HI_KSH_CLEAN$_HI_KSH_NC"

  _hi_kg_color="$_HI_KSH_BRPURPLE"
  [ "$_hi_kg_detached" = 1 ] && _hi_kg_color="$_HI_KSH_RED"

  _hi_kg_out="($_hi_kg_color$_hi_kg_ref$_HI_KSH_NC"
  [ -n "$_hi_kg_state" ] && _hi_kg_out="$_hi_kg_out|$_hi_kg_state"
  [ -n "$_hi_kg_up" ] && _hi_kg_out="$_hi_kg_out|$_hi_kg_up"

  # %b so the \033 escapes above become real ones, matching git_prompt.sh's
  # `printf ' %b'`
  printf ' %b' "$_hi_kg_out|$_hi_kg_flags)"
}
