#!/bin/bash
# Unit tests for shells/aliases.sh's two pieces of logic that aren't covered
# by tests/alias_test.sh (which only checks the file loads and everything it
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
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

_HI_SHELLS="zsh sh bash fish"

# ---- fake PATH scaffolding -------------------------------------------------

# writes a no-op executable named $2 into fake bin dir $1
function _hi_fake_bin() {
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$1/$2"
  chmod +x "$1/$2"
}

# builds an isolated bin dir under $_HI_WORKDIR containing only the named
# binaries (possibly none); nothing else on PATH is required, since every
# check below only depends on shell builtins (`.`/source, `[`/test, alias,
# export, command) plus these fakes.
function _hi_fake_path() {
  local dir="$_HI_WORKDIR/$1" bin
  shift
  mkdir -p "$dir"
  for bin in "$@"; do
    _hi_fake_bin "$dir" "$bin"
  done
  printf '%s' "$dir"
}

# first candidate (space-separated, in aliases.sh's own preference order)
# that's present in the installed set (space-separated); empty if none are
function _hi_expect_winner() {
  local candidates="$1" installed="$2" c i
  for c in $candidates; do
    for i in $installed; do
      [ "$c" = "$i" ] && { printf '%s' "$c" && return; }
    done
  done
  printf ''
}

# ---- static per-shell-family check scripts ---------------------------------
# same two scripts are reused for every scenario below; only the env passed
# to the shell invocation (PATH, flags, expected values) changes per run.

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

# ---- scenario runner --------------------------------------------------------
# runs one scenario (a set of _HI_* env vars) against one shell in a
# from-scratch environment: only $fakepath, $HOME (empty) and the vars this
# function passes through survive - nothing from the host shell leaks in.
function _hi_run_scenario() {
  local shell="$1" fakepath="$2" label="$3"
  shift 3
  local script shell_bin

  # resolved with the real (unrestricted) PATH, since $fakepath below is
  # deliberately too narrow to contain the shell binary itself
  shell_bin="$(command -v "$shell" 2>/dev/null)" || return 0 # skip cleanly, tallied separately by the caller

  if [ "$shell" = fish ]; then
    script="$_HI_FISH_CHECK"
  else
    script="$_HI_POSIX_CHECK"
  fi

  if env -i HOME="$_HI_FAKEHOME" PATH="$fakepath" _HI_ALIASES="$_HI_ALIASES" \
    _HI_NANORC="$_HI_WORKDIR/nanorc" _HI_VIMRC="$_HI_WORKDIR/vimrc" \
    _HI_DISABLE_EDITORS="${_HI_DISABLE_EDITORS:-0}" _HI_DISABLE_ALIASES="${_HI_DISABLE_ALIASES:-0}" \
    "$@" "$shell_bin" "$script" 2>"$_HI_WORKDIR/err"; then
    _hi_cecho " | $shell -- $label: OK" "$GREEN"
  else
    _hi_h3 "$shell -- $label: FAILED"
    sed 's/^/      /' "$_HI_WORKDIR/err"
    return 1
  fi
}

# ---- fallthrough scenarios --------------------------------------------------
# for each var, in the exact preference order aliases.sh itself uses: with
# every candidate installed (first should win), with only the last-resort
# candidate installed (should fall all the way through), with only a middle
# candidate installed (order-sensitivity, not just presence/absence), and
# with nothing installed at all (should degrade to empty, not error)
function run_fallthrough_tests() {
  _hi_h1 "Fallthrough (command -v a || b || ...) resolution"
  local failed=0 var last mid installed expect fakepath shell

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
      for shell in $_HI_SHELLS; do
        _hi_run_scenario "$shell" "$fakepath" "$name installed=[${installed:-none}] -> want [${expect:-empty}]" \
          _HI_CHECK_VAR="$name" _HI_EXPECT="$([ -n "$expect" ] && printf '%s/%s' "$fakepath" "$expect" || printf '')" \
          || failed=1
      done
    done
  done

  return "$failed"
}

# ---- flag-guard scenarios ---------------------------------------------------
# _HI_DISABLE_EDITORS only gates the nano/vim rcfile aliases; _HI_DISABLE_ALIASES
# returns before everything else (sudo, EDITOR, ...) but must NOT affect the
# editors block, since that sits above the guard on purpose
function run_flag_tests() {
  _hi_h1 "_HI_DISABLE_EDITORS / _HI_DISABLE_ALIASES guards"
  local failed=0 shell fakepath
  fakepath="$(_hi_fake_path fp_flags vi)"

  for combo in "0 0 1 1 1" "1 0 0 1 1" "0 1 1 0 0" "1 1 0 0 0"; do
    # shellcheck disable=SC2086 # fixed 5-field combo, splitting is intended
    set -- $combo
    local de="$1" da="$2" want_nano="$3" want_sudo="$4" want_editor="$5"
    for shell in $_HI_SHELLS; do
      _HI_DISABLE_EDITORS="$de" _HI_DISABLE_ALIASES="$da" \
        _hi_run_scenario "$shell" "$fakepath" \
        "_HI_DISABLE_EDITORS=$de _HI_DISABLE_ALIASES=$da" \
        _HI_CHECK_FLAGS=1 _HI_EXPECT_NANO="$want_nano" _HI_EXPECT_SUDO="$want_sudo" _HI_EXPECT_EDITOR_SET="$want_editor" \
        || failed=1
    done
  done

  return "$failed"
}

function run_alias_fallthrough_test() {
  _hi_h1 "Testing aliases.sh fallthrough + flag logic across shells"

  _HI_WORKDIR="$(mktemp -d -t hi.aliasfallthrough.XXXXXX)"
  _HI_FAKEHOME="$_HI_WORKDIR/home"
  mkdir -p "$_HI_FAKEHOME"
  # shellcheck disable=SC2016 # $_HI_WORKDIR is resolved when the trap fires
  _hi_on_exit 'rm -rf "$_HI_WORKDIR"'

  _hi_write_check_scripts

  local missing=""
  for shell in $_HI_SHELLS; do
    command -v "$shell" >/dev/null 2>&1 || missing="$missing $shell"
  done
  [ -n "$missing" ] && _hi_cecho " | not installed, skipped:$missing" "$YELLOW"

  local failed=0
  run_fallthrough_tests || failed=1
  run_flag_tests || failed=1

  if [ "$failed" -eq 0 ]; then
    _hi_h1 "All fallthrough + flag scenarios passed on every installed shell"
  else
    _hi_h1 "One or more fallthrough + flag scenarios FAILED"
  fi
  exit "$failed"
}

run_alias_fallthrough_test
