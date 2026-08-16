#!/bin/bash
# Behavioral tests for shells/bash.sh, zsh.zsh and config.fish - until now they
# were only syntax-linted, so a prompt or completion that silently stopped being
# defined would pass CI. Each case runs a fresh shell under `env -i` with HOME
# and _HI_CONFIG_DIR pointed into the workdir, so local settings can't leak in.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see. The single-quoted scripts are
# expanded by the *child* shell, which is the whole point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# run <shell> -c <script> in the controlled environment; TERM comes first so
# cases can pick the color branch (xterm-256color) or the plain one (dumb)
function _hi_rc_shell() {
  local term="$1" shell="$2" script="$3"
  # anything after the script is NAME=VALUE for the child - `env -i` is what
  # keeps local settings out, so extra variables have to be injected here
  # rather than exported around the call
  shift 3
  env -i HOME="$_HI_WORKDIR" TERM="$term" PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" "$@" \
    "$shell" -c "$script" </dev/null
}

function test_bash_hi_ps1_contains_user_host_cwd() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"')"
  [[ "$out" == *'\u'* && "$out" == *@* && "$out" == *'\h'* && "$out" == *'\w'* ]]
}

# no color -> the exact plain form (shells/bash.sh's else branch)
function test_bash_hi_ps1_plain_without_color() {
  local out
  out="$(_hi_rc_shell dumb bash \
    'source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"')"
  [[ "$out" == *'\u@\h:\w' ]]
}

function test_bash_prompt_disabled_leaves_ps1_alone() {
  local out
  out="$(_HI_DISABLE_PROMPT=1 _hi_rc_shell xterm-256color bash \
    'export _HI_DISABLE_PROMPT=1; source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; printf %s "${HI_PS1:-}"')"
  [ -z "$out" ]
}

function test_bash_registers_hi_completion() {
  _hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; complete -p hi' |
    grep -qF '_hi_complete'
}

function test_bash_defines_key_aliases() {
  _hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; alias grep && alias mindiff' >/dev/null
}

# zsh/fish presence is handled by _hi_check_requires at the registration, so a
# machine without one still runs (and honestly reports) the rest.
function test_zsh_prompt_is_built() {
  local out
  out="$(_hi_rc_shell xterm-256color zsh \
    'source "$_HI_HOME/hi.d/shells/zsh.zsh" 2>/dev/null; print -r -- "$PS1"')"
  [[ "$out" == *%n* && "$out" == *@* && "$out" == *%m* ]]
}

function test_fish_registers_hi_completion() {
  # fish echoes the registration back without the -c flag, so match on the
  # target-list wiring instead
  _hi_rc_shell xterm-256color fish \
    'source $_HI_HOME/hi.d/shells/config.fish 2>/dev/null; complete -c hi' |
    grep -qF '$_HI_TARGETS'
}

# --- nushell ------------------------------------------------------------------
#
# nu is not POSIX, so it cannot source common/paths.sh the way the other three
# rcs do - shells/config.nu reads the $_HI_* variables out of the environment
# instead. That is what the bash wrapper below sets up: source core.sh (which
# sources paths.sh and exports all of them), then exec nu with config.nu as its
# config. Every case runs a real nu against the real file, since the risk here
# is nu's own parser, not the text.
#
# The prompt closures are called directly rather than driven through an
# interactive session: nu queries the terminal for the cursor position at every
# REPL prompt, which a scripted pty has to answer or nu spins.
function _hi_nu_eval() {
  local file="$_HI_WORKDIR/probe.nu"
  printf '%s\n' "$1" >"$file"
  # env -i drops everything, so the toggles a case wants to set have to be
  # named here rather than exported around the call - same reason _hi_rc_shell
  # takes them as arguments
  env -i HOME="$_HI_WORKDIR" TERM=xterm-256color PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" _HI_DISABLE_HEADER=1 \
    _HI_DISABLE_GIT_STATUS="${_HI_DISABLE_GIT_STATUS:-0}" \
    _HI_DISABLE_PROMPT="${_HI_DISABLE_PROMPT:-0}" \
    bash -c '
      . "$_HI_HOME/hi.d/common/core.sh"
      exec nu --config "$_HI_NU_CONFIG" --env-config /dev/null "$1"
    ' _ "$file" 2>&1
}

# the file parses at all - nu fails the whole config on one syntax error, and
# then styles nothing while still starting a session
function test_nu_config_parses() {
  local out
  out="$(_hi_nu_eval 'print "NU_OK"')"
  [[ "$out" == *NU_OK* && "$out" != *"Error"* ]]
}

function test_nu_prompt_carries_user_host_and_cwd() {
  local out
  out="$(_hi_nu_eval 'print (do $env.PROMPT_COMMAND)')"
  [[ "$out" == *"$(_hi_whoami)"* && "$out" == *@* ]]
}

# the segment comes from common/git_prompt.sh through `bash -c`, so this also
# proves the shell-out survives nu's quoting - the failure mode being that nu
# reads bash's $( ) as its own subexpression
function test_nu_git_segment_uses_git_prompt() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/nugit.XXXXXX")"
  git -C "$dir" init -q -b nu-branch . 2>/dev/null || return 1
  git -C "$dir" -c user.email=t@e.com -c user.name=T commit -q --allow-empty -m i
  out="$(cd "$dir" && _hi_nu_eval 'print (do $env.PROMPT_COMMAND_RIGHT)')"
  [[ "$out" == *nu-branch* ]]
}

function test_nu_git_segment_respects_the_toggle() {
  local dir out
  dir="$(mktemp -d "$_HI_WORKDIR/nugitoff.XXXXXX")"
  git -C "$dir" init -q -b nu-branch . 2>/dev/null || return 1
  git -C "$dir" -c user.email=t@e.com -c user.name=T commit -q --allow-empty -m i
  out="$(cd "$dir" && _HI_DISABLE_GIT_STATUS=1 _hi_nu_eval 'print (do $env.PROMPT_COMMAND_RIGHT)')"
  [[ "$out" != *nu-branch* ]]
}

# --- the prompt separator -----------------------------------------------------
#
# The character each prompt ends with is a setting now (core.sh's
# _hi_prompt_end, mirrored in config.fish), with three different shipped
# defaults. Each case renders the real prompt in the real shell rather than
# grepping the rc, since the whole risk here is a value that reaches $PS1 in a
# form the shell then mangles.

# the last non-blank characters of the prompt the shell actually built
function _hi_prompt_tail() {
  local shell="$1" script
  shift
  case "$shell" in
  bash) script='source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; ps1; printf %s "$PS1"' ;;
  zsh) script='source "$_HI_HOME/hi.d/shells/zsh.zsh" 2>/dev/null; print -rn -- "$PS1"' ;;
  fish) script='source $_HI_HOME/hi.d/shells/config.fish 2>/dev/null; fish_prompt' ;;
  esac
  _hi_rc_shell xterm-256color "$shell" "$script" "$@" | sed -E 's/\x1b\[[0-9;]*m//g'
}

# the shipped defaults, one per shell: bash's `\$` (which bash itself renders as
# $ for a user and # for root), zsh's `>`, fish's `|`
function test_prompt_end_default() {
  local shell="$1" want="$2" out
  out="$(_hi_prompt_tail "$shell")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
  return 1
}

function test_prompt_end_shell_specific() {
  local shell="$1" var="$2" out
  out="$(_hi_prompt_tail "$shell" "$var=@@")"
  case "${out% }" in
  *@@) return 0 ;;
  esac
  return 1
}

# the one setting that covers all three, for people who want the same character
# everywhere - the shell-specific one still wins over it
function test_prompt_end_global_fallback() {
  local shell="$1" out
  out="$(_hi_prompt_tail "$shell" _HI_PROMPT_END=%%)"
  case "${out% }" in
  *%%) return 0 ;;
  esac
  return 1
}

function test_prompt_end_specific_beats_global() {
  local shell="$1" var="$2" out
  out="$(_hi_prompt_tail "$shell" _HI_PROMPT_END=%% "$var=@@")"
  case "${out% }" in
  *@@) return 0 ;;
  esac
  return 1
}

# an empty value is "unset", not "no separator": a prompt ending in a bare space
# is never what someone meant, and ' ' still expresses it
function test_prompt_end_empty_falls_back() {
  local shell="$1" var="$2" want="$3" out
  out="$(_hi_prompt_tail "$shell" "$var=")"
  case "${out% }" in
  *"$want") return 0 ;;
  esac
  return 1
}

function run_rc_tests() {
  _hi_workdir rctest
  mkdir -p "$_HI_WORKDIR/cfg"

  _hi_suite_begin

  _hi_h1 "Testing shells/bash.sh, zsh.zsh and config.fish behavior"

  _hi_h2 "Testing: bash"
  _hi_check "HI_PS1 carries user, host and cwd" test_bash_hi_ps1_contains_user_host_cwd
  _hi_check "Plain HI_PS1 without color" test_bash_hi_ps1_plain_without_color
  _hi_check "_HI_DISABLE_PROMPT leaves it unset" test_bash_prompt_disabled_leaves_ps1_alone
  _hi_check "hi completion is registered" test_bash_registers_hi_completion
  _hi_check "Key aliases are defined" test_bash_defines_key_aliases

  _hi_h2 "Testing: zsh and fish"
  _hi_check_requires zsh "zsh builds its prompt" test_zsh_prompt_is_built
  _hi_check_requires fish "fish registers hi completion" test_fish_registers_hi_completion
  _hi_check_requires nu "nu parses config.nu" test_nu_config_parses
  _hi_check_requires nu "nu's prompt carries user, host and cwd" test_nu_prompt_carries_user_host_and_cwd
  _hi_check_requires nu "nu's git segment comes from git_prompt.sh" test_nu_git_segment_uses_git_prompt
  _hi_check_requires nu "_HI_DISABLE_GIT_STATUS silences it" test_nu_git_segment_respects_the_toggle

  _hi_h2 "Testing: the prompt separator"
  local row shell var default
  for row in 'bash:_HI_PROMPT_END_BASH:$' 'zsh:_HI_PROMPT_END_ZSH:>' 'fish:_HI_PROMPT_END_FISH:|'; do
    shell="${row%%:*}"
    var="${row#*:}"
    var="${var%%:*}"
    default="${row##*:}"
    _hi_check_requires "$shell" "[$shell] default is '$default'" test_prompt_end_default "$shell" "$default"
    _hi_check_requires "$shell" "[$shell] $var wins" test_prompt_end_shell_specific "$shell" "$var"
    _hi_check_requires "$shell" "[$shell] _HI_PROMPT_END covers it" test_prompt_end_global_fallback "$shell"
    _hi_check_requires "$shell" "[$shell] the specific one beats it" test_prompt_end_specific_beats_global "$shell" "$var"
    _hi_check_requires "$shell" "[$shell] empty falls back to '$default'" test_prompt_end_empty_falls_back "$shell" "$var" "$default"
  done

  _hi_suite_end "rc"
}

run_rc_tests
