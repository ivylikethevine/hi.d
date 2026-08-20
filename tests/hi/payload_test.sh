#!/bin/bash
# Unit tests for hi.sh: the ssh payload, the config overlay stream, and the size
# hi reports on connect. The payload is an allow list, so most of this file is
# its drift guard - what ships, what an overlay trims, and what never trims.
#
# Sourcing hi.sh goes through the same `[[ BASH_SOURCE == $0 ]]` hatch install.sh
# uses, which defines every function without connecting to anything - so the pure
# half is reachable here, where a mis-parse is an assertion rather than a
# confusing connection failure. _say_hi stays e2e-only by nature.
#
# GLOSSARY: HI.30 + HI.34. The linter follows `source "$_HI_LAUNCHER"` into hi.sh's
# trailing `_hi "$@"`, decides it never returns, and marks this file unreachable
# (SC2317) - it does not model the BASH_SOURCE guard. The single-quoted strings
# below are the target's to expand, not ours (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# The overlay trims the tar. Pins one toggle to the file it stops shipping, and
# the same run asserts the rest of the tree is still there - a broken --exclude
# that dropped everything would satisfy "vim.rc is gone" just as well.
function test_payload_trims_what_the_overlay_disabled() {
  local dir="$_HI_WORKDIR/trim" listing
  mkdir -p "$dir"
  printf "#!/bin/sh\nexport _HI_DISABLE_EDITORS='1'\n" >"$dir/settings.sh"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in *say-hi/misc/vim.rc*)
    _hi_cecho " | _HI_DISABLE_EDITORS=1 still shipped misc/vim.rc" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/misc/nano.rc*)
    _hi_cecho " | _HI_DISABLE_EDITORS=1 still shipped misc/nano.rc" "$RED"
    return 1
    ;;
  esac
  # ...and the tree is otherwise intact
  case "$listing" in *say-hi/misc/aliases.sh*) ;; *)
    _hi_cecho " | the trim took misc/aliases.sh with it" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/load.sh*) return 0 ;; esac
  _hi_cecho " | the trim took load.sh with it" "$RED"
  return 1
}

# An unconfigured client ships everything - which is also what both size budgets
# are measuring, so this is the case that keeps those numbers meaning something.
function test_payload_ships_everything_by_default() {
  local dir="$_HI_WORKDIR/notrim" listing
  mkdir -p "$dir"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in *say-hi/misc/vim.rc*) ;; *)
    _hi_cecho " | a default client did not ship misc/vim.rc" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/shells/osc52.sh*) return 0 ;; esac
  _hi_cecho " | a default client did not ship shells/osc52.sh" "$RED"
  return 1
}

# _HI_DISABLE_ALIASES cuts along the seam between the two alias files and not
# through either: misc/personal.sh leaves the payload, misc/aliases.sh stays.
# Both halves matter. aliases.sh installs the vim/nano, hi_copy and tmux
# aliases above the source line, so trimming it would be a behaviour change
# wearing a size saving's clothes; personal.sh is preference the target will
# not read, so shipping it is bytes on the wire for nothing.
function test_payload_trims_personal_but_keeps_aliases() {
  local dir="$_HI_WORKDIR/noalias" listing
  mkdir -p "$dir"
  printf "#!/bin/sh\nexport _HI_DISABLE_ALIASES='1'\n" >"$dir/settings.sh"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in
  *say-hi/misc/personal.sh*)
    _hi_cecho " | _HI_DISABLE_ALIASES=1 still shipped misc/personal.sh" "$RED"
    return 1
    ;;
  esac
  case "$listing" in *say-hi/misc/aliases.sh*) ;; *)
    _hi_cecho " | _HI_DISABLE_ALIASES=1 dropped misc/aliases.sh, which still carries the editor, hi_copy and tmux aliases" "$RED"
    return 1
    ;;
  esac
  # and the default client ships both
  listing="$(_hi_payload_tar | tar tzf - 2>/dev/null)"
  case "$listing" in *say-hi/misc/personal.sh*) return 0 ;; esac
  _hi_cecho " | a default client did not ship misc/personal.sh" "$RED"
  return 1
}

# The payload is an allow list; this is its drift guard. Exact match on the
# list (so nothing sneaks on the wire unnoticed) plus an existence check on
# every member (so a rename can't quietly ship an empty payload).
function test_payload_ships_exactly_the_travelled_paths() {
  local m
  [ "${_HI_PAYLOAD[*]}" = "common misc shells load.sh hi.sh" ] || {
    _hi_cecho " | payload list changed: ${_HI_PAYLOAD[*]} - update this guard deliberately" "$RED"
    return 1
  }
  for m in "${_HI_PAYLOAD[@]}"; do
    [ -e "$_HI_ROOT/$m" ] || {
      _hi_cecho " | payload member missing from the tree: $m" "$RED"
      return 1
    }
  done
}

# The payload only carries the *in-tree* misc/, so once the user's real
# settings/colors/packages live outside the tree they need their own stream or a
# target silently falls back to the shipped defaults. These assert the two
# halves that can be checked without a target: that nothing is sent when there
# is nothing to send, and that what is sent lands under the names paths.sh
# looks for.

function _hi_overlay_fixture() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  shift
  for f in "$@"; do printf 'x\n' >"$dir/$f"; done
  printf '%s' "$dir"
}

function test_overlay_is_empty_without_one() {
  local dir="$_HI_WORKDIR/no-overlay"
  mkdir -p "$dir"
  ! (_HI_CONFIG_DIR="$dir" _hi_has_overlay) &&
    [ -z "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar)" ]
}

function test_overlay_is_seen_when_present() {
  local dir
  dir="$(_hi_overlay_fixture some colors)"
  (_HI_CONFIG_DIR="$dir" _hi_has_overlay)
}

# members land at the archive's top level under their plain names, since it is
# unpacked straight into the target's config/ - a "colors" that arrived as
# "say-hi/colors" or "./config/colors" would be invisible to paths.sh
function test_overlay_tar_members_are_bare_names() {
  local dir listing
  dir="$(_hi_overlay_fixture members colors packages settings.sh)"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  [ "$(printf '%s\n' "$listing" | sort | paste -sd, -)" = "colors,packages,settings.sh" ]
}

# only what the user actually has - an overlay holding one file must not carry
# a placeholder for the other two, which would shadow the tree's defaults
function test_overlay_tar_carries_only_what_exists() {
  local dir
  dir="$(_hi_overlay_fixture partial colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "colors" ]
}

# the additive personal aliases ride the same stream under their bare name,
# which is where misc/aliases.sh's tail line ($_HI_CONFIG_DIR/aliases.sh, the
# target's config/) looks - a separate file from the shipped one, on purpose
function test_overlay_tar_carries_aliases() {
  local dir
  dir="$(_hi_overlay_fixture withaliases aliases.sh)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "aliases.sh" ]
}

# ksh.sh has to ride the payload, or the rc sources a file that isn't there
function test_payload_carries_ksh_sh() {
  [ -f "$_HI_ROOT/shells/ksh.sh" ] && [[ " ${_HI_PAYLOAD[*]} " == *" shells "* ]]
}

# This block exists because both halves were wrong at once: the connect line
# reported `du` over the payload directories (the uncompressed tree, roughly
# double the truth), and the armored script had grown to within a few kilobytes
# of the *single-argument* execve limit, which is 128KB on Linux however large
# ARG_MAX is. The second one is a hard failure - "Argument list too long", no
# session at all - so it gets a guard with headroom rather than a comment.

function test_human_bytes_matches_du_shapes() {
  [ "$(_hi_human_bytes 0)" = 0B ] || return 1
  [ "$(_hi_human_bytes 1023)" = 1023B ] || return 1
  [ "$(_hi_human_bytes 1024)" = 1.0K ] || return 1
  [ "$(_hi_human_bytes 34559)" = 34K ] || return 1
  [ "$(_hi_human_bytes 5000000)" = 4.8M ]
}

# the reported number counts what is sent, not what is on disk: it must be
# nowhere near `du` over the payload
function test_wire_size_is_not_the_disk_size() {
  local wire disk
  wire="$(_hi_wire_estimate)"
  disk="$(_hi_size)"
  [ -n "$wire" ] && [ "$wire" != "$disk" ]
}

# The guard with teeth: the assembled script is what every session pays in
# bandwidth, so measure the thing that is sent rather than re-deriving it from
# the armored streams (which omits the boilerplate wrapping them).
function test_payload_stays_clear_of_the_arg_limit() {
  local bytes
  bytes="$(_hi_wire_bytes)"
  # 128KB (MAX_ARG_STRLEN) is where this breaks outright; 256KB is the
  # "this has doubled, come and look" line
  [ "$bytes" -lt 262144 ]
}

function run_hi_payload_tests() {
  _hi_workdir hipayloadtest

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the payload"

  _hi_h2 "Testing: the payload list"
  _hi_check "Ships exactly common/misc/shells/load.sh" test_payload_ships_exactly_the_travelled_paths
  _hi_check "Overlay trims what it disabled" test_payload_trims_what_the_overlay_disabled
  _hi_check "A default client ships everything" test_payload_ships_everything_by_default
  _hi_check "The toggle trims personal.sh and keeps aliases.sh" test_payload_trims_personal_but_keeps_aliases
  _hi_check "ksh.sh rides the payload" test_payload_carries_ksh_sh

  _hi_h2 "Testing: the config overlay stream"
  _hi_check "Nothing sent without an overlay" test_overlay_is_empty_without_one
  _hi_check "Seen when present" test_overlay_is_seen_when_present
  _hi_check "Members are bare names" test_overlay_tar_members_are_bare_names
  _hi_check "Carries only what exists" test_overlay_tar_carries_only_what_exists
  _hi_check "aliases.sh rides the stream" test_overlay_tar_carries_aliases

  _hi_h2 "Testing: the size hi reports"
  _hi_check "_hi_human_bytes matches du's shapes" test_human_bytes_matches_du_shapes
  _hi_check "The wire size isn't the disk size" test_wire_size_is_not_the_disk_size
  _hi_check "The payload stays clear of the argv limit" test_payload_stays_clear_of_the_arg_limit
  _hi_suite_end "hi.sh (the payload)"
}

run_hi_payload_tests
