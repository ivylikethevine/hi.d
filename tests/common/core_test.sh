#!/bin/bash
# Unit tests for common/core.sh
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see. The single-quoted probe scripts are
# expanded by the *child* shell, which is the whole point (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# --- _hi_use_ascii / _hi_choose_glyphs ---------------------------------------

function test_use_ascii_in_a_c_locale() {
  (
    unset LC_ALL LC_CTYPE LANG _HI_ASCII
    LANG=C _hi_use_ascii
  )
}

function test_use_ascii_not_under_utf8() {
  (
    unset LC_ALL LC_CTYPE LANG _HI_ASCII
    ! LANG=en_US.UTF-8 _hi_use_ascii &&
      ! LC_ALL=C.utf8 _hi_use_ascii # LC_ALL outranks, both spellings count
  )
}

function test_use_ascii_override_beats_the_locale() {
  (
    unset LC_ALL LC_CTYPE LANG
    LANG=en_US.UTF-8 _HI_ASCII=1 _hi_use_ascii &&
      ! LANG=C _HI_ASCII=0 _hi_use_ascii
  )
}

# the chooser's two sets, via the marks the header suite also matches on
function test_choose_glyphs_picks_a_whole_set() {
  (
    _HI_ASCII=1
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = ok ] && [ "$_HI_MARK_NO" = x ] &&
      [ "$_HI_GLYPH_AHEAD" = "^" ] && [ "$_HI_MARK_OK_W" = 2 ]
  ) && (
    _HI_ASCII=0
    _hi_choose_glyphs
    [ "$_HI_MARK_OK" = "✓" ] && [ "$_HI_MARK_NO" = "✗" ] &&
      [ "$_HI_GLYPH_AHEAD" = "↑" ] && [ "$_HI_MARK_OK_W" = 1 ]
  )
}

function test_sanitize_leaves_plain_text_alone() {
  [ "$(_hi_sanitize "hello world")" = "hello world" ]
}

function test_sanitize_strips_control_chars_and_backslashes() {
  [ "$(_hi_sanitize $'a\tb\\c')" = "abc" ]
}

function test_color_escape_matches_red_constant() {
  [ "$(_hi_color_escape red)" = "$(_hi_rendered "$RED")" ]
}

function test_color_escape_matches_brcyan_constant() {
  [ "$(_hi_color_escape brcyan)" = "$(_hi_rendered "$BRCYAN")" ]
}

function test_color_escape_unknown_name_resets() {
  [ "$(_hi_color_escape not-a-real-color)" = "$(_hi_rendered "$NC")" ]
}

# https://no-color.org - the convention is "non-empty means off", so both the
# per-call gates and the source-time palette blanking are asserted, the second
# through a fresh bash: this shell sourced core.sh before the variable was set.
function test_no_color_blanks_the_escape() {
  [ -z "$(NO_COLOR=1 _hi_color_escape red)" ]
}

function test_no_color_beats_the_terminal() {
  ! NO_COLOR=1 TERM=xterm-256color _hi_has_color
}

function test_no_color_empty_means_on() {
  [ -n "$(NO_COLOR='' _hi_color_escape red)" ] &&
    NO_COLOR='' TERM=xterm-256color _hi_has_color
}

function test_no_color_blanks_the_palette_at_source_time() {
  local out
  out="$(env NO_COLOR=1 _HI_HOME="$_HI_HOME" bash -c \
    '. "$_HI_HOME/hi.d/common/core.sh"; printf "%s" "$NC$RED$BRCYAN"')"
  [ -z "$out" ]
}

function test_hash_color_deterministic() {
  [ "$(_hi_hash_color someuser)" = "$(_hi_hash_color someuser)" ]
}

function test_hash_color_matches_hand_computed_bucket() {
  # ord('a')=97, 97 % 12 == 1 -> _HI_COLOR_NAMES[1] == green
  [ "$(_hi_hash_color a)" = "green" ] || return 1
  # ord('a')+ord('b')=97+98=195, 195 % 12 == 3 -> _HI_COLOR_NAMES[3] == blue
  [ "$(_hi_hash_color ab)" = "blue" ]
}

function test_override_color_exact_match() {
  local colors="$_HI_WORKDIR/colors.exact"
  printf 'username,alice,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_override_color username alice)" = "red" ]
}

function test_override_color_no_match_fails() {
  local colors="$_HI_WORKDIR/colors.nomatch"
  printf 'username,alice,red\n' >"$colors"
  ! _HI_COLORS="$colors" _hi_override_color username bob
}

function test_override_color_localuser_special_case() {
  local colors="$_HI_WORKDIR/colors.localuser"
  printf 'username,LOCALUSER,cyan\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_USER=testuser _hi_override_color username testuser)" = "cyan" ]
}

function test_override_color_localhostname_special_case() {
  local colors="$_HI_WORKDIR/colors.localhost"
  printf 'hostname,LOCALHOSTNAME,magenta\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _HI_LOCAL_HOSTNAME=testhost _hi_override_color hostname testhost)" = "magenta" ]
}

function _hi_ssh_tag_fixture() {
  local f="$_HI_WORKDIR/ssh_config"
  cat >"$f" <<'EOF'
# Tags: prod, web
Host myhost
    HostName 1.2.3.4

Host untaggedhost
    HostName 5.6.7.8

# Tags= dev
Host devhost otheralias
    HostName 9.9.9.9
EOF
  printf '%s' "$f"
}

function test_ssh_host_tag_leftmost_of_multiple() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag myhost)" = "prod" ]
}

function test_ssh_host_tag_untagged_host_fails() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  ! _HI_SSH_CONFIG="$f" _hi_ssh_host_tag untaggedhost
}

function test_ssh_host_tag_equals_syntax_and_multialias() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag devhost)" = "dev" ] || return 1
  [ "$(_HI_SSH_CONFIG="$f" _hi_ssh_host_tag otheralias)" = "dev" ]
}

function test_ssh_host_tag_unknown_host_fails() {
  local f
  f="$(_hi_ssh_tag_fixture)"
  ! _HI_SSH_CONFIG="$f" _hi_ssh_host_tag no-such-host
}

function test_resolve_color_override_wins() {
  local colors="$_HI_WORKDIR/colors.resolve1"
  printf 'username,bob,red\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username bob)" = "red" ]
}

function test_resolve_color_hosttag_via_ssh_config() {
  local f colors
  f="$(_hi_ssh_tag_fixture)"
  colors="$_HI_WORKDIR/colors.resolve2"
  printf 'hosttag,prod,blue\n' >"$colors"
  [ "$(_HI_SSH_CONFIG="$f" _HI_COLORS="$colors" _hi_resolve_color hostname myhost)" = "blue" ]
}

function test_resolve_color_usertag_when_no_exact_override() {
  local colors="$_HI_WORKDIR/colors.resolve3"
  printf 'usertag,prodtag,green\n' >"$colors"
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username someuser prodtag)" = "green" ]
}

function test_resolve_color_falls_back_to_hash() {
  local colors="$_HI_WORKDIR/colors.missing" # never created - no override file
  [ "$(_HI_COLORS="$colors" _hi_resolve_color username unknownxyz)" = "$(_hi_hash_color unknownxyz)" ]
}

# --- the settings overlay -----------------------------------------------------
#
# core.sh's preamble runs once per shell and is guarded by $_hi_core_loaded,
# so there is no function to call: the case is a fresh bash sourcing core.sh
# against a scratch $_HI_CONFIG_DIR whose settings.sh claims $_HI_PROBE.
# shellcheck disable=SC2016 # the probe expands in the child bash, not here
function test_settings_sh_is_sourced() {
  local dir="$_HI_WORKDIR/overlay"
  mkdir -p "$dir"
  printf 'export _HI_PROBE=global\n' >"$dir/settings.sh"
  [ "$(env -u _hi_core_loaded -u _HI_PROBE _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$dir" \
    bash -c 'source "$_HI_HOME/hi.d/common/core.sh"; printf "%s" "${_HI_PROBE:-unset}"')" = global ]
}

# --- the same primitives, in zsh ----------------------------------------------
#
# shells/zsh.zsh sources core.sh directly, so its functions run in zsh too - and
# three zsh differences had each silently broken something: `${name:i:1}` is a
# history modifier there, $BASH_REMATCH is never populated, and an unquoted
# `$var` is not word-split. All three were invisible to a bash-only suite, so
# these cases run the real functions in a real zsh and compare with bash's
# answer; the point is that the two agree.

function _hi_in_shell() {
  local shell="$1" script="$2"
  env _HI_HOME="$_HI_HOME" _HI_SSH_CONFIG="$_HI_WORKDIR/ssh_config" \
    "$shell" -c "source \"\$_HI_HOME/hi.d/common/core.sh\"; $script" 2>&1
}

function _hi_shell_agrees() {
  local script="$1" a b
  a="$(_hi_in_shell bash "$script")"
  b="$(_hi_in_shell zsh "$script")"
  [ -n "$a" ] && [ "$a" = "$b" ]
}

function test_zsh_hash_color_agrees_with_bash() {
  _hi_ssh_tag_fixture >/dev/null
  _hi_shell_agrees 'printf "%s,%s,%s" "$(_hi_hash_color alice)" "$(_hi_hash_color prod-db)" "$(_hi_hash_color x)"'
}

function test_zsh_host_tag_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s|%s" "$(_hi_ssh_host_tag myhost)" "$(_hi_ssh_host_tag devhost)"'
}

function test_zsh_host_tag_rejects_the_same_hosts() {
  _hi_shell_agrees '_hi_ssh_host_tag untaggedhost >/dev/null; printf "untagged:%s " "$?"; _hi_ssh_host_tag nope >/dev/null; printf "unknown:%s" "$?"'
}

function test_zsh_resolve_color_agrees_with_bash() {
  _hi_shell_agrees 'printf "%s" "$(_hi_resolve_color hostname myhost)"'
}

# the regression that matters for oh-my-zsh: hi must not leave KSH_ARRAYS on in
# the user's shell, because omz and its plugins index arrays from 1
function test_zsh_rc_leaves_ksharrays_alone() {
  local out
  out="$(env _HI_HOME="$_HI_HOME" TERM=xterm-256color zsh -c \
    'source "$_HI_HOME/hi.d/shells/zsh.zsh"; setopt | grep -c ksharrays' 2>/dev/null)"
  [ "$out" = 0 ]
}

# ...and it still has to work when the user (or their framework) turned it on
function test_zsh_rc_survives_ksharrays_being_on() {
  local out
  out="$(env _HI_HOME="$_HI_HOME" TERM=xterm-256color zsh -c \
    'setopt KSH_ARRAYS; source "$_HI_HOME/hi.d/shells/zsh.zsh"; print -n "$USER_COLOR"' 2>/dev/null)"
  [ -n "$out" ]
}

function run_core_tests() {
  _hi_workdir sharedtest

  _hi_h1 "Testing common/core.sh"

  _hi_suite_begin

  _hi_h2 "Testing: _hi_use_ascii / _hi_choose_glyphs"
  _hi_check "C locale means ASCII" test_use_ascii_in_a_c_locale
  _hi_check "UTF-8 keeps the glyphs" test_use_ascii_not_under_utf8
  _hi_check "_HI_ASCII beats the locale" test_use_ascii_override_beats_the_locale
  _hi_check "The chooser swaps whole sets" test_choose_glyphs_picks_a_whole_set

  _hi_h2 "Testing: _hi_sanitize"
  _hi_check "Leaves plain text alone" test_sanitize_leaves_plain_text_alone
  _hi_check "Strips control chars and backslashes" test_sanitize_strips_control_chars_and_backslashes

  _hi_h2 "Testing: _hi_color_escape"
  _hi_check "Red matches \$RED" test_color_escape_matches_red_constant
  _hi_check "Brcyan matches \$BRCYAN" test_color_escape_matches_brcyan_constant
  _hi_check "Unknown name resets" test_color_escape_unknown_name_resets

  _hi_h2 "Testing: NO_COLOR"
  _hi_check "Blanks the escape" test_no_color_blanks_the_escape
  _hi_check "Beats the terminal's yes" test_no_color_beats_the_terminal
  _hi_check "Empty means on (non-empty rule)" test_no_color_empty_means_on
  _hi_check "Blanks the palette at source time" test_no_color_blanks_the_palette_at_source_time

  _hi_h2 "Testing: _hi_hash_color"
  _hi_check "Deterministic across calls" test_hash_color_deterministic
  _hi_check "Matches hand-computed buckets" test_hash_color_matches_hand_computed_bucket

  _hi_h2 "Testing: _hi_override_color"
  _hi_check "Exact match" test_override_color_exact_match
  _hi_check "No match fails" test_override_color_no_match_fails
  _hi_check "LOCALUSER special case" test_override_color_localuser_special_case
  _hi_check "LOCALHOSTNAME special case" test_override_color_localhostname_special_case

  _hi_h2 "Testing: _hi_ssh_host_tag"
  _hi_check "Leftmost tag of a multi-tag comment" test_ssh_host_tag_leftmost_of_multiple
  _hi_check "Untagged host fails" test_ssh_host_tag_untagged_host_fails
  _hi_check "'Tags=' syntax and multi-alias Host lines" test_ssh_host_tag_equals_syntax_and_multialias
  _hi_check "Unknown host fails" test_ssh_host_tag_unknown_host_fails

  _hi_h2 "Testing: _hi_resolve_color precedence"
  _hi_check "Exact override wins" test_resolve_color_override_wins
  _hi_check "Hosttag via ssh config" test_resolve_color_hosttag_via_ssh_config
  _hi_check "Usertag when no exact override" test_resolve_color_usertag_when_no_exact_override
  _hi_check "Falls back to the hash" test_resolve_color_falls_back_to_hash

  _hi_h2 "Testing: the settings overlay"
  _hi_check "settings.sh is sourced" test_settings_sh_is_sourced

  _hi_h2 "Testing: the same answers in zsh"
  _hi_check_requires zsh "_hi_hash_color agrees with bash" test_zsh_hash_color_agrees_with_bash
  _hi_check_requires zsh "_hi_ssh_host_tag agrees with bash" test_zsh_host_tag_agrees_with_bash
  _hi_check_requires zsh "...and rejects the same hosts" test_zsh_host_tag_rejects_the_same_hosts
  _hi_check_requires zsh "_hi_resolve_color agrees with bash" test_zsh_resolve_color_agrees_with_bash
  _hi_check_requires zsh "zsh.zsh leaves KSH_ARRAYS off" test_zsh_rc_leaves_ksharrays_alone
  _hi_check_requires zsh "zsh.zsh survives KSH_ARRAYS being on" test_zsh_rc_survives_ksharrays_being_on

  _hi_suite_end "core.sh"
}

run_core_tests
