#!/bin/bash
# hi.d installed somewhere other than $HOME/hi.d, driven through the real
# scripts/install.sh and then read back out of a *fresh* shell in each dialect.
#
# Every path in the product resolves through $_HI_HOME/hi.d, and every entry
# point derives $_HI_HOME from its own location rather than defaulting to $HOME
# (GLOSSARY: HI.33). Both halves of that are only load-bearing when the tree is
# not at the default path, which is exactly the shape nothing else here builds:
# the e2e suites' `installed` case models a permanent install at $HOME/hi.d,
# and a developer's checkout sits elsewhere by accident rather than by
# assertion. So this suite installs to $HOME/opt/nested/hi.d and to a tree
# outside $HOME entirely, and asks the two questions that shape raises:
#
#   the rc wiring   the `export _HI_HOME=...` install.sh writes into .bashrc /
#                   .zshrc / config.fish is what carries a non-default location
#                   into a new login shell, and nothing else reads it back
#   the derivation  a tree outside $HOME with $_HI_HOME *unset* has to resolve
#                   from the file being sourced, in all four dialects
#
# Four dialects, as the four masters GLOSSARY names them. bash, zsh and fish
# each get the full pass - the tree, hi's prompt, the header, and `hi --doctor`
# through the `hi` alias - since each has an rc file install.sh wires up. sh has
# none (it is reached as a *target* fallback, not as a local login shell), so
# its arm is the one thing that path actually does: source common/paths.sh and
# resolve the tree from it.
#
# Fresh shells run under `env -i`, so the only way any of them can find hi.d is
# the wiring under test. $_HI_HOME in particular is never passed: passing it
# would answer the question the suite is asking.
#
# GLOSSARY: HI.30
# shellcheck disable=SC2329
# The single-quoted scripts below are expanded by the *child* shell (SC2016).
# shellcheck disable=SC2016
set -euo pipefail

: "${_HI_HOME:=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=../../common/core.sh
source "$_HI_HOME/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# What a tree has to hold for install.sh to run and for `hi --doctor` to
# answer: the shipped payload, plus scripts/ (install.sh, doctor.sh, table.sh),
# which no target ever gets and which every one of these cases needs.
_HI_LOC_DIRS=(common misc shells scripts)
_HI_LOC_FILES=(hi.sh load.sh)

# _hi_loc_tree <parent> - a hi.d under <parent>, printed. cp -R of four
# directories rather than the whole checkout: .git is the expensive half and
# nothing here reads it (doctor.sh reports "no .git", which is a fine answer).
function _hi_loc_tree() {
  local root="$1/hi.d" item
  mkdir -p "$root"
  for item in "${_HI_LOC_DIRS[@]}" "${_HI_LOC_FILES[@]}"; do
    cp -R "$_HI_ROOT/$item" "$root/"
  done
  chmod +x "$root/hi.sh"
  printf '%s' "$root"
}

# The nested install: a real `install.sh --no-link -y` from a tree at
# $HOME/opt/nested/hi.d, against a $HOME of this suite's own. --no-link because
# the symlink wants sudo and /usr/bin, neither of which a test may touch; -y
# because there is no tty to answer the validation prompt on.
_HI_LOC_HOME=""
_HI_LOC_PARENT=""
_HI_LOC_ROOT=""

function _hi_loc_install() {
  _HI_LOC_HOME="$_HI_WORKDIR/home"
  _HI_LOC_PARENT="$_HI_LOC_HOME/opt/nested"
  mkdir -p "$_HI_LOC_PARENT"
  _HI_LOC_ROOT="$(_hi_loc_tree "$_HI_LOC_PARENT")"
  _hi_loc_env "$_HI_LOC_ROOT/scripts/install.sh" --no-link -y >"$_HI_WORKDIR/install.log" 2>&1
}

# The controlled environment every child here runs in. `env -i` and then only
# what a login shell genuinely has: no _HI_HOME, and no _HI_CONFIG_DIR either -
# test_lib.sh exports one for the whole suite, and inheriting it would put this
# install's settings in another suite's overlay. $SHELL is set because
# install.sh reports `${SHELL##*/}` under `set -u`.
function _hi_loc_env() {
  env -i HOME="$_HI_LOC_HOME" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
    SHELL=/bin/bash XDG_CONFIG_HOME="$_HI_LOC_HOME/.config" "$@"
}

# _hi_loc_shell <shell> <script> - <script> in a fresh interactive <shell>,
# which is what makes the shell read the rc file install.sh just wrote. stdout
# only: an interactive shell with no tty is entitled to complain on stderr, and
# the assertions are about what hi produced.
function _hi_loc_shell() {
  _hi_loc_env "$1" -i -c "$2" </dev/null 2>/dev/null
}

# --- the rc wiring --------------------------------------------------------

# _hi_loc_rc_states_the_tree <rc-path> - that rc file names the nested parent
function _hi_loc_rc_states_the_tree() {
  grep -qF "_HI_HOME" "$_HI_LOC_HOME/$1" && grep -qF "$_HI_LOC_PARENT" "$_HI_LOC_HOME/$1"
}

function test_bashrc_states_the_tree() { _hi_loc_rc_states_the_tree .bashrc; }
function test_zshrc_states_the_tree() { _hi_loc_rc_states_the_tree .zshrc; }
function test_fish_config_states_the_tree() { _hi_loc_rc_states_the_tree .config/fish/config.fish; }

# the tree stays where it is: an install writes the user's rc files and the
# overlay, never the checkout it was run from
function test_the_install_wrote_nothing_into_the_tree() {
  [ ! -e "$_HI_LOC_ROOT/config" ] && [ ! -e "$_HI_LOC_ROOT/misc/settings.sh" ]
}

# --- a fresh shell in each dialect ----------------------------------------

function test_bash_resolves_the_nested_tree() {
  [ "$(_hi_loc_shell bash 'printf %s "$_HI_ROOT"')" = "$_HI_LOC_ROOT" ]
}

function test_zsh_resolves_the_nested_tree() {
  [ "$(_hi_loc_shell zsh 'printf %s "$_HI_ROOT"')" = "$_HI_LOC_ROOT" ]
}

function test_fish_resolves_the_nested_tree() {
  [ "$(_hi_loc_shell fish 'printf %s "$_HI_ROOT"')" = "$_HI_LOC_ROOT" ]
}

# sh has no rc of its own to wire up - it reaches paths.sh directly, told where
# the tree is, which is the shape hi.sh's bash-less fallback rc builds
function test_sh_sources_paths_from_the_nested_tree() {
  local out
  out="$(env -i HOME="$_HI_LOC_HOME" PATH="$PATH" _HI_HOME="$_HI_LOC_PARENT" \
    sh -c ". \"\$_HI_HOME/hi.d/common/paths.sh\"; printf %s \"\$_HI_ROOT\"" 2>/dev/null)"
  [ "$out" = "$_HI_LOC_ROOT" ]
}

# --- prompt, header, doctor ----------------------------------------------

function test_bash_has_his_prompt() {
  [ -n "$(_hi_loc_shell bash 'printf %s "${HI_PS1:-}"')" ]
}

function test_zsh_has_his_prompt() {
  [[ "$(_hi_loc_shell zsh 'printf %s "$PS1"')" == *'%~'* ]]
}

function test_fish_has_his_prompt() {
  [ "$(_hi_loc_shell fish 'functions -q fish_prompt; and echo yes')" = yes ]
}

# _hi_loc_header <shell> <script> - the banner, as that shell reaches it. The
# assertion is the same in all three: hi_header renders out of the *nested*
# tree, which only works if $_HI_HEADER resolved into it.
function _hi_loc_renders_the_header() {
  local out
  out="$(_hi_loc_shell "$1" "$2")"
  _hi_has_rendered "$out" Online
}

function test_bash_renders_the_header() {
  _hi_loc_renders_the_header bash 'source "$_HI_HEADER"; hi_header Online'
}

function test_zsh_renders_the_header() {
  _hi_loc_renders_the_header zsh 'bash -c "source $_HI_HEADER; hi_header Online"'
}

# fish's own greeting is hi's header (shells/config.fish's fish_greeting), so
# this asks for the thing a user actually sees rather than a stand-in
function test_fish_renders_the_header() {
  _hi_loc_renders_the_header fish 'fish_greeting'
}

# `hi --doctor` through the `hi` alias common/paths.sh defines - the launcher,
# the alias and doctor.sh all have to have resolved into the nested tree, and
# doctor's first row is the tree itself
function _hi_loc_doctor_names_the_tree() {
  local out
  out="$(_hi_loc_shell "$1" "$2")"
  [[ "$(_hi_strip_ansi "$out")" == *"$_HI_LOC_ROOT"* ]]
}

function test_bash_doctor_names_the_nested_tree() {
  _hi_loc_doctor_names_the_tree bash 'hi --doctor'
}

function test_zsh_doctor_names_the_nested_tree() {
  _hi_loc_doctor_names_the_tree zsh 'hi --doctor'
}

function test_fish_doctor_names_the_nested_tree() {
  _hi_loc_doctor_names_the_tree fish 'hi --doctor'
}

# sh's arm of the same two. It has no prompt of its own to check - hi styles a
# POSIX prompt only on a *target*, out of hi.sh's fallback rc - but the header
# and the launcher are both reachable from it once paths.sh has resolved, and
# both have to land in the nested tree rather than beside $HOME.
function _hi_loc_sh() {
  env -i HOME="$_HI_LOC_HOME" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
    _HI_HOME="$_HI_LOC_PARENT" XDG_CONFIG_HOME="$_HI_LOC_HOME/.config" \
    sh -c ". \"\$_HI_HOME/hi.d/common/paths.sh\"; $1" 2>/dev/null
}

function test_sh_renders_the_header() {
  _hi_has_rendered "$(_hi_loc_sh 'bash -c ". \"$_HI_HEADER\"; hi_header Online"')" Online
}

function test_sh_doctor_names_the_nested_tree() {
  [[ "$(_hi_strip_ansi "$(_hi_loc_sh '"$_HI_LAUNCHER" --doctor')")" == *"$_HI_LOC_ROOT"* ]]
}

# --- a tree outside $HOME, with $_HI_HOME unset ---------------------------
#
# The rc wiring above is one way to carry a non-default location. This is the
# other, and the one that has to hold when there is no wiring at all: a file
# that can find itself has no business guessing $HOME. $HOME here is a
# directory with no hi.d in it whatsoever, so a surviving $HOME default would
# fail loudly rather than silently reading the checkout.

_HI_LOC_OUT_ROOT=""

function _hi_loc_outside_env() {
  env -i HOME="$_HI_WORKDIR/elsewhere" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
    XDG_CONFIG_HOME="$_HI_WORKDIR/elsewhere/.config" "$@"
}

function _hi_loc_outside_resolves() {
  [ "$(_hi_loc_outside_env "$1" -c "$2" </dev/null 2>/dev/null)" = "$_HI_LOC_OUT_ROOT" ]
}

function test_outside_bash_derives_the_tree() {
  _hi_loc_outside_resolves bash "source '$_HI_LOC_OUT_ROOT/shells/bash.sh'; printf %s \"\$_HI_ROOT\""
}

function test_outside_zsh_derives_the_tree() {
  _hi_loc_outside_resolves zsh "source '$_HI_LOC_OUT_ROOT/shells/zsh.zsh'; printf %s \"\$_HI_ROOT\""
}

function test_outside_fish_derives_the_tree() {
  _hi_loc_outside_resolves fish "source '$_HI_LOC_OUT_ROOT/shells/config.fish'; printf %s \"\$_HI_ROOT\""
}

function test_outside_core_derives_the_tree() {
  _hi_loc_outside_resolves bash "source '$_HI_LOC_OUT_ROOT/common/core.sh'; printf %s \"\$_HI_ROOT\""
}

# the launcher answers rather than reporting a path nobody typed
function test_outside_launcher_runs() {
  _hi_loc_outside_env "$_HI_LOC_OUT_ROOT/hi.sh" --version >/dev/null 2>&1
}

# and through the $_HI_LINK shape: a symlink from somewhere else entirely,
# which is what a packaged install puts on $PATH. Unwalked, the link's own
# directory is the answer and the tree is invisible - so this asks doctor for
# the tree it resolved rather than merely for a zero exit.
function test_outside_launcher_runs_through_a_symlink() {
  local link="$_HI_WORKDIR/bin/hi" out
  mkdir -p "$_HI_WORKDIR/bin"
  ln -sfn "$_HI_LOC_OUT_ROOT/hi.sh" "$link"
  out="$(_hi_loc_outside_env "$link" --doctor 2>/dev/null)" || true
  [[ "$(_hi_strip_ansi "$out")" == *"$_HI_LOC_OUT_ROOT"* ]]
}

# a tree that genuinely isn't there says so, rather than sourcing a stranger
function test_a_missing_tree_is_named_and_refused() {
  local out rc=0
  out="$(_HI_HOME="$_HI_WORKDIR/nothing-here" "$_HI_LOC_OUT_ROOT/hi.sh" --version 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"no hi.d at $_HI_WORKDIR/nothing-here"* ]] &&
    [[ "$out" == *"set _HI_HOME"* ]]
}

# --- the inverse ----------------------------------------------------------

# --uninstall takes its own line back out of all three rc files, wherever the
# tree is - the half that would rot if only the install were tested
function test_uninstall_removes_the_tree_line() {
  _hi_loc_env "$_HI_LOC_ROOT/scripts/install.sh" --uninstall >/dev/null 2>&1
  ! grep -qF "$_HI_LOC_PARENT" "$_HI_LOC_HOME/.bashrc" &&
    ! grep -qF "$_HI_LOC_PARENT" "$_HI_LOC_HOME/.zshrc" &&
    ! grep -qF "$_HI_LOC_PARENT" "$_HI_LOC_HOME/.config/fish/config.fish"
}

function run_install_location_tests() {
  _hi_workdir installloctest
  _hi_h1 "Testing hi.d installed outside \$HOME/hi.d"

  _hi_loc_install
  _hi_cecho " | tree:  $_HI_LOC_ROOT" "$BLUE"
  _hi_cecho " | \$HOME: $_HI_LOC_HOME" "$BLUE"

  mkdir -p "$_HI_WORKDIR/elsewhere"
  _HI_LOC_OUT_ROOT="$(_hi_loc_tree "$_HI_WORKDIR/outside")"

  _hi_suite_begin

  _hi_h2 "Testing: the rc wiring install.sh wrote"
  _hi_check "bashrc names the tree" test_bashrc_states_the_tree
  _hi_check "zshrc names the tree" test_zshrc_states_the_tree
  _hi_check "config.fish names the tree" test_fish_config_states_the_tree
  _hi_check "The tree itself was not written to" test_the_install_wrote_nothing_into_the_tree

  _hi_h2 "Testing: a fresh shell finds the nested tree"
  _hi_check "bash" test_bash_resolves_the_nested_tree
  _hi_check_requires zsh "zsh" test_zsh_resolves_the_nested_tree
  _hi_check_requires fish "fish" test_fish_resolves_the_nested_tree
  _hi_check "sh, through common/paths.sh" test_sh_sources_paths_from_the_nested_tree

  _hi_h2 "Testing: prompt, header and hi --doctor out of it"
  _hi_check "bash has hi's prompt" test_bash_has_his_prompt
  _hi_check_requires zsh "zsh has hi's prompt" test_zsh_has_his_prompt
  _hi_check_requires fish "fish has hi's prompt" test_fish_has_his_prompt
  _hi_check "bash renders the header" test_bash_renders_the_header
  _hi_check_requires zsh "zsh renders the header" test_zsh_renders_the_header
  _hi_check_requires fish "fish renders the header" test_fish_renders_the_header
  _hi_check "bash: hi --doctor names the tree" test_bash_doctor_names_the_nested_tree
  _hi_check_requires zsh "zsh: hi --doctor names the tree" test_zsh_doctor_names_the_nested_tree
  _hi_check_requires fish "fish: hi --doctor names the tree" test_fish_doctor_names_the_nested_tree
  _hi_check "sh renders the header" test_sh_renders_the_header
  _hi_check "sh: hi --doctor names the tree" test_sh_doctor_names_the_nested_tree

  _hi_h2 "Testing: a tree outside \$HOME, with \$_HI_HOME unset"
  _hi_check "bash.sh derives it" test_outside_bash_derives_the_tree
  _hi_check_requires zsh "zsh.zsh derives it" test_outside_zsh_derives_the_tree
  _hi_check_requires fish "config.fish derives it" test_outside_fish_derives_the_tree
  _hi_check "core.sh derives it" test_outside_core_derives_the_tree
  _hi_check "hi.sh runs from it" test_outside_launcher_runs
  _hi_check "hi.sh runs through a symlink onto it" test_outside_launcher_runs_through_a_symlink
  _hi_check "A missing tree is named and refused" test_a_missing_tree_is_named_and_refused

  _hi_h2 "Testing: install.sh --uninstall"
  _hi_check "Takes the tree line back out" test_uninstall_removes_the_tree_line

  _hi_suite_end "a non-default install location"
}

run_install_location_tests
