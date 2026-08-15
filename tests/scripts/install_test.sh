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

# the block goes at the end, after whatever the file already had
function test_config_shell_appends_at_the_end() {
  local target="$_HI_WORKDIR/appends"
  printf '%s\n' "first line" >"$target"
  config_shell appends "$target" "hi line"
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

# config_shell and ensure_settings_shebang write into $_HI_ROOT and
# $_HI_SETTINGS_WRITE - which for a real run are this very checkout and the
# user's real overlay. Shadow them with scratch paths first, the same way
# load_test.sh's _hi_clean_all wrapper shadows $_HI_ROOT before letting
# clean_all near it.
#
# The scratch overlay is deliberately a *different* directory from the scratch
# tree's misc/, so "writes land outside the tree" is something these tests can
# see rather than assume.
function _hi_settings_fixture() {
  local dir="$_HI_WORKDIR/$1"
  local _HI_ROOT="$dir" _HI_CONFIG_DIR="$dir/config"
  local _HI_SETTINGS="$dir/misc/settings.sh" _HI_SETTINGS_WRITE="$dir/config/settings.sh"
  mkdir -p "$dir/common" "$dir/misc"
  shift
  "$@" >/dev/null
}

# where _hi_settings_fixture's install writes, as the assertions see it
function _hi_fixture_settings() { printf '%s' "$_HI_WORKDIR/$1/config/settings.sh"; }

# settings.sh is sourced by sh, bash, zsh and fish, so line 1 has to be the
# `#!/bin/sh` all four read as a comment - and has to stay line 1 once
# config_shell has written the settings block under it.
function _hi_shebang_fresh() { ensure_settings_shebang; }

function test_shebang_is_written_to_a_new_settings_file() {
  _hi_settings_fixture shebang_new _hi_shebang_fresh
  [ "$(head -n 1 "$(_hi_fixture_settings shebang_new)")" = "#!/bin/sh" ]
}

# the whole point of the overlay: a fresh install leaves the tree untouched, so
# `hi_update`'s git pull still applies and a root-owned tree still works
function test_settings_are_written_outside_the_tree() {
  _hi_settings_fixture outside _hi_shebang_fresh
  [ -f "$(_hi_fixture_settings outside)" ] && [ ! -e "$_HI_WORKDIR/outside/misc/settings.sh" ]
}

function _hi_shebang_then_settings() {
  ensure_settings_shebang
  config_shell settings "$_HI_SETTINGS_WRITE" "export _HI_DISABLE_PROMPT=1"
}

function test_shebang_stays_first_under_the_settings_block() {
  _hi_settings_fixture shebang_block _hi_shebang_then_settings
  local f
  f="$(_hi_fixture_settings shebang_block)"
  [ "$(head -n 1 "$f")" = "#!/bin/sh" ] && grep -qF "export _HI_DISABLE_PROMPT=1" "$f"
}

# re-running must not stack a second shebang
function _hi_shebang_twice() {
  ensure_settings_shebang
  ensure_settings_shebang
}

function test_shebang_is_not_duplicated_on_reruns() {
  _hi_settings_fixture shebang_twice _hi_shebang_twice
  [ "$(grep -c '^#!' "$(_hi_fixture_settings shebang_twice)")" -eq 1 ]
}

# a hand-edited shebang for the wrong shell is replaced, not left alongside:
# dash and fish both source this file, so sh is the only correct one
function _hi_shebang_wrong() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf '%s\n%s\n' '#!/bin/bash' 'export _HI_MAX_WIDTH=120' >"$_HI_SETTINGS_WRITE"
  ensure_settings_shebang
}

function test_shebang_replaces_a_different_one_and_keeps_content() {
  _hi_settings_fixture shebang_wrong _hi_shebang_wrong
  local f
  f="$(_hi_fixture_settings shebang_wrong)"
  [ "$(head -n 1 "$f")" = "#!/bin/sh" ] &&
    [ "$(grep -c '^#!' "$f")" -eq 1 ] &&
    grep -qF "export _HI_MAX_WIDTH=120" "$f"
}

# the three config_* groups accumulate rather than each calling config_shell,
# because one config_shell call per group against one file would have each
# wipe the other two's lines
function _hi_settings_one_write() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "" "export _HI_HEADER_CHECK=0")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS_WRITE" "${_HI_SETTING_LINES[@]}"
}

function test_config_settings_writes_every_group_at_once() {
  _hi_settings_fixture onewrite _hi_settings_one_write
  local f
  f="$(_hi_fixture_settings onewrite)"
  grep -qF "export _HI_DISABLE_PROMPT=1" "$f" && grep -qF "export _HI_HEADER_CHECK=0" "$f"
}

# An install predating the overlay left settings inside the tree. The answers in
# it are read back through $_HI_SETTINGS, rewritten to the overlay, and the
# in-tree copy taken away - two files both claiming to be the settings is the
# failure this prevents.
function _hi_settings_migrate() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf '#!/bin/sh\nexport _HI_MAX_WIDTH=120\n' >"$_HI_SETTINGS"
  ensure_settings_shebang
  config_shell settings "$_HI_SETTINGS_WRITE" "export _HI_MAX_WIDTH=120"
  migrate_in_tree_settings
}

function test_in_tree_settings_are_migrated_to_the_overlay() {
  _hi_settings_fixture migrate _hi_settings_migrate
  grep -qF "export _HI_MAX_WIDTH=120" "$(_hi_fixture_settings migrate)" &&
    [ ! -e "$_HI_WORKDIR/migrate/misc/settings.sh" ]
}

# this run's answer wins over the file, which still holds the previous run's
function test_setting_off_sees_this_runs_answer() {
  local target="$_HI_WORKDIR/pending"
  : >"$target"
  local -A _HI_SETTING_PENDING=([_HI_DISABLE_HEADER]=1)
  setting_off _HI_DISABLE_HEADER "$target" 1 &&
    ! setting_off _HI_DISABLE_PROMPT "$target" 1
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
  check_one_config bash "$target" bash -n
}

function test_check_one_config_invalid_bash() {
  command -v bash >/dev/null 2>&1 || return 0
  local target="$_HI_WORKDIR/invalid.bashrc"
  printf 'if [ 1 = 1 ]; then\n' >"$target" # unterminated if
  ! check_one_config bash "$target" bash -n
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
  check_one_config bash "$target" bash -n
}

function test_config_hi_skips_when_already_linked() {
  local link="$_HI_WORKDIR/already-linked"
  ln -sfn "$_HI_LAUNCHER" "$link"
  (
    _HI_LINK="$link"
    config_hi
  ) | grep -q "already points at"
}

# A packaged tree is root-owned and hi.sh already has its mode from the
# packager. An unconditional `chmod +x` there aborts the whole run under
# `set -e`, so a user could not configure a perfectly good install.
#
# chmod is stubbed rather than the file made genuinely unwritable: the owner of
# a file can always chmod it whatever its mode, so short of running as another
# user this is the only way to reach the failure from a test.
function test_config_hi_survives_an_unwritable_launcher() {
  local dir="$_HI_WORKDIR/rootowned" link="$_HI_WORKDIR/rootowned-link"
  mkdir -p "$dir"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  ln -sfn "$dir/hi.sh" "$link"
  (
    function chmod() { return 1; }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$link"
    config_hi
  ) | grep -q "couldn't make"
}

# the packaged case proper: hi.sh arrives executable, so no chmod is attempted
# at all and the run carries on to the link check
function test_config_hi_skips_chmod_when_already_executable() {
  local dir="$_HI_WORKDIR/preexec" link="$_HI_WORKDIR/preexec-link"
  mkdir -p "$dir"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 555 "$dir/hi.sh"
  ln -sfn "$dir/hi.sh" "$link"
  (
    function chmod() { echo "CHMOD RAN"; }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$link"
    config_hi
  ) | grep -q "already points at" &&
    ! (
      function chmod() { echo "CHMOD RAN"; }
      _HI_LAUNCHER="$dir/hi.sh"
      _HI_LINK="$link"
      config_hi
    ) | grep -q "CHMOD RAN"
}

# --- packaging mode ---------------------------------------------------------
#
# install_tree is the whole of what a PKGBUILD's package() (or a deb/rpm recipe)
# calls. It must lay the tree down under $DESTDIR and touch nothing else - no rc
# file, no sudo, no prompt - since none of those belong to the packager.

# Stand a scratch tree up and run install_tree against it, returning the DESTDIR.
function _hi_package_fixture() {
  local dir="$_HI_WORKDIR/$1" item
  local _HI_ROOT="$dir/src/hi.d" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  mkdir -p "$_HI_ROOT/common" "$_HI_ROOT/misc" "$_HI_ROOT/scripts" "$_HI_ROOT/shells"
  for item in hi.sh load.sh LICENSE README.md; do printf 'x\n' >"$_HI_ROOT/$item"; done
  install_tree >/dev/null
}

function test_install_tree_copies_the_tree_under_destdir() {
  _hi_package_fixture copies
  local dest="$_HI_WORKDIR/copies/dest/usr/share/hi.d"
  [ -d "$dest/common" ] && [ -d "$dest/misc" ] && [ -d "$dest/shells" ] &&
    [ -f "$dest/load.sh" ] && [ -x "$dest/hi.sh" ]
}

# scripts/ is the one place this list differs from hi.sh's $_HI_EXCLUDE: a
# payload doesn't need it, but a packaged install does, or `hi_install` (which
# every user of that package has to run once) would not be there to run.
function test_install_tree_ships_scripts() {
  _hi_package_fixture scripts
  [ -d "$_HI_WORKDIR/scripts/dest/usr/share/hi.d/scripts" ]
}

# the link has to point where hi.sh will be on the installed system, not into
# the staging root, which won't exist by then
function test_install_tree_links_hi_without_destdir_in_the_target() {
  _hi_package_fixture link
  [ "$(readlink "$_HI_WORKDIR/link/dest/usr/bin/hi")" = "/usr/share/hi.d/hi.sh" ]
}

# a package can't rewrite anyone's rc file, so profile.d is the only place it
# can put the _HI_HOME every shell needs before it sources anything
function test_install_tree_writes_the_profile_snippet() {
  _hi_package_fixture profile
  grep -qF 'export _HI_HOME="/usr/share"' "$_HI_WORKDIR/profile/dest/etc/profile.d/hi.d.sh"
}

function test_install_tree_touches_no_rc_file() {
  _hi_package_fixture norc
  local dest="$_HI_WORKDIR/norc/dest"
  [ ! -e "$dest/root" ] && [ ! -e "$dest$HOME" ] && [ ! -e "$dest/etc/bash.bashrc" ]
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
  _hi_check "Appends at the end" test_config_shell_appends_at_the_end

  _hi_h2 "Testing: settings are sourced ahead of paths.sh"
  _hi_check "common/bootstrap.sh" test_bootstrap_sources_settings_first
  _hi_check "common/shared.sh" test_shared_sources_settings_first
  _hi_check "shells/config.fish" test_fish_config_sources_settings_first

  _hi_h2 "Testing: ensure_settings_shebang"
  _hi_check "Written to a new settings.sh" test_shebang_is_written_to_a_new_settings_file
  _hi_check "Stays first under the settings block" test_shebang_stays_first_under_the_settings_block
  _hi_check "Not duplicated on reruns" test_shebang_is_not_duplicated_on_reruns
  _hi_check "Replaces a different shebang" test_shebang_replaces_a_different_one_and_keeps_content

  _hi_h2 "Testing: config_settings"
  _hi_check "Writes every group at once" test_config_settings_writes_every_group_at_once
  _hi_check "Written outside the tree" test_settings_are_written_outside_the_tree
  _hi_check "In-tree settings are migrated" test_in_tree_settings_are_migrated_to_the_overlay
  _hi_check "setting_off sees this run's answer" test_setting_off_sees_this_runs_answer

  _hi_h2 "Testing: setting_off / setting_enabled"
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
  _hi_check "Survives an unwritable launcher" test_config_hi_survives_an_unwritable_launcher
  _hi_check "Skips chmod when already executable" test_config_hi_skips_chmod_when_already_executable

  _hi_h2 "Testing: install_tree (packaging mode)"
  _hi_check "Copies the tree under DESTDIR" test_install_tree_copies_the_tree_under_destdir
  _hi_check "Ships scripts/" test_install_tree_ships_scripts
  _hi_check "Links hi without DESTDIR in the target" test_install_tree_links_hi_without_destdir_in_the_target
  _hi_check "Writes the profile.d snippet" test_install_tree_writes_the_profile_snippet
  _hi_check "Touches no rc file" test_install_tree_touches_no_rc_file

  _hi_suite_end "install.sh logic"
}

run_install_tests
