#!/bin/bash
# Unit tests for scripts/install.sh's reusable logic.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

set -- # install.sh reads "$@" for its own args; make sure it sees none
# shellcheck source=../../scripts/install.sh
source "$_HI_INSTALL"


function test_config_shell_fresh_insert() {
  local target="$_HI_WORKDIR/fresh"
  : >"$target"
  config_shell "fresh block" "$target" "line one" "line two"
  grep -qF "line one" "$target" && grep -qF "line two" "$target" && grep -qF "$_HI_MARKER" "$target"
}

function test_config_shell_idempotent() {
  local target="$_HI_WORKDIR/idempotent" before after
  : >"$target"
  config_shell idempotent "$target" "line one"
  before="$(cat "$target")"
  config_shell idempotent "$target" "line one"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

function test_config_shell_repairs_stale_line() {
  local target="$_HI_WORKDIR/repair"
  : >"$target"
  config_shell repair "$target" "old line"
  config_shell repair "$target" "new line"
  grep -qF "new line" "$target" && ! grep -qF "old line" "$target"
}

function test_config_shell_preserves_unrelated_content() {
  local target="$_HI_WORKDIR/preserve"
  printf '%s\n' "# a user comment" "alias ll='ls -la'" >"$target"
  config_shell preserve "$target" "hi line"
  grep -qF "# a user comment" "$target" && grep -qF "alias ll='ls -la'" "$target" && grep -qF "hi line" "$target"
}

function test_config_shell_skips_empty_args() {
  local target="$_HI_WORKDIR/emptyargs"
  : >"$target"
  config_shell emptyargs "$target" "" "real line" ""
  [ "$(grep -cF "$_HI_MARKER" "$target")" -eq 1 ]
}

function test_config_shell_splices_above_the_anchor() {
  local target="$_HI_WORKDIR/anchored" block_line gate_line
  printf '%s\n' "export SOMETHING=1" "$_HI_ANCHOR" "[ \"\$SOMETHING\" = 1 ] && echo gate" >"$target"
  config_shell anchored "$target" "export _HI_DISABLE_LOCAL=1"
  block_line="$(grep -nF "$_HI_MARKER" "$target" | cut -d: -f1)"
  gate_line="$(grep -nF "$_HI_ANCHOR" "$target" | cut -d: -f1)"
  [ -n "$block_line" ] && [ "$block_line" -lt "$gate_line" ]
}

function test_config_shell_rewrites_in_place_above_the_anchor() {
  local target="$_HI_WORKDIR/anchored-repair"
  printf '%s\n' "$_HI_ANCHOR" "tail line" >"$target"
  config_shell anchored "$target" "export _HI_DISABLE_LOCAL=1"
  config_shell anchored "$target" "export _HI_DISABLE_HEADER=1"
  [ "$(grep -cF "$_HI_MARKER" "$target")" -eq 1 ] || return 1
  grep -qF "_HI_DISABLE_HEADER" "$target" || return 1
  ! grep -qF "_HI_DISABLE_LOCAL" "$target" || return 1
  [ "$(tail -1 "$target")" = "tail line" ]
}

function test_config_shell_appends_when_there_is_no_anchor() {
  local target="$_HI_WORKDIR/unanchored"
  printf '%s\n' "first line" >"$target"
  config_shell unanchored "$target" "hi line"
  [[ "$(tail -1 "$target")" == *"hi line"* ]]
}

function test_paths_sh_still_carries_the_anchor() {
  grep -qF "$_HI_ANCHOR" "$_HI_ROOT/common/paths.sh"
}

function test_setting_enabled_default_true_when_absent() {
  local target="$_HI_WORKDIR/absent"
  : >"$target"
  setting_enabled _HI_DISABLE_FOO "$target"
}

function test_setting_enabled_false_when_off_present() {
  local target="$_HI_WORKDIR/off"
  printf 'export _HI_DISABLE_FOO=1\n' >"$target"
  ! setting_enabled _HI_DISABLE_FOO "$target"
}

function test_setting_enabled_respects_custom_off_value() {
  local target="$_HI_WORKDIR/customoff"
  printf 'export _HI_HEADER_TIMESTAMP=0\n' >"$target"
  ! setting_enabled _HI_HEADER_TIMESTAMP "$target" 0
}

function test_tmpdir_line_empty_when_home_matches() {
  local out
  out="$(_HI_HOME="$HOME" tmpdir_line sh)"
  [ -z "$out" ]
}

function test_tmpdir_line_posix_variant() {
  local out
  out="$(_HI_HOME=/opt/elsewhere tmpdir_line sh)"
  [ "$out" = 'export _HI_HOME="/opt/elsewhere"' ]
}

function test_tmpdir_line_fish_variant() {
  local out
  out="$(_HI_HOME=/opt/elsewhere tmpdir_line fish)"
  [ "$out" = 'set -gx _HI_HOME "/opt/elsewhere"' ]
}

function test_ask_setting_default_keeps_enabled() {
  local target="$_HI_WORKDIR/ask_enabled"
  : >"$target"
  ask_setting _HI_DISABLE_FOO "" "$target" 1 "" </dev/null
}

function test_ask_setting_default_keeps_disabled() {
  local target="$_HI_WORKDIR/ask_disabled"
  printf 'export _HI_DISABLE_FOO=1\n' >"$target"
  ! ask_setting _HI_DISABLE_FOO "" "$target" 1 "" </dev/null
}

function test_visible_len_plain_text() {
  [ "$(_hi_visible_len "hello")" -eq 5 ]
}

function test_visible_len_strips_color_codes() {
  local colored
  colored="$(_hi_rendered "${GREEN}hi${NC}")"
  [ "$(_hi_visible_len "$colored")" -eq 2 ]
}

function test_check_one_config_valid_bash() {
  command -v bash >/dev/null 2>&1 || return 0
  local target="$_HI_WORKDIR/valid.bashrc"
  printf 'echo hi\n' >"$target"
  check_one_config bash "$target" bash bash -n
}

function test_check_one_config_invalid_bash() {
  command -v bash >/dev/null 2>&1 || return 0
  local target="$_HI_WORKDIR/invalid.bashrc"
  printf 'if [ 1 = 1 ]; then\n' >"$target" # unterminated if
  ! check_one_config bash "$target" bash bash -n
}

function test_check_one_config_skips_missing_shell() {
  local target="$_HI_WORKDIR/whatever"
  printf 'irrelevant\n' >"$target"
  check_one_config nope "$target" definitely-not-a-real-shell-xyz
}

function test_check_one_config_skips_empty_file() {
  command -v bash >/dev/null 2>&1 || return 0
  local target="$_HI_WORKDIR/empty.bashrc"
  : >"$target"
  check_one_config bash "$target" bash bash -n
}

function test_config_hi_skips_when_already_linked() {
  local link="$_HI_WORKDIR/already-linked"
  ln -sfn "$_HI_LAUNCHER" "$link"
  (
    _HI_LINK="$link"
    config_hi
  ) | grep -q "already points at"
}

function run_install_tests() {
  _hi_workdir installtest

  _hi_h1 "Testing scripts/install.sh's reusable logic"

  _hi_suite_begin

  _hi_h2 "Testing: config_shell"
  _hi_check "Fresh insert" test_config_shell_fresh_insert
  _hi_check "Idempotent re-run" test_config_shell_idempotent
  _hi_check "Repairs a stale line" test_config_shell_repairs_stale_line
  _hi_check "Preserves unrelated content" test_config_shell_preserves_unrelated_content
  _hi_check "Skips empty args" test_config_shell_skips_empty_args
  _hi_check "Splices the block above the anchor" test_config_shell_splices_above_the_anchor
  _hi_check "Rewrites an anchored block in place" test_config_shell_rewrites_in_place_above_the_anchor
  _hi_check "Appends when there's no anchor" test_config_shell_appends_when_there_is_no_anchor
  _hi_check "common/paths.sh still carries the anchor" test_paths_sh_still_carries_the_anchor

  _hi_h2 "Testing: setting_enabled"
  _hi_check "Defaults to enabled when absent" test_setting_enabled_default_true_when_absent
  _hi_check "Disabled when off-value present" test_setting_enabled_false_when_off_present
  _hi_check "Respects a custom off value" test_setting_enabled_respects_custom_off_value

  _hi_h2 "Testing: tmpdir_line"
  _hi_check "Empty when _HI_HOME == HOME" test_tmpdir_line_empty_when_home_matches
  _hi_check "Posix export line" test_tmpdir_line_posix_variant
  _hi_check "Fish set -gx line" test_tmpdir_line_fish_variant

  _hi_h2 "Testing: ask_setting (non-interactive)"
  _hi_check "Keeps enabled default" test_ask_setting_default_keeps_enabled
  _hi_check "Keeps disabled default" test_ask_setting_default_keeps_disabled

  _hi_h2 "Testing: _hi_visible_len"
  _hi_check "Plain text" test_visible_len_plain_text
  _hi_check "Strips color codes" test_visible_len_strips_color_codes

  _hi_h2 "Testing: check_one_config"
  _hi_check "Valid bash syntax" test_check_one_config_valid_bash
  _hi_check "Invalid bash syntax" test_check_one_config_invalid_bash
  _hi_check "Skips a missing shell" test_check_one_config_skips_missing_shell
  _hi_check "Skips an empty file" test_check_one_config_skips_empty_file

  _hi_h2 "Testing: config_hi (skip path only)"
  _hi_check "Skips when already linked" test_config_hi_skips_when_already_linked

  _hi_suite_end "install.sh logic"
}

run_install_tests
