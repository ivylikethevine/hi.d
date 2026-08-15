#!/bin/bash
# Unit tests for shells/aliases.sh's two pieces of logic that aren't covered
# by tests/compat/alias_test.sh (which only checks the file loads and everything it
# unconditionally defines actually landed):
#
#   1. "preferential fallthrough" - the `command -v a || command -v b || ...`
#      chains (_HI_EDITOR_BIN, _HI_EXA_BIN, _HI_EZA_BIN) that pick the first
#      installed binary from an ordered candidate list.
#   2. the _HI_DISABLE_EDITORS / _HI_DISABLE_ALIASES guards that skip parts
#      of the file wholesale.
#
# Both are run for real in zsh, sh, bash and fish against a from-scratch PATH
# containing only hand-picked no-op fake binaries, so results assert actual
# resolution behavior ("candidate X is missing, does it fall through to Y")
# rather than just "did it load" - and don't depend on what happens to be
# installed on the machine running the test.
#
# This is also the regression test for a real bug this file caught: in zsh,
# dash and POSIX sh (not bash, not fish), `command -v name` returns an
# *alias's* definition once `name` has been aliased, instead of skipping to
# the real binary - so a fallthrough chain reachable from an already-aliased
# name silently broke (e.g. $EDITOR resolved to the literal text
# "alias nano='nano --rcfile ...'" any time nano was aliased above it, which
# is the default). See the resolve-before-aliasing block at the top of
# shells/aliases.sh.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_SHELLS="zsh sh bash fish"
declare -A _HI_SHELL_BIN=()

function _hi_fake_bin() {
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$1/$2"
  chmod +x "$1/$2"
}

function _hi_fake_path() {
  local dir="$_HI_WORKDIR/$1" bin
  shift
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    for bin in "$@"; do
      _hi_fake_bin "$dir" "$bin"
    done
  fi
  printf '%s' "$dir"
}

function _hi_expect_winner() {
  local candidates="$1" installed="$2" c i
  for c in $candidates; do
    for i in $installed; do
      [ "$c" = "$i" ] && { printf '%s' "$c" && return; }
    done
  done
  printf ''
}

function _hi_write_check_scripts() {
  _HI_POSIX_CHECK="$_HI_WORKDIR/posix_check.sh"
  _HI_FISH_CHECK="$_HI_WORKDIR/fish_check.fish"

  cat >"$_HI_POSIX_CHECK" <<'EOF'
. "$_HI_ALIASES" || exit 1
fail=0

if [ -n "${_HI_CHECK_VAR:-}" ]; then
  case "$_HI_CHECK_VAR" in
  EDITOR_BIN) actual=$_HI_EDITOR_BIN ;;
  EXA_BIN) actual=$_HI_EXA_BIN ;;
  EZA_BIN) actual=$_HI_EZA_BIN ;;
  esac
  [ "$actual" = "$_HI_EXPECT" ] || { echo "$_HI_CHECK_VAR: got [$actual] want [$_HI_EXPECT]" >&2; fail=1; }
fi

if [ -n "${_HI_CHECK_FLAGS:-}" ]; then
  if [ "$_HI_EXPECT_NANO" = 1 ]; then
    alias nano >/dev/null 2>&1 || { echo "expected nano alias, missing" >&2; fail=1; }
  else
    alias nano >/dev/null 2>&1 && { echo "expected no nano alias, but found one" >&2; fail=1; }
  fi
  if [ "$_HI_EXPECT_SUDO" = 1 ]; then
    alias sudo >/dev/null 2>&1 || { echo "expected sudo alias, missing" >&2; fail=1; }
  else
    alias sudo >/dev/null 2>&1 && { echo "expected no sudo alias, but found one" >&2; fail=1; }
  fi
  if [ "$_HI_EXPECT_EDITOR_SET" = 1 ]; then
    [ -n "${EDITOR:-}" ] || { echo "expected EDITOR set, got empty" >&2; fail=1; }
  else
    [ -z "${EDITOR:-}" ] || { echo "expected EDITOR unset, got [$EDITOR]" >&2; fail=1; }
  fi
fi

exit $fail
EOF

  cat >"$_HI_FISH_CHECK" <<'EOF'
source "$_HI_ALIASES"; or exit 1
set fail 0

if set -q _HI_CHECK_VAR
  switch "$_HI_CHECK_VAR"
  case EDITOR_BIN
    set actual $_HI_EDITOR_BIN
  case EXA_BIN
    set actual $_HI_EXA_BIN
  case EZA_BIN
    set actual $_HI_EZA_BIN
  end
  if [ "$actual" != "$_HI_EXPECT" ]
    echo "$_HI_CHECK_VAR: got [$actual] want [$_HI_EXPECT]" >&2
    set fail 1
  end
end

if set -q _HI_CHECK_FLAGS
  if test "$_HI_EXPECT_NANO" = 1
    functions -q -- nano; or begin; echo "expected nano alias, missing" >&2; set fail 1; end
  else
    functions -q -- nano; and begin; echo "expected no nano alias, but found one" >&2; set fail 1; end
  end
  if test "$_HI_EXPECT_SUDO" = 1
    functions -q -- sudo; or begin; echo "expected sudo alias, missing" >&2; set fail 1; end
  else
    functions -q -- sudo; and begin; echo "expected no sudo alias, but found one" >&2; set fail 1; end
  end
  if test "$_HI_EXPECT_EDITOR_SET" = 1
    set -q EDITOR; or begin; echo "expected EDITOR set, got empty" >&2; set fail 1; end
  else
    set -q EDITOR; and begin; echo "expected EDITOR unset, got [$EDITOR]" >&2; set fail 1; end
  end
end

exit $fail
EOF
}

function _hi_run_scenario() {
  local shell="$1" fakepath="$2" label="$3"
  shift 3
  local script shell_bin t0 t1

  # resolved against the real (unrestricted) PATH by the caller's one-time
  # probe, since $fakepath below is deliberately too narrow to contain the
  # shell binary itself; only installed shells ever reach here
  shell_bin="${_HI_SHELL_BIN[$shell]}"

  if [ "$shell" = fish ]; then
    script="$_HI_FISH_CHECK"
  else
    script="$_HI_POSIX_CHECK"
  fi

  t0="$(_hi_now)"
  if env -i HOME="$_HI_FAKEHOME" PATH="$fakepath" _HI_ALIASES="$_HI_ALIASES" \
    _HI_NANORC="$_HI_WORKDIR/nanorc" _HI_VIMRC="$_HI_WORKDIR/vimrc" \
    _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS:-0}" _HI_DISABLE_ALIASES="${_HI_DISABLE_ALIASES:-0}" \
    "$@" "$shell_bin" "$script" 2>"$_HI_WORKDIR/err"; then
    t1="$(_hi_now)"
    _hi_cecho "  [$shell] -- $label: OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
  else
    t1="$(_hi_now)"
    _hi_h3 "[$shell] -- $label: FAILED ($(_hi_elapsed "$t0" "$t1")s)" "$RED"
    sed 's/^/      /' "$_HI_WORKDIR/err"
    return 1
  fi
}

function run_fallthrough_tests() {
  _hi_h1 "Fallthrough (command -v a || b || ...) resolution"
  local var last mid installed expect fakepath shell

  for var in EDITOR_BIN:"nano micro pico vim vi" EXA_BIN:"exa eza ls" EZA_BIN:"eza exa ls"; do
    local name="${var%%:*}" cands="${var#*:}"
    # shellcheck disable=SC2086 # word-splitting into positional candidates is intended
    set -- $cands
    eval "last=\$$#"
    mid="$2"

    for installed in "$cands" "$last" "$mid" ""; do
      expect="$(_hi_expect_winner "$cands" "$installed")"
      # shellcheck disable=SC2086 # $installed is an intentionally unquoted word list
      fakepath="$(_hi_fake_path "fp_${name}_$(echo "$installed" | tr -d ' ')" $installed)"
      for shell in $_HI_INSTALLED_SHELLS; do
        _hi_case _hi_run_scenario "$shell" "$fakepath" "$name installed=[${installed:-none}] -> want [${expect:-empty}]" \
          _HI_CHECK_VAR="$name" _HI_EXPECT="$([ -n "$expect" ] && printf '%s/%s' "$fakepath" "$expect" || printf '')"
      done
    done
  done
}

function run_flag_tests() {
  _hi_h1 "_HI_DISABLE_EDITORS / _HI_DISABLE_ALIASES guards"
  local shell fakepath
  fakepath="$(_hi_fake_path fp_flags vi)"

  for combo in "0 0 1 1 1" "1 0 0 1 1" "0 1 1 0 0" "1 1 0 0 0"; do
    # shellcheck disable=SC2086 # fixed 5-field combo, splitting is intended
    set -- $combo
    local de="$1" da="$2" want_nano="$3" want_sudo="$4" want_editor="$5"
    for shell in $_HI_INSTALLED_SHELLS; do
      _HI_DISABLE_EDITORS="$de" _HI_DISABLE_ALIASES="$da" \
        _hi_case _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_EDITORS=$de _HI_DISABLE_ALIASES=$da" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO="$want_nano" _HI_EXPECT_SUDO="$want_sudo" _HI_EXPECT_EDITOR_SET="$want_editor"
    done
  done
}

function run_alias_fallthrough_test() {
  _hi_h1 "Testing aliases.sh fallthrough + flag logic across shells"

  _hi_workdir aliasfallthrough
  _HI_FAKEHOME="$_HI_WORKDIR/home"
  mkdir -p "$_HI_FAKEHOME"

  _hi_write_check_scripts

  # Resolved once here rather than re-probed inside the scenario loops, which
  # ask the same question 64 times over. The resolved *path* is what gets
  # kept, not just the name: $fakepath is deliberately too narrow to contain
  # the shell binary, so every scenario needs the real path anyway.
  local missing="" shell
  _HI_INSTALLED_SHELLS=""
  for shell in $_HI_SHELLS; do
    if _HI_SHELL_BIN[$shell]="$(command -v "$shell" 2>/dev/null)"; then
      _HI_INSTALLED_SHELLS="$_HI_INSTALLED_SHELLS $shell"
    else
      missing="$missing $shell"
    fi
  done
  [ -n "$missing" ] && _hi_cecho " | not installed, skipped:$missing" "$YELLOW"

  _hi_suite_begin
  run_fallthrough_tests
  run_flag_tests

  _hi_suite_end "" \
    "All fallthrough + flag scenarios passed on every installed shell ($_HI_TOTAL scenarios)" \
    "$_HI_FAILED/$_HI_TOTAL fallthrough + flag scenarios FAILED"
}

run_alias_fallthrough_test
