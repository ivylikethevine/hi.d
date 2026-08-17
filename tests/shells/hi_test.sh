#!/bin/bash
# Unit tests for hi.sh, the client entry point. Sourcing it goes through the
# same `[[ BASH_SOURCE == $0 ]]` hatch install.sh uses, which defines every
# function without connecting to anything - so the pure half is reachable here
# (argument parsing, the backend predicates, the heredoc generators), where a
# mis-parse is an assertion rather than a confusing connection failure. The
# predicates run against fake backend CLIs on $PATH, so their answers don't
# depend on what this machine is running; _say_hi stays e2e-only by nature.
#
# Functions here are invoked indirectly through _hi_case's "$@" (SC2329). The
# linter also follows `source "$_HI_LAUNCHER"` into hi.sh's trailing `_hi "$@"`,
# decides it never returns, and marks this file unreachable (SC2317) - it does
# not model the BASH_SOURCE guard. (A comment line may not *begin* with the
# linter's name, or it is read as a directive.)
# The single-quoted strings below are the target's to expand, not ours (SC2016).
# shellcheck disable=SC2329,SC2317,SC2016
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

# The fake backend CLIs come from test_lib.sh's _hi_probe_shims - the one
# home of the exact argv shapes hi.sh's predicates make. "yes" is
# running/Running, anything else is not.
_HI_SHIM_PATH=""

# _hi_parse writes to the globals DOMAIN/CMDARG/SSHARGS and can exit outright,
# so every case runs it in a subshell and prints what it produced. Fields are
# newline-separated: DOMAIN, CMDARG, then one line per SSHARGS entry.
function _hi_parse_out() {
  (
    unset DOMAIN CMDARG
    _hi_parse "$@" >/dev/null 2>&1
    printf '%s\n%s\n' "${DOMAIN:-}" "${CMDARG:-}"
    [ "${#SSHARGS[@]}" -eq 0 ] || printf '%s\n' "${SSHARGS[@]}"
  )
}

function test_parse_takes_a_bare_target() {
  [ "$(_hi_parse_out myhost)" = "$(printf 'myhost\n\n')" ]
}

function test_parse_keeps_valueless_flags() {
  [ "$(_hi_parse_out -v myhost)" = "$(printf 'myhost\n\n-v\n')" ]
}

function test_parse_pairs_a_flag_with_its_value() {
  [ "$(_hi_parse_out -p 2222 myhost)" = "$(printf 'myhost\n\n-p\n2222\n')" ]
}

# the regression this list exists for: -J takes a value, so without it in the
# case arm "bastion" becomes DOMAIN and hi connects to the wrong machine
function test_parse_treats_jump_host_as_a_value_not_the_target() {
  [ "$(_hi_parse_out -J bastion myhost)" = "$(printf 'myhost\n\n-J\nbastion\n')" ]
}

function test_parse_treats_bind_interface_as_a_value_not_the_target() {
  [ "$(_hi_parse_out -B eth0 myhost)" = "$(printf 'myhost\n\n-B\neth0\n')" ]
}

function test_parse_handles_several_flags_before_the_target() {
  [ "$(_hi_parse_out -4 -o StrictHostKeyChecking=no -i /tmp/k myhost)" = \
    "$(printf 'myhost\n\n-4\n-o\nStrictHostKeyChecking=no\n-i\n/tmp/k\n')" ]
}

# a trailing command becomes CMDARG - suffixed with "; exit" so the target
# shell closes after it - and never a second target. The spacing between the
# two is incidental (_hi_parse pastes '; ' and ' exit'), so don't pin it.
# hi's own flags are consumed by the parse, never forwarded - ssh would reject
# --tmux outright, and the target is still the first bare word after it
function test_parse_takes_hi_flags_without_forwarding_them() {
  [ "$(_hi_parse_out --tmux myhost)" = "$(printf 'myhost\n\n')" ] || return 1
  [ "$(_hi_parse_out -p 2222 --no-tmux myhost)" = "$(printf 'myhost\n\n-p\n2222\n')" ]
}

function test_parse_tmux_flags_set_the_toggle() {
  local on off
  on="$( (
    unset DOMAIN CMDARG
    _hi_parse --tmux myhost >/dev/null 2>&1
    printf '%s' "${_HI_TMUX_ATTACH:-unset}"
  ))"
  off="$( (
    unset DOMAIN CMDARG
    _HI_TMUX_ATTACH=1
    _hi_parse --no-tmux myhost >/dev/null 2>&1
    printf '%s' "${_HI_TMUX_ATTACH:-unset}"
  ))"
  [ "$on" = 1 ] && [ "$off" = 0 ]
}

function test_parse_turns_trailing_words_into_a_command() {
  local out
  out="$(_hi_parse_out myhost echo hello)"
  [[ "$out" == myhost*"echo hello;"*exit* ]]
}

function test_parse_leaves_cmdarg_empty_for_a_plain_session() {
  [ "$(_hi_parse_out myhost | sed -n 2p)" = "" ]
}

# a value-taking flag with nothing after it must report itself, not die on an
# unbound $2 or swallow the next argument
function test_parse_rejects_a_flag_missing_its_value() {
  local rc=0
  (_hi_parse -p >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 1 ]
}

function test_parse_names_the_offending_flag() {
  local out
  out="$( (_hi_parse -o 2>&1 >/dev/null) || true)"
  [[ "$out" == *"-o"* ]]
}

function test_is_docker_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_docker_container yes
}

function test_is_docker_container_rejects_a_stopped_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_docker_container no
}

function test_is_podman_container_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_podman_container yes
}

function test_is_nomad_alloc_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc yes
}

function test_is_nomad_alloc_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_nomad_alloc no
}

function test_is_k8s_pod_accepts_a_running_one() {
  PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod yes
}

function test_is_k8s_pod_rejects_a_pending_one() {
  ! PATH="$_HI_SHIM_PATH" _hi_is_k8s_pod no
}

# with no backend CLI on $PATH at all, every predicate must answer "no"
# rather than erroring - that is what lets _hi fall through to ssh
function test_predicates_are_false_without_their_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  ! PATH="$empty" _hi_is_docker_container yes &&
    ! PATH="$empty" _hi_is_podman_container yes &&
    ! PATH="$empty" _hi_is_nomad_alloc yes &&
    ! PATH="$empty" _hi_is_k8s_pod yes
}

# --- _hi_resolve_backend ------------------------------------------------------
#
# The predicates run together now, so the guarantee worth pinning is that the
# *answer* is still the roster's first match rather than whichever CLI
# happened to reply first. The shims answer for target "yes", so a target
# every backend claims must still resolve to docker - the row at the top of
# $_HI_BACKENDS.

function test_resolve_backend_picks_the_first_matching_row() {
  [ "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend yes)" = docker ]
}

# ...and the roster order is the thing being asserted, not "docker": prove it
# moves with the table rather than being baked into the resolver
function test_resolve_backend_follows_the_roster_order() {
  local out
  out="$(
    _HI_BACKENDS=("${_HI_BACKENDS[1]}" "${_HI_BACKENDS[0]}")
    PATH="$_HI_SHIM_PATH" _hi_resolve_backend yes
  )"
  [ "$out" = podman ]
}

function test_resolve_backend_prints_nothing_for_a_stranger() {
  [ -z "$(PATH="$_HI_SHIM_PATH" _hi_resolve_backend no)" ]
}

# no CLI at all: every predicate is false, and _hi falls through to ssh
function test_resolve_backend_prints_nothing_without_any_cli() {
  local empty="$_HI_WORKDIR/empty"
  mkdir -p "$empty"
  [ -z "$(PATH="$empty" _hi_resolve_backend yes)" ]
}

# an interactive session chainloads load.sh then calls load()
function test_bootloader_calls_load_for_a_session() {
  local out
  out="$(CMDARG="" _hi_bootloader)"
  # shellcheck disable=SC2016 # the rc must carry a literal $_HI_ROOT for the target to expand
  [[ "$out" == *'source $_HI_ROOT/load.sh'* && "$out" == *$'\nload'* ]]
}

# ...and a one-off command replaces that call outright, so load() - and with
# it the header, the rc grafting and clean_all - never runs
function test_bootloader_replaces_load_with_the_command() {
  local out
  out="$(CMDARG='echo hi; exit' _hi_bootloader)"
  [[ "$out" == *'echo hi; exit'* && "$out" != *$'\nload\n'* ]]
}

# load.sh sets `-euo pipefail` at source time and only load() clears it, but
# the $CMDARG shape replaces load() outright - so the bootloader has to clear
# it itself or the user's command runs with an unset variable being fatal and
# any non-zero status ending the session. That killed `source $_HI_ALIASES` on
# any target without explicit toggles, which is the default.
function test_bootloader_drops_strict_mode_before_the_command() {
  _hi_before "$(CMDARG='echo hi' _hi_bootloader)" 'set +euo pipefail' 'echo hi'
}

# ...and the strict-mode reset must land after load.sh is sourced, not before,
# or it's simply overwritten by load.sh's own `set -euo pipefail`
function test_bootloader_drops_strict_mode_after_sourcing_load() {
  _hi_before "$(CMDARG='echo hi' _hi_bootloader)" 'load\.sh' 'set +euo pipefail'
}

function test_fallback_rc_sources_paths_and_aliases() {
  local out
  out="$(CMDARG="" _hi_fallback_rc)"
  # shellcheck disable=SC2016 # same as above - $_HI_ROOT is the target's to expand
  [[ "$out" == *'$_HI_ROOT/common/paths.sh'* && "$out" == *'$_HI_ROOT/shells/aliases.sh'* ]]
}

function test_fallback_rc_appends_the_command() {
  [[ "$(CMDARG='echo hi; exit' _hi_fallback_rc)" == *'echo hi; exit'* ]]
}

# the no-bash target is one of the four entry points that has to source the
# settings ahead of paths.sh - paths.sh's local-only gate reads them, so lines
# arriving after it would be set too late to have any effect
function test_fallback_rc_sources_settings_before_paths() {
  _hi_before "$(CMDARG="" _hi_fallback_rc)" 'misc/settings\.sh' 'common/paths\.sh'
}

# bash reads an --rcfile only when it is interactive, and decides that from its
# own stdin rather than the flag - so without the explicit -i, a target reached
# with no local tty (`ssh -t` can't allocate one then) silently ignores
# hi.bashrc, taking load.sh and $CMDARG with it, and `hi <target> <command>`
# from a script or a pipe does nothing at all while still exiting 0.
# The flag order is part of the assertion, not incidental: bash parses its GNU
# long options in a pass that ends at the first short one, so `bash -i --rcfile
# f` exits with "--: invalid option" and no shell at all.
# $hi_esc/$nc_esc/$DOMAIN are _say_hi's locals, supplied here because this file
# runs under `set -u`.
function test_remote_suffix_forces_an_interactive_bash() {
  # shellcheck disable=SC2016 # $_hi_rc_dir is the target's to expand, not ours
  [[ "$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)" == *'bash --rcfile "$_hi_rc_dir/hi.bashrc" -i'* ]]
}

# the mirror of the above: every fallback shell already starts explicitly
# interactive, which is why they kept working when the bash arm didn't
function test_remote_suffix_fallbacks_are_interactive() {
  local out
  out="$(hi_esc="" nc_esc="" DOMAIN=host _hi_remote_suffix)"
  [[ "$out" == *'zsh -i'* && "$out" == *'sh -i'* && "$out" == *'fish -C'* ]]
}

# The payload is an allow list; this is its drift guard. Exact match on the
# list (so nothing sneaks on the wire unnoticed) plus an existence check on
# every member (so a rename can't quietly ship an empty payload).
function test_payload_ships_exactly_the_travelled_paths() {
  local m
  [ "${_HI_PAYLOAD[*]}" = "common misc shells load.sh" ] || {
    _hi_cecho " | payload list changed: ${_HI_PAYLOAD[*]} - update this guard deliberately" "$RED"
    return 1
  }
  for m in "${_HI_PAYLOAD[@]}"; do
    [ -e "$_HI_ROOT/$m" ] || {
      _hi_cecho " | payload member missing from the tree: $m" "$RED"
      return 1
    }
  done
}

# --- the config overlay -----------------------------------------------------
#
# The payload only carries the *in-tree* misc/, so once the user's real
# settings/colors/packages live outside the tree they need their own stream or a
# target silently falls back to the shipped defaults. These assert the two
# halves that can be checked without a target: that nothing is sent when there
# is nothing to send, and that what is sent lands under the names paths.sh
# looks for.

function _hi_overlay_fixture() {
  local dir="$_HI_WORKDIR/$1"
  mkdir -p "$dir"
  shift
  for f in "$@"; do printf 'x\n' >"$dir/$f"; done
  printf '%s' "$dir"
}

function test_overlay_is_empty_without_one() {
  local dir="$_HI_WORKDIR/no-overlay"
  mkdir -p "$dir"
  ! (_HI_CONFIG_DIR="$dir" _hi_has_overlay) &&
    [ -z "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar)" ]
}

function test_overlay_is_seen_when_present() {
  local dir
  dir="$(_hi_overlay_fixture some colors)"
  (_HI_CONFIG_DIR="$dir" _hi_has_overlay)
}

# members land at the archive's top level under their plain names, since it is
# unpacked *over* the target's misc/ - a "colors" that arrived as "hi.d/colors"
# or "./config/colors" would be invisible to paths.sh
function test_overlay_tar_members_are_bare_names() {
  local dir listing
  dir="$(_hi_overlay_fixture members colors packages settings.sh)"
  listing="$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)"
  [ "$(printf '%s\n' "$listing" | sort | paste -sd, -)" = "colors,packages,settings.sh" ]
}

# only what the user actually has - an overlay holding one file must not carry
# a placeholder for the other two, which would shadow the tree's defaults
function test_overlay_tar_carries_only_what_exists() {
  local dir
  dir="$(_hi_overlay_fixture partial colors)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "colors" ]
}

# the additive personal aliases ride the same stream under their bare name,
# which is where shells/aliases.sh's tail line looks on the target
function test_overlay_tar_carries_aliases() {
  local dir
  dir="$(_hi_overlay_fixture withaliases aliases.sh)"
  [ "$(_HI_CONFIG_DIR="$dir" _hi_overlay_tar | tar tzf -)" = "aliases.sh" ]
}

# --- the basher shim (bin/hi) -------------------------------------------------
#
# basher links bin/hi onto PATH as a symlink into its cellar; the shim has to
# resolve through that link, name the package root's parent as _HI_HOME, and
# refuse a clone not named hi.d (every path resolves against $_HI_HOME/hi.d).
function test_basher_shim_works_through_a_symlink() {
  local dir="$_HI_WORKDIR/basherlink"
  mkdir -p "$dir"
  ln -sf "$_HI_ROOT/bin/hi" "$dir/hi"
  [ -n "$("$dir/hi" --version)" ]
}

function test_basher_shim_refuses_a_misnamed_clone() {
  local dir="$_HI_WORKDIR/not-hid/bin" out rc=0
  mkdir -p "$dir"
  cp "$_HI_ROOT/bin/hi" "$dir/hi"
  out="$("$dir/hi" --version 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && [[ "$out" == *"not named hi.d"* ]]
}

# --- the ksh/mksh git segment -------------------------------------------------
#
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

# ksh.sh has to ride the payload, or the rc sources a file that isn't there
function test_payload_carries_ksh_sh() {
  [ -f "$_HI_ROOT/shells/ksh.sh" ] && [[ " ${_HI_PAYLOAD[*]} " == *" shells "* ]]
}

# --- hi --help ----------------------------------------------------------------
#
# The one arm of the dispatch block that has to be *executed* rather than
# sourced: sourcing hi.sh stops at the BASH_SOURCE guard, which is above the
# `case "${1:-}"`. So these run the real launcher as a subprocess, with an ssh
# that fails loudly on $PATH - the whole point of the flag is that it never
# reaches ssh, and before it existed `hi -h` answered with ssh's usage block.

function _hi_help_out() {
  local dir="$_HI_WORKDIR/nossh"
  mkdir -p "$dir"
  cat >"$dir/ssh" <<'EOF'
#!/bin/sh
echo "ssh was called: $*" >&2
exit 97
EOF
  chmod +x "$dir/ssh"
  PATH="$dir:$PATH" "$_HI_LAUNCHER" "$@" 2>&1
}

function test_help_long_flag_prints_usage() {
  local out
  out="$(_hi_help_out --help)" || return 1
  [[ "$out" == "Usage: hi "* && "$out" != *"ssh was called"* ]]
}

function test_help_short_flag_prints_the_same() {
  [ "$(_hi_help_out -h)" = "$(_hi_help_out --help)" ]
}

# the two things a usage block is for: what the flags are, and how a name is
# resolved - hi's target ladder is the part no ssh user can guess
function test_help_lists_hi_s_own_flags() {
  local out flag
  out="$(_hi_help_out --help)" || return 1
  for flag in --doctor --version --tmux --no-tmux; do
    [[ "$out" == *"$flag"* ]] || return 1
  done
  [[ "$out" == *docker* && "$out" == *podman* && "$out" == *nomad* && "$out" == *kubernetes* ]]
}

# The same drift guard tests/test_runner.sh's suite table gets: a flag hi
# answers itself but the man page never mentions is a flag nobody finds.
# $_HI_USAGE's synopsis has to match the man page's .SH SYNOPSIS too. The
# flag list is scraped from the live --help output rather than copied here,
# so a flag added there is guarded the moment it exists - with a floor on the
# scrape's size, so a broken scrape can't pass as an empty loop.
function test_help_flags_are_all_in_the_man_page() {
  local man="$_HI_HOME/hi.d/docs/hi.1" out flags flag
  [ -f "$man" ] || return 1
  out="$(_hi_help_out --help)" || return 1
  _hi_read_lines flags < <(printf '%s\n' "$out" | grep -oE -- '\-\-[a-z][a-z-]+' | sort -u)
  [ "${#flags[@]}" -ge 4 ] || return 1
  for flag in -h "${flags[@]}"; do
    # the man page escapes every dash as \- for roff
    grep -q -- "${flag//-/\\\\-}" "$man" || return 1
  done
}

# The ladders drift the same way the flags do - doctor.sh once still promised
# "zsh/fish/sh" after ksh joined (the comment above $_HI_SHELL_LADDER tells
# it), and the man page repeated the trick with the session shells. Every
# shell either ladder can land you in has to be named in the page. The
# no-bash half reads the live variable; the session half is spelled out here
# because load.sh's default ranking is a literal inside _hi_session_shell -
# a stale copy of it fails this test the same way a stale man page would.
function test_shell_ladders_are_in_the_man_page() {
  local man="$_HI_HOME/hi.d/docs/hi.1" shell
  [ -f "$man" ] || return 1
  for shell in $_HI_SHELL_LADDER fish zsh bash nu; do
    # nu appears in prose as "nushell"; -w keeps "sh" from riding on "ssh"
    grep -Eqw -- "$shell(shell)?" "$man" || return 1
  done
}

# --- the bash-less prompt -----------------------------------------------------
#
# sh/ash/dash/ksh sessions used to get aliases and the host's own prompt, which
# on busybox is a bare "$". The line hi writes has to survive shells with no
# readline and no command substitution in PS1, so it bakes everything in on the
# client and leaves exactly one escape for the target to expand.

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

# --- the size hi reports, and the transport that carries it -------------------
#
# This block exists because both halves were wrong at once: the connect line
# reported `du` over the payload directories (the uncompressed tree, roughly
# double the truth), and the armored script had grown to within a few kilobytes
# of the *single-argument* execve limit, which is 128KB on Linux however large
# ARG_MAX is. The second one is a hard failure - "Argument list too long", no
# session at all - so it gets a guard with headroom rather than a comment.

function test_human_bytes_matches_du_shapes() {
  [ "$(_hi_human_bytes 0)" = 0B ] || return 1
  [ "$(_hi_human_bytes 1023)" = 1023B ] || return 1
  [ "$(_hi_human_bytes 1024)" = 1.0K ] || return 1
  [ "$(_hi_human_bytes 34559)" = 34K ] || return 1
  [ "$(_hi_human_bytes 5000000)" = 4.8M ]
}

# four characters per three bytes, rounded up - the padding is part of the
# answer, so n * 4 / 3 (which truncates it) is the wrong formula
function test_armored_len_rounds_up() {
  [ "$(_hi_armored_len 0)" = 0 ] || return 1
  [ "$(_hi_armored_len 1)" = 4 ] || return 1
  [ "$(_hi_armored_len 3)" = 4 ] || return 1
  [ "$(_hi_armored_len 4)" = 8 ] || return 1
  # against the real encoder, which is the only opinion that counts
  local n
  for n in 1 2 3 100 999; do
    [ "$(_hi_armored_len "$n")" -eq "$(head -c "$n" /dev/zero | base64 | tr -d '\n' | wc -c)" ] || return 1
  done
}

# the reported number counts what is sent, not what is on disk: it must be
# nowhere near `du` over the payload, which is what it used to be
function test_wire_size_is_not_the_disk_size() {
  local wire disk
  wire="$(_hi_wire_estimate)"
  disk="$(_hi_size)"
  [ -n "$wire" ] && [ "$wire" != "$disk" ]
}

# The guard with teeth. The script hi sends is armored twice - the tar and
# hi.sh inside it, then the whole thing again - and until it moved to stdin it
# travelled as one argv entry. It no longer does, but the number is worth
# watching: it is also what every session pays in bandwidth.
function test_payload_stays_clear_of_the_arg_limit() {
  local bytes
  bytes="$(_hi_armored_len "$(($(_hi_armored_len "$(wc -c <"$_HI_LAUNCHER")") + \
  $(_hi_armored_len "$(_hi_payload_tar | wc -c)")))")"
  # 128KB (MAX_ARG_STRLEN) is where it used to break outright; 256KB is the
  # "this has doubled, come and look" line
  [ "$bytes" -lt 262144 ]
}

# --- hi --version -----------------------------------------------------------
#
# The dispatch is executed, not sourced: --version lives in the trailing case
# below the source guard, which sourcing (this suite's usual route) never
# reaches.

# a packager's stamp (here stood in for by the env seam) wins outright
function test_version_prints_the_stamp() {
  [ "$(_HI_RELEASE=1.2.3 bash "$_HI_LAUNCHER" --version)" = "1.2.3" ]
}

# an unstamped checkout answers with git describe (--always: a bare commit
# hash before any tag exists), never with "unknown"
function test_version_falls_back_to_git_describe() {
  [ -d "$_HI_ROOT/.git" ] || return 0 # nothing to describe in a tarball tree
  local out
  out="$(_HI_RELEASE="" _hi_version)"
  [ -n "$out" ] && [[ "$out" != unknown* ]]
}

# ...and with neither stamp nor git, it says so instead of printing nothing
function test_version_is_candid_without_stamp_or_git() {
  [[ "$(_HI_RELEASE="" _HI_ROOT="$_HI_WORKDIR" _hi_version)" == unknown* ]]
}

# the version rides the preamble so the target's header can show it
function test_remote_preamble_exports_the_version() {
  [[ "$(DOMAIN=host _hi_remote_preamble)" == *'export _HI_RELEASE='* ]]
}

# ...and so does the client's glyph verdict: the glyphs render in the
# client's terminal, so the target must not re-probe its own locale
function test_remote_preamble_ships_the_glyph_verdict() {
  [[ "$(DOMAIN=host _HI_ASCII=1 _hi_remote_preamble)" == *'export _HI_ASCII="1"'* ]] &&
    [[ "$(DOMAIN=host _HI_ASCII="" LC_ALL=en_US.UTF-8 _hi_remote_preamble)" == *'export _HI_ASCII="0"'* ]]
}

# --- the preamble's TERM fallback --------------------------------------------
#
# The generated preamble is executed under a real sh with a controlled TERM
# and terminfo fixture, and the TERM it leaves behind is the assertion. Names
# invented here can't exist in the host's terminfo trees, so the host's own
# entries can't leak into the result.

function _hi_preamble_final_term() { # <env assignments...> - prints $TERM after the preamble ran
  local script
  script="$(DOMAIN=host _hi_remote_preamble)"
  # shellcheck disable=SC2016 # $TERM is the spawned sh's to expand, not ours
  env "$@" sh -c "$script"'
printf %s "$TERM"' 2>/dev/null
}

function test_term_fallback_swaps_an_unknown_term() {
  [ "$(_hi_preamble_final_term TERM=hi-test-no-such-term)" = xterm-256color ]
}

function test_term_fallback_keeps_a_term_with_terminfo() {
  local ti="$_HI_WORKDIR/terminfo"
  mkdir -p "$ti/h"
  : >"$ti/h/hi-test-present-term"
  [ "$(_hi_preamble_final_term TERM=hi-test-present-term TERMINFO="$ti")" = hi-test-present-term ]
}

function test_term_fallback_skips_ubiquitous_names() {
  [ "$(_hi_preamble_final_term TERM=xterm)" = xterm ]
}

function test_term_fallback_can_be_disabled() {
  [ "$(_hi_preamble_final_term TERM=hi-test-no-such-term _HI_TERM_FALLBACK=0)" = hi-test-no-such-term ]
}

# On a target, $_HI_CONFIG_DIR is the misc/ we just unpacked over, not
# ${XDG_CONFIG_HOME:-...}: a ~/.config/hi.d belonging to whoever we logged in as
# is not the config this session was asked to run with.
function test_fallback_rc_points_config_dir_at_the_shipped_tree() {
  # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand, not ours
  [[ "$(CMDARG="" _hi_fallback_rc)" == *'export _HI_CONFIG_DIR=$_HI_ROOT/misc'* ]]
}

function run_hi_tests() {
  _hi_workdir hitest
  _hi_probe_shims "$_HI_WORKDIR/shims"
  _HI_SHIM_PATH="$_HI_WORKDIR/shims:$PATH"

  _hi_suite_begin

  _hi_h1 "Testing hi.sh"

  _hi_h2 "Testing: _hi_parse (targets and flags)"
  _hi_check "A bare target" test_parse_takes_a_bare_target
  _hi_check "Keeps valueless flags" test_parse_keeps_valueless_flags
  _hi_check "Pairs a flag with its value" test_parse_pairs_a_flag_with_its_value
  _hi_check "-J's value is not mistaken for the target" test_parse_treats_jump_host_as_a_value_not_the_target
  _hi_check "-B's value is not mistaken for the target" test_parse_treats_bind_interface_as_a_value_not_the_target
  _hi_check "Several flags before the target" test_parse_handles_several_flags_before_the_target

  _hi_h2 "Testing: _hi_parse (commands and errors)"
  _hi_check "Trailing words become a command" test_parse_turns_trailing_words_into_a_command
  _hi_check "A plain session has no command" test_parse_leaves_cmdarg_empty_for_a_plain_session
  _hi_check "Rejects a flag missing its value" test_parse_rejects_a_flag_missing_its_value
  _hi_check "hi's own flags aren't forwarded to ssh" test_parse_takes_hi_flags_without_forwarding_them
  _hi_check "--tmux/--no-tmux set the toggle" test_parse_tmux_flags_set_the_toggle
  _hi_check "Names the offending flag" test_parse_names_the_offending_flag

  _hi_h2 "Testing: backend predicates"
  _hi_check "docker: running" test_is_docker_container_accepts_a_running_one
  _hi_check "docker: stopped" test_is_docker_container_rejects_a_stopped_one
  _hi_check "podman: running" test_is_podman_container_accepts_a_running_one
  _hi_check "nomad: running" test_is_nomad_alloc_accepts_a_running_one
  _hi_check "nomad: pending" test_is_nomad_alloc_rejects_a_pending_one
  _hi_check "kube: running" test_is_k8s_pod_accepts_a_running_one
  _hi_check "kube: pending" test_is_k8s_pod_rejects_a_pending_one
  _hi_check "All false with no CLI installed" test_predicates_are_false_without_their_cli

  _hi_h2 "Testing: _hi_resolve_backend"
  _hi_check "Picks the roster's first match" test_resolve_backend_picks_the_first_matching_row
  _hi_check "The roster decides, not the resolver" test_resolve_backend_follows_the_roster_order
  _hi_check "Nothing for an unknown target" test_resolve_backend_prints_nothing_for_a_stranger
  _hi_check "Nothing with no backend CLI at all" test_resolve_backend_prints_nothing_without_any_cli

  _hi_h2 "Testing: bootloader / fallback rc"
  _hi_check "A session calls load" test_bootloader_calls_load_for_a_session
  _hi_check "A command replaces load" test_bootloader_replaces_load_with_the_command
  _hi_check "Bootloader drops strict mode before the command" test_bootloader_drops_strict_mode_before_the_command
  _hi_check "Bootloader drops strict mode after sourcing load.sh" test_bootloader_drops_strict_mode_after_sourcing_load
  _hi_check "Fallback rc sources paths and aliases" test_fallback_rc_sources_paths_and_aliases
  _hi_check "Fallback rc appends the command" test_fallback_rc_appends_the_command
  _hi_check "Fallback rc sources settings before paths" test_fallback_rc_sources_settings_before_paths
  _hi_check "Fallback rc points at the shipped tree" test_fallback_rc_points_config_dir_at_the_shipped_tree

  _hi_h2 "Testing: remote shell handoff"
  _hi_check "The bash handoff is explicitly interactive" test_remote_suffix_forces_an_interactive_bash
  _hi_check "So is every no-bash fallback" test_remote_suffix_fallbacks_are_interactive

  _hi_h2 "Testing: the payload list"
  _hi_check "Ships exactly common/misc/shells/load.sh" test_payload_ships_exactly_the_travelled_paths

  _hi_h2 "Testing: hi --version"
  _hi_check "A stamp wins" test_version_prints_the_stamp
  _hi_check "A checkout answers with git describe" test_version_falls_back_to_git_describe
  _hi_check "Candid with no stamp and no git" test_version_is_candid_without_stamp_or_git
  _hi_check "The preamble exports it" test_remote_preamble_exports_the_version
  _hi_check "The preamble ships the glyph verdict" test_remote_preamble_ships_the_glyph_verdict

  _hi_h2 "Testing: the preamble's TERM fallback"
  _hi_check "Unknown TERM becomes xterm-256color" test_term_fallback_swaps_an_unknown_term
  _hi_check "A TERM with terminfo is kept" test_term_fallback_keeps_a_term_with_terminfo
  _hi_check "Ubiquitous names skip the probe" test_term_fallback_skips_ubiquitous_names
  _hi_check "_HI_TERM_FALLBACK=0 opts out" test_term_fallback_can_be_disabled

  _hi_h2 "Testing: the config overlay stream"
  _hi_check "Nothing sent without an overlay" test_overlay_is_empty_without_one
  _hi_check "Seen when present" test_overlay_is_seen_when_present
  _hi_check "Members are bare names" test_overlay_tar_members_are_bare_names
  _hi_check "Carries only what exists" test_overlay_tar_carries_only_what_exists
  _hi_check "aliases.sh rides the stream" test_overlay_tar_carries_aliases

  _hi_h2 "Testing: the basher shim (bin/hi)"
  _hi_check "Works through a symlink" test_basher_shim_works_through_a_symlink
  _hi_check "Refuses a clone not named hi.d" test_basher_shim_refuses_a_misnamed_clone

  _hi_h2 "Testing: the bash-less prompt"
  _hi_check "Carries user, host, color and separator" test_fallback_prompt_carries_user_host_and_color
  _hi_check "_HI_PROMPT_END applies here too" test_fallback_prompt_honors_the_separator_setting
  _hi_check "_HI_DISABLE_PROMPT skips it" test_fallback_prompt_respects_the_toggle
  _hi_check_requires dash "Renders in a real dash" test_fallback_prompt_renders_in_dash
  _hi_check "The shared rc stays shell-agnostic" test_fallback_rc_stays_shell_agnostic
  _hi_check "The POSIX arm appends it" test_remote_suffix_appends_the_prompt_for_posix_shells
  _hi_check "The container fallback gives ksh the git segment" test_container_fallback_gives_ksh_the_git_segment

  _hi_h2 "Testing: the size hi reports"
  _hi_check "_hi_human_bytes matches du's shapes" test_human_bytes_matches_du_shapes
  _hi_check "_hi_armored_len rounds up like base64" test_armored_len_rounds_up
  _hi_check "The wire size isn't the disk size" test_wire_size_is_not_the_disk_size
  _hi_check "The payload stays clear of the argv limit" test_payload_stays_clear_of_the_arg_limit

  _hi_h2 "Testing: the ksh/mksh git segment"
  _hi_check "ksh.sh's colors match core.sh" test_ksh_colors_match_core
  _hi_check "ksh.sh's glyphs match core.sh" test_ksh_glyphs_match_core
  _hi_check "The ksh arm sources it" test_remote_suffix_gives_ksh_the_segment
  _hi_check "The segment is expanded per prompt" test_fallback_prompt_git_segment_is_deferred
  _hi_check "No segment for sh/ash/dash" test_fallback_prompt_has_no_segment_by_default
  _hi_check "It rides the payload" test_payload_carries_ksh_sh

  _hi_h2 "Testing: hi --help"
  _hi_check "--help prints the usage line" test_help_long_flag_prints_usage
  _hi_check "-h is the same text" test_help_short_flag_prints_the_same
  _hi_check "Lists hi's flags and the target ladder" test_help_lists_hi_s_own_flags
  _hi_check "Every flag is in the man page" test_help_flags_are_all_in_the_man_page
  _hi_check "Both shell ladders are in the man page" test_shell_ladders_are_in_the_man_page

  _hi_suite_end "hi.sh"
}

run_hi_tests
