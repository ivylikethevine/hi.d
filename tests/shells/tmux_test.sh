#!/bin/bash
# Unit tests for the tmux integration: misc/tmux.conf, the `tmux` alias, and the
# overlay/path plumbing behind both. Two assertions matter and are invisible
# until someone is inside a multiplexer on a remote box: the alias must not
# exist on a disposable tree ($_HI_CLEANUP), whose deletion a detached tmux
# would outlive, and the config must forward the _HI_* variables, or a new
# window gets a shell that cannot find hi.
#
# GLOSSARY: HI.30
# shellcheck disable=SC2329
set -euo pipefail

# test_lib.sh sources core.sh itself; $_HI_TEST_LIB wins under the runner
# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

# tmux itself is the parser: -f is only read when a *server* starts, so this
# starts a throwaway one on its own socket and kills it again. A syntax error
# anywhere in the file makes this exit non-zero.
function test_conf_parses() {
  tmux -f "$_HI_TMUXCONF" -L "hi-test-$$" start-server \; kill-server
}

# every variable hi's rc reads to find itself has to survive into a new window
function test_conf_forwards_the_hi_environment() {
  local var
  for var in _HI_HOME _HI_ROOT _HI_CONFIG_DIR _HI_REMOTE_SESSION; do
    grep -q "update-environment.*$var" "$_HI_TMUXCONF" || return 1
  done
}

# -ga, never -g: tmux's own default list (DISPLAY, SSH_AUTH_SOCK, ...) is not
# ours to drop, and overwriting it breaks agent forwarding inside tmux
function test_conf_appends_to_update_environment() {
  ! grep -qE '^[[:space:]]*set +-g +update-environment' "$_HI_TMUXCONF"
}

# both halves of the clipboard story - see shells/osc52.sh
function test_conf_allows_the_clipboard_escape() {
  grep -q 'set-clipboard on' "$_HI_TMUXCONF" &&
    grep -q 'allow-passthrough on' "$_HI_TMUXCONF"
}

function test_path_defaults_to_the_tree_copy() {
  [ "$_HI_TMUXCONF" = "$_HI_ROOT/misc/tmux.conf" ]
}

# same per-file overlay pair colors and packages use: a user copy in
# $_HI_CONFIG_DIR wins, and an absent one keeps tracking the tree
function test_path_prefers_a_user_copy() {
  local dir="$_HI_WORKDIR/cfg" out
  mkdir -p "$dir"
  printf '# mine\n' >"$dir/tmux.conf"
  # shellcheck disable=SC2016 # the probe expands in the child sh, not here
  out="$(env _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$dir" \
    sh -c '. "$_HI_HOME/hi.d/common/paths.sh"; printf "%s" "$_HI_TMUXCONF"')"
  [ "$out" = "$dir/tmux.conf" ]
}

# the tmux alias, asked for through test_lib.sh's _hi_alias_probe (which
# holds the fish-vs-POSIX dialect split and scrubs _HI_CLEANUP)
function test_alias_defined_on_a_permanent_tree() {
  local shell="$1"
  [ "$(_hi_alias_probe "$shell" tmux)" = yes ]
}

function test_alias_off_by_toggle() {
  local shell="$1"
  [ "$(_hi_alias_probe "$shell" tmux _HI_DISABLE_TMUX=1)" = no ]
}

# the one that matters: a disposable tree is deleted when the session ends, and
# a detached tmux would still be reading it
function test_alias_absent_on_a_disposable_tree() {
  local shell="$1"
  [ "$(_hi_alias_probe "$shell" tmux _HI_CLEANUP=/tmp/whatever.hi)" = no ]
}

# the container fallback ships aliases.sh with no paths.sh to define
# $_HI_TMUXCONF; `tmux -f ` with an empty path would fail on every invocation
function test_alias_absent_without_paths() {
  local out
  out="$(env -u _HI_TMUXCONF -u _HI_CLEANUP sh -c \
    ". $_HI_ALIASES; alias tmux >/dev/null 2>&1 && echo yes || echo no" 2>/dev/null)"
  [ "$out" = no ]
}

function test_toggle_in_core_list() {
  case " ${_HI_TOGGLES[*]} " in
  *" _HI_DISABLE_TMUX "*) return 0 ;;
  esac
  return 1
}

function test_toggle_in_fish_list() {
  grep -q '_HI_DISABLE_TMUX' "$_HI_FISH_CONFIG"
}

# tmux.conf has to ride the overlay stream like colors and packages, or a user
# copy would stay on the client and every target would get the tree's default
function test_tmux_conf_is_an_overlay_file() {
  grep -qE '^_HI_OVERLAY_FILES=\(.*tmux\.conf.*\)' "$_HI_LAUNCHER"
}

function run_tmux_test() {
  _hi_h1 "Testing the tmux integration (misc/tmux.conf, the tmux alias)"
  _hi_workdir tmuxtest
  _hi_suite_begin

  _hi_h2 "misc/tmux.conf"
  _hi_check_requires tmux "tmux parses it" test_conf_parses
  _hi_check "Forwards the hi environment to new windows" test_conf_forwards_the_hi_environment
  _hi_check "Appends to update-environment, never replaces it" test_conf_appends_to_update_environment
  _hi_check "Lets the OSC 52 escape through" test_conf_allows_the_clipboard_escape

  _hi_h2 "the path"
  _hi_check "Defaults to the tree copy" test_path_defaults_to_the_tree_copy
  _hi_check "A user copy wins" test_path_prefers_a_user_copy
  _hi_check "Rides the overlay stream" test_tmux_conf_is_an_overlay_file

  _hi_h2 "the alias"
  local shell
  for shell in sh bash zsh fish; do
    _hi_check_requires "$shell" "[$shell] defined on a permanent tree" test_alias_defined_on_a_permanent_tree "$shell"
    _hi_check_requires "$shell" "[$shell] off on _HI_DISABLE_TMUX=1" test_alias_off_by_toggle "$shell"
    _hi_check_requires "$shell" "[$shell] absent on a disposable tree" test_alias_absent_on_a_disposable_tree "$shell"
  done
  _hi_check "Absent without paths.sh (container fallback)" test_alias_absent_without_paths

  _hi_h2 "the toggle"
  _hi_check "_HI_DISABLE_TMUX in core.sh's _HI_TOGGLES" test_toggle_in_core_list
  _hi_check "_HI_DISABLE_TMUX in config.fish's copy" test_toggle_in_fish_list

  _hi_suite_end "tmux"
}

run_tmux_test
