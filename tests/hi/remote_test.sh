#!/bin/bash
# Unit tests for hi.sh: everything the client writes for the target to run.
# The bootloader, the fallback rc, `_hi_remote_root`'s probe, the ssh preamble
# and `--version` - strings assembled on this side and executed on the other.
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

# --- _hi_remote_root's probe -------------------------------------------------
#
# The probe runs on the *target*, under whatever `sh` is there, so these cases
# run it the same way: a real `sh -c` against a fake $HOME rather than the
# bash this suite is written in. What it has to answer is where a permanent
# say-hi is, and the only durable statement of that is the line
# scripts/install.sh wrote into a login rc - which is why each fixture writes
# one rather than relying on the tree being findable.

# _hi_probe_home <name> <tree-parent-relative-path> [tree-name] - a fake $HOME
# under $_HI_WORKDIR/<name> holding a tree at <path>/<tree-name>, printed. No rc
# line: the cases that want one add it themselves, so "an installed tree nothing
# points at" stays a shape the suite can build. <tree-name> defaults to say-hi
# and is `hi.d` for the cases covering targets installed before the rename.
function _hi_probe_home() {
  local home="$_HI_WORKDIR/$1" tree="$_HI_WORKDIR/$1/${2#/}" name="${3:-say-hi}"
  rm -rf "$home"
  mkdir -p "$tree/$name/common" "$home/.config/fish"
  : >"$tree/$name/hi.sh"
  chmod +x "$tree/$name/hi.sh"
  : >"$tree/$name/common/paths.sh"
  printf '%s' "$home"
}

# _hi_probe_add_tree <home> <tree-parent-relative-path> <tree-name> - a second
# tree beside one _hi_probe_home already built, for the both-names cases
function _hi_probe_add_tree() {
  local tree="$1/${2#/}" name="$3"
  mkdir -p "$tree/$name/common"
  : >"$tree/$name/hi.sh"
  chmod +x "$tree/$name/hi.sh"
  : >"$tree/$name/common/paths.sh"
}

# what a target would answer, run through a real sh
function _hi_probe_answer() {
  HOME="$1" sh -c "$(_hi_remote_root_probe)"
}

function test_remote_probe_finds_the_default_tree() {
  local home
  home="$(_hi_probe_home probe_default .)"
  [ "$(_hi_probe_answer "$home")" = "$home/say-hi" ]
}

# the whole point: a curated tree somewhere else, named by the export
# install.sh put in .bashrc, is found rather than copied over
function test_remote_probe_finds_a_nested_tree_from_bashrc() {
  local home
  home="$(_hi_probe_home probe_bashrc opt/nested)"
  printf 'export _HI_HOME="%s/opt/nested"\n' "$home" >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/nested/say-hi" ]
}

function test_remote_probe_reads_the_fish_dialect() {
  local home
  home="$(_hi_probe_home probe_fish opt/nested)"
  printf 'set -gx _HI_HOME "%s/opt/nested"\n' "$home" >"$home/.config/fish/config.fish"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/nested/say-hi" ]
}

function test_remote_probe_reads_the_zsh_rc() {
  local home
  home="$(_hi_probe_home probe_zsh opt/nested)"
  printf 'export _HI_HOME="%s/opt/nested"\n' "$home" >"$home/.zshrc"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/nested/say-hi" ]
}

# $HOME/say-hi stays the fallback, so a target that says nothing still resolves
function test_remote_probe_falls_back_to_home_when_the_rc_says_nothing() {
  local home
  home="$(_hi_probe_home probe_fallback .)"
  printf 'export PATH="$PATH:/nowhere"\n' >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/say-hi" ]
}

# a stale export outliving the tree it named must not be the answer, and must
# not stop the fallback from being one
function test_remote_probe_skips_a_path_with_no_tree_on_it() {
  local home
  home="$(_hi_probe_home probe_stale .)"
  printf 'export _HI_HOME="%s/gone"\n' "$home" >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/say-hi" ]
}

# nothing installed anywhere is an empty answer, which is what sends hi down
# the payload path
function test_remote_probe_is_silent_with_no_tree_at_all() {
  local home="$_HI_WORKDIR/probe_none"
  rm -rf "$home"
  mkdir -p "$home"
  [ -z "$(_hi_probe_answer "$home")" ]
}

# --- the hi.d fallback -------------------------------------------------------
#
# The tree was renamed hi.d -> say-hi and the probe reads what a *target* wrote,
# so it accepts both names. These are the cases that keep that true: dropping
# the old name would turn every un-updated permanent install into a disposable
# copy, which is silent - the session still works, it just stops being the
# target's own tree and starts costing a payload.

function test_remote_probe_finds_an_old_named_tree() {
  local home
  home="$(_hi_probe_home probe_old . hi.d)"
  [ "$(_hi_probe_answer "$home")" = "$home/hi.d" ]
}

function test_remote_probe_finds_an_old_named_tree_from_bashrc() {
  local home
  home="$(_hi_probe_home probe_old_nested opt/nested hi.d)"
  printf '%-45s %s\n' "export _HI_HOME=\"$home/opt/nested\"" "$_HI_MARKER" >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/nested/hi.d" ]
}

# a half-finished migration: the renamed tree is the one being kept, so it wins
function test_remote_probe_prefers_the_new_name_when_both_exist() {
  local home
  home="$(_hi_probe_home probe_both .)"
  _hi_probe_add_tree "$home" . hi.d
  [ "$(_hi_probe_answer "$home")" = "$home/say-hi" ]
}

# the packaged install's snippet is named after the tree too, so both are read
function test_remote_probe_reads_the_old_packaging_profile_snippet() {
  [[ "$(_hi_remote_root_probe)" == */etc/profile.d/hi.d.sh* ]]
}

# The line install.sh actually writes, marker and padding included - the probe
# reads real rc files, so the shape config_shell pads onto them is the shape
# that has to parse. A hand-written unquoted export works too.
function test_remote_probe_reads_the_marker_padded_line() {
  local home
  home="$(_hi_probe_home probe_marker opt/nested)"
  printf '%-45s %s\n' "export _HI_HOME=\"$home/opt/nested\"" "$_HI_MARKER" >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/nested/say-hi" ]
}

function test_remote_probe_reads_an_unquoted_export() {
  local home
  home="$(_hi_probe_home probe_unquoted opt/nested)"
  printf 'export _HI_HOME=%s/opt/nested\n' "$home" >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/nested/say-hi" ]
}

# a packaged install writes no rc line anywhere - /etc/profile.d is the only
# place it can say where the tree went, so the probe reads that too
function test_remote_probe_reads_the_packaging_profile_snippet() {
  [[ "$(_hi_remote_root_probe)" == */etc/profile.d/say-hi.sh* ]]
}

# The cases above retype install.sh's format. This one has install.sh write the
# rc itself, so a change to tmpdir_line's quoting or config_shell's padding
# turns this red instead of silently blinding the probe on every real target.
function test_remote_probe_reads_what_install_sh_actually_wrote() {
  local home
  home="$(_hi_probe_home probe_real opt/nested)"
  # a real bash, not a subshell: sourcing install.sh here would land its
  # functions in this suite's shell. tmpdir_line's $2 names the tree, the same
  # override packaging mode uses - install.sh derives its own $_HI_HOME.
  bash -c '
    _i="$1" _h="$2"
    set -- # install.sh reads "$@" for its own args
    source "$_i"
    config_shell bashrc "$_h/.bashrc" "$(tmpdir_line sh "$_h/opt/nested")"
  ' bash "$_HI_INSTALL" "$home" >/dev/null 2>&1
  [ "$(_hi_probe_answer "$home")" = "$home/opt/nested/say-hi" ]
}

# The probe restates the rc roster core.sh single-homes as _HI_SHELL_TABLE.
# Every shell install.sh writes a tree line for has to be a candidate here, or
# a target running that shell goes invisible and gets the payload copied over
# a curated tree.
function test_remote_probe_covers_every_rc_in_the_roster() {
  local probe rel _shell _label _tree_rc _home_rc _rest
  probe="$(_hi_remote_root_probe)"
  while IFS='|' read -r _shell _label _tree_rc _home_rc _rest; do
    rel="${_home_rc#"$HOME/"}"
    case "$probe" in *"$rel"*) ;; *) return 1 ;; esac
  done < <(_hi_shell_rows local)
}

# an install path with a space in it survives the candidate list
function test_remote_probe_handles_a_path_with_a_space() {
  local home
  home="$(_hi_probe_home probe_space "opt/my trees")"
  printf 'export _HI_HOME="%s/opt/my trees"\n' "$home" >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/my trees/say-hi" ]
}

# and one with a `#` in it: the value is quoted, so the marker strip must not
# treat the first `#` on the line as the start of the comment. This is the case
# the unwrapping sed's expression *order* exists for - reversed, it answers
# "$home/opt/hash" and the probe silently falls back to $HOME/say-hi.
function test_remote_probe_handles_a_path_with_a_hash() {
  local home
  home="$(_hi_probe_home probe_hash "opt/hash#tree")"
  printf '%-45s %s\n' "export _HI_HOME=\"$home/opt/hash#tree\"" "$_HI_MARKER" >"$home/.bashrc"
  [ "$(_hi_probe_answer "$home")" = "$home/opt/hash#tree/say-hi" ]
}

# an interactive session chainloads load.sh then calls load()
function test_bootloader_calls_load_for_a_session() {
  local out
  out="$(CMDARG="" _hi_bootloader)"
  # shellcheck disable=SC2016 # the rc must carry a literal $_HI_ROOT for the target to expand
  [[ "$out" == *'source $_HI_ROOT/load.sh'* && "$out" == *$'\nload'* ]]
}

# ...and a one-off command replaces that call outright, so load() - and with
# it the header, the rc grafting and clean_all - never runs
function test_bootloader_replaces_load_with_the_command() {
  local out
  out="$(CMDARG='echo hi; exit' _hi_bootloader)"
  [[ "$out" == *'echo hi; exit'* && "$out" != *$'\nload\n'* ]]
}

# load.sh sets `-euo pipefail` at source time and only load() clears it, but
# the $CMDARG shape replaces load() outright - so the bootloader has to clear
# it itself or the user's command runs with an unset variable being fatal and
# any non-zero status ending the session. That killed `source $_HI_ALIASES` on
# any target without explicit toggles, which is the default.
function test_bootloader_drops_strict_mode_before_the_command() {
  _hi_before "$(CMDARG='echo hi' _hi_bootloader)" 'set +euo pipefail' 'echo hi'
}

# ...and the strict-mode reset must land after load.sh is sourced, not before,
# or it's simply overwritten by load.sh's own `set -euo pipefail`
function test_bootloader_drops_strict_mode_after_sourcing_load() {
  _hi_before "$(CMDARG='echo hi' _hi_bootloader)" 'load\.sh' 'set +euo pipefail'
}

function test_fallback_rc_sources_paths_and_aliases() {
  local out
  out="$(CMDARG="" _hi_fallback_rc)"
  # shellcheck disable=SC2016 # same as above - $_HI_ROOT is the target's to expand
  [[ "$out" == *'$_HI_ROOT/common/paths.sh'* && "$out" == *'$_HI_ROOT/misc/aliases.sh'* ]]
}

function test_fallback_rc_appends_the_command() {
  [[ "$(CMDARG='echo hi; exit' _hi_fallback_rc)" == *'echo hi; exit'* ]]
}

# the no-bash target is one of the four entry points that has to source the
# settings ahead of paths.sh - paths.sh's local-only gate reads them, so lines
# arriving after it would be set too late to have any effect
function test_fallback_rc_sources_settings_before_paths() {
  _hi_before "$(CMDARG="" _hi_fallback_rc)" 'config/settings\.sh' 'common/paths\.sh'
}

# bash reads an --rcfile only when it is interactive, and decides that from its
# own stdin rather than the flag - so without the explicit -i, a target reached
# with no local tty (`ssh -t` can't allocate one then) silently ignores
# hi.bashrc, taking load.sh and $CMDARG with it, and `hi <target> <command>`
# from a script or a pipe does nothing at all while still exiting 0.
# The flag order is part of the assertion, not incidental: bash parses its GNU
# long options in a pass that ends at the first short one, so `bash -i --rcfile
# f` exits with "--: invalid option" and no shell at all.
# $hi_esc/$nc_esc/$DOMAIN are _say_hi's locals, supplied here because this file
# runs under `set -u`.
function test_remote_suffix_forces_an_interactive_bash() {
  # shellcheck disable=SC2016 # $_hi_rc_dir is the target's to expand, not ours
  [[ "$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)" == *'bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'* ]]
}

# the mirror of the above: every fallback shell already starts explicitly
# interactive, which is why they kept working when the bash arm didn't
function test_remote_suffix_fallbacks_are_interactive() {
  local out
  out="$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)"
  [[ "$out" == *'zsh -i'* && "$out" == *'sh -i'* && "$out" == *'fish -C'* ]]
}

# The dispatch is executed, not sourced: --version lives in the trailing case
# below the source guard, which sourcing (this suite's usual route) never
# reaches.

# a packager's stamp (here stood in for by the env seam) wins outright
function test_version_prints_the_stamp() {
  [ "$(_HI_RELEASE=1.2.3 bash "$_HI_LAUNCHER" --version)" = "1.2.3" ]
}

# an unstamped checkout answers with git describe (--always: a bare commit
# hash before any tag exists), never with "unknown"
function test_version_falls_back_to_git_describe() {
  [ -d "$_HI_ROOT/.git" ] || return 0 # nothing to describe in a tarball tree
  local out
  out="$(_HI_RELEASE="" _hi_version)"
  [ -n "$out" ] && [[ "$out" != unknown* ]]
}

# ...and with neither stamp nor git, it says so instead of printing nothing
function test_version_is_candid_without_stamp_or_git() {
  [[ "$(_HI_RELEASE="" _HI_ROOT="$_HI_WORKDIR" _hi_version)" == unknown* ]]
}

# the version rides the preamble so the target's header can show it
function test_remote_preamble_exports_the_version() {
  [[ "$(DOMAIN=host _hi_remote_preamble)" == *'export _HI_RELEASE='* ]]
}

# ...and so does the client's glyph verdict: the glyphs render in the
# client's terminal, so the target must not re-probe its own locale
function test_remote_preamble_ships_the_glyph_verdict() {
  [[ "$(DOMAIN=host _HI_ASCII=1 _hi_remote_preamble)" == *'export _HI_ASCII="1"'* ]] &&
    [[ "$(DOMAIN=host _HI_ASCII="" LC_ALL=en_US.UTF-8 _hi_remote_preamble)" == *'export _HI_ASCII="0"'* ]]
}

# The generated preamble is executed under a real sh with a controlled TERM
# and terminfo fixture, and the TERM it leaves behind is the assertion. Names
# invented here can't exist in the host's terminfo trees, so the host's own
# entries can't leak into the result.

function _hi_preamble_final_term() { # <env assignments...> - prints $TERM after the preamble ran
  local script
  script="$(DOMAIN=host _hi_remote_preamble)"
  # shellcheck disable=SC2016 # $TERM is the spawned sh's to expand, not ours
  env "$@" sh -c "$script"'
printf %s "$TERM"' 2>/dev/null
}

function test_term_fallback_swaps_an_unknown_term() {
  [ "$(_hi_preamble_final_term TERM=hi-test-no-such-term)" = xterm-256color ]
}

function test_term_fallback_keeps_a_term_with_terminfo() {
  local ti="$_HI_WORKDIR/terminfo"
  mkdir -p "$ti/h"
  : >"$ti/h/hi-test-present-term"
  [ "$(_hi_preamble_final_term TERM=hi-test-present-term TERMINFO="$ti")" = hi-test-present-term ]
}

function test_term_fallback_skips_ubiquitous_names() {
  [ "$(_hi_preamble_final_term TERM=xterm)" = xterm ]
}

function test_term_fallback_can_be_disabled() {
  [ "$(_hi_preamble_final_term TERM=hi-test-no-such-term _HI_TERM_FALLBACK=0)" = hi-test-no-such-term ]
}

# On a target, $_HI_CONFIG_DIR is the config/ the overlay was unpacked into,
# not ${XDG_CONFIG_HOME:-...}: a ~/.config/say-hi belonging to whoever we logged
# in as is not the config this session was asked to run with. It must also not
# be misc/, which holds the *shipped* aliases.sh - pointed there,
# misc/aliases.sh's tail line sources itself forever.
function test_fallback_rc_points_config_dir_at_the_overlay() {
  # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand, not ours
  [[ "$(CMDARG="" _hi_fallback_rc)" == *'export _HI_CONFIG_DIR=$_HI_ROOT/config'* ]]
}

function run_hi_remote_tests() {
  _hi_workdir hiremotetest

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the target-side strings"

  _hi_h2 "Testing: bootloader / fallback rc"
  _hi_check "A session calls load" test_bootloader_calls_load_for_a_session
  _hi_check "A command replaces load" test_bootloader_replaces_load_with_the_command
  _hi_check "Bootloader drops strict mode before the command" test_bootloader_drops_strict_mode_before_the_command
  _hi_check "Bootloader drops strict mode after sourcing load.sh" test_bootloader_drops_strict_mode_after_sourcing_load
  _hi_check "Fallback rc sources paths and aliases" test_fallback_rc_sources_paths_and_aliases
  _hi_check "Fallback rc appends the command" test_fallback_rc_appends_the_command
  _hi_check "Fallback rc sources settings before paths" test_fallback_rc_sources_settings_before_paths
  _hi_check "Fallback rc points at the overlay config dir" test_fallback_rc_points_config_dir_at_the_overlay

  _hi_h2 "Testing: _hi_remote_root's target-side probe"
  _hi_check "Finds a tree at the default \$HOME/say-hi" test_remote_probe_finds_the_default_tree
  _hi_check "Finds a nested tree named by .bashrc" test_remote_probe_finds_a_nested_tree_from_bashrc
  _hi_check "Reads fish's set -gx dialect" test_remote_probe_reads_the_fish_dialect
  _hi_check "Reads .zshrc too" test_remote_probe_reads_the_zsh_rc
  _hi_check "Falls back to \$HOME when nothing says" test_remote_probe_falls_back_to_home_when_the_rc_says_nothing
  _hi_check "Reads install.sh's marker-padded line" test_remote_probe_reads_the_marker_padded_line
  _hi_check "Reads a hand-written unquoted export" test_remote_probe_reads_an_unquoted_export
  _hi_check "Skips a stale export with no tree on it" test_remote_probe_skips_a_path_with_no_tree_on_it
  _hi_check "Silent when nothing is installed" test_remote_probe_is_silent_with_no_tree_at_all
  _hi_check "Looks in the packaging profile snippet" test_remote_probe_reads_the_packaging_profile_snippet
  _hi_check "Finds a tree still named hi.d" test_remote_probe_finds_an_old_named_tree
  _hi_check "Finds a nested hi.d named by .bashrc" test_remote_probe_finds_an_old_named_tree_from_bashrc
  _hi_check "Prefers say-hi when both names exist" test_remote_probe_prefers_the_new_name_when_both_exist
  _hi_check "Reads the old packaging profile snippet" test_remote_probe_reads_the_old_packaging_profile_snippet
  _hi_check "Reads what install.sh actually wrote" test_remote_probe_reads_what_install_sh_actually_wrote
  _hi_check "Covers every rc in the shell roster" test_remote_probe_covers_every_rc_in_the_roster
  _hi_check "Handles a path with a space in it" test_remote_probe_handles_a_path_with_a_space
  _hi_check "Handles a path with a # in it" test_remote_probe_handles_a_path_with_a_hash

  _hi_h2 "Testing: remote shell handoff"
  _hi_check "The bash handoff is explicitly interactive" test_remote_suffix_forces_an_interactive_bash
  _hi_check "So is every no-bash fallback" test_remote_suffix_fallbacks_are_interactive

  _hi_h2 "Testing: hi --version"
  _hi_check "A stamp wins" test_version_prints_the_stamp
  _hi_check "A checkout answers with git describe" test_version_falls_back_to_git_describe
  _hi_check "Candid with no stamp and no git" test_version_is_candid_without_stamp_or_git
  _hi_check "The preamble exports it" test_remote_preamble_exports_the_version
  _hi_check "The preamble ships the glyph verdict" test_remote_preamble_ships_the_glyph_verdict

  _hi_h2 "Testing: the preamble's TERM fallback"
  _hi_check "Unknown TERM becomes xterm-256color" test_term_fallback_swaps_an_unknown_term
  _hi_check "A TERM with terminfo is kept" test_term_fallback_keeps_a_term_with_terminfo
  _hi_check "Ubiquitous names skip the probe" test_term_fallback_skips_ubiquitous_names
  _hi_check "_HI_TERM_FALLBACK=0 opts out" test_term_fallback_can_be_disabled
  _hi_suite_end "hi.sh (target-side strings)"
}

run_hi_remote_tests
