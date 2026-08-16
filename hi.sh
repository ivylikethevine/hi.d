#!/bin/bash
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies hi.d to the target and chainloads load.sh there.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# shellcheck source=./common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"

# The version this copy answers `hi --version` with. Empty in git - a checkout
# answers with `git describe` instead (see _hi_version) - and sed to the real
# version by every packager at build time: package.sh stamps the staged copy
# for deb/rpm/apk, the PKGBUILD and the Homebrew formula stamp theirs. The
# ${...:-} default keeps the env seam open: the ssh preamble exports the
# resolved version into a session, so the shipped copy on a target answers
# too. Once a packager stamps a literal, the file wins and env stops mattering.
_HI_RELEASE="${_HI_RELEASE:-}"

# What ships to a target, by name. An allow list, not excludes: anything new in
# the tree (docs, CI, editor config) stays off the wire until it earns a place
# here. install.sh's _HI_PACKAGE_CONTENTS answers the different question of
# what an *installed* copy needs.
_HI_PAYLOAD=(common misc shells load.sh)

# The user's config overlay ($_HI_CONFIG_DIR, outside the tree), by the names it
# has to land under in the target's misc/. Until the overlay existed these rode
# along inside the payload above for free; now they need their own stream.
_HI_OVERLAY_FILES=(settings.sh colors packages tmux.conf)

# base64, not openssl: the armor is pure ASCII transport encoding (no crypto),
# and base64 ships on strictly more targets - coreutils, busybox, macOS/BSD,
# Git Bash. Decode tries GNU/busybox -d first, then old BSD/macOS -D; the
# failed flag parse consumes no stdin, so the fallback still sees the whole
# stream. tr first, because GNU base64 -d tolerates the armor's newlines but
# not spaces, and a transport that folds newlines into spaces would otherwise
# break it. $_HI_UNARMOR only ever runs inside the sh bootloader (the login
# shell never parses its braces - fish couldn't).
# Stands in for the connect line's size until the script carrying it has been
# assembled and measured (see _say_hi); wider than any answer it can produce.
# What a bash-less target falls back to, best first. One definition, because
# both transports probe for it and scripts/doctor.sh reports on it - it was
# three copies, and doctor's had already drifted (it still promised
# "zsh/fish/sh" after ksh joined). ksh and mksh need no arm of their own: they
# read $ENV exactly as sh does.
export _HI_SHELL_LADDER="zsh fish ksh mksh sh"

_HI_SIZE_TOKEN="@@SIZE@@"

_HI_ARMOR="base64"
_HI_UNARMOR="tr -s ' ' '\n' | { base64 -d 2>/dev/null || base64 -D; }"

# The target's tag and color, resolved once per run. Each resolution walks
# ~/.ssh/config line by line, and three callers wanted the same answer: the
# remote preamble, the per-host overlay selection, and the bash-less prompt.
# Memoized the way core.sh memoizes _hi_hostname, for the same reason.
function _hi_target_tag() {
  [ -n "${_HI_TARGET_TAG_CACHE+x}" ] ||
    _HI_TARGET_TAG_CACHE="$(_hi_ssh_host_tag "$DOMAIN" 2>/dev/null || true)"
  printf '%s' "$_HI_TARGET_TAG_CACHE"
}

function _hi_target_color() {
  [ -n "${_HI_TARGET_COLOR_CACHE:-}" ] ||
    _HI_TARGET_COLOR_CACHE="$(_hi_resolve_color hostname "${DOMAIN##*@}")"
  printf '%s' "$_HI_TARGET_COLOR_CACHE"
}

# The per-host settings for this target, named as they sit under
# $_HI_CONFIG_DIR: hosttag file, then exact-host file (core.sh sources them in
# that order, so the specific one wins). Only files matching *this* target are
# ever sent. $DOMAIN is unset when hi.sh is merely sourced - hence the guard.
function _hi_overlay_host_files() {
  local tag f
  [ -n "${DOMAIN:-}" ] || return 0
  tag="$(_hi_target_tag)"
  for f in ${tag:+"settings.d/tag-$tag.sh"} "settings.d/$DOMAIN.sh"; do
    [ -f "$_HI_CONFIG_DIR/$f" ] && printf '%s\n' "$f"
  done
  return 0
}

# True when the user has any overlay at all. Both transports ask first rather
# than piping an empty archive at `tar mxzf -`, which is an "unexpected EOF"
# error rather than a no-op - an unconfigured user must pay nothing for this.
function _hi_has_overlay() {
  local f
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    [ -f "$_HI_CONFIG_DIR/$f" ] && return 0
  done
  [ -n "$(_hi_overlay_host_files)" ] && return 0
  return 1
}

# A tar of whichever overlay files the user has, to be unpacked over the
# target's misc/. One `tar` with explicit member names rather than a rename
# pass, so it stays portable to bsdtar (no GNU --transform) and the members land
# at misc/'s top level under the names paths.sh already looks for.
function _hi_overlay_tar() {
  local f
  local -a present=()
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    [ -f "$_HI_CONFIG_DIR/$f" ] && present+=("$f")
  done
  # the per-host files ride the same stream, keeping their settings.d/ prefix so
  # they land where core.sh looks for them on the target
  while IFS= read -r f; do
    [ -n "$f" ] && present+=("$f")
  done < <(_hi_overlay_host_files)
  ((${#present[@]})) || return 0
  tar czf - -h -C "$_HI_CONFIG_DIR" "${present[@]}"
}

# Reads ~/.ssh/config directly rather than through targets.sh, which would fork
# a shell, an awk and a grep plus the completion cache to answer a question
# about a static file. Same matching rule targets.sh uses: literal names only,
# no wildcards, stopping at a trailing comment.
function _hi_is_ssh_host() {
  [ -f "$_HI_SSH_CONFIG" ] &&
    awk -v want="$1" '
      tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) break
          if ($i !~ /[*?]/ && $i == want) { found = 1; exit }
        }
      }
      END { exit !found }
    ' "$_HI_SSH_CONFIG"
}

# podman's CLI is a drop-in for docker's here, so only the binary differs. Both
# named wrappers stay - the dispatcher and hi_test.sh call them by name.
function _hi_is_container_running() {
  command -v "$1" >/dev/null 2>&1 &&
    [ "$("$1" container inspect -f '{{.State.Running}}' "$2" 2>/dev/null)" = true ]
}

function _hi_is_docker_container() { _hi_is_container_running docker "$1"; }
function _hi_is_podman_container() { _hi_is_container_running podman "$1"; }

function _hi_is_nomad_alloc() {
  command -v nomad >/dev/null 2>&1 &&
    [ "$(nomad alloc status -t '{{.ClientStatus}}' "$1" 2>/dev/null)" = running ]
}

# like nomad's multi-task allocations, a multi-container pod needs `-c <name>`
# to pick one; that isn't passed through, so this wants a single unambiguous
# container. kubectl warns and uses the first rather than failing outright.
function _hi_is_k8s_pod() {
  command -v kubectl >/dev/null 2>&1 &&
    [ "$(kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]
}

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@" ahead
# of it. Every command hi sends meets the target's *login* shell first, and that
# shell may be fish, which parses neither `x=1` nor `{ ...; }` nor `||` as sh
# does. Wrapping is therefore not per-site care but the transport's job - the
# alternative is finding out one function at a time (the install probe answered
# "nothing installed" on every fish-login host until it was wrapped).
#
# The quoting is single-quote-and-escape rather than printf %q: %q escapes every
# space with a backslash, which the login shell then has to unescape - readable
# in neither the code nor a `ssh -v` log, and one more thing for fish to differ
# about. Callers write plain sh and never count quotes.
function _hi_ssh_sh() {
  local script="$1"
  shift
  # shellcheck disable=SC2029 # the script is ours to expand, here, on purpose
  ssh "$@" "${SSHARGS[@]}" "$DOMAIN" "sh -c '${script//\'/\'\\\'\'}'"
}

# Cheap check for a permanent hi.d already on $DOMAIN (scripts/install.sh has
# been run there): prints its path if so. Runs over the ssh ControlMaster in
# "$@", so it costs no extra authentication - _say_hi's real connection
# multiplexes through the same socket.
# shellcheck disable=SC2016 # the probe's variables are the target's to expand
function _hi_remote_root() {
  local out
  out="$(_hi_ssh_sh '_r="$HOME/hi.d"; [ -x "$_r/hi.sh" ] && [ -f "$_r/common/paths.sh" ] && printf "%s" "$_r"' \
    "$@" -o ConnectTimeout=5 2>/dev/null)" || out=""
  printf '%s' "$out"
}

# `hi --update <target>` - update a *permanent* hi.d on the target without
# opening a session, so a fleet is one command per host. This is paths.sh's
# `hi_update` alias run over ssh: `git pull` and nothing else, with the same two
# refusals. An ephemeral session ships a fresh copy every connect and has
# nothing to update; a package-manager install belongs to the package manager.
function _hi_update() {
  local root ctl_path ec=0
  local -a ctl_opts

  [ $# -gt 0 ] || {
    _hi_cecho "hi --update needs a target" "$RED" >&2
    return 1
  }
  # the same parse the connection paths use, so ssh flags still work
  # (`hi --update -p 2222 host`); a trailing command does not, since this
  # runs one specific command of its own
  _hi_parse "$@"
  [ -z "${CMDARG:-}" ] && [ -n "${DOMAIN:-}" ] || {
    _hi_cecho "hi --update takes a target and ssh flags, nothing else" "$RED" >&2
    return 1
  }

  # containers, allocs and pods never have a permanent install: they get a
  # fresh tree per session and take it with them when they stop
  if _hi_is_docker_container "$DOMAIN" || _hi_is_podman_container "$DOMAIN" ||
    _hi_is_nomad_alloc "$DOMAIN" || _hi_is_k8s_pod "$DOMAIN"; then
    _hi_cecho "hi --update is for ssh targets with a permanent hi.d; [$DOMAIN] gets a fresh copy every session" "$YELLOW" >&2
    return 1
  fi

  # one connection for the probe and the pull, exactly as _say_hi multiplexes
  # its probe and its session - two authentications for one command would be
  # the wrong price for a convenience
  ctl_path="$(mktemp -u -t hi.cm.XXXXXX)"
  ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o ControlPersist=30)
  root="$(_hi_remote_root "${ctl_opts[@]}")"

  if [ -z "$root" ]; then
    # the probe answers the same empty string for "reachable, nothing installed"
    # and "never reached at all", so the message has to own both cases rather
    # than assert the one it can't tell from the other
    _hi_cecho "hi --update: no permanent hi.d on [$DOMAIN], or the host could not be reached. A hi session ships a fresh copy every connect, so there is nothing there to update" "$YELLOW" >&2
    ec=1
  else
    _hi_cecho " updating $root on [$DOMAIN]" "$BRBLUE"
    # .git as the test, the same one hi_update makes locally: it is absent both
    # from a payload and from a packaged install
    _hi_ssh_sh "[ -d '$root/.git' ] || { echo 'hi --update: no .git in $root - if a package manager installed hi.d there, update it with that package manager' >&2; exit 1; }; git -C '$root' pull" \
      "${ctl_opts[@]}" || ec=$?
  fi

  ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$ctl_path" 2>/dev/null || true
  return "$ec"
}

function _hi_copy_time() {
  awk -v now="$(_hi_now)" -v a="$1" -v b="$2" -v c="$3" 'BEGIN { printf "%.3f", (now - a) - (c - b) }'
}

# load.sh turns `set -euo pipefail` on at source time and load() turns it back
# off before the header. The $CMDARG shape replaces load() rather than calling
# it, so without the middle line a one-off `hi <target> <cmd>` would run the
# user's command under -e -u pipefail, where an unset variable is fatal and any
# non-zero status ends the session.
# (This made `source $_HI_ALIASES` die on _HI_DISABLE_EDITORS whenever the
# target had no explicit toggles set - the default.)
function _hi_bootloader() {
  cat <<EOF
source \$_HI_ROOT/load.sh
set +euo pipefail
${CMDARG:-load}
EOF
}

# The no-bash target's rc, consumed by sh, zsh *and* fish (see _say_hi's
# `fish -C` branch), so every line must be valid in all three - `export
# NAME=value` and `[ -f x ] && . x` are. Anything shell-specific (the POSIX
# prompt, say) is appended by that shell's own arm, not written here.
#
# Toggle defaults come first so the files after them can still win.
# _HI_REMOTE_SESSION is 1 because this *is* a remote session and this path never
# reaches load.sh, which normally exports it; unset, paths.sh's gate reads the
# target as local and strips hi for anyone with _HI_DISABLE_LOCAL=1. settings.sh
# needs its `[ -f ]` guard because nothing writes it until install.sh runs, and
# a bare `.` on a missing file abandons the rest of the file in ash/dash.
# _HI_CONFIG_DIR is the target's own misc/, where the shipped overlay was
# unpacked - not a ~/.config/hi.d belonging to whoever we logged in as.
function _hi_fallback_rc() {
  local t
  # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
  printf 'export _HI_CONFIG_DIR=$_HI_ROOT/misc\nexport _HI_REMOTE_SESSION=1\n'
  # the toggle list is core.sh's _HI_TOGGLES, so a new toggle can't be missed
  # here (unset + `set -u` on a bash-less target was exactly that failure)
  for t in "${_HI_TOGGLES[@]}"; do
    [ "$t" = _HI_REMOTE_SESSION ] || printf 'export %s=0\n' "$t"
  done
  # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
  printf '[ -f $_HI_ROOT/misc/settings.sh ] && . $_HI_ROOT/misc/settings.sh\n'
  # The per-host overlay, resolved here because this rc has no $_HI_TARGET to
  # test and never reaches core.sh, which does it everywhere else. Same order
  # (hosttag, then host) and after settings.sh, so the specific file wins.
  for t in $(_hi_overlay_host_files); do
    # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
    printf '[ -f $_HI_ROOT/misc/%s ] && . $_HI_ROOT/misc/%s\n' "$t" "$t"
  done
  cat <<EOF
. \$_HI_ROOT/common/paths.sh 2>/dev/null
. \$_HI_ROOT/shells/aliases.sh 2>/dev/null
${CMDARG:-}
EOF
}

# A prompt for the bash-less tiers (sh, ash, dash, ksh, mksh - fish and zsh get
# their own rc). Until now they got aliases and their host's default prompt,
# which on a busybox target is a bare "$".
#
# Thin on purpose: the colors are resolved here (the same ones hi uses
# everywhere else), the username once when the rc is sourced rather than per
# prompt, and the only thing left for the shell to expand is the separator -
# `\$` by default, which every POSIX shell renders as $ for a user and # for
# root. No command substitution inside PS1: busybox ash does not do it there.
# shellcheck disable=SC2016 # $_hi_u and the separator are the target's to expand
function _hi_fallback_prompt() {
  local host="${DOMAIN##*@}" nc
  [ "${_HI_DISABLE_PROMPT:-0}" = 1 ] && return 0
  # _hi_color_escape already emits real escapes; only $NC is a literal to expand
  printf -v nc '%b' "$NC"
  printf '_hi_u=$(id -un 2>/dev/null || echo "${USER:-?}")\n'
  printf 'PS1=" %s${_hi_u}%s@%s%s%s %s "\n' \
    "$(_hi_user_escape)" "$nc" "$(_hi_color_escape "$(_hi_target_color)")" \
    "$host" "$nc" "$(_hi_prompt_end SH '\$')"
}

# The tree on disk, uncompressed - not what a session sends (see _hi_wire_size),
# but the right answer to "how big is the thing hi would ship". doctor.sh asks.
function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What crosses the connection: the streams measured as *sent* (gzipped, then
# armored), not the directories they came from - which is what `du` answered and
# why it overstated every session. Callers pass the strings they are about to
# send; the scaffolding around them isn't counted.
function _hi_wire_size() {
  local total=0 part
  for part in "$@"; do total=$((total + ${#part})); done
  # the outer armor, which every one of these streams also passes through
  _hi_human_bytes "$(_hi_armored_len "$total")"
}

# base64 length of <n> bytes: four chars per three-byte group, rounded up.
# Divide-then-multiply is the formula, not a slip - n * 4 / 3 loses the padding.
function _hi_armored_len() {
  # shellcheck disable=SC2017
  printf '%s' "$((($1 + 2) / 3 * 4))"
}

# What a fresh session would put on the wire, without connecting: the same
# streams _say_hi armors. The overlay isn't counted - which files ride along is
# a question about a target, and this has none. doctor.sh is the caller.
function _hi_wire_estimate() {
  # $_HI_LAUNCHER, not $0: this is reached by *sourcing* hi.sh (doctor.sh does),
  # where $0 is whatever ran the source. _say_hi keeps $0 - there it is the
  # running copy, which is the copy it ships.
  _hi_wire_size "$($_HI_ARMOR <"$_HI_LAUNCHER")" "$(_hi_bootloader | $_HI_ARMOR)" \
    "$(tar czf - -h -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/hi.d/}" | $_HI_ARMOR)"
}

# a file's size in bytes; `stat`'s flags differ GNU/BSD, `wc -c` doesn't
function _hi_file_bytes() {
  wc -c <"$1" | tr -d ' '
}

# bytes -> the shape `du -sh` prints ("28K", "1.2M"), which is what the connect
# line has always carried
function _hi_human_bytes() {
  awk -v b="$1" 'BEGIN {
    split("B K M G", unit, " ")
    i = 1
    while (b >= 1024 && i < 4) { b /= 1024; i++ }
    if (i == 1) printf "%dB", b
    else if (b < 10) printf "%.1f%s", b, unit[i]
    else printf "%.0f%s", b, unit[i]
  }'
}

# what this copy is: the packager's stamp when there is one, `git describe` in
# a checkout (--always answers with the bare commit before any tag exists),
# and a candid unknown for a stampless tree with no git to ask.
function _hi_version() {
  if [ -n "$_HI_RELEASE" ]; then
    printf '%s\n' "$_HI_RELEASE"
  elif [ -d "$_HI_ROOT/.git" ]; then
    git -C "$_HI_ROOT" describe --tags --always --dirty 2>/dev/null ||
      printf 'unknown (git would not answer)\n'
  else
    printf 'unknown (no stamp, no git)\n'
  fi
}

# The bit both _say_hi branches need before anything target-specific happens.
# The tmux lines settle only *whether it was asked for*; whether the target has
# tmux, and whether its tree is permanent, are load.sh's questions.
#
# Everything here is expanded on the client, so no backtick or unescaped $( )
# may appear below - not even inside a comment, which the shell hasn't seen yet.
function _hi_remote_preamble() {
  cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
      export _HI_TARGET="$DOMAIN"
      export _HI_TARGET_COLOR="$(_hi_target_color)"
      export _HI_TARGET_TAG="$(_hi_target_tag)"
      export _HI_LOCAL_USER="$(whoami)"
      export _HI_LOCAL_HOSTNAME="$(_hi_hostname)"
      export _HI_RELEASE="$(_hi_version)"
      export _HI_TMUX_ATTACH="${_HI_TMUX_ATTACH:-0}"
      export _HI_TMUX_SESSION="${_HI_TMUX_SESSION:-hi}"
      # the client's glyph verdict, not the target's: see _hi_ascii_flag
      export _HI_ASCII="${_HI_ASCII:-$(_hi_ascii_flag)}"
      # ssh forwards the client TERM verbatim, and a TERM the target has no
      # terminfo entry for (ghostty's xterm-ghostty is the canonical case)
      # breaks clear/backspace before hi even matters. Ubiquitous names skip
      # the probe; anything else must be found in a terminfo tree - plain
      # dirs and the BSD/macOS hex layout both checked - or it is swapped
      # for xterm-256color, which every tree that exists at all carries.
      # _HI_TERM_FALLBACK=0 keeps the original TERM no matter what.
      case "\${_HI_TERM_FALLBACK:-1}:\$TERM" in
      0:* | 1:xterm | 1:xterm-256color | 1:xterm-color | 1:screen | 1:screen-256color | 1:tmux | 1:tmux-256color | 1:linux | 1:vt100 | 1:vt220 | 1:dumb | 1:) ;;
      *)
        _hi_ti_ok=""
        _hi_ti_c=\${TERM%"\${TERM#?}"}
        _hi_ti_x=\$(printf '%x' "'\$_hi_ti_c" 2>/dev/null)
        for _hi_ti_d in "\${TERMINFO:-}" "\$HOME/.terminfo" /etc/terminfo /lib/terminfo /usr/share/terminfo; do
          [ -n "\$_hi_ti_d" ] || continue
          if [ -e "\$_hi_ti_d/\$_hi_ti_c/\$TERM" ] || [ -e "\$_hi_ti_d/\$_hi_ti_x/\$TERM" ]; then
            _hi_ti_ok=1
            break
          fi
        done
        [ -n "\$_hi_ti_ok" ] || export TERM=xterm-256color
        ;;
      esac
REMOTE
}

# What both _say_hi branches need once their own setup is done: report copy
# time, then hand off to bash, or to the best fallback shell. Expects
# \$_hi_rc_dir to point at wherever hi.bashrc/.hi_fallback_rc lives.
#
# `bash --rcfile X -i` needs both parts in that order: without -i bash decides
# it isn't interactive (from stdin, not the flag) and ignores the rcfile
# entirely - that was `hi <target> <cmd>` doing nothing from a script or cron -
# and after --rcfile, because bash's long-option pass ends at the first short
# one. fish's `exit` inside a sourced file only unwinds the source, so the fish
# case feeds the file's content to -C instead.
function _hi_remote_suffix() {
  cat <<REMOTE
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      if command -v bash >/dev/null 2>&1; then
        bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
      else
        _hi_fallback=sh
        for _hi_s in $_HI_SHELL_LADDER; do command -v "\$_hi_s" >/dev/null 2>&1 && { _hi_fallback="\$_hi_s"; break; }; done
        printf '%s no bash on [$DOMAIN], dropping into plain %s w/ aliases only %s\n' "$hi_esc" "\$_hi_fallback" "$nc_esc" >&2
        echo "$(_hi_fallback_rc | $_HI_ARMOR)" | $_HI_UNARMOR > "\$_hi_rc_dir/.hi_fallback_rc"
        case "\$_hi_fallback" in
        zsh)
          cp "\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_rc_dir/.zshrc"
          ZDOTDIR="\$_hi_rc_dir" zsh -i
          ;;
        fish) fish -C "\$(cat "\$_hi_rc_dir/.hi_fallback_rc")" ;;
        # ksh and mksh read the ENV variable for interactive shells exactly
        # as sh does, and the rc is POSIX, so they need no arm of their own -
        # only a name. The prompt is appended here rather than written into the
        # shared rc: that file also feeds fish (no PS1 at all) and zsh (where
        # the backslash-dollar escape means something else).
        *)
          echo "$(_hi_fallback_prompt | $_HI_ARMOR)" | $_HI_UNARMOR >> "\$_hi_rc_dir/.hi_fallback_rc"
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        esac
      fi
REMOTE
}

# Connect to the target, copy hi.d over, and hand off to load.sh.
# The payload goes to `sh -c` rather than the login shell, which may not parse
# the same syntax - every line up to the bash/sh branch is plain POSIX. So all
# of hi runs under one sh sub-process on the target, which chainloads bash when
# it's there.
function _say_hi() {
  local size hi_esc nc_esc script middle b64 boot_tmp remote_root tmp_root ctl_path ec=0
  local launcher="" bootloader="" tree="" overlay="" overlay_line=""
  local -a ctl_opts

  # only this path armors its payload; the container backends stream through
  # their own CLI's cp/exec. No target-side check: the bootloader itself only
  # arrives through the target's base64, so a target without one fails the
  # one-liner loudly before any of our script runs.
  command -v base64 >/dev/null 2>&1 || {
    _hi_cecho >&2 "hi requires base64 on [$(_hi_hostname)] to reach an ssh target, but it is not installed. Aborting..." "$RED"
    return 1
  }

  printf -v hi_esc '%b' "$YELLOW"
  printf -v nc_esc '%b' "$NC"

  # multiplex the install-probe and the real session over one ssh connection,
  # so checking for an existing install never costs a second authentication
  ctl_path="$(mktemp -u -t hi.cm.XXXXXX)"
  ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o ControlPersist=30)
  remote_root="$(_hi_remote_root "${ctl_opts[@]}")"

  if [ -n "$remote_root" ]; then
    # install.sh has already run on the target - load that copy in place
    # instead of shipping one over, and never delete it. No _HI_CLEANUP here is
    # what tells load.sh's clean_all to leave $_HI_ROOT alone.
    tmp_root="${remote_root%/hi.d}"
    middle="$(
      cat <<REMOTE
      export _HI_HOME="$tmp_root"
      export _HI_ROOT="$remote_root"
      _hi_rc_dir="\$(dirname "\$0")"
      printf '%s %s%s' "$hi_esc" "$nc_esc" "-> local hi.d install"
      echo "$(_hi_bootloader | $_HI_ARMOR)" | $_HI_UNARMOR > "\$_hi_rc_dir/hi.bashrc"
      export _HI_CONNECT_PREFIX="-> local hi.d install"
REMOTE
    )"
  else
    # armored before the script is assembled, so the size below is measured on
    # the bytes that actually go out
    launcher="$($_HI_ARMOR <"$0")"
    bootloader="$(_hi_bootloader | $_HI_ARMOR)"
    tree="$(tar czf - -h -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/hi.d/}" | $_HI_ARMOR)"
    # second, tiny stream over the tree we just unpacked: the payload carries
    # only the *in-tree* misc/, so an overlay outside it has to be sent
    # explicitly. Empty (and the line omitted entirely) when there is no
    # overlay to send. _HI_CONFIG_DIR then points at the target's own misc/, so
    # paths.sh resolves against what we shipped rather than against a
    # ~/.config/hi.d belonging to whoever we logged in as.
    if _hi_has_overlay; then
      overlay="$(_hi_overlay_tar | $_HI_ARMOR)"
      overlay_line="echo \"$overlay\" | $_HI_UNARMOR | tar mxzf - -C \"\$_HI_ROOT/misc\""
    fi
    # not known yet: everything above is armored again with the rest of the
    # script, so the figure can only be measured once it is assembled
    size="$_HI_SIZE_TOKEN"
    middle="$(
      cat <<REMOTE
      export _HI_HOME=\$(mktemp -d -t $(whoami).hi.XXXXXX) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_HOME/hi.d
      export _HI_CONFIG_DIR=\$_HI_ROOT/misc
      export _HI_CLEANUP=\$_HI_HOME
      mkdir "\$_HI_ROOT"
      trap 'rm -rf \$_HI_CLEANUP' exit
      _hi_rc_dir="\$_HI_ROOT"
      printf '%s %s%s' "$hi_esc" "$nc_esc" "$size"
      echo "$launcher" | $_HI_UNARMOR > "\$_HI_ROOT/hi.sh"
      chmod +x "\$_HI_ROOT/hi.sh"
      echo "$bootloader" | $_HI_UNARMOR > "\$_hi_rc_dir/hi.bashrc"
      echo "$tree" | $_HI_UNARMOR | tar mxzf - -C "\$_HI_HOME"
      $overlay_line
      export _HI_CONNECT_PREFIX=" $size"
REMOTE
    )"
  fi

  script="$(_hi_remote_preamble)
$middle
$(_hi_remote_suffix)"

  # The bytes this connection carries: base64 of the whole script, itself
  # base64 of the tar, hi.sh and the bootloader - armored twice, each armor 4/3
  # of what it wraps. Derived arithmetically before the outer armor, since the
  # number has to appear *inside* the thing it measures; $_HI_SIZE_TOKEN holds
  # its place and is the same width, so the figure is honest to a few bytes.
  if [ -z "$remote_root" ]; then
    size="$(_hi_human_bytes "$(_hi_armored_len "${#script}")")"
    script="${script//$_HI_SIZE_TOKEN/$size}"
  fi

  # single-line armor portably: GNU spells it -w0, BSD doesn't wrap by
  # default - piping through tr is the one shape that does both
  b64="$(printf '%s' "$script" | base64 | tr -d '\n')"
  # -u: a name only, never a local file - the directory it names is created on
  # the *target* by the mkdir below (which fails loudly if the name is taken)
  boot_tmp="$(mktemp -u -t hi.boot.XXXXXX)"

  # Two calls, multiplexed over the one connection (so still one
  # authentication). The script cannot travel as an argument: Linux caps a
  # *single* argv entry at 128KB (MAX_ARG_STRLEN) however large ARG_MAX is, and
  # the payload had grown within a few KB of it - one more shipped file and
  # every session would have died with "Argument list too long". stdin has no
  # ceiling. It has to be two calls because the second one's stdin belongs to
  # the interactive session; feed it a pipe and the remote shell reads EOF.
  #
  # The write doubles as the probe, inside one `sh -c` for the reason
  # $_HI_UNARMOR gives above: the command meets the *login* shell first, and
  # that may be fish, which parses neither `{ ...; }` nor `||` as sh does. A
  # target where even `sh -c` won't run has no POSIX shell (stock Windows
  # OpenSSH), which is what selects the PowerShell fallback below. The `tr` step
  # is dropped: stdin delivers the armor byte for byte, and folding newlines
  # into spaces was the only thing it ever fixed.
  # shellcheck disable=SC2029 # $boot_tmp is ours to expand, into the target's shell
  if printf '%s' "$b64" | ssh "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
    "sh -c 'mkdir -m 700 $boot_tmp && { base64 -d 2>/dev/null || base64 -D; } > $boot_tmp/bootloader'" 2>/dev/null; then
    # shellcheck disable=SC2029
    ssh -t "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      "sh $boot_tmp/bootloader; rm -rf $boot_tmp" || ec=$?
  else
    ssh -t "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      powershell -NoLogo -NoExit -Command \
      "Write-Host 'hi from PowerShell - no bash or sh on this host, hi.d colors/aliases are unavailable' -ForegroundColor Yellow" || ec=$?
  fi

  ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$ctl_path" 2>/dev/null || true
  return "$ec"
}

# Four backends share this function: docker, podman (docker-CLI-compatible),
# nomad (its own alloc exec syntax) and kube (kubectl exec, `--` separating its
# flags from the remote command). The case below picks the command shape;
# everything past it is identical.
function _say_hi_container() {
  local label="$1" shell_end root fallback exit_code shell_secs size prefix tarball
  local -a probe cp attach
  case "$label" in
  # one arm, since podman reuses docker's exec syntax outright
  docker | podman)
    probe=("$label" exec "$DOMAIN")
    cp=("$label" exec -i "$DOMAIN")
    attach=("$label" exec -it "$DOMAIN")
    ;;
  nomad)
    probe=(nomad alloc exec -i=false -t=false "$DOMAIN")
    cp=(nomad alloc exec -i=true -t=false "$DOMAIN")
    # explicit -t=true rather than nomad's own "-t defaults to true if stdin
    # is a tty session" auto-detection - that heuristic can land on the wrong
    # answer once our stdin is a pty shared with another process instead of
    # a plain direct terminal (e.g. a backgrounded/wrapped invocation), which
    # then hangs the exec session outright instead of just misrendering it
    attach=(nomad alloc exec -i=true -t=true "$DOMAIN")
    ;;
  kube)
    probe=(kubectl exec "$DOMAIN" --)
    cp=(kubectl exec -i "$DOMAIN" --)
    attach=(kubectl exec -it "$DOMAIN" --)
    ;;
  esac

  root="/tmp/$(whoami).hi.log.$$"
  shell_end="$(_hi_now)"

  # no bash on the target means no fancy stuff, just our aliases
  if ! "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>"$tmp"; then
    # shellcheck disable=SC2016
    fallback=$("${probe[@]}" sh -c "for s in $_HI_SHELL_LADDER; do command -v \"\$s\" >/dev/null 2>&1 && { echo \"\$s\"; break; }; done" 2>"$tmp")
    [ -n "$fallback" ] || return 1
    _hi_cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW"

    if ! "${cp[@]}" sh -c "mkdir -p '$root' && cat > '$root/aliases.sh'" <"$_HI_ALIASES" 2>"$tmp"; then
      _hi_cecho " failed to copy aliases.sh into [$DOMAIN]" "$BRRED"
      "${attach[@]}" "$fallback"
      return $?
    fi

    # aliases.sh, plus CMDARG (already suffixed with "; exit" by _hi_parse) on
    # its own raw line rather than as a quoted CLI arg, so it survives
    # quotes/spaces in the user's command. Toggle defaults lead for the same
    # reason _hi_fallback_rc's do: aliases.sh reads both bare, and this path
    # copies it without paths.sh or settings.sh to define them.
    # No config overlay here either, for the same reason - nothing on this path
    # reads $_HI_COLORS or $_HI_PACKAGES, so there is nothing for it to affect.
    {
      printf 'export _HI_DISABLE_EDITORS=0\nexport _HI_DISABLE_ALIASES=0\n'
      printf 'export _HI_ASCII=%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
      printf '. %s/aliases.sh 2>/dev/null\n' "$root"
      # the POSIX prompt, for the shells that can parse it - the same rule as
      # the ssh path's `*)` arm, applied while the file is being written rather
      # than in a second `exec` round trip afterwards
      case "$fallback" in
      zsh | fish) ;;
      *) _hi_fallback_prompt ;;
      esac
      [ -n "${CMDARG:-}" ] && printf '%s\n' "$CMDARG"
    } |
      "${cp[@]}" sh -c "cat > '$root/.hi_fallback_rc'" 2>"$tmp"

    case "$fallback" in
    zsh)
      "${cp[@]}" sh -c "cp '$root/.hi_fallback_rc' '$root/.zshrc'" 2>"$tmp"
      "${attach[@]}" sh -c "export ZDOTDIR='$root'; exec zsh -i"
      ;;
    # see the ssh path's identical fish case in _hi_remote_suffix for why this
    # reads the file into -C directly instead of `source`ing it
    fish) "${attach[@]}" fish -C "$("${probe[@]}" cat "$root/.hi_fallback_rc")" ;;
    *) "${attach[@]}" sh -c "export ENV='$root/.hi_fallback_rc'; exec $fallback -i" ;;
    esac
    exit_code=$?
    "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
    return $exit_code
  fi

  shell_secs="$(_hi_elapsed "$_HI_SHELL_START" "$shell_end")"
  _hi_cecho " shell: ${shell_secs}s " "$BLUE" 1

  # Staged to a file rather than piped in, so the size announced is the one
  # actually sent: `du` answers about the uncompressed tree, and `tee | wc -c`
  # knows only after the copy it is announcing. No armor here - `exec -i` takes
  # raw bytes.
  tarball="$tmp.tar.gz"
  if ! tar czf "$tarball" -h -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/hi.d/}"; then
    _hi_cecho " failed to archive hi.d for [$DOMAIN]" "$BRRED"
    return 1
  fi
  size="$(_hi_human_bytes "$(_hi_file_bytes "$tarball")")"
  prefix=" shell: ${shell_secs}s -> bash ($label) $size"
  echo -ne "$YELLOW-> bash ($label)$NC $size"

  # this is a failure state, so we exit early
  if ! "${cp[@]}" sh -c "mkdir -p '$root' && tar mxzf - -C '$root'" <"$tarball"; then
    rm -f "$tarball"
    _hi_cecho " failed to copy hi.d into [$DOMAIN]" "$BRRED"
    "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
    return 1
  fi
  rm -f "$tarball"

  # the config overlay, as a second stream over the misc/ the tar above just
  # laid down - see the ssh path for why it can't ride along in the first one.
  # Failing to place it is not worth losing the session over: the shell still
  # comes up, just with the tree's default colors/packages.
  if _hi_has_overlay &&
    ! _hi_overlay_tar | "${cp[@]}" sh -c "tar mxzf - -C '$root/hi.d/misc'" 2>"$tmp"; then
    _hi_cecho " failed to copy your hi.d config overlay into [$DOMAIN], using defaults" "$YELLOW"
  fi

  "${cp[@]}" sh -c "cat > '$root/hi.d/hi.sh' && chmod +x '$root/hi.d/hi.sh'" <"$0"
  _hi_bootloader | "${cp[@]}" sh -c "cat > '$root/hi.d/hi.bashrc'"

  # _HI_CLEANUP marks this tree as disposable for load.sh's clean_all - the
  # `rm -rf "$root"` below is the client-side belt to its braces
  "${attach[@]}" sh -c "export _HI_TARGET='$DOMAIN' _HI_HOME='$root' _HI_ROOT='$root/hi.d' _HI_CONFIG_DIR='$root/hi.d/misc' _HI_CLEANUP='$root' _HI_COPY_TIME='$(_hi_copy_time "$copy_start" "$_HI_SHELL_START" "$shell_end")' _HI_CONNECT_PREFIX='$prefix' _HI_ASCII='${_HI_ASCII:-$(_hi_ascii_flag)}' _HI_RELEASE='$(_hi_version)'; exec bash --rcfile '$root/hi.d/hi.bashrc'"
  exit_code=$?

  "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
  return $exit_code
}

# split ssh's arguments from the target and any trailing remote command
function _hi_parse() {
  SSHARGS=()
  while [ $# -gt 0 ]; do
    case $1 in
    # every ssh option taking a separate value, so the value is never mistaken
    # for the target. -B/-J especially: without them `hi -J bastion myhost`
    # would treat "bastion" as the target and connect to the wrong host
    -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
      [ "$#" -ge 2 ] || {
        _hi_cecho "hi: $1 needs a value" "$RED" >&2
        exit 1
      }
      SSHARGS+=("$1" "$2")
      shift
      ;;
    # hi's own flags, allowed anywhere before the target and never forwarded to
    # ssh - unlike --doctor/--version/--update, dispatched on $1 alone below
    --tmux) _HI_TMUX_ATTACH=1 ;;
    --no-tmux) _HI_TMUX_ATTACH=0 ;;
    -*) SSHARGS+=("$1") ;;
    *)
      if [ -z "${DOMAIN:-}" ]; then
        DOMAIN="$1"
      else
        CMDARG="$*$([[ "$*" = *[![:space:]]* ]] && echo '; ') exit"
        return
      fi
      ;;
    esac
    shift
  done
  [ -n "${DOMAIN:-}" ] || {
    ssh "${SSHARGS[@]}"
    exit 1
  }
}

function _hi() {
  local copy_start tmp exit_code errors

  [ -d "$_HI_ROOT" ] || {
    _hi_cecho "No such directory: $_HI_ROOT" "$RED" >&2
    exit 1
  }

  copy_start="$(_hi_now)"
  tmp="$(mktemp -t hi.log.XXXXXX)"
  # shellcheck disable=SC2016 # $tmp is resolved when the trap fires
  _hi_on_exit 'rm -f "$tmp"'

  # parse the args and determine the target type
  _hi_parse "$@"
  _HI_SHELL_START="$(_hi_now)"
  # one redirect around the whole dispatch, not one per arm a new backend could
  # be added without. The predicates' stderr lands in $tmp too; each already
  # sends its probe to /dev/null, and $tmp only prints when the session failed.
  {
    if _hi_is_ssh_host "$DOMAIN"; then
      _say_hi
    elif _hi_is_docker_container "$DOMAIN"; then
      _say_hi_container docker
    elif _hi_is_podman_container "$DOMAIN"; then
      _say_hi_container podman
    elif _hi_is_nomad_alloc "$DOMAIN"; then
      _say_hi_container nomad
    elif _hi_is_k8s_pod "$DOMAIN"; then
      _say_hi_container kube
    else
      _say_hi
    fi
  } 2>"$tmp"
  exit_code="$?"

  if [ "$exit_code" -ne 0 ]; then
    errors="$(<"$tmp")"
    echo -ne "\r\r\r\r"
    _hi_cecho "hi failed [code: $exit_code]" "$BRRED"
    _hi_cecho "$errors" "$BRRED"
  fi
  exit "$exit_code"
}

set +euo pipefail # the connection paths below run against unknown hosts, where a probe that fails is normal, not fatal

# Same hatch as scripts/install.sh: sourcing this file defines its functions
# without connecting to anything, which tests/shells/hi_test.sh needs. Executed
# normally, $0 is this file and we dispatch.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# hi's own flags, dispatched on $1 alone: _hi_parse hands every other -flag
# to ssh, so anything hi answers itself has to be caught before it.
case "${1:-}" in
# `hi --doctor [target]` hands off to the pre-flight report. Checkouts and
# packaged installs have scripts/; a hi session on a target does not, and
# says so rather than silently connecting somewhere.
--doctor)
  shift
  [ -f "$_HI_DOCTOR" ] && exec "$_HI_DOCTOR" "$@"
  _hi_cecho "hi --doctor needs the full hi.d checkout - not available in a hi session" "$RED" >&2
  exit 1
  ;;
# `hi --update <target>` updates a permanent hi.d on that target instead of
# connecting to it. Caught here for the same reason --doctor is: _hi_parse
# would otherwise hand --update to ssh.
--update)
  shift
  _hi_update "$@"
  exit $?
  ;;
--version)
  _hi_version
  exit 0
  ;;
esac

_hi "$@"
