#!/bin/bash
# Unit tests for hi.sh: the prompt the bash-less tiers get.
# shells/ksh.sh and shells/config.fish each render a git segment without
# common/git_prompt.sh, so each carries its own copy of core.sh's palette and
# glyphs. Most of this file is the drift guard on those copies; the rendering
# itself is proven against a real mksh in tests/targets/ssh_test.sh, which is
# where a prompt belongs.
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

# shells/ksh.sh is the one place hi renders a git segment without bash, so it
# carries its own copy of core.sh's palette and glyphs. These cases are the
# drift guard on that copy - the segment rendering itself is proven against a
# real mksh in tests/targets/ssh_test.sh, which is where a prompt belongs.

# _hi_ksh_values <name...> - "<name>=<value>" per line, read from a child bash
# that sourced the real shells/ksh.sh (one spawn for the whole list, and no
# assertion on how the constants are spelled - re-quoting one can't fail a
# guard, only a changed value can). $_HI_ASCII rides the environment.
function _hi_ksh_values() {
  bash -c '
    source "$_HI_ROOT/shells/ksh.sh" >/dev/null 2>&1
    for name in "$@"; do
      eval "printf \"%s=%s\\n\" \"$name\" \"\$_HI_KSH_$name\""
    done' _ "$@"
}

# ...and core.sh's answer for the same names, from a subshell so the suite's
# own glyph choice is untouched. <prefix> is the core-side variable family.
function _hi_core_values() {
  local prefix="$1" ascii="$2" name
  shift 2
  (
    _HI_ASCII="$ascii"
    _hi_choose_glyphs
    for name in "$@"; do
      eval "printf '%s=%s\n' \"$name\" \"\${$prefix$name}\""
    done
  )
}

function _hi_blocks_agree() {
  local label="$1" a="$2" b="$3"
  [ -n "$a" ] && [ "$a" = "$b" ] && return 0
  _hi_cecho " | $label: ksh.sh and core.sh disagree -" "$RED"
  printf 'ksh.sh:\n%s\ncore.sh:\n%s\n' "$a" "$b" | sed 's/^/      /'
  return 1
}

# every escape ksh.sh defines has to be the one core.sh defines under the same
# name, or the two tiers disagree about what "dirty" looks like
_HI_KSH_COLOR_NAMES=(NC RED YELLOW BRGREEN BRBLUE BRPURPLE)
function test_ksh_colors_match_core() {
  # core.sh writes them as \e, ksh.sh as \033 - the same byte, spelled for a
  # shell with no `echo -e`
  _hi_blocks_agree colors \
    "$(_hi_ksh_values "${_HI_KSH_COLOR_NAMES[@]}")" \
    "$(_hi_core_values "" 0 "${_HI_KSH_COLOR_NAMES[@]}" | sed 's/\\e/\\033/')"
}

# the same for the glyph set, both halves of the ASCII switch: a new glyph in
# core.sh's _hi_choose_glyphs that never reaches ksh.sh is the drift this
# catches
_HI_KSH_GLYPH_NAMES=(AHEAD BEHIND STAGED DIRTY INVALID UNTRACKED STASH CLEAN ELLIPSIS)
function test_ksh_glyphs_match_core() {
  local ascii
  for ascii in 0 1; do
    _hi_blocks_agree "glyphs (_HI_ASCII=$ascii)" \
      "$(_HI_ASCII="$ascii" _hi_ksh_values "${_HI_KSH_GLYPH_NAMES[@]}")" \
      "$(_hi_core_values _HI_GLYPH_ "$ascii" "${_HI_KSH_GLYPH_NAMES[@]}")" || return 1
  done
}

# fish renders its git segment with its own __fish_git_prompt, so config.fish
# carries a third copy of the glyphs and palette - one say-hi never guarded. The
# cases below read the file rather than running fish: the copy is a set of
# literals, so parsing them is the whole check, and it holds on a runner with
# no fish installed (which is where the drift would land unnoticed).

# <role>=<value> per line, for the char_/color_ family named by $1
function _hi_fish_settings() {
  sed -n "s/^ *set -g __fish_git_prompt_$1_\([a-z_]*\) '\{0,1\}\([^']*\)'\{0,1\}\$/\1=\2/p" \
    "$_HI_ROOT/shells/config.fish"
}

function _hi_fish_agrees() {
  local label="$1" a="$2" b="$3"
  [ -n "$a" ] && [ "$a" = "$b" ] && return 0
  _hi_cecho " | $label: config.fish and core.sh disagree -" "$RED"
  printf 'config.fish:\n%s\ncore.sh:\n%s\n' "$a" "$b" | sed 's/^/      /'
  return 1
}

# config.fish only overrides the glyphs on the ASCII side - the UTF-8 ones are
# fish's own - so the ASCII set is the copy, and this is the guard on it. Role
# names are fish's; the values have to be core.sh's _HI_ASCII=1 answers.
_HI_FISH_GLYPH_ROLES=("upstream_ahead:AHEAD" "upstream_behind:BEHIND"
  "stagedstate:STAGED" "dirtystate:DIRTY" "invalidstate:INVALID"
  "untrackedfiles:UNTRACKED" "stashstate:STASH" "cleanstate:CLEAN")
function test_fish_ascii_glyphs_match_core() {
  local pair role name want=""
  for pair in "${_HI_FISH_GLYPH_ROLES[@]}"; do
    role="${pair%%:*}"
    name="${pair#*:}"
    want="$want$role=$(_hi_core_values _HI_GLYPH_ 1 "$name" | sed 's/^[A-Z_]*=//')"$'\n'
  done
  _hi_fish_agrees "ascii glyphs" "$(_hi_fish_settings char)" "$(printf '%s' "$want")"
}

# the palette copy: fish names colors, core.sh spells escapes, and
# _hi_color_escape is the bridge - so a renamed color that stops resolving to
# the escape the bash tier uses for the same role fails here
_HI_FISH_COLOR_ROLES=("branch:BRPURPLE" "stagedstate:YELLOW"
  "invalidstate:RED" "cleanstate:BRGREEN")
function test_fish_colors_match_core() {
  local pair role var fish_name got want mismatch=""
  for pair in "${_HI_FISH_COLOR_ROLES[@]}"; do
    role="${pair%%:*}"
    var="${pair#*:}"
    fish_name="$(_hi_fish_settings color | sed -n "s/^$role=//p")"
    [ -n "$fish_name" ] || {
      _hi_cecho " | config.fish sets no color for $role" "$RED"
      return 1
    }
    got="$(_hi_color_escape "$fish_name")"
    eval "want=\"\${$var}\""
    want="$(printf '%b' "$want")"
    [ "$got" = "$want" ] || mismatch="$mismatch $role($fish_name vs $var)"
  done
  [ -z "$mismatch" ] || {
    _hi_cecho " | color roles disagree:$mismatch" "$RED"
    return 1
  }
}

# fish's default is `|`, bash's `\$`, zsh's `>` - three answers, and config.fish
# cannot call _hi_prompt_end_default to get its own. This is that pin.
function test_fish_prompt_end_default_matches_core() {
  local fish_default core_default
  fish_default="$(sed -n "s/^set -g _hi_prompt_end '\(.*\)'\$/\1/p" \
    "$_HI_ROOT/shells/config.fish")"
  core_default="$(_hi_prompt_end_default FISH)"
  [ -n "$fish_default" ] && [ "$fish_default" = "$core_default" ] || {
    _hi_cecho " | config.fish: '$fish_default'  core.sh: '$core_default'" "$RED"
    return 1
  }
}

# the branch is shortened at the same width in all three implementations, or
# the same repo renders a different branch name per shell
function test_branch_shorten_length_agrees() {
  local missing=""
  grep -q 'shorten_branch_len 32' "$_HI_ROOT/shells/config.fish" ||
    missing="$missing config.fish"
  grep -q '#ref} > 32' "$_HI_ROOT/common/git_prompt.sh" ||
    missing="$missing git_prompt.sh"
  grep -q -- '-gt 32' "$_HI_ROOT/shells/ksh.sh" ||
    missing="$missing ksh.sh"
  [ -z "$missing" ] || {
    _hi_cecho " | not shortening at 32:$missing" "$RED"
    return 1
  }
}

# the wiring: the ksh arm sources ksh.sh and asks for the git-carrying prompt,
# and the sh/ash/dash arm still gets neither - busybox ash would print the text
# of the command substitution rather than running it
function test_remote_suffix_gives_ksh_the_segment() {
  local out
  out="$(DOMAIN=hitest@myhost hi_esc="" nc_esc="" _hi_remote_suffix)"
  [[ "$out" == *"ksh | mksh)"* ]] || return 1
  [[ "$out" == *'$_HI_ROOT/shells/ksh.sh'* ]]
}

# the segment reaches PS1 single-quoted, so it is expanded per prompt rather
# than once at assignment - the whole reason the tier can have a live segment
function test_fallback_prompt_git_segment_is_deferred() {
  local out
  out="$(DOMAIN=hitest@myhost _hi_fallback_prompt git | sed -n 's/^PS1=//p')"
  [[ "$out" == *"'\$(_hi_ksh_git)'"* ]]
}

function test_fallback_prompt_has_no_segment_by_default() {
  [[ "$(DOMAIN=hitest@myhost _hi_fallback_prompt)" != *_hi_ksh_git* ]]
}

# sh/ash/dash/ksh sessions get hi's prompt, not the host's own (on busybox a
# bare "$"). The line hi writes has to survive shells with no readline and no
# command substitution in PS1, so it bakes everything in on the client and
# leaves exactly one escape for the target to expand.

# one line, so one case reads all of it: the username resolved once by the rc
# rather than per prompt, the host without its user@ part, a color from hi's own
# palette, the separator left for the shell (\$ - $ for a user, # for root), and
# no `$( )` inside PS1, which busybox ash would not expand anyway
function test_fallback_prompt_carries_user_host_and_color() {
  local out ps1
  out="$(DOMAIN=hitest@myhost _hi_fallback_prompt)"
  ps1="$(printf '%s\n' "$out" | sed -n 's/^PS1=//p')"
  [[ "$out" == *'_hi_u=$(id -un'* ]] || return 1
  [[ "$ps1" == *myhost* && "$ps1" == *$'\e['* ]] || return 1
  [[ "$ps1" == *'\$ "'* && "$ps1" != *'$('* ]]
}

# the separator is a setting everywhere else, so it is one here too
function test_fallback_prompt_honors_the_separator_setting() {
  [[ "$(_HI_PROMPT_END='>>' DOMAIN=hitest@myhost _hi_fallback_prompt)" == *'>> "'* ]]
}

function test_fallback_prompt_respects_the_toggle() {
  [ -z "$(_HI_DISABLE_PROMPT=1 DOMAIN=hitest@myhost _hi_fallback_prompt)" ]
}

# the whole point: a real POSIX shell renders it without complaint
function test_fallback_prompt_renders_in_dash() {
  local out
  out="$(DOMAIN=hitest@myhost _hi_fallback_prompt |
    dash -s -c '. /dev/stdin; printf %s "$PS1"' 2>&1)" || return 1
  [[ "$out" == *myhost* && "$out" != *'id -un'* ]]
}

# The shared rc must NOT carry it: that file is also fed to fish, which has no
# PS1 and stops dead on the line, and to zsh, where `\$` is not this escape.
# The POSIX arm appends it instead - which is what the suffix below shows.
function test_fallback_rc_stays_shell_agnostic() {
  local out
  out="$(DOMAIN=hitest@myhost CMDARG="" _hi_fallback_rc)"
  [[ "$out" != *PS1=* ]]
}

function test_remote_suffix_appends_the_prompt_for_posix_shells() {
  local out
  out="$(DOMAIN=hitest@myhost _hi_remote_suffix)"
  # the append lands after the fish arm - on the ksh/mksh arm, which is the
  # first one past fish - and every arm that appends also exports ENV
  _hi_before "$out" 'fish -C' '>> "\$_hi_rc_dir/.hi_fallback_rc"' &&
    _hi_before "$out" '>> "\$_hi_rc_dir/.hi_fallback_rc"' 'ENV='
}

# The container fallback ships aliases.sh alone, so the ssh path's
# `. $_HI_ROOT/shells/ksh.sh` has nothing to resolve against here: the segment
# is copied in beside it and sourced by absolute path. Pinned because a mksh
# container silently got the plain-sh prompt until Aug 2026 - no error, just a
# missing git segment nobody was looking for.
function test_container_fallback_gives_ksh_the_git_segment() {
  local dir rc out
  dir="$_HI_WORKDIR/ksh-container"
  rc="$dir/rc.captured"
  mkdir -p "$dir"
  # answers only the three shapes _say_hi_container makes on this path: the
  # bash probe (fails, forcing the fallback), the ladder probe (mksh), and the
  # rc write (captured). `exec -it` never runs - the attach is the last thing
  # the function does and its exit code is all the case needs.
  cat >"$dir/docker" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
  *'command -v bash'*) exit 1 ;;
  *_hi_s*) printf 'mksh\n'; exit 0 ;;
  # the write, not the attach - both name the rc, and matching loosely here
  # lets the attach truncate what the write just captured
  'cat > '*.hi_fallback_rc*) cat > '$rc'; exit 0 ;;
  esac
done
exit 0
EOF
  chmod +x "$dir/docker"

  PATH="$dir:$PATH" DOMAIN=hitest _HI_SHELL_START=0 \
    _say_hi_container docker "$dir/err.log" 0 >/dev/null 2>&1
  [ -s "$rc" ] || return 1
  out="$(cat "$rc")"
  # the source line must land after the rc's verdict exports (ksh.sh reads
  # them) and before the prompt that calls into it
  _hi_before "$out" 'export _HI_ASCII=' '/ksh.sh' &&
    _hi_before "$out" '/ksh.sh' 'PS1=' &&
    [[ "$out" == *'$(_hi_ksh_git)'* ]]
}

function run_hi_prompt_tests() {
  _hi_workdir hiprompttest

  _hi_suite_begin

  _hi_h1 "Testing hi.sh: the bash-less prompt"

  _hi_h2 "Testing: the bash-less prompt"
  _hi_check "Carries user, host, color and separator" test_fallback_prompt_carries_user_host_and_color
  _hi_check "_HI_PROMPT_END applies here too" test_fallback_prompt_honors_the_separator_setting
  _hi_check "_HI_DISABLE_PROMPT skips it" test_fallback_prompt_respects_the_toggle
  _hi_check_requires dash "Renders in a real dash" test_fallback_prompt_renders_in_dash
  _hi_check "The shared rc stays shell-agnostic" test_fallback_rc_stays_shell_agnostic
  _hi_check "The POSIX arm appends it" test_remote_suffix_appends_the_prompt_for_posix_shells
  _hi_check "The container fallback gives ksh the git segment" test_container_fallback_gives_ksh_the_git_segment

  _hi_h2 "Testing: the ksh/mksh git segment"
  _hi_check "ksh.sh's colors match core.sh" test_ksh_colors_match_core
  _hi_check "ksh.sh's glyphs match core.sh" test_ksh_glyphs_match_core
  _hi_check "The ksh arm sources it" test_remote_suffix_gives_ksh_the_segment
  _hi_check "The segment is expanded per prompt" test_fallback_prompt_git_segment_is_deferred
  _hi_check "No segment for sh/ash/dash" test_fallback_prompt_has_no_segment_by_default

  _hi_h2 "Testing: the fish git segment's copies"
  _hi_check "config.fish's ascii glyphs match core.sh" test_fish_ascii_glyphs_match_core
  _hi_check "config.fish's colors match core.sh" test_fish_colors_match_core
  _hi_check "config.fish's prompt end matches core.sh" test_fish_prompt_end_default_matches_core
  _hi_check "All three segments shorten at 32" test_branch_shorten_length_agrees
  _hi_suite_end "hi.sh (the bash-less prompt)"
}

run_hi_prompt_tests
