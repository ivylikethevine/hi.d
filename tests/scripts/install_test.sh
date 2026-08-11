#!/bin/bash
# Unit tests for scripts/install.sh's reusable logic: the marker-based
# rc-file rewriting (config_shell, shared with scripts/uninstall.sh's
# strip_marker - see uninstall_test.sh), its idempotency/repair behavior,
# setting_enabled's "is this currently on" detection, tmpdir_line,
# ask_setting's non-interactive defaulting, config_hi's already-linked skip
# path, and check_one_config's syntax validation. All run against scratch
# files under a temp dir - nothing real (rc files, /usr/bin/hi) is ever
# touched.
#
# install.sh runs its actual install unconditionally once sourced, past its
# function definitions - reaching config_hi's real `sudo ln` branch from a
# test would be an unwanted system change. The
# `[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` guard right above that flow
# in install.sh is what makes sourcing it here safe: it only runs when
# install.sh is executed directly, never when sourced.
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

set -- # install.sh reads "$@" for its own args; make sure it sees none
# shellcheck source=../../scripts/install.sh
source "$_HI_INSTALL"

_HI_WORKDIR="$(mktemp -d -t hi.installtest.XXXXXX)"
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

# ---- config_shell -----------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_config_shell_fresh_insert() {
  local target="$_HI_WORKDIR/fresh"
  : >"$target"
  config_shell "fresh block" "$target" "line one" "line two"
  grep -qF "line one" "$target" && grep -qF "line two" "$target" && grep -qF "$_HI_MARKER" "$target"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_config_shell_idempotent() {
  local target="$_HI_WORKDIR/idempotent" before after
  : >"$target"
  config_shell idempotent "$target" "line one"
  before="$(cat "$target")"
  config_shell idempotent "$target" "line one"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_config_shell_repairs_stale_line() {
  local target="$_HI_WORKDIR/repair"
  : >"$target"
  config_shell repair "$target" "old line"
  config_shell repair "$target" "new line"
  grep -qF "new line" "$target" && ! grep -qF "old line" "$target"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_config_shell_preserves_unrelated_content() {
  local target="$_HI_WORKDIR/preserve"
  printf '%s\n' "# a user comment" "alias ll='ls -la'" >"$target"
  config_shell preserve "$target" "hi line"
  grep -qF "# a user comment" "$target" && grep -qF "alias ll='ls -la'" "$target" && grep -qF "hi line" "$target"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_config_shell_skips_empty_args() {
  local target="$_HI_WORKDIR/emptyargs"
  : >"$target"
  config_shell emptyargs "$target" "" "real line" ""
  [ "$(grep -cF "$_HI_MARKER" "$target")" -eq 1 ]
}

# ---- setting_enabled ----------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_setting_enabled_default_true_when_absent() {
  local target="$_HI_WORKDIR/absent"
  : >"$target"
  setting_enabled _HI_DISABLE_FOO "$target"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_setting_enabled_false_when_off_present() {
  local target="$_HI_WORKDIR/off"
  printf 'export _HI_DISABLE_FOO=1\n' >"$target"
  ! setting_enabled _HI_DISABLE_FOO "$target"
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_setting_enabled_respects_custom_off_value() {
  local target="$_HI_WORKDIR/customoff"
  printf 'export _HI_HEADER_TIMESTAMP=0\n' >"$target"
  ! setting_enabled _HI_HEADER_TIMESTAMP "$target" 0
}

# ---- tmpdir_line ----------------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_tmpdir_line_empty_when_home_matches() {
  local out
  out="$(_HI_HOME="$HOME" tmpdir_line sh)"
  [ -z "$out" ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_tmpdir_line_posix_variant() {
  local out
  out="$(_HI_HOME=/opt/elsewhere tmpdir_line sh)"
  [ "$out" = 'export _HI_HOME="/opt/elsewhere"' ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_tmpdir_line_fish_variant() {
  local out
  out="$(_HI_HOME=/opt/elsewhere tmpdir_line fish)"
  [ "$out" = 'set -gx _HI_HOME "/opt/elsewhere"' ]
}

# ---- ask_setting (non-interactive defaulting) ------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_ask_setting_default_keeps_enabled() {
  local target="$_HI_WORKDIR/ask_enabled"
  : >"$target"
  ask_setting _HI_DISABLE_FOO "" "$target" 1 "" </dev/null
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_ask_setting_default_keeps_disabled() {
  local target="$_HI_WORKDIR/ask_disabled"
  printf 'export _HI_DISABLE_FOO=1\n' >"$target"
  ! ask_setting _HI_DISABLE_FOO "" "$target" 1 "" </dev/null
}

# ---- _hi_visible_len --------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_visible_len_plain_text() {
  [ "$(_hi_visible_len "hello")" -eq 5 ]
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_visible_len_strips_color_codes() {
  local colored
  printf -v colored '%b' "${GREEN}hi${NC}" # GREEN/NC are literal \e[...m text until rendered this way
  [ "$(_hi_visible_len "$colored")" -eq 2 ]
}

# ---- check_one_config -------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_one_config_valid_bash() {
  command -v bash >/dev/null 2>&1 || return 0
  local target="$_HI_WORKDIR/valid.bashrc"
  printf 'echo hi\n' >"$target"
  check_one_config bash "$target" bash bash -n
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_one_config_invalid_bash() {
  command -v bash >/dev/null 2>&1 || return 0
  local target="$_HI_WORKDIR/invalid.bashrc"
  printf 'if [ 1 = 1 ]; then\n' >"$target" # unterminated if
  ! check_one_config bash "$target" bash bash -n
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_one_config_skips_missing_shell() {
  local target="$_HI_WORKDIR/whatever"
  printf 'irrelevant\n' >"$target"
  check_one_config nope "$target" definitely-not-a-real-shell-xyz
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_check_one_config_skips_empty_file() {
  command -v bash >/dev/null 2>&1 || return 0
  local target="$_HI_WORKDIR/empty.bashrc"
  : >"$target"
  check_one_config bash "$target" bash bash -n
}

# ---- config_hi (skip path only - the sudo-affecting match is out of scope) --

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_config_hi_skips_when_already_linked() {
  local link="$_HI_WORKDIR/already-linked"
  ln -sfn "$_HI_LAUNCHER" "$link"
  (
    _HI_LINK="$link"
    config_hi
  ) | grep -q "already points at"
}

function run_install_tests() {
  _hi_h1 "Testing scripts/install.sh's reusable logic"

  _HI_FAILED=0
  _HI_TOTAL=0

  _hi_h2 "Testing: config_shell"
  _hi_case _hi_assert "Fresh insert" test_config_shell_fresh_insert
  _hi_case _hi_assert "Idempotent re-run" test_config_shell_idempotent
  _hi_case _hi_assert "Repairs a stale line" test_config_shell_repairs_stale_line
  _hi_case _hi_assert "Preserves unrelated content" test_config_shell_preserves_unrelated_content
  _hi_case _hi_assert "Skips empty args" test_config_shell_skips_empty_args

  _hi_h2 "Testing: setting_enabled"
  _hi_case _hi_assert "Defaults to enabled when absent" test_setting_enabled_default_true_when_absent
  _hi_case _hi_assert "Disabled when off-value present" test_setting_enabled_false_when_off_present
  _hi_case _hi_assert "Respects a custom off value" test_setting_enabled_respects_custom_off_value

  _hi_h2 "Testing: tmpdir_line"
  _hi_case _hi_assert "Empty when _HI_HOME == HOME" test_tmpdir_line_empty_when_home_matches
  _hi_case _hi_assert "Posix export line" test_tmpdir_line_posix_variant
  _hi_case _hi_assert "Fish set -gx line" test_tmpdir_line_fish_variant

  _hi_h2 "Testing: ask_setting (non-interactive)"
  _hi_case _hi_assert "Keeps enabled default" test_ask_setting_default_keeps_enabled
  _hi_case _hi_assert "Keeps disabled default" test_ask_setting_default_keeps_disabled

  _hi_h2 "Testing: _hi_visible_len"
  _hi_case _hi_assert "Plain text" test_visible_len_plain_text
  _hi_case _hi_assert "Strips color codes" test_visible_len_strips_color_codes

  _hi_h2 "Testing: check_one_config"
  _hi_case _hi_assert "Valid bash syntax" test_check_one_config_valid_bash
  _hi_case _hi_assert "Invalid bash syntax" test_check_one_config_invalid_bash
  _hi_case _hi_assert "Skips a missing shell" test_check_one_config_skips_missing_shell
  _hi_case _hi_assert "Skips an empty file" test_check_one_config_skips_empty_file

  _hi_h2 "Testing: config_hi (skip path only)"
  _hi_case _hi_assert "Skips when already linked" test_config_hi_skips_when_already_linked

  if [ "$_HI_FAILED" -eq 0 ]; then
    _hi_h1 "All install.sh logic checks passed ($_HI_TOTAL cases)"
  else
    _hi_h1 "$_HI_FAILED/$_HI_TOTAL install.sh logic checks FAILED" "$RED"
  fi
  exit "$_HI_FAILED"
}

run_install_tests
