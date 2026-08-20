#!/bin/bash
# Behavioral tests for shells/bash.sh, zsh.zsh and config.fish - until now they
# were only syntax-linted, so a prompt or completion that silently stopped being
# defined would pass CI. Each case runs a fresh shell under `env -i` with HOME
# and _HI_CONFIG_DIR pointed into the workdir, so local settings can't leak in.
#
# GLOSSARY: HI.30. The single-quoted scripts are expanded by the *child*
# shell, which is the whole point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# test_lib.sh sources core.sh itself; $_HI_TEST_LIB wins under the runner
# shellcheck source=../test_lib.sh
source "${_HI_TEST_LIB:-${BASH_SOURCE[0]%/*}/../test_lib.sh}"

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

# _HI_PROMPT=starship hands the prompt over when starship exists; a stub on a
# prepended PATH stands in for it, answering `init <shell>` with a line whose
# effect the case can see. Three assertions per family: deferred when asked
# and present, hi's prompt kept when not asked, and hi's prompt kept - with
# no error - when asked but starship is absent.
function _hi_starship_stub_dir() {
  local dir="$_HI_WORKDIR/starship-bin"
  [ -x "$dir/starship" ] || {
    mkdir -p "$dir"
    printf '#!/bin/sh\ncase "$2" in\nbash | zsh) echo "PS1=STARSHIP-STUB" ;;\nfish) echo "function fish_prompt; echo -n STARSHIP-STUB; end" ;;\nesac\n' >"$dir/starship"
    chmod +x "$dir/starship"
  }
  printf '%s' "$dir"
}

# One case for all three shells: the per-shell rc, prompt-print incantation
# and expected shape live in the case's own table. Extra NAME=VALUE arguments
# ride _hi_rc_shell (env applies the last assignment, so the prepended-PATH
# override wins over the baseline), so there is one `env -i` block here rather
# than one per case.
function test_defers_to_starship_when_asked() {
  local shell="$1" script want out
  case "$shell" in
  bash)
    script='source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; printf "%s|%s" "$PS1" "${HI_PS1:-unset}"'
    want="STARSHIP-STUB|unset"
    ;;
  zsh)
    script='source "$_HI_HOME/hi.d/shells/zsh.zsh" 2>/dev/null; printf %s "$PS1"'
    want="STARSHIP-STUB"
    ;;
  fish)
    script='source $_HI_HOME/hi.d/shells/config.fish 2>/dev/null; fish_prompt'
    want="*STARSHIP-STUB*"
    ;;
  esac
  out="$(_hi_rc_shell xterm-256color "$shell" "$script" \
    PATH="$(_hi_starship_stub_dir):$PATH" _HI_PROMPT=starship)"
  # shellcheck disable=SC2053 # $want is a pattern (fish's is a glob)
  [[ "$out" == $want ]]
}

function test_bash_keeps_hi_prompt_without_the_setting() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    PATH="$(_hi_starship_stub_dir):$PATH")"
  [[ "$out" == *'\u'* ]]
}

# asked for, not installed: hi's prompt, and nothing on stderr
function test_bash_falls_back_when_starship_is_absent() {
  local out
  out="$(_hi_rc_shell xterm-256color bash \
    'source "$_HI_HOME/hi.d/shells/bash.sh" 2>/dev/null; printf %s "$HI_PS1"' \
    _HI_PROMPT=starship 2>&1)"
  [[ "$out" == *'\u'* ]]
}

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
  _hi_strip_ansi "$(_hi_rc_shell xterm-256color "$shell" "$script" "$@")"
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

  _hi_h2 "Testing: starship deference (_HI_PROMPT=starship)"
  _hi_check "[bash] defers when asked and present" test_defers_to_starship_when_asked bash
  _hi_check "[bash] keeps hi's prompt without the setting" test_bash_keeps_hi_prompt_without_the_setting
  _hi_check "[bash] falls back silently when absent" test_bash_falls_back_when_starship_is_absent
  _hi_check_requires zsh "[zsh] defers when asked and present" test_defers_to_starship_when_asked zsh
  _hi_check_requires fish "[fish] defers when asked and present" test_defers_to_starship_when_asked fish
  _hi_check_requires fish "fish registers hi completion" test_fish_registers_hi_completion

  _hi_h2 "Testing: the prompt separator"
  # the shells install.sh wires up locally, and their shipped defaults, both
  # read off core.sh's rosters rather than spelled again here
  local shell upper var default
  for shell in $(_hi_shell_rows local | cut -d'|' -f1); do
    upper="$(printf '%s' "$shell" | tr '[:lower:]' '[:upper:]')"
    var="_HI_PROMPT_END_$upper"
    # bash's default ships as the two characters `\$`, which bash renders as $
    # for a user and # for root; these cases run as a user, so the leading
    # backslash comes off before comparing against a rendered prompt.
    default="$(_hi_prompt_end_default "$upper")"
    default="${default#\\}"
    _hi_check_requires "$shell" "[$shell] default is '$default'" test_prompt_end_default "$shell" "$default"
    _hi_check_requires "$shell" "[$shell] $var wins" test_prompt_end_shell_specific "$shell" "$var"
    _hi_check_requires "$shell" "[$shell] _HI_PROMPT_END covers it" test_prompt_end_global_fallback "$shell"
    _hi_check_requires "$shell" "[$shell] the specific one beats it" test_prompt_end_specific_beats_global "$shell" "$var"
    _hi_check_requires "$shell" "[$shell] empty falls back to '$default'" test_prompt_end_empty_falls_back "$shell" "$var" "$default"
  done

  _hi_suite_end "rc"
}

run_rc_tests
