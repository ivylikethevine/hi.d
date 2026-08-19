#!/bin/bash
# The entry point every bash/zsh script sources: toggles, settings, paths,
# colors, shared primitives. One file - fish reaches it via bare `bash -c`.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# Sourced twice in one shell is a no-op; $_hi_core_loaded is deliberately not
# exported, so a child process (fish's `bash -c`) still runs the preamble.
if [ -z "${_hi_core_loaded:-}" ]; then
  _hi_core_loaded=1

  # `: "${X:=default}"` assigns only when X is unset, so a value an outer layer
  # already exported (hi.sh on the client, load.sh on the target) survives
  : "${_HI_HOME:=$HOME}"
  export _HI_HOME
  # GLOSSARY: toggle defaulting + dynamic-name assignment. List shared with
  # _hi_fallback_rc; config.fish keeps its own copy.
  _HI_TOGGLES=(_HI_DISABLE_LOCAL _HI_REMOTE_SESSION _HI_DISABLE_HEADER
    _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL _HI_DISABLE_GIT_STATUS
    _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES _HI_DISABLE_OSC52 _HI_DISABLE_TMUX)
  for _hi_t in "${_HI_TOGGLES[@]}"; do
    eval ": \"\${$_hi_t:=0}\"; export $_hi_t"
  done
  unset _hi_t
  # the config overlay's home - every entry point sets it (fish can't expand
  # this); `:=` lets hi.sh point a target at its shipped copy instead
  : "${_HI_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/hi.d}"
  export _HI_CONFIG_DIR
  # settings ahead of paths.sh, whose gate reads them - hence the spelled path
  # shellcheck source=/dev/null # user config, may not exist
  if [ -f "$_HI_CONFIG_DIR/settings.sh" ]; then
    . "$_HI_CONFIG_DIR/settings.sh"
  fi
  # shellcheck source=./paths.sh
  source "$_HI_HOME/hi.d/common/paths.sh"
fi

# Every shell hi wires up, one row each:
# <shell>|<rc label>|<hi's rc>|<the user's rc>|<syntax check>|<flags>.
# Flags name the mechanism: `local` is install.sh appending to the user's own
# rc, `graft` is load.sh copying hi's rc into a target's. The mechanisms stay
# separate (see install.sh's config_shell); only the roster is single-homed,
# since three copies is what let a shell go missing from one. nu is graft-only
# - config.nu needs env a hi session exports and a local nu never has.
_HI_SHELL_TABLE=(
  "bash|bashrc|$_HI_BASHRC|$_HI_HOME_BASHRC|bash -n|local,graft"
  "zsh|zshrc|$_HI_ZSHRC|$_HI_HOME_ZSHRC|zsh -n|local,graft"
  "fish|config.fish|$_HI_FISH_CONFIG|$_HI_HOME_FISH_CONFIG|fish --no-execute|local,graft"
  "nu|config.nu|$_HI_NU_CONFIG|$_HI_HOME_NU_CONFIG|nu --commands true|graft"
)

# _hi_shell_rows [flag] - the roster, or only rows carrying <flag>. One per
# line, for `while IFS='|' read` callers.
function _hi_shell_rows() {
  local row
  for row in "${_HI_SHELL_TABLE[@]}"; do
    if [ -z "${1:-}" ]; then
      printf '%s\n' "$row"
      continue
    fi
    case ",${row##*|}," in
    *",$1,"*) printf '%s\n' "$row" ;;
    esac
  done
}

# The one ordering hi resolves shells by, best first. Two consumers read it and
# each takes the part it can serve: load.sh's _hi_session_shell walks it for a
# shell hi styles (fish, zsh, bash - it only ever runs where bash exists), and
# hi.sh's $_HI_SHELL_LADDER is this same list with bash taken out, since a
# missing bash is that ladder's whole precondition. One list because it used to
# be two literals that disagreed: the ladder led with zsh and mksh-before-ksh,
# the session picker with fish. dash/ash/sh are one tier in practice - naming
# them separately is what says which `sh` a target gets when it has more.
export _HI_SHELL_TREE="fish zsh bash mksh ksh dash ash sh"

# color names match fish's set_color vocabulary; greys are skipped, since fish has none.
_HI_COLOR_NAMES=(red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan)

# https://no-color.org: non-empty $NO_COLOR blanks the palette, which is what
# turns the rule into behavior everywhere bash renders; hi.sh ships it along.
if [ -n "${NO_COLOR:-}" ]; then
  export NC='' RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' \
    BRRED='' BRGREEN='' BRYELLOW='' BRBLUE='' BRPURPLE='' BRCYAN=''
else
  export NC='\e[0m'
  export RED='\e[0;31m'
  export GREEN='\e[0;32m'
  export YELLOW='\e[0;33m'
  export BLUE='\e[0;34m'
  export PURPLE='\e[0;35m'
  export CYAN='\e[0;36m'
  export BRRED='\e[1;31m'
  export BRGREEN='\e[1;32m'
  export BRYELLOW='\e[1;33m'
  export BRBLUE='\e[1;34m'
  export BRPURPLE='\e[1;35m'
  export BRCYAN='\e[1;36m'
fi

# _hi_cecho <text> [color] [no_newline]
function _hi_cecho() {
  local out="${2:-}${1:-}$NC"
  [ $# -ge 3 ] && printf '%b' "$out" || printf '%b\n' "$out"
}

# _hi_read_lines <array-name> - stdin into that array, one element per line,
# used like `_hi_read_lines lines < <(cmd)`. GLOSSARY: _hi_read_lines
function _hi_read_lines() {
  local _hi_rl_var="$1" _hi_rl_line
  eval "$_hi_rl_var=()"
  while IFS= read -r _hi_rl_line || [ -n "$_hi_rl_line" ]; do
    eval "$_hi_rl_var+=(\"\$_hi_rl_line\")"
  done
}

# _hi_repeat <var> <count> <char> - $count copies of $char into $var, without
# the subshell and `tr` a `printf | tr` costs per call.
function _hi_repeat() {
  local _hi_pad=""
  ((${2:-0} > 0)) && printf -v _hi_pad '%*s' "$2" ''
  printf -v "$1" '%s' "${_hi_pad// /$3}"
}

# _hi_hrule <label> <bar-char> <inset> <color> - the worker behind the three
# heading levels: a _HI_MAX_WIDTH rule with the label centered
function _hi_hrule() {
  local pad label width=$((${_HI_MAX_WIDTH:-80} - 1)) total left right lbar rbar
  _hi_repeat pad "$3" ' '
  label="$pad$1$pad"
  total=$((width - ${#label}))
  # a label longer than the width keeps a 4-bar rule each side (same floor as
  # the banner's tildes) and overflows, rather than losing the rule entirely
  ((total < 8)) && total=8
  left=$((total / 2))
  right=$((total - left))
  _hi_repeat lbar "$left" "$2"
  _hi_repeat rbar "$right" "$2"
  _hi_cecho " $lbar$label$rbar" "$4"
}

function _hi_h1() {
  _hi_hrule "$1" '=' 1 "${2:-$BRBLUE}"
}

function _hi_h2() {
  _hi_hrule "$1" '-' 2 "${2:-$BRCYAN}"
}

function _hi_h3() {
  _hi_hrule "$1" '~' 3 "${2:-$BRPURPLE}"
}

function _hi_now() {
  printf '%s' "${EPOCHREALTIME:-$(date +%s)}"
}

function _hi_elapsed() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'
}

# total size of the given paths; --apparent-size is GNU-only, so the verdict is
# taken once per shell rather than per call - load.sh asks at session close,
# with the user waiting on it
function _hi_du_size() {
  if [ -z "${_HI_DU_FLAGS+x}" ]; then
    _HI_DU_FLAGS=""
    case "$(du --version 2>/dev/null)" in
    *"GNU coreutils"*) _HI_DU_FLAGS="--apparent-size" ;;
    esac
  fi
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  du -shc $_HI_DU_FLAGS "$@" | awk 'END { print $1 }'
}

# Memoized; the binaries stay authoritative over $HOSTNAME/$USER - the exact
# string feeds _hi_hash_color, and a different one repaints every unpinned host.
function _hi_hostname() {
  [ -n "${_HI_HOSTNAME_CACHE:-}" ] || _HI_HOSTNAME_CACHE="$(hostname 2>/dev/null || uname -n)"
  printf '%s\n' "$_HI_HOSTNAME_CACHE"
}

function _hi_whoami() {
  [ -n "${_HI_WHOAMI_CACHE:-}" ] || _HI_WHOAMI_CACHE="$(whoami)"
  printf '%s\n' "$_HI_WHOAMI_CACHE"
}

# Fill the memos in the *calling* shell: prompt builders reach them through
# $( ), where a cache filled inside the subshell dies with it. The two *colors*
# and not the two escapes - resolving a color is the expensive half (see
# _hi_host_escape), and it is the half both prompt builders want; zsh.zsh takes
# the names and never asks for an escape, so priming those too made it pay for
# two answers it throws away.
function _hi_prime_identity() {
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
  _hi_host_color >/dev/null
  _hi_user_color >/dev/null
}

# Bound a backend CLI so a downed daemon can't hang a waited-on path; bare
# when GNU `timeout` is absent (stock macOS). targets.sh keeps its own copy.
if command -v timeout >/dev/null 2>&1; then
  function _hi_probe() { timeout "${_HI_PROBE_TIMEOUT:-2}" "$@"; }
else
  function _hi_probe() { "$@"; }
fi

# lesspipe + the debian_chroot prompt label, shared by bash.sh and zsh.zsh;
# sets $debian_chroot in the caller's scope
function _hi_interactive_extras() {
  [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
  # shellcheck disable=SC2034 # read by shells/bash.sh and shells/zsh.zsh's PS1
  [ -r /etc/debian_chroot ] && debian_chroot="($(</etc/debian_chroot)) "
}

function _hi_sanitize() {
  local out="${1//[[:cntrl:]]/}"
  printf '%s' "${out//\\/}"
}

# _hi_sanitize_var <var> <text> - the same scrub straight into <var>. The
# header reaches this seven times a banner, and through $( ) each one was a
# fork to run two parameter expansions. GLOSSARY: printf -v out-var
function _hi_sanitize_var() {
  local _hi_s="${2//[[:cntrl:]]/}"
  printf -v "$1" '%s' "${_hi_s//\\/}"
}

# _hi_rewrite <file> <sed-expr>... - every expression in one pass, in place.
# A temp file rather than `sed -i`: its in-place flag differs BSD/GNU (which
# made the caller sniff the userland), and -i replaces a *symlinked* rc with a
# regular file, where the append that put hi's lines there wrote through the
# link. Written back with cat, not mv, so the destination keeps its own inode,
# mode and any hardlink or ACL on it.
function _hi_rewrite() {
  local file="$1" e tmp
  shift
  local -a exprs=()
  for e in "$@"; do exprs+=(-e "$e"); done
  tmp="$(mktemp -t hi.rewrite.XXXXXX)"
  sed "${exprs[@]}" "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# The version this tree answers with, raw and unpresented: a packager's stamp
# (or the client's answer, which the ssh preamble exports) wins, else git
# describe in a checkout, else nothing. Each caller adds its own presentation -
# the header wants a short sanitized cell, `hi --version` and the doctor want a
# diagnostic that says *why* there is no answer.
function _hi_release_or_describe() {
  if [ -n "${_HI_RELEASE:-}" ]; then
    printf '%s\n' "$_HI_RELEASE"
  elif [ -d "$_HI_ROOT/.git" ]; then
    git -C "$_HI_ROOT" describe --tags --always --dirty 2>/dev/null || true
  fi
}

# zsh's `trap ... EXIT` doesn't fire the way bash's does; it has TRAPEXIT instead
function _hi_on_exit() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "TRAPEXIT() { $1; }"
  else
    # shellcheck disable=SC2064 # $1 is the command we want stored, expanded now
    trap "$1" EXIT
  fi
}

# What each shell's prompt ends with unless overridden, <SHELL>:<char>. Five
# different characters, so they are data rather than something each call site
# repeats. SH is the ksh/mksh/sh fallback prompt hi.sh bakes on the client.
# config.fish keeps its own copy (fish parses no bash); hi_test pins it here.
_HI_PROMPT_END_DEFAULTS=('BASH:\$' 'ZSH:>' 'FISH:|' 'NU:>' 'SH:\$')

# _hi_prompt_end_default <SHELL> - the shipped default for one shell, empty if
# the roster does not name it.
function _hi_prompt_end_default() {
  local row
  for row in "${_HI_PROMPT_END_DEFAULTS[@]}"; do
    [ "${row%%:*}" = "$1" ] && {
      printf '%s' "${row#*:}"
      return 0
    }
  done
}

# _hi_prompt_end <SHELL> - the prompt's end character: per-shell setting, then
# the all-three one, then the roster's default. Empty counts as unset (`' '`
# still means "none"); reaches $PS1 unescaped on purpose, so `%#` and `\$` keep
# their meaning. The roster default sits inside the expansion so it is resolved
# only when nothing overrode it - the overriding case costs no fork at all.
# config.fish keeps its own copy of this rule.
function _hi_prompt_end() {
  local specific
  eval "specific=\"\${_HI_PROMPT_END_$1:-}\""
  printf '%s' "${specific:-${_HI_PROMPT_END:-$(_hi_prompt_end_default "$1")}}"
}

function _hi_at_color() {
  [ -n "${SSH_TTY:-}" ] && printf '%b' "$YELLOW" || printf '%b' "$NC"
}

# Deference: _HI_PROMPT=starship hands the prompt to starship when the
# target has it, keeping hi's header and aliases; anything else - unset
# included - keeps hi's own prompt, and a missing starship falls back to it
# silently. Never auto-detected: a target that happens to carry starship
# must not surprise a user who chose hi's prompt. (bash/zsh/fish only: nu
# would need `starship init nu` sourced at parse time, which nu cannot do)
function _hi_wants_starship() {
  [ "${_HI_PROMPT:-}" = starship ] && command -v starship >/dev/null 2>&1
}

# Does this terminal do color? $TERM, not `tput` (a fork per shell); a
# non-empty $NO_COLOR overrides the terminal's yes. GLOSSARY: no-fork reads
function _hi_has_color() {
  [ -z "${NO_COLOR:-}" ] && [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]
}

# Can this session render multibyte glyphs? The locale says; _HI_ASCII
# overrides both ways (1 forces ASCII, 0 forces glyphs, else ask the locale).
function _hi_use_ascii() {
  case "${_HI_ASCII:-}" in
  1) return 0 ;;
  0) return 1 ;;
  esac
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) return 1 ;;
  *) return 0 ;;
  esac
}

# the same decision as a 1/0 flag, for shipping: glyphs render in the
# *client's* terminal, so the client's verdict is the one the target honors
function _hi_ascii_flag() { _hi_use_ascii && echo 1 || echo 0; }

# One glyph set per session, decided at source time so hot paths read plain
# variables; tests flip _HI_ASCII and re-call. The _W widths are visible
# columns, not bytes (GLOSSARY: bytes vs columns); the marks are named so the
# suite matches these bytes, not a lookalike codepoint.
function _hi_choose_glyphs() {
  if _hi_use_ascii; then
    _HI_GLYPH_AHEAD="^" _HI_GLYPH_BEHIND="v" _HI_GLYPH_STAGED="*"
    _HI_GLYPH_DIRTY="+" _HI_GLYPH_INVALID="x" _HI_GLYPH_UNTRACKED="?"
    _HI_GLYPH_STASH="\$" _HI_GLYPH_CLEAN="ok" _HI_GLYPH_ELLIPSIS=".."
    _HI_GLYPH_MASK="*"
    _HI_MARK_OK="ok" _HI_MARK_ALT="~" _HI_MARK_NO="x"
    _HI_MARK_OK_W=2 _HI_MARK_ALT_W=1 _HI_MARK_NO_W=1
  else
    _HI_GLYPH_AHEAD="↑" _HI_GLYPH_BEHIND="↓" _HI_GLYPH_STAGED="●"
    _HI_GLYPH_DIRTY="✚" _HI_GLYPH_INVALID="✖" _HI_GLYPH_UNTRACKED="…"
    _HI_GLYPH_STASH="⚑" _HI_GLYPH_CLEAN="✔" _HI_GLYPH_ELLIPSIS="…"
    _HI_GLYPH_MASK="●"
    _HI_MARK_OK="✓"  # installed, and it was the preferred name
    _HI_MARK_ALT="~" # installed, but via a fallback alternative
    _HI_MARK_NO="✗"  # not installed
    _HI_MARK_OK_W=1 _HI_MARK_ALT_W=1 _HI_MARK_NO_W=1
  fi
}
_hi_choose_glyphs

# the ANSI escape for a palette name (see _HI_COLOR_NAMES); unknown names
# reset, and $NO_COLOR blanks the lot - the hashed user/host/target colors
# all come through here, so this is their one gate
function _hi_color_escape() {
  local i=0 name
  if [ -n "${NO_COLOR:-}" ]; then return 0; fi
  for name in "${_HI_COLOR_NAMES[@]}"; do
    [ "$name" = "$1" ] && {
      printf '\e[%d;3%dm' "$((i / 6))" "$((i % 6 + 1))"
      return
    }
    i=$((i + 1))
  done
  printf '%b' "$NC"
}

# Deterministic name -> palette bucket, right in zsh as well as bash:
# `${name:$i:1}` needs the `$` (zsh reads `:i` as a history modifier), and the
# bucket is taken with the *slice* form, not `${arr[n]}` - zsh indexes arrays
# from 1 (`setopt KSH_ARRAYS` papered over that at oh-my-zsh's expense), while
# `${arr[@]:n:1}` counts from 0 in both shells. It replaced a counted walk over
# the whole palette per resolution.
function _hi_hash_color() {
  local name="$1" sum=0 i=0 ord
  while [ "$i" -lt "${#name}" ]; do
    printf -v ord '%d' "'${name:$i:1}"
    sum=$((sum + ord))
    i=$((i + 1))
  done
  printf '%s\n' "${_HI_COLOR_NAMES[@]:$((sum % ${#_HI_COLOR_NAMES[@]})):1}"
}

# the user/host of the machine hi.d is permanently installed on. hi.sh ships
# these ahead as _HI_LOCAL_USER/_HI_LOCAL_HOSTNAME (see hi.sh's _hi_remote_preamble)
function _hi_local_username() { printf '%s\n' "${_HI_LOCAL_USER:-$(_hi_whoami)}"; }
function _hi_local_hostname() { printf '%s\n' "${_HI_LOCAL_HOSTNAME:-$(_hi_hostname)}"; }

# The two readers of misc/colors' "<type>,<name>,<color>" lines; everything that
# needs the file goes through them rather than re-deriving the format.
# _hi_colors_lookup <type> <name> - that pin's color, or 1 if there isn't one
function _hi_colors_lookup() {
  local cur_type cur_name color
  [[ -f "$_HI_COLORS" ]] || return 1
  while IFS=',' read -r cur_type cur_name color; do
    [[ "$cur_type" = "$1" && "$cur_name" = "$2" ]] || continue
    printf '%s\n' "$color"
    return 0
  done <"$_HI_COLORS"
  return 1
}

# _hi_colors_names <type> [skip-name] - deduped pinned names of that type
function _hi_colors_names() {
  local cur_type cur_name
  [[ -f "$_HI_COLORS" ]] || return 0
  while IFS=',' read -r cur_type cur_name _; do
    [[ "$cur_type" = "$1" && "$cur_name" != "${2:-}" ]] || continue
    printf '%s\n' "$cur_name"
  done <"$_HI_COLORS" | awk '!seen[$0]++'
}

# look up an exact "<type>,<name>,<color>" override
# most names won't have an override and will return 1. exact matches always win.
function _hi_override_color() {
  local special=""
  _hi_colors_lookup "$1" "$2" && return 0
  case "$1" in
  username) [[ "$2" = "$(_hi_local_username)" ]] && special="LOCALUSER" ;;
  hostname) [[ "$2" = "$(_hi_local_hostname)" ]] && special="LOCALHOSTNAME" ;;
  esac
  [[ -n "$special" ]] || return 1
  _hi_colors_lookup "$1" "$special"
}

# _hi_ssh_host_tag <name>, memoized one deep: every caller asks about the same
# host in a row - the connect path alone reaches it from _hi_is_ssh_host, from
# _hi_session_env and from each _hi_resolve_color hostname - and each miss was
# a full in-shell walk of ~/.ssh/config. The rc carries meaning (see below), so
# it is remembered alongside the value.
function _hi_ssh_host_tag() {
  if [ "${_HI_TAG_NAME+x}" != x ] || [ "$_HI_TAG_NAME" != "$1" ]; then
    _HI_TAG_RC=0
    _HI_TAG_VALUE="$(_hi_ssh_host_tag_walk "$1")" || _HI_TAG_RC=$?
    _HI_TAG_NAME="$1"
  fi
  [ -n "$_HI_TAG_VALUE" ] && printf '%s\n' "$_HI_TAG_VALUE"
  return "$_HI_TAG_RC"
}

# The "# Tags: a, b" comment directly above a "Host <alias>" line in
# ~/.ssh/config; unknown host returns 1, a known host with no tag returns 2 -
# `Host` matches case-insensitively (ssh reads its keywords that way
function _hi_ssh_host_tag_walk() {
  local line trimmed rest tag="" aliases
  [ -f "$_HI_SSH_CONFIG" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    # leading whitespace off, once, for every branch below
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
    '#'*)
      rest="${trimmed#\#}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      case "$rest" in
      [Tt]ags[:=]*)
        rest="${rest#*[:=]}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        # the leftmost tag only - "prod, web" pins on prod
        tag="${rest%%[,[:space:]]*}"
        ;;
      esac
      ;;
    [Hh][Oo][Ss][Tt][[:space:]]*)
      aliases="${trimmed#[Hh][Oo][Ss][Tt]}"
      aliases="${aliases%%#*}" # a trailing comment is not an alias
      # padded substring, not a loop: zsh doesn't word-split unquoted, so a
      # loop never matched. Tabs folded first; literal names only.
      aliases="${aliases//	/ }"
      case " $aliases " in
      *" $1 "*)
        [ -n "$tag" ] && printf '%s\n' "$tag" && return 0
        return 2
        ;;
      esac
      tag=""
      ;;
    '') ;;
    *) tag="" ;;
    esac
  done <"$_HI_SSH_CONFIG"
  return 1
}

function _hi_ssh_tag_color() {
  local tag
  tag=$(_hi_ssh_host_tag "$1") && _hi_override_color hosttag "$tag" && return
  return 1
}

function _hi_resolve_color() {
  local type="$1" name="$2" tag="${3:-}"
  _hi_override_color "$type" "$name" && return
  case "$type" in
  hostname) _hi_ssh_tag_color "$name" && return ;;
  username) [[ -n "$tag" ]] && _hi_override_color usertag "$tag" && return ;;
  esac
  _hi_hash_color "$name"
}

# This machine's own two colors, and the escapes for them. All four are
# memoized because none of them can change under a running shell, and none was
# cheap: every layer returns on stdout, so one unmemoized escape cost about
# seven forks - hostname, up to three reads of misc/colors, and a walk of
# ~/.ssh/config - which the prompt paid at every shell start and the banner
# twice a session. `+x` tests *set*, not non-empty: a $NO_COLOR shell resolves
# to the empty string and must not re-resolve it forever.
function _hi_host_color() {
  [ "${_HI_HOST_COLOR+x}" = x ] ||
    _HI_HOST_COLOR="${_HI_TARGET_COLOR:-$(_hi_resolve_color hostname "$(_hi_hostname)")}"
  printf '%s\n' "$_HI_HOST_COLOR"
}
function _hi_user_color() {
  [ "${_HI_USER_COLOR+x}" = x ] ||
    _HI_USER_COLOR="$(_hi_resolve_color username "$(_hi_whoami)" "${_HI_TARGET_TAG:-}")"
  printf '%s\n' "$_HI_USER_COLOR"
}
function _hi_host_escape() {
  [ "${_HI_HOST_ESC+x}" = x ] || _HI_HOST_ESC="$(_hi_color_escape "$(_hi_host_color)")"
  printf '%s' "$_HI_HOST_ESC"
}
function _hi_user_escape() {
  [ "${_HI_USER_ESC+x}" = x ] || _HI_USER_ESC="$(_hi_color_escape "$(_hi_user_color)")"
  printf '%s' "$_HI_USER_ESC"
}

# The out-var forms, for the prompt builders: reached through $( ), the memo
# above is filled inside a subshell and dies with it, so the caller pays every
# time. GLOSSARY: printf -v out-var
function _hi_host_escape_var() {
  _hi_host_escape >/dev/null
  printf -v "$1" '%s' "$_HI_HOST_ESC"
}
function _hi_user_escape_var() {
  _hi_user_escape >/dev/null
  printf -v "$1" '%s' "$_HI_USER_ESC"
}

# The literal colored " user@host" fragment (@ yellow over ssh) that nu's
# prompt and install.sh's preview both render; bash.sh/zsh.zsh keep their
# escape-based (\u/%n) forms, which are a different substrate on purpose.
function _hi_userhost() {
  printf '%b' " $(_hi_user_escape)$(_hi_whoami)$(_hi_at_color)@$(_hi_host_escape)$(_hi_hostname)$NC"
}

set +euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)
