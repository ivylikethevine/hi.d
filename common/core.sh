#!/bin/bash
# The entry point every bash/zsh script sources: preamble (toggles, settings,
# paths.sh), colors, and the shared primitives. One file, because fish reaches
# it via a bare `bash -c "source $_HI_CORE"` with no separate bootstrap.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# Sourced twice in one shell is a no-op; $_hi_core_loaded is deliberately not
# exported, so a child process (fish's `bash -c`) still runs the preamble.
if [ -z "${_hi_core_loaded:-}" ]; then
  _hi_core_loaded=1

  # `: "${X:=default}"` assigns only when X is unset, so a value an outer layer
  # already exported (hi.sh on the client, load.sh on the target) survives
  : "${_HI_HOME:=$HOME}"
  export _HI_HOME
  # GLOSSARY: toggle defaulting + dynamic-name assignment. Defaulted, never
  # assigned - settings.sh and paths.sh's gate still win. List shared with
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
  # install.sh's settings, ahead of paths.sh whose gate reads them
  # ($_HI_SETTINGS comes *from* paths.sh, hence the spelled-out path)
  # shellcheck source=/dev/null # user config, may not exist
  if [ -f "$_HI_CONFIG_DIR/settings.sh" ]; then
    . "$_HI_CONFIG_DIR/settings.sh"
  fi
  # Per-host overlay: $_HI_CONFIG_DIR/settings.d/<name>.sh, after settings.sh so
  # a host can override a global toggle (a slow link wants _HI_HEADER_CHECK=0, a
  # shared root box wants the prompt only). Two names, in this order: the
  # hosttag file from the `# Tags:` comment colors already read, then the
  # exact-host file - they stack, and the more specific one wins.
  #
  # $_HI_TARGET/$_HI_TARGET_TAG are set only inside a session hi opened (hi.sh's
  # remote preamble), so every line here is a no-op on the client. A name
  # carrying a slash is skipped rather than resolved: the value arrives from the
  # command line, and settings.d is meant to be one flat directory.
  # shells/config.fish keeps its own copy of this block.
  for _hi_o in "tag-${_HI_TARGET_TAG:-}" "${_HI_TARGET:-}"; do
    case "$_hi_o" in
    tag- | '' | */*) continue ;;
    esac
    # shellcheck source=/dev/null # user config, may not exist
    if [ -f "$_HI_CONFIG_DIR/settings.d/$_hi_o.sh" ]; then
      . "$_HI_CONFIG_DIR/settings.d/$_hi_o.sh"
    fi
  done
  unset _hi_o
  # shellcheck source=./paths.sh
  source "$_HI_HOME/hi.d/common/paths.sh"
fi

# color names match fish's set_color vocabulary; greys are skipped, since fish has none.
_HI_COLOR_NAMES=(red green yellow blue magenta cyan brred brgreen bryellow brblue brmagenta brcyan)

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

# _hi_cecho <text> [color] [no_newline]
function _hi_cecho() {
  local out="${2:-}${1:-}$NC"
  [ $# -ge 3 ] && printf '%b' "$out" || printf '%b\n' "$out"
}

# _hi_read_lines <array-name> - stdin into that array, one element per line;
# `mapfile -t` for bash 3.2, unterminated last line kept. Use it the same way:
# _hi_read_lines lines < <(cmd). GLOSSARY: _hi_read_lines.
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
# heading levels: a full _HI_MAX_WIDTH rule of <bar-char> with the label
# centered in it, inset by <inset> spaces a side - deeper levels get more
# breathing room around the label. Colors are one per level, with green
# reserved for success banners and yellow/red for warnings and failures -
# callers meaning one of those pass the color explicitly.
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

# high-res-ish timestamp that falls back to whole seconds on bash <5
function _hi_now() {
  printf '%s' "${EPOCHREALTIME:-$(date +%s)}"
}

function _hi_elapsed() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'
}

# total size of the given paths; --apparent-size is GNU-only, probed once
function _hi_du_size() {
  if [ -z "${_HI_LINUX_FLAGS+x}" ]; then
    _HI_LINUX_FLAGS=""
    du --version 2>/dev/null | grep -q "GNU coreutils" && _HI_LINUX_FLAGS="--apparent-size"
  fi
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  du -shc $_HI_LINUX_FLAGS "$@" | awk 'END { print $1 }'
}

# Memoized; `hostname`/`whoami` stay authoritative rather than $HOSTNAME/$USER,
# since the exact string feeds _hi_hash_color - a short name where the binary
# returns an FQDN would repaint every unpinned host.
function _hi_hostname() {
  [ -n "${_HI_HOSTNAME_CACHE:-}" ] || _HI_HOSTNAME_CACHE="$(hostname 2>/dev/null || uname -n)"
  printf '%s\n' "$_HI_HOSTNAME_CACHE"
}

function _hi_whoami() {
  [ -n "${_HI_WHOAMI_CACHE:-}" ] || _HI_WHOAMI_CACHE="$(whoami)"
  printf '%s\n' "$_HI_WHOAMI_CACHE"
}

# Fill both memos in the *calling* shell: prompt builders reach them through
# $( ), where a cache filled inside the subshell dies with it.
function _hi_prime_identity() {
  _hi_whoami >/dev/null
  _hi_hostname >/dev/null
}

# Bound a backend CLI so a downed daemon can't hang a waited-on path; bare
# when GNU `timeout` is absent (stock macOS). targets.sh keeps its own copy.
if command -v timeout >/dev/null 2>&1; then
  function _hi_probe() { timeout "${_HI_PROBE_TIMEOUT:-2}" "$@"; }
else
  function _hi_probe() { "$@"; }
fi

# lesspipe plus the debian_chroot prompt label - identical bash/zsh setup,
# shared by shells/bash.sh and shells/zsh.zsh. Sets $debian_chroot in the
# caller's scope.
function _hi_interactive_extras() {
  [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
  # shellcheck disable=SC2034 # read by shells/bash.sh and shells/zsh.zsh's PS1
  [ -r /etc/debian_chroot ] && debian_chroot="($(</etc/debian_chroot)) "
}

function _hi_sanitize() {
  local out="${1//[[:cntrl:]]/}"
  printf '%s' "${out//\\/}"
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

# _hi_prompt_end <SHELL> <default> - the character the prompt ends with, for
# that shell. Each shell's prompt has always closed with a different one (bash
# `\$`, zsh `>`, fish `|`) and they were hardcoded three times; these are now
# only the defaults.
#
# Precedence: the shell-specific setting, then the one that covers all three,
# then the shipped default. An empty value counts as unset rather than as "no
# separator" - a prompt ending in a bare space is almost never what someone
# meant, and `_HI_PROMPT_END_ZSH=' '` still expresses it.
#
# The value lands in $PS1 unquoted and is *not* escaped: that is deliberate, so
# `%#` in zsh or `\$` in bash still mean what they mean there. shells/config.fish
# keeps its own copy of this rule, as it does for the toggle list.
function _hi_prompt_end() {
  local specific
  eval "specific=\"\${_HI_PROMPT_END_$1:-}\""
  printf '%s' "${specific:-${_HI_PROMPT_END:-$2}}"
}

function _hi_at_color() {
  [ -n "${SSH_TTY:-}" ] && printf '%b' "$YELLOW" || printf '%b' "$NC"
}

# Does this terminal do color? $TERM rather than `tput setaf 1`, which forks a
# binary per shell. Differs only for terminals that set a non-dumb $TERM and
# still have no color - the standard trade for this check.
function _hi_has_color() {
  [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]
}

# Can this session render multibyte glyphs? The locale says (same no-fork
# trade as _hi_has_color): a LANG=C busybox or a serial console turns ↑ ✓ ✗
# into mojibake. _HI_ASCII overrides the probe both ways - 1 forces ASCII,
# 0 forces the glyphs, anything else asks the locale.
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

# the same decision as a 1/0 flag, for shipping to a target: glyphs render in
# the *client's* terminal, so the client's capability is what the target's
# session should honor - its own LANG=C says nothing about your display
function _hi_ascii_flag() { _hi_use_ascii && echo 1 || echo 0; }

# One glyph set per session, decided at source time where the hot paths (the
# prompt renders per command) read plain variables. Tests flip _HI_ASCII and
# call this again to re-decide. The _W widths are visible columns, not bytes -
# the multibyte glyphs are all one column, "ok" is two - for the width math in
# check_line and banner. The marks are named so the suite matches these same
# bytes: a lookalike literal can differ in codepoint while looking identical.
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

# the ANSI escape for a palette name (see _HI_COLOR_NAMES); unknown names reset
function _hi_color_escape() {
  local i=0 name
  for name in "${_HI_COLOR_NAMES[@]}"; do
    [ "$name" = "$1" ] && {
      printf '\e[%d;3%dm' "$((i / 6))" "$((i % 6 + 1))"
      return
    }
    i=$((i + 1))
  done
  printf '%b' "$NC"
}

# deterministic name -> palette bucket, so the same item -> same color
function _hi_hash_color() {
  local name="$1" sum=0 i ord
  for ((i = 0; i < ${#name}; i++)); do
    printf -v ord '%d' "'${name:i:1}"
    sum=$((sum + ord))
  done
  printf '%s\n' "${_HI_COLOR_NAMES[sum % ${#_HI_COLOR_NAMES[@]}]}"
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

# grab the "# Tags: a, b" comment sitting directly above
# a "Host <alias>" line in ~/.ssh/config. an unknown host will return 1
function _hi_ssh_host_tag() {
  local line tag=""
  [[ -f "$_HI_SSH_CONFIG" ]] || return 1
  while IFS=$' ' read -r line; do
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*[Tt]ags[:=][[:space:]]*(.+)$ ]]; then
      tag=${BASH_REMATCH[1]%%[,[:space:]]*}
    elif [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+([^#]+) ]]; then
      local alias
      for alias in ${BASH_REMATCH[1]}; do
        [[ "$alias" = "$1" ]] || continue
        [[ -n "$tag" ]] && printf '%s\n' "$tag" && return 0
        return 1
      done
      tag=""
    elif [[ -n "$line" ]]; then
      tag=""
    fi
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

# locally calculated to properly apply colors
function _hi_host_color() { printf '%s\n' "${_HI_TARGET_COLOR:-$(_hi_resolve_color hostname "$(_hi_hostname)")}"; }
function _hi_user_color() { _hi_resolve_color username "$(_hi_whoami)" "${_HI_TARGET_TAG:-}"; }
function _hi_host_escape() { _hi_color_escape "$(_hi_host_color)"; }
function _hi_user_escape() { _hi_color_escape "$(_hi_user_color)"; }

set +euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)
