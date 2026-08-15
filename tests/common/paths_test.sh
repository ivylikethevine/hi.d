#!/bin/bash
# Unit tests for common/paths.sh's local-only gate - the six-var flip at the
# bottom of the file, which is real branching logic and the whole point of the
# _HI_DISABLE_LOCAL feature.
#
# The gate turns every toggle off on the machine hi.d is *installed* on while
# leaving them on when that machine says `hi` elsewhere, told apart by
# _HI_REMOTE_SESSION - which load.sh exports on a remote session and a local
# shell's own rc never does. Getting that backwards would either strip hi from
# every target or leave it running where the user asked it not to, and nothing
# asserted either direction before this file.
#
# paths.sh is sourced rather than executed, in a child shell per case so one
# case's exports can't leak into the next. Each case reads the vars back out
# of that child, which is also what proves the settings file is picked up
# ahead of the gate rather than after it.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_GATED_VARS=(_HI_DISABLE_HEADER _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL
  _HI_DISABLE_GIT_STATUS _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES)

# Source paths.sh in a child shell with $1/$2 as the two gate inputs, then
# print "<var>=<value>" for every toggle the gate governs. bootstrap.sh does
# the defaulting paths.sh relies on ( _HI_DISABLE_LOCAL / _HI_REMOTE_SESSION
# both have to exist), so the child goes through it exactly like a real shell.
function _hi_gate() {
  _HI_DISABLE_LOCAL="$1" _HI_REMOTE_SESSION="$2" bash -c '
    source "$_HI_HOME/hi.d/common/bootstrap.sh"
    for v in "$@"; do printf "%s=%s\n" "$v" "${!v:-}"; done
  ' _ "${_HI_GATED_VARS[@]}"
}

function _hi_all_gated() {
  local out="$1" want="$2" v
  for v in "${_HI_GATED_VARS[@]}"; do
    printf '%s\n' "$out" | grep -qxF "$v=$want" || {
      _hi_cecho " | $v is not $want: $(printf '%s\n' "$out" | grep "^$v=")" "$RED"
      return 1
    }
  done
}

# _HI_DISABLE_LOCAL=1 on the install machine itself: hi stays out of the way
function test_local_only_disables_every_toggle_locally() {
  _hi_all_gated "$(_hi_gate 1 0)" 1
}

# ...but the same setting must not follow the user onto a target, which is the
# entire reason the gate looks at _HI_REMOTE_SESSION at all.
#
# "Not disabled" is an explicit 0 rather than an empty value: the entry points
# default every toggle so that aliases.sh and config.fish, which read them
# bare, can't blow up under `set -u`. Asserting 0 here is what keeps that true.
function test_local_only_leaves_a_remote_session_alone() {
  _hi_all_gated "$(_hi_gate 1 1)" 0
}

function test_toggles_stay_on_without_local_only() {
  _hi_all_gated "$(_hi_gate 0 0)" 0
}

function test_toggles_stay_on_remotely_without_local_only() {
  _hi_all_gated "$(_hi_gate 0 1)" 0
}

# the gate is the last thing paths.sh does and it ends in `|| true`, so a
# no-flip run must still leave the file sourceable under set -e
function test_paths_sources_cleanly_under_strict_mode() {
  _HI_DISABLE_LOCAL=0 _HI_REMOTE_SESSION=0 bash -c '
    set -euo pipefail
    source "$_HI_HOME/hi.d/common/bootstrap.sh"
    [ -n "$_HI_ROOT" ]
  '
}

# $_HI_SETTINGS is sourced *ahead* of paths.sh precisely so the gate can read
# what install.sh wrote. A settings file arriving after it would parse fine
# and do nothing, which is the failure this catches.
function test_settings_are_visible_to_the_gate() {
  local home
  home="$(_hi_scratch_tree tree common misc shells)"
  printf 'export _HI_DISABLE_LOCAL=1\n' >"$home/hi.d/misc/settings.sh"
  # _HI_DISABLE_LOCAL comes only from the settings file here, so every toggle
  # flipping proves the gate saw it
  _hi_all_gated "$(_HI_HOME="$home" _hi_gate 0 0)" 1
}

# --- toggle defaults --------------------------------------------------------
#
# shells/aliases.sh and shells/config.fish read the toggles bare, and neither
# can use ${X:-0} because fish sources both and has no such expansion. So the
# entry points guarantee the variables exist instead. Getting this wrong is
# invisible until something runs under `set -u`, where an unset toggle is fatal
# rather than empty - which is exactly how `hi <target> <command>` broke.

function _hi_defaults_via() {
  bash -c "$1"' ; for v in '"${_HI_GATED_VARS[*]}"' _HI_DISABLE_LOCAL _HI_REMOTE_SESSION; do
    printf "%s=%s\n" "$v" "${!v-UNSET}"; done'
}

function _hi_none_unset() {
  local out="$1" v
  for v in "${_HI_GATED_VARS[@]}" _HI_DISABLE_LOCAL _HI_REMOTE_SESSION; do
    printf '%s\n' "$out" | grep -qxF "$v=UNSET" && {
      _hi_cecho " | $v is still unset" "$RED"
      return 1
    }
  done
  return 0
}

function test_bootstrap_defines_every_toggle() {
  # shellcheck disable=SC2016 # this is source for a child bash, not for us
  _hi_none_unset "$(_hi_defaults_via 'source "$_HI_HOME/hi.d/common/bootstrap.sh"')"
}

# shared.sh is reached directly, without bootstrap, by config.fish's `bash -c`
function test_shared_defines_every_toggle() {
  # shellcheck disable=SC2016 # this is source for a child bash, not for us
  _hi_none_unset "$(_hi_defaults_via 'source "$_HI_HOME/hi.d/common/shared.sh"')"
}

# the whole point: sourcing aliases.sh under `set -u` must not be fatal
function test_aliases_source_cleanly_under_nounset() {
  bash -c 'set -euo pipefail
    source "$_HI_HOME/hi.d/common/bootstrap.sh"
    source "$_HI_ALIASES"' 2>/dev/null
}

function test_settings_beat_the_defaults() {
  local home
  home="$(_hi_scratch_tree prec common misc shells)"
  printf 'export _HI_DISABLE_PROMPT=1\n' >"$home/hi.d/misc/settings.sh"
  [ "$(_HI_HOME="$home" bash -c \
    'source "$_HI_HOME/hi.d/common/bootstrap.sh"; printf "%s" "$_HI_DISABLE_PROMPT"')" = 1 ]
}

# an explicit export from the caller's environment outranks the default too,
# which is what makes `_HI_DISABLE_PROMPT=1 bash` work as a one-off
function test_environment_beats_the_defaults() {
  [ "$(_HI_DISABLE_EDITORS=1 bash -c \
    'source "$_HI_HOME/hi.d/common/bootstrap.sh"; printf "%s" "$_HI_DISABLE_EDITORS"')" = 1 ]
}

# --- the config overlay -----------------------------------------------------
#
# settings/colors/packages each resolve to $_HI_CONFIG_DIR's copy when the user
# has made one and to the tree's otherwise, per file rather than all-or-nothing.
# That is what keeps configuring hi.d from dirtying the checkout - and what lets
# the tree be root-owned, which is the whole reason a distro package can work.
#
# test_lib.sh points $_HI_CONFIG_DIR at a scratch path that doesn't exist, so
# the un-overridden direction is the default here and a real ~/.config/hi.d
# can't decide the result.

# Print $1's value from a child shell that went through bootstrap, with
# $_HI_CONFIG_DIR pointed at $2.
function _hi_resolved() {
  _HI_CONFIG_DIR="$2" bash -c \
    'source "$_HI_HOME/hi.d/common/bootstrap.sh"; printf "%s" "${!1}"' _ "$1"
}

function _hi_overlay_dir() {
  local dir="$_HI_WORKDIR/overlay"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

function test_overlay_settings_win() {
  local dir
  dir="$(_hi_overlay_dir)"
  printf '#!/bin/sh\n' >"$dir/settings.sh"
  [ "$(_hi_resolved _HI_SETTINGS "$dir")" = "$dir/settings.sh" ]
}

function test_overlay_colors_win() {
  local dir
  dir="$(_hi_overlay_dir)"
  printf 'hostname,foo,brred\n' >"$dir/colors"
  [ "$(_hi_resolved _HI_COLORS "$dir")" = "$dir/colors" ]
}

# per file, not all-or-nothing: an overlay holding only colors must leave
# packages tracking the tree, or `hi_update` would stop delivering new defaults
# for everything the user never overrode
function test_overlay_falls_back_per_file() {
  local dir
  dir="$(_hi_overlay_dir)"
  printf 'hostname,foo,brred\n' >"$dir/colors"
  rm -f "$dir/packages"
  [ "$(_hi_resolved _HI_PACKAGES "$dir")" = "$_HI_ROOT/misc/packages" ]
}

function test_no_overlay_uses_the_tree() {
  local dir="$_HI_WORKDIR/no-such-overlay"
  [ "$(_hi_resolved _HI_COLORS "$dir")" = "$_HI_ROOT/misc/colors" ] &&
    [ "$(_hi_resolved _HI_SETTINGS "$dir")" = "$_HI_ROOT/misc/settings.sh" ]
}

# install.sh needs somewhere to write on a machine that has no overlay yet, so
# this one is unguarded and always points at the overlay
function test_settings_write_always_points_at_the_overlay() {
  local dir="$_HI_WORKDIR/no-such-overlay"
  [ "$(_hi_resolved _HI_SETTINGS_WRITE "$dir")" = "$dir/settings.sh" ]
}

# the gate reads what install.sh wrote, and after this change that file is the
# overlay's - so the ordering test above has to hold from there too
function test_overlay_settings_are_visible_to_the_gate() {
  local dir home
  dir="$(_hi_overlay_dir)"
  home="$(_hi_scratch_tree overlaygate common misc shells)"
  printf 'export _HI_DISABLE_LOCAL=1\n' >"$dir/settings.sh"
  _hi_all_gated "$(_HI_HOME="$home" _HI_CONFIG_DIR="$dir" _hi_gate 0 0)" 1
}

function run_paths_tests() {
  _hi_workdir pathstest

  _hi_h1 "Testing common/paths.sh's local-only gate"

  _hi_suite_begin

  _hi_h2 "Testing: _HI_DISABLE_LOCAL / _HI_REMOTE_SESSION"
  _hi_check "Local-only disables every toggle locally" test_local_only_disables_every_toggle_locally
  _hi_check "Local-only leaves a remote session alone" test_local_only_leaves_a_remote_session_alone
  _hi_check "Toggles stay on without local-only" test_toggles_stay_on_without_local_only
  _hi_check "Toggles stay on remotely without local-only" test_toggles_stay_on_remotely_without_local_only
  _hi_check "Sources cleanly under strict mode" test_paths_sources_cleanly_under_strict_mode

  _hi_h2 "Testing: misc/settings.sh reaches the gate"
  _hi_check "Settings are visible to the gate" test_settings_are_visible_to_the_gate

  _hi_h2 "Testing: the toggles are always defined"
  _hi_check "bootstrap.sh defines every toggle" test_bootstrap_defines_every_toggle
  _hi_check "shared.sh defines every toggle" test_shared_defines_every_toggle
  _hi_check "aliases.sh sources cleanly under set -u" test_aliases_source_cleanly_under_nounset
  _hi_check "Settings beat the defaults" test_settings_beat_the_defaults
  _hi_check "The environment beats the defaults" test_environment_beats_the_defaults

  _hi_h2 "Testing: the \$_HI_CONFIG_DIR overlay"
  _hi_check "Overlay settings win" test_overlay_settings_win
  _hi_check "Overlay colors win" test_overlay_colors_win
  _hi_check "Falls back per file" test_overlay_falls_back_per_file
  _hi_check "No overlay uses the tree" test_no_overlay_uses_the_tree
  _hi_check "Settings are written to the overlay" test_settings_write_always_points_at_the_overlay
  _hi_check "Overlay settings reach the gate" test_overlay_settings_are_visible_to_the_gate

  _hi_suite_end "paths.sh"
}

run_paths_tests
