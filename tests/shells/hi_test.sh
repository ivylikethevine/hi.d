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
# shellcheck disable=SC2329,SC2317
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"
# shellcheck source=../../hi.sh
source "$_HI_LAUNCHER"

_HI_SHIM_PATH=""

# Each shim answers only the exact invocation hi.sh makes and fails anything
# else, so a changed command shape shows up as a failing predicate rather than
# a silently passing test. "yes" is running/Running, "no" is not.
function _hi_write_shims() {
  local dir="$_HI_WORKDIR/shims"
  mkdir -p "$dir"

  cat >"$dir/docker" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "container inspect -f" ] || exit 1
case "$5" in yes) printf 'true\n' ;; *) printf 'false\n' ;; esac
EOF

  # podman is a drop-in for docker in hi.sh, so the shim is the same file
  cp "$dir/docker" "$dir/podman"

  cat >"$dir/nomad" <<'EOF'
#!/bin/sh
[ "$1 $2 $3" = "alloc status -t" ] || exit 1
case "$5" in yes) printf 'running\n' ;; *) printf 'pending\n' ;; esac
EOF

  cat >"$dir/kubectl" <<'EOF'
#!/bin/sh
[ "$1 $2 $4" = "get pod -o" ] || exit 1
case "$3" in yes) printf 'Running\n' ;; *) printf 'Pending\n' ;; esac
EOF

  chmod +x "$dir"/*
  _HI_SHIM_PATH="$dir:$PATH"
}

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

# --- the per-host settings overlay ------------------------------------------
#
# settings.d/<host>.sh and settings.d/tag-<tag>.sh ride the same stream, but
# unlike the three flat files they are *selected*: only the files matching this
# target are sent, since another host's settings have no business on this box.

# a config dir holding settings.d/{myhost,otherhost,tag-prod}.sh, plus an ssh
# config that tags myhost as prod - enough for every selection case below
function _hi_host_overlay_fixture() {
  local dir="$_HI_WORKDIR/hostoverlay" f
  [ -d "$dir/settings.d" ] || {
    mkdir -p "$dir/settings.d"
    for f in myhost otherhost tag-prod; do printf 'x\n' >"$dir/settings.d/$f.sh"; done
    printf '# Tags: prod, web\nHost myhost\n' >"$dir/ssh_config"
  }
  printf '%s' "$dir"
}

# _hi_host_overlay_members <target> - the tar's members for that target
function _hi_host_overlay_members() {
  local dir
  dir="$(_hi_host_overlay_fixture)"
  DOMAIN="$1" _HI_CONFIG_DIR="$dir" _HI_SSH_CONFIG="$dir/ssh_config" \
    _hi_overlay_tar | tar tzf - | sort | paste -sd, -
}

# an untagged host gets its own file and nothing else
function test_host_overlay_sends_only_the_matching_file() {
  [ "$(_hi_host_overlay_members otherhost)" = "settings.d/otherhost.sh" ]
}

# a tagged host gets both, and the members keep their settings.d/ prefix - they
# are unpacked over the target's misc/, which is its $_HI_CONFIG_DIR
function test_host_overlay_sends_the_hosttag_file_too() {
  [ "$(_hi_host_overlay_members myhost)" = "settings.d/myhost.sh,settings.d/tag-prod.sh" ]
}

function test_host_overlay_sends_nothing_for_an_unknown_host() {
  [ -z "$(_hi_host_overlay_members nosuchhost)" ]
}

# a settings.d file alone is still an overlay: without this, a user who only
# configured one host would have nothing sent at all
function test_host_overlay_counts_as_an_overlay() {
  local dir
  dir="$(_hi_host_overlay_fixture)"
  (DOMAIN=otherhost _HI_CONFIG_DIR="$dir" _HI_SSH_CONFIG="$dir/ssh_config" _hi_has_overlay)
}

# the bash-less rc resolves the same files on the client, and must source them
# after settings.sh - the specific file has to be able to override the global one
function test_fallback_rc_sources_the_host_overlay_after_settings() {
  local dir out
  dir="$(_hi_host_overlay_fixture)"
  out="$(DOMAIN=myhost _HI_CONFIG_DIR="$dir" _HI_SSH_CONFIG="$dir/ssh_config" CMDARG="" _hi_fallback_rc)"
  _hi_before "$out" 'misc/settings\.sh' 'settings\.d/tag-prod\.sh' &&
    _hi_before "$out" 'settings\.d/tag-prod\.sh' 'settings\.d/myhost\.sh' &&
    _hi_before "$out" 'settings\.d/myhost\.sh' 'common/paths\.sh'
}

# --- hi --update ------------------------------------------------------------
#
# Three branches, all reachable without a host: no permanent install on the
# target, one without a .git (a packaged install), and the real pull. `ssh` is
# shadowed by a shell function - _hi_update calls the binary by name, so a
# function of that name in this shell is what it reaches. Each case runs in a
# subshell, since _hi_parse assigns $DOMAIN/$SSHARGS/$CMDARG globally.
#
# $_HI_SSH_LOG records what the stub was asked to run, so the assertions can be
# about the command that would have reached the target rather than about our
# own plumbing.

# shellcheck disable=SC2016 # the probe's $HOME is the target's, matched literally
function _hi_ssh_stub() {
  # the ControlMaster teardown _hi_update always ends with
  [ "${1:-}" = "-O" ] && return 0
  local last="${*: -1}"
  printf '%s\n' "$last" >>"$_HI_SSH_LOG"
  case "$last" in
  # the install probe: _hi_remote_root's one-liner, answered with whatever
  # this case wants the target to look like
  *'$HOME/hi.d'*) printf '%s' "$_HI_REMOTE_ROOT" ;;
  # the update itself, run for real under sh so its own guard is exercised
  *) sh -c "$last" ;;
  esac
}

function _hi_update_case() {
  local root="$1"
  shift
  _HI_SSH_LOG="$_HI_WORKDIR/ssh.log"
  : >"$_HI_SSH_LOG"
  (
    # shellcheck disable=SC2317 # called through _hi_update's `ssh`
    function ssh() { _hi_ssh_stub "$@"; }
    _HI_REMOTE_ROOT="$root" _hi_update "$@"
  )
}

function test_update_needs_a_target() {
  ! _hi_update_case "" 2>/dev/null
}

function test_update_refuses_a_trailing_command() {
  ! _hi_update_case "" myhost 'echo hi' 2>/dev/null
}

# nothing installed there: a session would ship a fresh copy anyway
function test_update_refuses_without_a_permanent_install() {
  local out
  out="$(_hi_update_case "" myhost 2>&1)" && return 1
  case "$out" in *"no permanent hi.d"*) return 0 ;; esac
  return 1
}

# a packaged install has no .git - the same refusal hi_update makes locally
function test_update_refuses_a_package_manager_install() {
  local root out
  root="$_HI_WORKDIR/packaged/hi.d"
  mkdir -p "$root"
  out="$(_hi_update_case "$root" myhost 2>&1)" && return 1
  case "$out" in *"package manager"*) return 0 ;; esac
  return 1
}

# the real branch: a checkout on the target gets `git pull` in it, and nothing
# else - no session, no payload, no rc grafting
function test_update_pulls_a_checkout() {
  local root
  root="$_HI_WORKDIR/checkout/hi.d"
  mkdir -p "$root/.git"
  _hi_update_case "$root" myhost >/dev/null 2>&1
  grep -q "git -C '$root' pull" "$_HI_SSH_LOG"
}

# ssh flags still reach ssh, so `hi --update -p 2222 host` works like `hi` does
function test_update_keeps_ssh_flags() {
  local root
  root="$_HI_WORKDIR/checkout/hi.d"
  mkdir -p "$root/.git"
  (
    # shellcheck disable=SC2317 # called through _hi_update's `ssh`
    function ssh() {
      [ "${1:-}" = "-O" ] && return 0
      printf '%s\n' "$*" >>"$_HI_WORKDIR/flags.log"
      printf '%s' "$_HI_REMOTE_ROOT"
    }
    : >"$_HI_WORKDIR/flags.log"
    _HI_REMOTE_ROOT="$root" _hi_update -p 2222 myhost >/dev/null 2>&1
    grep -q -- "-p 2222 myhost" "$_HI_WORKDIR/flags.log"
  )
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
  $(_hi_armored_len "$(tar czf - -h -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/hi.d/}" | wc -c)")))")"
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
  _hi_write_shims

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

  _hi_h2 "Testing: bootloader / fallback rc"
  _hi_check "A session calls load" test_bootloader_calls_load_for_a_session
  _hi_check "A command replaces load" test_bootloader_replaces_load_with_the_command
  _hi_check "Bootloader drops strict mode before the command" test_bootloader_drops_strict_mode_before_the_command
  _hi_check "Bootloader drops strict mode after sourcing load.sh" test_bootloader_drops_strict_mode_after_sourcing_load
  _hi_check "Fallback rc sources paths and aliases" test_fallback_rc_sources_paths_and_aliases
  _hi_check "Fallback rc appends the command" test_fallback_rc_appends_the_command
  _hi_check "Fallback rc sources settings before paths" test_fallback_rc_sources_settings_before_paths

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
  _hi_check "Fallback rc points at the shipped tree" test_fallback_rc_points_config_dir_at_the_shipped_tree

  _hi_h2 "Testing: the size hi reports"
  _hi_check "_hi_human_bytes matches du's shapes" test_human_bytes_matches_du_shapes
  _hi_check "_hi_armored_len rounds up like base64" test_armored_len_rounds_up
  _hi_check "The wire size isn't the disk size" test_wire_size_is_not_the_disk_size
  _hi_check "The payload stays clear of the argv limit" test_payload_stays_clear_of_the_arg_limit

  _hi_h2 "Testing: the per-host settings overlay"
  _hi_check "Only the matching host's file is sent" test_host_overlay_sends_only_the_matching_file
  _hi_check "A tagged host gets its hosttag file too" test_host_overlay_sends_the_hosttag_file_too
  _hi_check "Nothing sent for an unconfigured host" test_host_overlay_sends_nothing_for_an_unknown_host
  _hi_check "A settings.d file alone counts as an overlay" test_host_overlay_counts_as_an_overlay
  _hi_check "Fallback rc sources it after settings.sh" test_fallback_rc_sources_the_host_overlay_after_settings

  _hi_h2 "Testing: hi --update"
  _hi_check "Needs a target" test_update_needs_a_target
  _hi_check "Refuses a trailing command" test_update_refuses_a_trailing_command
  _hi_check "Refuses without a permanent install" test_update_refuses_without_a_permanent_install
  _hi_check "Refuses a package-manager install" test_update_refuses_a_package_manager_install
  _hi_check "Pulls a checkout on the target" test_update_pulls_a_checkout
  _hi_check "Keeps ssh flags" test_update_keeps_ssh_flags

  _hi_suite_end "hi.sh"
}

run_hi_tests
