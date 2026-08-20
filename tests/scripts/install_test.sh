#!/bin/bash
# Unit tests for scripts/install.sh's reusable logic - both halves of it, since
# `--uninstall` lives in the same script: the marker-based rc rewriting and the
# settings/toggle handling, then the stripping that reverses them (incl. an
# install+uninstall round trip).
#
# GLOSSARY: HI.30
# shellcheck disable=SC2329
set -euo pipefail

# test_lib.sh sources core.sh itself; $_HI_TEST_LIB wins under the runner
# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

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

# mode read via ls's first field - stat's flags differ GNU/BSD
# shellcheck disable=SC2012 # the paths are fixtures this suite just wrote
function test_config_shell_preserves_target_mode() {
  local target="$_HI_WORKDIR/mode" before
  printf 'content\n' >"$target"
  chmod 640 "$target"
  before="$(ls -l "$target" | awk '{ print $1 }')"
  config_shell mode "$target" "hi line"
  [ "$(ls -l "$target" | awk '{ print $1 }')" = "$before" ]
}

# a dotfile manager's hardlinked ~/.bashrc must not be severed by a mv
function test_config_shell_preserves_hardlinks() {
  local target="$_HI_WORKDIR/hardlink" twin="$_HI_WORKDIR/hardlink.twin"
  printf 'content\n' >"$target"
  ln "$target" "$twin"
  config_shell hardlink "$target" "hi line"
  grep -qF "hi line" "$twin"
}

function test_config_shell_backs_up_on_first_insert() {
  local target="$_HI_WORKDIR/backup"
  printf 'original content\n' >"$target"
  config_shell backup "$target" "hi line"
  [ -f "$target.hi-orig" ] && [ "$(cat "$target.hi-orig")" = "original content" ]
}

# the backup stays the pre-hi original - a rerun must not overwrite it
function test_config_shell_backup_survives_reruns() {
  local target="$_HI_WORKDIR/backup2"
  printf 'original\n' >"$target"
  config_shell backup2 "$target" "hi line"
  config_shell backup2 "$target" "another line"
  [ "$(cat "$target.hi-orig")" = "original" ]
}

# nothing to preserve, nothing to back up
function test_config_shell_no_backup_for_empty_target() {
  local target="$_HI_WORKDIR/backup3"
  : >"$target"
  config_shell backup3 "$target" "hi line"
  [ ! -e "$target.hi-orig" ]
}

# Nothing is spliced into common/paths.sh any more - the settings live in
# $_HI_SETTINGS, which every entry point sources *ahead* of paths.sh so that
# paths.sh's local-only gate can read them. That ordering is the load-bearing
# property now, and it's spread across three files (no single include line is
# valid in sh, bash, zsh and fish alike), so assert it in each.
# Comment lines are filtered out first: both files explain themselves in prose
# that names the very files being looked for, and a comment mentioning paths.sh
# above the code that sources settings.sh would read as the wrong order.
function _hi_first_code_line() {
  grep -n "$2" "$1" | grep -v ':[[:space:]]*#' | head -1 | cut -d: -f1
}

function _hi_sources_settings_before_paths() {
  local target="$1" settings_line paths_line
  settings_line="$(_hi_first_code_line "$target" 'settings\.sh')"
  paths_line="$(_hi_first_code_line "$target" 'paths\.sh')"
  [ -n "$settings_line" ] && [ -n "$paths_line" ] && [ "$settings_line" -lt "$paths_line" ]
}

function test_core_sources_settings_first() {
  _hi_sources_settings_before_paths "$_HI_ROOT/common/core.sh"
}

function test_fish_config_sources_settings_first() {
  _hi_sources_settings_before_paths "$_HI_ROOT/shells/config.fish"
}

# hi.sh's fallback rc is the third entry point, but it's *generated* rather
# than sourced, so it's asserted against _hi_fallback_rc's real output over in
# tests/shells/hi_test.sh instead of by grepping the file.

# settings.sh is sourced by sh, bash, zsh and fish, so line 1 has to be the
# `#!/bin/sh` all four read as a comment - and has to stay line 1 once
# config_shell has written the settings block under it.
function _hi_shebang_fresh() { ensure_settings_shebang; }

# The versioning contract: init makes a repo with one (possibly empty) first
# commit and is idempotent; overlay_commit turns settings writes into history
# only where a repo already exists, and never creates one. Each case gets a
# fresh scratch $_HI_CONFIG_DIR; the identity fallback keeps the commits
# working on a machine that never ran `git config`.
function _hi_overlay_commits() {
  git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0
}

function test_overlay_init_creates_a_repo_with_a_first_commit() {
  local dir="$_HI_WORKDIR/ovl-init"
  mkdir -p "$dir"
  printf 'export X=1\n' >"$dir/settings.sh"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) &&
    [ -d "$dir/.git" ] && [ "$(_hi_overlay_commits "$dir")" = 1 ] &&
    git -C "$dir" ls-files | grep -qx settings.sh
}

function test_overlay_init_is_idempotent() {
  local dir="$_HI_WORKDIR/ovl-idem"
  mkdir -p "$dir"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) &&
    (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) &&
    [ "$(_hi_overlay_commits "$dir")" = 1 ]
}

function test_overlay_commit_records_a_change_when_tracked() {
  local dir="$_HI_WORKDIR/ovl-commit"
  mkdir -p "$dir"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) || return 1
  printf 'export Y=2\n' >"$dir/settings.sh"
  (_HI_CONFIG_DIR="$dir" overlay_commit) &&
    [ "$(_hi_overlay_commits "$dir")" = 2 ]
}

function test_overlay_commit_is_a_noop_with_nothing_new() {
  local dir="$_HI_WORKDIR/ovl-noop"
  mkdir -p "$dir"
  (_HI_CONFIG_DIR="$dir" overlay_init >/dev/null) || return 1
  (_HI_CONFIG_DIR="$dir" overlay_commit) &&
    [ "$(_hi_overlay_commits "$dir")" = 1 ]
}

function test_overlay_commit_never_creates_a_repo() {
  local dir="$_HI_WORKDIR/ovl-untracked"
  mkdir -p "$dir"
  printf 'export X=1\n' >"$dir/settings.sh"
  (_HI_CONFIG_DIR="$dir" overlay_commit) &&
    [ ! -d "$dir/.git" ]
}

function test_shebang_is_written_to_a_new_settings_file() {
  _hi_settings_fixture shebang_new _hi_shebang_fresh
  [ "$(head -n 1 "$(_hi_fixture_settings shebang_new)")" = "#!/bin/sh" ]
}

# the whole point of the overlay: a fresh install leaves the tree untouched, so
# `hi --update`'s git pull still applies and a root-owned tree still works
function test_settings_are_written_outside_the_tree() {
  _hi_settings_fixture outside _hi_shebang_fresh
  [ -f "$(_hi_fixture_settings outside)" ] && [ ! -e "$_HI_WORKDIR/outside/misc/settings.sh" ]
}

function _hi_shebang_then_settings() {
  ensure_settings_shebang
  config_shell settings "$_HI_SETTINGS" "export _HI_DISABLE_PROMPT=1"
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
  printf '%s\n%s\n' '#!/bin/bash' 'export _HI_MAX_WIDTH=120' >"$_HI_SETTINGS"
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

# same mode-preservation contract as config_shell
function _hi_shebang_mode() {
  mkdir -p "$_HI_CONFIG_DIR"
  printf 'X=1\n' >"$_HI_SETTINGS"
  chmod 604 "$_HI_SETTINGS"
  ensure_settings_shebang
}

# shellcheck disable=SC2012 # fixture paths, mode via ls as above
function test_settings_shebang_preserves_mode() {
  _hi_settings_fixture shebang_mode _hi_shebang_mode
  local ref="$_HI_WORKDIR/mode.ref"
  : >"$ref"
  chmod 604 "$ref"
  [ "$(ls -l "$(_hi_fixture_settings shebang_mode)" | awk '{ print $1 }')" = "$(ls -l "$ref" | awk '{ print $1 }')" ]
}

# the three config_* groups accumulate rather than each calling config_shell,
# because one config_shell call per group against one file would have each
# wipe the other two's lines
function _hi_settings_one_write() {
  local -a _HI_SETTING_LINES=("export _HI_DISABLE_PROMPT=1" "" "export _HI_HEADER_CHECK=0")
  mkdir -p "$_HI_CONFIG_DIR"
  config_shell settings "$_HI_SETTINGS" "${_HI_SETTING_LINES[@]}"
}

function test_config_settings_writes_every_group_at_once() {
  _hi_settings_fixture onewrite _hi_settings_one_write
  local f
  f="$(_hi_fixture_settings onewrite)"
  grep -qF "export _HI_DISABLE_PROMPT=1" "$f" && grep -qF "export _HI_HEADER_CHECK=0" "$f"
}

# this run's answer wins over the file, which still holds the previous run's
function test_setting_off_sees_this_runs_answer() {
  local target="$_HI_WORKDIR/pending"
  : >"$target"
  local _HI_SETTING_PENDING=("_HI_DISABLE_HEADER=1")
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

# Written even for a tree at the default location: nothing defaults to $HOME
# any more, and a new process with no tree to derive from reads this line or
# nothing at all (GLOSSARY: HI.33)
function test_tmpdir_line_states_the_tree_even_at_home() {
  local out
  out="$(_HI_HOME="$HOME" tmpdir_line sh)"
  [ "$out" = "export _HI_HOME=\"$HOME\"" ]
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
  local len
  _hi_visible_len len "hello"
  [ "$len" -eq 5 ]
}

function test_visible_len_strips_color_codes() {
  local colored len
  colored="$(_hi_rendered "${GREEN}hi${NC}")"
  _hi_visible_len len "$colored"
  [ "$len" -eq 2 ]
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
  local out
  out="$(
    function chmod() { echo "CHMOD RAN"; }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$link"
    config_hi
  )"
  [[ "$out" == *"already points at"* && "$out" != *"CHMOD RAN"* ]]
}

# a writable bindir needs no sudo at all - root installs, userland prefixes
function test_config_hi_links_plainly_when_bindir_is_writable() {
  local dir="$_HI_WORKDIR/writablebin"
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  (
    function sudo() {
      echo "SUDO RAN"
      return 1
    }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  ) >/dev/null
  [ "$(readlink "$dir/bin/hi")" = "$dir/hi.sh" ]
}

# refused/absent sudo on an unwritable bindir must end in instructions, not a
# `set -e` death at the last step of a completed install
function test_config_hi_degrades_when_sudo_cannot_link() {
  local dir="$_HI_WORKDIR/nosudo" out rc=0
  mkdir -p "$dir/bin"
  printf '#!/bin/bash\n' >"$dir/hi.sh"
  chmod 755 "$dir/hi.sh"
  chmod 555 "$dir/bin"
  out="$(
    function sudo() { return 1; }
    _HI_LAUNCHER="$dir/hi.sh"
    _HI_LINK="$dir/bin/hi"
    config_hi
  )" || rc=$?
  chmod 755 "$dir/bin"
  [ "$rc" -eq 0 ] && [[ "$out" == *"--no-link"* ]] && [ ! -e "$dir/bin/hi" ]
}

# install_tree is the whole of what a PKGBUILD's package() (or a deb/rpm recipe)
# calls. It must lay the tree down under $DESTDIR and touch nothing else - no rc
# file, no sudo, no prompt - since none of those belong to the packager.

# the scratch source tree alone, for cases that need setup between it and the
# install_tree run (or several runs)
function _hi_package_src() {
  local dir="$_HI_WORKDIR/$1" item
  mkdir -p "$dir/src/hi.d/common" "$dir/src/hi.d/misc" "$dir/src/hi.d/scripts" "$dir/src/hi.d/shells"
  for item in hi.sh load.sh LICENSE.md README.md; do printf 'x\n' >"$dir/src/hi.d/$item"; done
}

# Stand a scratch tree up and run install_tree against it.
function _hi_package_fixture() {
  local dir="$_HI_WORKDIR/$1"
  local _HI_ROOT="$dir/src/hi.d" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  _hi_package_src "$1"
  install_tree >/dev/null
}

function test_install_tree_copies_the_tree_under_destdir() {
  _hi_package_fixture copies
  local dest="$_HI_WORKDIR/copies/dest/usr/share/hi.d"
  [ -d "$dest/common" ] && [ -d "$dest/misc" ] && [ -d "$dest/shells" ] &&
    [ -f "$dest/load.sh" ] && [ -x "$dest/hi.sh" ]
}

# scripts/ is the one place this list differs from hi.sh's $_HI_PAYLOAD: a
# payload doesn't need it, but a packaged install does, or `hi --install` (which
# every user of that package has to run once) would not be there to run.
function test_install_tree_ships_scripts() {
  _hi_package_fixture scripts
  [ -d "$_HI_WORKDIR/scripts/dest/usr/share/hi.d/scripts" ]
}

# the man page: gzipped outside the tree when the source has one (a checkout
# or tarball does; docs/ is not in $_HI_PACKAGE_CONTENTS, so an installed
# tree doesn't, and install_tree must simply skip it then)
function test_install_tree_stages_the_man_page() {
  local dir="$_HI_WORKDIR/man"
  local _HI_ROOT="$dir/src/hi.d" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  _hi_package_src man
  mkdir -p "$_HI_ROOT/docs"
  printf '.TH HI 1\n' >"$_HI_ROOT/docs/hi.1"
  install_tree >/dev/null
  [ -f "$dir/dest/usr/share/man/man1/hi.1.gz" ]
}

function test_install_tree_skips_the_man_page_without_a_source() {
  _hi_package_fixture noman
  [ ! -e "$_HI_WORKDIR/noman/dest/usr/share/man" ]
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

# cp -R merges, so a re-stage must clear the dest or removed files keep shipping
function test_install_tree_clears_a_stale_destination() {
  local dir="$_HI_WORKDIR/staledest"
  _hi_package_fixture staledest
  printf 'stale\n' >"$dir/dest/usr/share/hi.d/leftover"
  local _HI_ROOT="$dir/src/hi.d" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  install_tree >/dev/null
  [ ! -e "$dir/dest/usr/share/hi.d/leftover" ] && [ -f "$dir/dest/usr/share/hi.d/load.sh" ]
}

# clearing the dest removes a pre-existing symlink itself, never its target
function test_install_tree_replaces_a_symlinked_dest_without_following() {
  local dir="$_HI_WORKDIR/symdest"
  _hi_package_src symdest
  mkdir -p "$dir/dest/usr/share" "$dir/elsewhere"
  printf 'keep\n' >"$dir/elsewhere/precious"
  ln -s "$dir/elsewhere" "$dir/dest/usr/share/hi.d"
  local _HI_ROOT="$dir/src/hi.d" _HI_PREFIX="/usr/share" DESTDIR="$dir/dest"
  install_tree >/dev/null
  [ -f "$dir/elsewhere/precious" ] && [ ! -L "$dir/dest/usr/share/hi.d" ] &&
    [ -f "$dir/dest/usr/share/hi.d/load.sh" ]
}

function test_strip_marker_removes_tagged_lines_only() {
  local target="$_HI_WORKDIR/tagged"
  printf '%s\n' "# a user comment" "alias ll='ls -la'" >"$target"
  config_shell fixture "$target" "hi line one" "hi line two"
  strip_marker test "$target"
  grep -qF "# a user comment" "$target" &&
    grep -qF "alias ll='ls -la'" "$target" &&
    ! grep -qF "$_HI_MARKER" "$target" &&
    ! grep -qF "hi line one" "$target"
}

function test_strip_marker_noop_when_marker_absent() {
  local target="$_HI_WORKDIR/untagged" before after
  printf '%s\n' "just a normal file" >"$target"
  before="$(cat "$target")"
  strip_marker test "$target"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

function test_strip_marker_safe_on_missing_file() {
  strip_marker test "$_HI_WORKDIR/does-not-exist"
}

function test_install_uninstall_round_trip() {
  local target="$_HI_WORKDIR/roundtrip" before after
  printf '%s\n' "# pre-existing line" >"$target"
  before="$(cat "$target")"
  config_shell fixture "$target" "some hi config line"
  grep -qF "some hi config line" "$target" || return 1
  strip_marker fixture "$target"
  after="$(cat "$target")"
  [ "$before" = "$after" ]
}

function _hi_strip_written_settings() {
  ensure_settings_shebang
  strip_settings
}

function test_strip_settings_removes_what_install_wrote() {
  _hi_settings_fixture strip _hi_strip_written_settings
  [ ! -e "$(_hi_fixture_settings strip)" ]
}

# colors and packages are the user's own writing, not something install.sh
# produced - uninstall leaves them for the same reason it leaves the checkout
function _hi_strip_beside_colors() {
  printf 'hostname,foo,brred\n' >"$_HI_CONFIG_DIR/colors"
  ensure_settings_shebang
  strip_settings
}

function test_strip_settings_leaves_the_rest_of_the_overlay() {
  _hi_settings_fixture keep _hi_strip_beside_colors
  [ -f "$_HI_WORKDIR/keep/config/colors" ] && [ ! -e "$(_hi_fixture_settings keep)" ]
}

function test_strip_settings_is_quiet_when_there_is_nothing() {
  _hi_settings_fixture nothing strip_settings
}

# The only path through config_hi a test may take: every other one ends in
# `sudo ln`, which has no business firing from a suite. --no-link returns before
# that, which is the whole point of it - a Homebrew/distro/Git Bash install has
# nothing to link and no way to link it.

function test_config_hi_no_link_skips_the_symlink() {
  local link="$_HI_WORKDIR/no-link-link"
  (
    _HI_LINK="$link"
    _HI_NO_LINK=1
    config_hi
  ) | grep -q "leaving $link alone"
  [ ! -e "$link" ]
}

# the flag has to be a real flag, not just a variable an internal caller sets
function test_no_link_flag_is_parsed_and_documented() {
  grep -qF -- '--no-link) _HI_NO_LINK=1' "$_HI_INSTALL" &&
    grep -qF -- '--no-link' <("$_HI_INSTALL" --help)
}

function test_unlink_hi_skips_when_link_missing() {
  local link="$_HI_WORKDIR/no-such-link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
}

function test_unlink_hi_skips_when_link_points_elsewhere() {
  local link="$_HI_WORKDIR/elsewhere-link"
  ln -sfn /bin/true "$link"
  (
    _HI_LINK="$link"
    unlink_hi
  ) | grep -q "leaving it alone"
}

# the shim is the only reason `hi --uninstall` and the documented
# scripts/uninstall.sh path still work, so assert it points at the flag
function test_uninstall_shim_delegates_to_install() {
  grep -qF -- '--uninstall' "$_HI_UNINSTALL" && grep -qF 'install.sh' "$_HI_UNINSTALL"
}

# Three questions, one per shell, all of which have to survive being written to
# a file four shells source. Every case runs non-interactive (`</dev/null`, no
# tty), which is the path that keeps whatever is already configured.

# _hi_prompt_ends_lines [existing-settings-line ...] - what config_prompt_ends
# would write, as one string
function _hi_prompt_ends_lines() {
  local dir="$_HI_WORKDIR/promptends"
  local _HI_SETTINGS="$dir/settings.sh"
  local -a _HI_SETTING_LINES=()
  mkdir -p "$dir"
  [ "$#" -eq 0 ] && : >"$_HI_SETTINGS" || printf '%s\n' "$@" >"$_HI_SETTINGS"
  config_prompt_ends </dev/null
  printf '%s' "${_HI_SETTING_LINES[*]}"
}

# the shipped defaults are core.sh's own, so writing them out would be noise
# that then has to be kept in sync - the same rule config_max_width has for 80
function test_prompt_ends_writes_nothing_for_the_defaults() {
  [ -z "$(_hi_prompt_ends_lines | tr -d ' ')" ]
}

function test_prompt_ends_keeps_an_existing_override() {
  local out
  out="$(_hi_prompt_ends_lines "export _HI_PROMPT_END_ZSH='::'")"
  [[ "$out" == *"export _HI_PROMPT_END_ZSH='::'"* ]]
}

# quoted on the way out: a separator is as likely to be $ or > as a letter, and
# the file is sourced by sh, bash, zsh and fish alike
function test_prompt_ends_quotes_what_it_writes() {
  local out
  out="$(_hi_prompt_ends_lines "export _HI_PROMPT_END_BASH='>'")"
  [[ "$out" == *"_HI_PROMPT_END_BASH='>'"* ]]
}

# the prompt is off, so what it ends with is moot - the same skip
# config_header_details makes when the header itself is off
function test_prompt_ends_skipped_when_the_prompt_is_off() {
  local out
  out="$(_hi_prompt_ends_lines "export _HI_DISABLE_PROMPT=1" "export _HI_PROMPT_END_ZSH='::'")"
  [ -z "$(printf '%s' "$out" | tr -d ' ')" ]
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
  _hi_check "Preserves the target's mode" test_config_shell_preserves_target_mode
  _hi_check "Preserves hardlinks" test_config_shell_preserves_hardlinks
  _hi_check "Backs up on the first insert" test_config_shell_backs_up_on_first_insert
  _hi_check "Backup survives reruns" test_config_shell_backup_survives_reruns
  _hi_check "No backup for an empty target" test_config_shell_no_backup_for_empty_target

  _hi_h2 "Testing: settings are sourced ahead of paths.sh"
  _hi_check "common/core.sh" test_core_sources_settings_first
  _hi_check "shells/config.fish" test_fish_config_sources_settings_first

  _hi_h2 "Testing: config_prompt_ends"
  _hi_check "Defaults write nothing" test_prompt_ends_writes_nothing_for_the_defaults
  _hi_check "An existing override is kept" test_prompt_ends_keeps_an_existing_override
  _hi_check "Written values are quoted" test_prompt_ends_quotes_what_it_writes
  _hi_check "Skipped when the prompt is off" test_prompt_ends_skipped_when_the_prompt_is_off

  _hi_h2 "Testing: overlay_init / overlay_commit"
  _hi_check_requires git "Init makes a repo with a first commit" test_overlay_init_creates_a_repo_with_a_first_commit
  _hi_check_requires git "Init is idempotent" test_overlay_init_is_idempotent
  _hi_check_requires git "A tracked overlay commits settings writes" test_overlay_commit_records_a_change_when_tracked
  _hi_check_requires git "Nothing new, no commit" test_overlay_commit_is_a_noop_with_nothing_new
  _hi_check_requires git "An untracked overlay never hears about git" test_overlay_commit_never_creates_a_repo

  _hi_h2 "Testing: ensure_settings_shebang"
  _hi_check "Written to a new settings.sh" test_shebang_is_written_to_a_new_settings_file
  _hi_check "Stays first under the settings block" test_shebang_stays_first_under_the_settings_block
  _hi_check "Not duplicated on reruns" test_shebang_is_not_duplicated_on_reruns
  _hi_check "Replaces a different shebang" test_shebang_replaces_a_different_one_and_keeps_content
  _hi_check "Preserves settings.sh's mode" test_settings_shebang_preserves_mode

  _hi_h2 "Testing: config_settings"
  _hi_check "Writes every group at once" test_config_settings_writes_every_group_at_once
  _hi_check "Written outside the tree" test_settings_are_written_outside_the_tree
  _hi_check "setting_off sees this run's answer" test_setting_off_sees_this_runs_answer

  _hi_h2 "Testing: setting_off / setting_enabled"
  _hi_check "Defaults to enabled when absent" test_setting_enabled_default_true_when_absent
  _hi_check "Disabled when off-value present" test_setting_enabled_false_when_off_present
  _hi_check "Respects a custom off value" test_setting_enabled_respects_custom_off_value

  _hi_h2 "Testing: tmpdir_line"
  _hi_check "States the tree even at \$HOME" test_tmpdir_line_states_the_tree_even_at_home
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
  _hi_check "Links plainly into a writable bindir" test_config_hi_links_plainly_when_bindir_is_writable
  _hi_check "Degrades when sudo can't link" test_config_hi_degrades_when_sudo_cannot_link

  _hi_h2 "Testing: install_tree (packaging mode)"
  _hi_check "Copies the tree under DESTDIR" test_install_tree_copies_the_tree_under_destdir
  _hi_check "Ships scripts/" test_install_tree_ships_scripts
  _hi_check "Stages the man page, gzipped" test_install_tree_stages_the_man_page
  _hi_check "Skips the man page without a source" test_install_tree_skips_the_man_page_without_a_source
  _hi_check "Links hi without DESTDIR in the target" test_install_tree_links_hi_without_destdir_in_the_target
  _hi_check "Writes the profile.d snippet" test_install_tree_writes_the_profile_snippet
  _hi_check "Touches no rc file" test_install_tree_touches_no_rc_file
  _hi_check "Clears a stale destination" test_install_tree_clears_a_stale_destination
  _hi_check "Replaces a symlinked dest without following" test_install_tree_replaces_a_symlinked_dest_without_following

  _hi_h2 "Testing: strip_marker (--uninstall)"
  _hi_check "Removes only tagged lines" test_strip_marker_removes_tagged_lines_only
  _hi_check "No-op when marker absent" test_strip_marker_noop_when_marker_absent
  _hi_check "Safe on a missing file" test_strip_marker_safe_on_missing_file
  _hi_check "Install+uninstall round-trips" test_install_uninstall_round_trip

  _hi_h2 "Testing: strip_settings"
  _hi_check "Removes what install wrote" test_strip_settings_removes_what_install_wrote
  _hi_check "Leaves the rest of the overlay" test_strip_settings_leaves_the_rest_of_the_overlay
  _hi_check "Quiet when there is nothing" test_strip_settings_is_quiet_when_there_is_nothing

  _hi_h2 "Testing: config_hi (--no-link only)"
  _hi_check "Skips the symlink entirely" test_config_hi_no_link_skips_the_symlink
  _hi_check "Flag is parsed and documented" test_no_link_flag_is_parsed_and_documented

  _hi_h2 "Testing: unlink_hi (skip paths only)"
  _hi_check "Skips a missing link" test_unlink_hi_skips_when_link_missing
  _hi_check "Skips a foreign link" test_unlink_hi_skips_when_link_points_elsewhere
  _hi_check "uninstall.sh shims onto --uninstall" test_uninstall_shim_delegates_to_install

  _hi_suite_end "install.sh logic"
}

run_install_tests
