#!/bin/ksh
# shellcheck shell=ksh
# The git segment for the bash-less ksh/mksh tier, and the only part of hi's
# prompt that has to be recomputed on every line.
# GLOSSARY: ksh git segment - why a second implementation, and only this tier

# Colors and glyphs copied, not shared - core.sh is bash; hi_test asserts
# they agree, so a palette change fails there rather than drifting here.
_HI_KSH_NC='\033[0m'
_HI_KSH_RED='\033[0;31m'
_HI_KSH_YELLOW='\033[0;33m'
_HI_KSH_BRGREEN='\033[1;32m'
_HI_KSH_BRBLUE='\033[1;34m'
_HI_KSH_BRPURPLE='\033[1;35m'

# the client's $NO_COLOR, shipped by hi.sh next to $_HI_ASCII: non-empty
# blanks the palette here exactly as core.sh blanks its own
if [ -n "${NO_COLOR:-}" ]; then
  _HI_KSH_NC='' _HI_KSH_RED='' _HI_KSH_YELLOW='' _HI_KSH_BRGREEN='' \
    _HI_KSH_BRBLUE='' _HI_KSH_BRPURPLE=''
fi

# _HI_ASCII is the client's verdict, shipped by the preamble - the same flag
# _hi_choose_glyphs reads, so both tiers agree about multibyte glyphs.
if [ "${_HI_ASCII:-0}" = 1 ]; then
  _HI_KSH_AHEAD='^' _HI_KSH_BEHIND='v' _HI_KSH_STAGED='*'
  _HI_KSH_DIRTY='+' _HI_KSH_INVALID='x' _HI_KSH_UNTRACKED='?'
  _HI_KSH_STASH='$' _HI_KSH_CLEAN='ok' _HI_KSH_ELLIPSIS='..'
else
  _HI_KSH_AHEAD='↑' _HI_KSH_BEHIND='↓' _HI_KSH_STAGED='●'
  _HI_KSH_DIRTY='✚' _HI_KSH_INVALID='✖' _HI_KSH_UNTRACKED='…'
  _HI_KSH_STASH='⚑' _HI_KSH_CLEAN='✔' _HI_KSH_ELLIPSIS='…'
fi

# _hi_ksh_git - the segment, to stdout, empty outside a repo. Two git calls
# per prompt and no more (git_prompt.sh's budget); --no-optional-locks, or a
# plain `git status` rewrites .git/index per keystroke for identical output.
_hi_ksh_git() {
  [ "${_HI_DISABLE_GIT_STATUS:-0}" = 1 ] && return 0

  _hi_kg_dir=$(LC_ALL=C git --no-optional-locks rev-parse --git-dir 2>/dev/null) || return 0

  _hi_kg_ref="" _hi_kg_oid=""
  _hi_kg_ahead=0 _hi_kg_behind=0 _hi_kg_staged=0 _hi_kg_dirty=0
  _hi_kg_invalid=0 _hi_kg_untracked=0 _hi_kg_detached=0

  # porcelain=v2 is a stable, parseable contract; the fields read here are the
  # same ones git_prompt.sh reads, in the same order
  while IFS= read -r _hi_kg_line; do
    case "$_hi_kg_line" in
    "# branch.oid "*) _hi_kg_oid="${_hi_kg_line#\# branch.oid }" ;;
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
    # "1 XY ..." - X staged, Y worktree, "." unchanged; substring removal
    # because ${line:2:1} is not POSIX
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
$(LC_ALL=C git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
EOF

  # detached: name the nearest tag, else the short sha in parentheses, which is
  # the ladder git_prompt.sh walks
  if [ -z "$_hi_kg_ref" ]; then
    _hi_kg_detached=1
    _hi_kg_ref=$(LC_ALL=C git describe --tags --contains HEAD 2>/dev/null) ||
      _hi_kg_ref=$(LC_ALL=C git describe --tags HEAD 2>/dev/null) || _hi_kg_ref=""
    # branch.oid already rode the porcelain stream - not a third git fork; the
    # rev-parse answers only for a stream too old to carry the header
    [ -z "$_hi_kg_ref" ] && [ -n "$_hi_kg_oid" ] && [ "$_hi_kg_oid" != "(initial)" ] &&
      _hi_kg_ref="($(printf '%.8s' "$_hi_kg_oid"))"
    [ -z "$_hi_kg_ref" ] &&
      _hi_kg_ref="($(LC_ALL=C git rev-parse --short=8 HEAD 2>/dev/null))"
  fi
  [ -n "$_hi_kg_ref" ] || return 0

  # in-progress operation, in fish_vcs_prompt's slot; file tests only - no
  # step/total, which costs two more reads for a line already saying "look"
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

  # one line per stash push/apply, the count `rev-list --walk-reflogs` gives -
  # counted with the read builtin (the shape git_prompt.sh's _hi_read_lines
  # gives the bash tier), not a wc|tr pipeline of two execs per prompt
  _hi_kg_stash=0
  if [ -f "$_hi_kg_dir/logs/refs/stash" ]; then
    while IFS= read -r _hi_kg_line || [ -n "$_hi_kg_line" ]; do
      _hi_kg_stash=$((_hi_kg_stash + 1))
    done <"$_hi_kg_dir/logs/refs/stash"
  fi

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
