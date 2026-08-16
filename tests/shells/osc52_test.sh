#!/bin/bash
# Unit tests for the OSC 52 clipboard feature: shells/osc52.sh (the emitter),
# the `hi_copy` alias in shells/aliases.sh, and misc/vim.rc's yank autocmd.
#
# The emitter's whole job is producing exactly the right bytes, so every case
# here reads the bytes: the escape is captured through a pipe (no controlling
# terminal, which is also the fallback path the script has to take) and matched
# against the literal sequence, not a paraphrase of it.
#
# Nearly every function below is invoked indirectly, through _hi_check's "$@",
# which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_ESC=$'\033'
_HI_BEL=$'\a'

# the emitter, run with a clean-ish env and its output captured. $1 is the text
# to copy; anything after is NAME=VALUE for the run (TMUX, TERM, ...).
function _hi_emit() {
  local text="$1"
  shift
  printf '%s' "$text" | env -u TMUX -u TERM "$@" sh "$_HI_OSC52"
}

function _hi_emits_plain() {
  local out want
  out="$(_hi_emit hello)"
  # base64 of "hello", spelled out rather than computed - a test that encodes
  # the text the same way the script does would pass on a broken encoder
  want="${_HI_ESC}]52;c;aGVsbG8=${_HI_BEL}"
  [ "$out" = "$want" ]
}

function _hi_unwrapped_payload() {
  # base64 wraps at 76 columns; a newline left in the payload lands mid-escape
  # and the terminal drops the whole sequence. 400 bytes is comfortably past
  # the wrap point.
  local text out
  text="$(printf '%*s' 400 '' | tr ' ' x)"
  out="$(_hi_emit "$text")"
  case "$out" in
  *$'\n'* | *' '*) return 1 ;;
  "${_HI_ESC}]52;c;"*"${_HI_BEL}") return 0 ;;
  esac
  return 1
}

function _hi_wraps_for_tmux() {
  local out
  out="$(_hi_emit hi TMUX=/tmp/fake,1,0)"
  [ "$out" = "${_HI_ESC}Ptmux;${_HI_ESC}${_HI_ESC}]52;c;aGk=${_HI_BEL}${_HI_ESC}\\" ]
}

# $TMUX wins over a screen-shaped $TERM: tmux commonly leaves TERM as
# screen-256color, and wrapping that in screen's DCS instead of tmux's would
# send the passthrough to the wrong multiplexer.
function _hi_tmux_beats_screen_term() {
  local out
  out="$(_hi_emit hi TMUX=/tmp/fake,1,0 TERM=screen-256color)"
  case "$out" in
  "${_HI_ESC}Ptmux;"*) return 0 ;;
  esac
  return 1
}

function _hi_wraps_for_screen() {
  local out
  out="$(_hi_emit hi TERM=screen-256color)"
  [ "$out" = "${_HI_ESC}P${_HI_ESC}]52;c;aGk=${_HI_BEL}${_HI_ESC}\\" ]
}

function _hi_no_wrap_for_xterm() {
  local out
  out="$(_hi_emit hi TERM=xterm-256color)"
  [ "$out" = "${_HI_ESC}]52;c;aGk=${_HI_BEL}" ]
}

# Past the cap the escape would be dropped by the terminal anyway; refusing
# loudly beats leaving the user pasting their previous clipboard.
function _hi_refuses_oversize() {
  local out rc=0
  out="$(printf '%*s' 90000 '' | env -u TMUX -u TERM sh "$_HI_OSC52" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || return 1
  case "$out" in
  *"OSC 52"*) return 0 ;;
  esac
  return 1
}

# Every shell aliases.sh has to parse, since the alias line sits in that file's
# POSIX+fish subset. fish is a function rather than an alias, hence the two
# probe shapes.
function _hi_alias_defined_in() {
  local shell="$1" disable="$2" want="$3" out script
  if [ "$shell" = fish ]; then
    script="source $_HI_ROOT/common/paths.sh; source $_HI_ALIASES; functions -q -- hi_copy; and echo yes; or echo no"
  else
    script=". $_HI_ROOT/common/paths.sh; . $_HI_ALIASES; alias hi_copy >/dev/null 2>&1 && echo yes || echo no"
  fi
  out="$(env _HI_HOME="$_HI_HOME" _HI_DISABLE_OSC52="$disable" "$shell" -c "$script" 2>/dev/null)"
  [ "$out" = "$want" ]
}

# The container fallback path copies aliases.sh alone, with no paths.sh to
# define $_HI_OSC52. A bare `alias hi_copy="sh "` there would drop the user
# into an interactive shell on their own terminal, so the alias must not exist.
function _hi_no_alias_without_paths() {
  local out
  out="$(env -u _HI_OSC52 sh -c ". $_HI_ALIASES; alias hi_copy >/dev/null 2>&1 && echo yes || echo no" 2>/dev/null)"
  [ "$out" = no ]
}

function _hi_toggle_in_core_list() {
  case " ${_HI_TOGGLES[*]} " in
  *" _HI_DISABLE_OSC52 "*) return 0 ;;
  esac
  return 1
}

# config.fish keeps its own copy of the toggle list (fish can't read core.sh's
# array); a toggle added to one and not the other is the exact drift this
# catches.
function _hi_toggle_in_fish_list() {
  grep -q '_HI_DISABLE_OSC52' "$_HI_FISH_CONFIG"
}

# vim.rc's autocmd, asked of a real vim rather than grepped: the four
# conditions it is guarded by are the whole point of the block.
function _hi_vim_autocmd() {
  local want="$1" out
  shift
  out="$_HI_WORKDIR/vim.$want"
  env "$@" vim -es -u "$_HI_VIMRC" \
    -c "call writefile([string(exists('#hi_osc52'))], '$out')" -c 'qa!' \
    >/dev/null 2>&1 || true
  [ -f "$out" ] && [ "$(cat "$out")" = "$want" ]
}

function run_osc52_test() {
  _hi_h1 "Testing OSC 52 clipboard (shells/osc52.sh, hi_copy, vim yank)"
  _hi_workdir osc52
  _hi_suite_begin

  _hi_h2 "the emitter"
  _hi_check "plain escape for a plain terminal" _hi_emits_plain
  _hi_check "payload carries no wrap or newline" _hi_unwrapped_payload
  _hi_check "tmux passthrough under \$TMUX" _hi_wraps_for_tmux
  _hi_check "\$TMUX wins over a screen \$TERM" _hi_tmux_beats_screen_term
  _hi_check "screen passthrough under TERM=screen*" _hi_wraps_for_screen
  _hi_check "no passthrough under TERM=xterm*" _hi_no_wrap_for_xterm
  _hi_check "refuses a payload past the OSC 52 cap" _hi_refuses_oversize

  _hi_h2 "the hi_copy alias"
  local shell
  for shell in sh bash zsh fish; do
    _hi_check_requires "$shell" "[$shell] defined by default" _hi_alias_defined_in "$shell" 0 yes
    _hi_check_requires "$shell" "[$shell] gone on _HI_DISABLE_OSC52=1" _hi_alias_defined_in "$shell" 1 no
  done
  _hi_check "absent without paths.sh (container fallback)" _hi_no_alias_without_paths

  _hi_h2 "the toggle"
  _hi_check "_HI_DISABLE_OSC52 in core.sh's _HI_TOGGLES" _hi_toggle_in_core_list
  _hi_check "_HI_DISABLE_OSC52 in config.fish's copy" _hi_toggle_in_fish_list

  _hi_h2 "the vim autocmd"
  _hi_check_requires vim "registered in a hi session" \
    _hi_vim_autocmd 1 "_HI_OSC52=$_HI_OSC52" "_HI_DISABLE_OSC52=0"
  _hi_check_requires vim "gone on _HI_DISABLE_OSC52=1" \
    _hi_vim_autocmd 0 "_HI_OSC52=$_HI_OSC52" "_HI_DISABLE_OSC52=1"
  _hi_check_requires vim "gone outside a hi session (no \$_HI_OSC52)" \
    _hi_vim_autocmd 0 "_HI_OSC52=" "_HI_DISABLE_OSC52=0"

  _hi_suite_end "OSC 52"
}

run_osc52_test
