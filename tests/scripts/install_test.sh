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

# Nothing is spliced into common/paths.sh any more - the settings live in
# $_HI_SETTINGS, which every entry point sources *ahead* of paths.sh so that
# paths.sh's local-only gate can read them. That ordering is the load-bearing
# property now, and it's spread across four files (no single include line is
# valid in sh, bash, zsh and fish alike), so assert it in all four.
function _hi_sources_settings_before_paths() {
  local target="$1" settings_line paths_line
  settings_line="$(grep -n 'misc/settings\.sh' "$target" | head -1 | cut -d: -f1)"
  paths_line="$(grep -n 'common/paths\.sh' "$target" | head -1 | cut -d: -f1)"
  [ -n "$settings_line" ] && [ -n "$paths_line" ] && [ "$settings_line" -lt "$paths_line" ]
}

function test_bootstrap_sources_settings_first() {
  _hi_sources_settings_before_paths "$_HI_ROOT/common/bootstrap.sh"
}

function test_shared_sources_settings_first() {
  _hi_sources_settings_before_paths "$_HI_ROOT/common/shared.sh"
}

function test_fish_config_sources_settings_first() {
  _hi_sources_settings_before_paths "$_HI_ROOT/shells/config.fish"
}

# hi.sh's fallback rc is the fourth entry point, but it's *generated* rather
# than sourced, so it's asserted against _hi_fallback_rc's real output over in
# tests/compat/hi_test.sh instead of by grepping the file.

# migrate_legacy_settings and config_settings both write into $_HI_ROOT and
# $_HI_SETTINGS - which for a real run are this very checkout. Shadow both
# with scratch paths first, the same way load_test.sh's _hi_clean_all wrapper
# shadows $_HI_ROOT before letting clean_all near it.
function _hi_settings_fixture() {
  local dir="$_HI_WORKDIR/$1"
  local _HI_ROOT="$dir" _HI_SETTINGS="$dir/misc/settings.sh"
  mkdir -p "$dir/common" "$dir/misc"
  : >"$dir/common/paths.sh"
  : >"$dir/common/header.sh"
  : >"$dir/common/shared.sh"
  shift
  "$@" >/dev/null
}

function _hi_legacy_carry() {
  config_shell paths.sh "$_HI_ROOT/common/paths.sh" "export _HI_DISABLE_PROMPT=1"
  config_shell shared.sh "$_HI_ROOT/common/shared.sh" "export _HI_MAX_WIDTH=120"
  migrate_legacy_settings
}

function test_migrate_carries_legacy_values_into_settings() {
  _hi_settings_fixture carry _hi_legacy_carry
  grep -qF "export _HI_DISABLE_PROMPT=1" "$_HI_WORKDIR/carry/misc/settings.sh" &&
    grep -qF "export _HI_MAX_WIDTH=120" "$_HI_WORKDIR/carry/misc/settings.sh"
}

function test_migrate_strips_the_tracked_files() {
  _hi_settings_fixture strip _hi_legacy_carry
  ! grep -qF "$_HI_MARKER" "$_HI_WORKDIR/strip/common/paths.sh" &&
    ! grep -qF "$_HI_MARKER" "$_HI_WORKDIR/strip/common/shared.sh"
}

function _hi_legacy_noop() { migrate_legacy_settings; }

function test_migrate_is_a_noop_without_legacy_lines() {
  _hi_settings_fixture noop _hi_legacy_noop
  [ ! -e "$_HI_WORKDIR/noop/misc/settings.sh" ]
}

# a settings.sh that already has answers is newer than whatever the tracked
# files still hold, so the stale lines get cleared without overwriting it
function _hi_legacy_stale() {
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_HEADER=1"
  config_shell paths.sh "$_HI_ROOT/common/paths.sh" "export _HI_DISABLE_PROMPT=1"
  migrate_legacy_settings
}

function test_migrate_does_not_clobber_newer_settings() {
  _hi_settings_fixture stale _hi_legacy_stale
  grep -qF "export _HI_DISABLE_HEADER=1" "$_HI_WORKDIR/stale/misc/settings.sh" &&
    ! grep -qF "export _HI_DISABLE_PROMPT=1" "$_HI_WORKDIR/stale/misc/settings.sh" &&
    ! grep -qF "$_HI_MARKER" "$_HI_WORKDIR/stale/common/paths.sh"
}

# the three config_* groups accumulate rather than each calling config_shell,
# because one config_shell call per group against one file would have each
# wipe the other two's lines
function _hi_settings_one_write() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "" "export _HI_HEADER_CHECK=0")
  config_settings
}

function test_config_settings_writes_every_group_at_once() {
  _hi_settings_fixture onewrite _hi_settings_one_write
  grep -qF "export _HI_DISABLE_PROMPT=1" "$_HI_WORKDIR/onewrite/misc/settings.sh" &&
    grep -qF "export _HI_HEADER_CHECK=0" "$_HI_WORKDIR/onewrite/misc/settings.sh"
}

function test_setting_pending_sees_this_runs_answer() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_HEADER=1")
  setting_pending "export _HI_DISABLE_HEADER=1" &&
    ! setting_pending "export _HI_DISABLE_PROMPT=1"
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

  _hi_h2 "Testing: settings are sourced ahead of paths.sh"
  _hi_check "common/bootstrap.sh" test_bootstrap_sources_settings_first
  _hi_check "common/shared.sh" test_shared_sources_settings_first
  _hi_check "shells/config.fish" test_fish_config_sources_settings_first

  _hi_h2 "Testing: migrate_legacy_settings"
  _hi_check "Carries legacy values into settings.sh" test_migrate_carries_legacy_values_into_settings
  _hi_check "Strips the tracked files" test_migrate_strips_the_tracked_files
  _hi_check "No-op without legacy lines" test_migrate_is_a_noop_without_legacy_lines
  _hi_check "Doesn't clobber newer settings" test_migrate_does_not_clobber_newer_settings

  _hi_h2 "Testing: config_settings"
  _hi_check "Writes every group at once" test_config_settings_writes_every_group_at_once
  _hi_check "setting_pending sees this run's answer" test_setting_pending_sees_this_runs_answer

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
