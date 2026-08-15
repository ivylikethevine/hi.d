#!/bin/bash
# The entry point every bash/zsh script and shell uses: the environment preamble
# (toggle defaults, settings, common/paths.sh) followed by colors and the
# handful of primitives every hi script needs (_hi_cecho, timing, hostname).
#
# One file rather than two because shells/config.fish reaches this directly
# through `bash -c "source $_HI_CORE"`, without a chance to run a separate
# bootstrap first - which is what used to make the preamble below exist twice.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# Sourced twice in one shell is a no-op; $_hi_core_loaded is deliberately not
# exported, so a child process (fish's `bash -c`) still runs the preamble.
if [ -z "${_hi_core_loaded:-}" ]; then
  _hi_core_loaded=1

  # `: "${X:=default}"` assigns only when X is unset, so a value an outer layer
  # already exported (hi.sh on the client, load.sh on the target) survives
  : "${_HI_HOME:=$HOME}"
  export _HI_HOME
  : "${_HI_DISABLE_LOCAL:=0}"
  export _HI_DISABLE_LOCAL
  : "${_HI_REMOTE_SESSION:=0}"
  export _HI_REMOTE_SESSION
  # The six feature toggles, defaulted so reading one is never an error.
  # shells/aliases.sh and shells/config.fish read them bare - they can't use
  # ${X:-0}, since fish has no such expansion and sources both - so an unset
  # toggle is fatal under `set -u`. (That is what broke `hi <target> <command>`
  # until hi.sh's bootloader stopped leaving strict mode on.)
  # Defaulted, never assigned: the settings file is sourced next and paths.sh's
  # local-only gate right after, and both still have to be able to win.
  : "${_HI_DISABLE_HEADER:=0}"
  : "${_HI_DISABLE_PROMPT:=0}"
  : "${_HI_DISABLE_PERSONAL:=0}"
  : "${_HI_DISABLE_GIT_STATUS:=0}"
  : "${_HI_DISABLE_EDITORS:=0}"
  : "${_HI_DISABLE_ALIASES:=0}"
  export _HI_DISABLE_HEADER _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL
  export _HI_DISABLE_GIT_STATUS _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES
  # where the user's config overlay lives. paths.sh resolves settings/colors/
  # packages against it but can't derive it (fish has no ${X:-y}), so every entry
  # point sets it; `:=` leaves an outer layer's value alone the way $_HI_HOME above
  # is left alone, which is what lets hi.sh point a target at its own copy.
  : "${_HI_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/hi.d}"
  export _HI_CONFIG_DIR
  # the settings scripts/install.sh writes, ahead of paths.sh because its
  # local-only gate reads them (see the note by that gate). $_HI_SETTINGS isn't
  # defined yet - it comes *from* paths.sh - so the path is spelled out here.
  # shellcheck source=/dev/null # user config, may not exist
  if [ -f "$_HI_CONFIG_DIR/settings.sh" ]; then
    . "$_HI_CONFIG_DIR/settings.sh"
  fi
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

# _hi_repeat <var> <count> <char> - $count copies of $char into $var, without
# the subshell and `tr` a `printf | tr` costs per call.
function _hi_repeat() {
  local _hi_pad=""
  ((${2:-0} > 0)) && printf -v _hi_pad '%*s' "$2" ''
  printf -v "$1" '%s' "${_hi_pad// /$3}"
}

function _hi_h1() {
  local label=" $1 " width=$((${_HI_MAX_WIDTH:-80} - 1)) total left right lbar rbar
  total=$((width - ${#label}))
  ((total < 0)) && total=0
  left=$((total / 2))
  right=$((total - left))
  _hi_repeat lbar "$left" '='
  _hi_repeat rbar "$right" '='
  _hi_cecho " $lbar$label$rbar" "${2:-$BRGREEN}"
}

function _hi_h2() {
  _hi_cecho " -------- $1 -------- " "${2:-$BRBLUE}"
}

function _hi_h3() {
  _hi_cecho " ~~~~ $1 ~~~~ " "${2:-$BRCYAN}"
}

# high-res-ish timestamp that falls back to whole seconds on bash <5
function _hi_now() {
  printf '%s' "${EPOCHREALTIME:-$(date +%s)}"
}

function _hi_elapsed() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'
}

# --apparent-size is a GNU-only flag, probed lazily (and cached) on first use
function _hi_du_size() {
  if [ -z "${_HI_LINUX_FLAGS+x}" ]; then
    _HI_LINUX_FLAGS=""
    du --version 2>/dev/null | grep -q "GNU coreutils" && _HI_LINUX_FLAGS="--apparent-size"
  fi
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  du -sh "$@" $_HI_LINUX_FLAGS "$_HI_ROOT" | awk '{ print $1 }'
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

# Run a backend CLI with an upper bound, so a downed daemon can't hang a path
# the user waits on. `timeout` is GNU coreutils and absent on stock macOS, so
# this degrades to running bare. common/targets.sh keeps its own copy
# (standalone POSIX sh) but shares the knob.
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

function _hi_at_color() {
  [ -n "${SSH_TTY:-}" ] && printf '%b' "$YELLOW" || printf '%b' "$NC"
}

# Does this terminal do color? $TERM rather than `tput setaf 1`, which forks a
# binary per shell. Differs only for terminals that set a non-dumb $TERM and
# still have no color - the standard trade for this check.
function _hi_has_color() {
  [ -n "${TERM:-}" ] && [ "$TERM" != dumb ]
}

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
