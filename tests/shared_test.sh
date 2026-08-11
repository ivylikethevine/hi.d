#!/bin/bash
# Unit tests for common/shared.sh's non-trivial logic: _hi_sanitize's
# control-char/backslash stripping, _hi_color_escape's name -> ANSI formula
# (checked against the real RED/BRCYAN constants, so a formula regression
# would actually be caught), _hi_hash_color's determinism (checked against
# hand-computed sums, not just "runs twice the same"), _hi_override_color's
# exact-match and LOCALUSER/LOCALHOSTNAME special-casing, _hi_ssh_host_tag's
# "# Tags: ..." comment parsing (leftmost tag, multi-alias Host lines, reset
# between hosts), and _hi_resolve_color's override > hosttag/usertag > hash
# precedence. Everything runs against scratch $_HI_COLORS/$_HI_SSH_CONFIG
# files in a subshell - the real ones are never read except where noted.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../common/shared.sh
source "$_HI_SHARED"

_HI_WORKDIR="$(mktemp -d -t hi.sharedtest.XXXXXX)"
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

# ---- _hi_sanitize -----------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_sanitize_leaves_plain_text_alone() {
  [ "$(_hi_sanitize "hello world")" = "hello world" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_sanitize_strips_control_chars_and_backslashes() {
  [ "$(_hi_sanitize $'a\tb\\c')" = "abc" ]
}

# ---- _hi_color_escape ---------------------------------------------------

# RED/BRCYAN/NC hold literal '\e[...m' text (interpreted later via printf
# '%b', e.g. in _hi_cecho) - _hi_color_escape's own printf interprets its
# '\e' immediately, so both sides need the same '%b' pass to compare equal.

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_color_escape_matches_red_constant() {
  local expected
  printf -v expected '%b' "$RED"
  [ "$(_hi_color_escape red)" = "$expected" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_color_escape_matches_brcyan_constant() {
  local expected
  printf -v expected '%b' "$BRCYAN"
  [ "$(_hi_color_escape brcyan)" = "$expected" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_color_escape_unknown_name_resets() {
  local expected
  printf -v expected '%b' "$NC"
  [ "$(_hi_color_escape not-a-real-color)" = "$expected" ]
}

# ---- _hi_hash_color -----------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_hash_color_deterministic() {
  [ "$(_hi_hash_color someuser)" = "$(_hi_hash_color someuser)" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_hash_color_matches_hand_computed_bucket() {
  # ord('a')=97, 97 % 12 == 1 -> _HI_COLOR_NAMES[1] == green
  [ "$(_hi_hash_color a)" = "green" ] || return 1
  # ord('a')+ord('b')=97+98=195, 195 % 12 == 3 -> _HI_COLOR_NAMES[3] == blue
  [ "$(_hi_hash_color ab)" = "blue" ]
}

# ---- _hi_override_color -------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_override_color_exact_match() {
  local colors="$_HI_WORKDIR/colors.exact"
  printf 'username,alice,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_override_color username alice)" = "red" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_override_color_no_match_fails() {
  local colors="$_HI_WORKDIR/colors.nomatch"
  printf 'username,alice,red\n' >"$colors"
  ! _HI_COLORS="$colors" _hi_override_color username bob
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_override_color_localuser_special_case() {
  local colors="$_HI_WORKDIR/colors.localuser"
  printf 'username,LOCALUSER,cyan\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_USER=testuser _hi_override_color username testuser)" = "cyan" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_override_color_localhostname_special_case() {
  local colors="$_HI_WORKDIR/colors.localhost"
  printf 'hostname,LOCALHOSTNAME,magenta\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_HOSTNAME=testhost _hi_override_color hostname testhost)" = "magenta" ]
}

# ---- _hi_ssh_host_tag ---------------------------------------------------

# shellcheck disable=SC2329 # invoked from the test_ssh_host_tag_* functions below
function _hi_ssh_tag_fixture() {
  local f="$_HI_WORKDIR/ssh_config"
  cat >"$f" <<'EOF'
# Tags: prod, web
Host myhost
    HostName 1.2.3.4

Host untaggedhost
    HostName 5.6.7.8

# Tags= dev
Host devhost otheralias
    HostName 9.9.9.9
EOF
  printf '%s' "$f"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_ssh_host_tag_leftmost_of_multiple() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag myhost)" = "prod" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_ssh_host_tag_untagged_host_fails() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  ! _HI_SSH_CONFIG="$f" _hi_ssh_host_tag untaggedhost
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_ssh_host_tag_equals_syntax_and_multialias() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag devhost)" = "dev" ] || return 1
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag otheralias)" = "dev" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_ssh_host_tag_unknown_host_fails() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  ! _HI_SSH_CONFIG="$f" _hi_ssh_host_tag no-such-host
}

# ---- _hi_resolve_color precedence ----------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_resolve_color_override_wins() {
  local colors="$_HI_WORKDIR/colors.resolve1"
  printf 'username,bob,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username bob)" = "red" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_resolve_color_hosttag_via_ssh_config() {
  local f colors
  f="$(_hi_ssh_tag_fixture)"
  colors="$_HI_WORKDIR/colors.resolve2"
  printf 'hosttag,prod,blue\n' >"$colors"
  [ "$(_HI_SSH_CONFIG="$f" _HI_COLORS="$colors" _hi_resolve_color hostname myhost)" = "blue" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_resolve_color_usertag_when_no_exact_override() {
  local colors="$_HI_WORKDIR/colors.resolve3"
  printf 'usertag,prodtag,green\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username someuser prodtag)" = "green" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_resolve_color_falls_back_to_hash() {
  local colors="$_HI_WORKDIR/colors.missing" # never created - no override file
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username unknownxyz)" = "$(_hi_hash_color unknownxyz)" ]
}

function run_shared_tests() {
  _hi_h1 "Testing common/shared.sh"

  _HI_FAILED=0
  _HI_TOTAL=0

  _hi_h2 "_hi_sanitize"
  _hi_case _hi_assert "leaves plain text alone" test_sanitize_leaves_plain_text_alone
  _hi_case _hi_assert "strips control chars and backslashes" test_sanitize_strips_control_chars_and_backslashes

  _hi_h2 "_hi_color_escape"
  _hi_case _hi_assert "red matches \$RED" test_color_escape_matches_red_constant
  _hi_case _hi_assert "brcyan matches \$BRCYAN" test_color_escape_matches_brcyan_constant
  _hi_case _hi_assert "unknown name resets" test_color_escape_unknown_name_resets

  _hi_h2 "_hi_hash_color"
  _hi_case _hi_assert "deterministic across calls" test_hash_color_deterministic
  _hi_case _hi_assert "matches hand-computed buckets" test_hash_color_matches_hand_computed_bucket

  _hi_h2 "_hi_override_color"
  _hi_case _hi_assert "exact match" test_override_color_exact_match
  _hi_case _hi_assert "no match fails" test_override_color_no_match_fails
  _hi_case _hi_assert "LOCALUSER special case" test_override_color_localuser_special_case
  _hi_case _hi_assert "LOCALHOSTNAME special case" test_override_color_localhostname_special_case

  _hi_h2 "_hi_ssh_host_tag"
  _hi_case _hi_assert "leftmost tag of a multi-tag comment" test_ssh_host_tag_leftmost_of_multiple
  _hi_case _hi_assert "untagged host fails" test_ssh_host_tag_untagged_host_fails
  _hi_case _hi_assert "'Tags=' syntax and multi-alias Host lines" test_ssh_host_tag_equals_syntax_and_multialias
  _hi_case _hi_assert "unknown host fails" test_ssh_host_tag_unknown_host_fails

  _hi_h2 "_hi_resolve_color precedence"
  _hi_case _hi_assert "exact override wins" test_resolve_color_override_wins
  _hi_case _hi_assert "hosttag via ssh config" test_resolve_color_hosttag_via_ssh_config
  _hi_case _hi_assert "usertag when no exact override" test_resolve_color_usertag_when_no_exact_override
  _hi_case _hi_assert "falls back to the hash" test_resolve_color_falls_back_to_hash

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "All shared.sh checks passed ($_HI_TOTAL cases)"
  else
    _hi_h1 "$_HI_FAILED/$_HI_TOTAL shared.sh checks FAILED" "$RED"
  fi
  exit "$_HI_FAILED"
}

run_shared_tests
