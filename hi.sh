#!/bin/bash
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies hi.d to the target and chainloads load.sh there.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# shellcheck source=./common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"

_HI_RELEASE="${_HI_RELEASE:-}"

# The synopsis, kept identical to docs/hi.1's .SH SYNOPSIS
_HI_USAGE="Usage: hi [ssh-options] <target> [command ...]"

# What ships to a target - an allow list instead of a deny list
_HI_PAYLOAD=(common misc shells load.sh)

# The user's config overlay, by the names it lands under in the target's
# config/ - its own second stream, since it lives outside the tree. It gets a
# directory of its own rather than being unpacked over misc/, because
# aliases.sh is additive, not a replacement: the shipped misc/aliases.sh
# sources $_HI_CONFIG_DIR/aliases.sh as its last act, so the user's
# definitions win. Landed in misc/ the two would be the same file - the
# shipped aliases overwritten, and then sourcing itself forever.
_HI_OVERLAY_FILES=(settings.sh colors packages tmux.conf aliases.sh)

# What a bash-less target falls back to, best first.
# ksh and mksh need no arm of their own: they read $ENV exactly as sh does.
export _HI_SHELL_LADDER="zsh fish ksh mksh sh"

# Stands in for the connect line's size until the script carrying it has been
# assembled and measured (see _say_hi); wider than any answer it can produce.
_HI_SIZE_TOKEN="@@SIZE@@"

# GLOSSARY: base64 armor - why base64 over openssl, the -d/-D ladder, and the
# `tr` fold $_HI_UNARMOR puts in front of the decode (armor that arrived as an
# argv word could be space-folded; the stdin transport needs no fold)
_HI_ARMOR="base64"
_HI_UNARMOR_RAW="{ base64 -d 2>/dev/null || base64 -D; }"
_HI_UNARMOR="tr -s ' ' '\n' | $_HI_UNARMOR_RAW"

function _hi_armored_line() {
  printf 'echo "%s" | %s %s %s' "$($_HI_ARMOR)" "$_HI_UNARMOR" "$1" "$2"
}

# The client-derived env both transports export into the session, one
# NAME<TAB>value pair per line: the ssh preamble renders `export NAME="v"`
# lines, the container path folds them into its one `sh -c "export ..."` string
function _hi_session_env() {
  printf '_HI_TARGET\t%s\n' "$DOMAIN"
  printf '_HI_TARGET_COLOR\t%s\n' "$(_hi_target_color)"
  printf '_HI_TARGET_TAG\t%s\n' "$(_hi_ssh_host_tag "$DOMAIN" 2>/dev/null || true)"
  printf '_HI_LOCAL_USER\t%s\n' "$(_hi_whoami)"
  printf '_HI_LOCAL_HOSTNAME\t%s\n' "$(_hi_hostname)"
  printf '_HI_RELEASE\t%s\n' "$(_hi_version)"
  printf '_HI_TMUX_ATTACH\t%s\n' "${_HI_TMUX_ATTACH:-0}"
  printf '_HI_TMUX_SESSION\t%s\n' "${_HI_TMUX_SESSION:-hi}"
  # the client's glyph verdict, not the target's: see _hi_ascii_flag
  printf '_HI_ASCII\t%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
  # the client's no-color choice travels the same way (nothing when unset,
  # which is the value https://no-color.org gives no meaning to)
  [ -n "${NO_COLOR:-}" ] && printf 'NO_COLOR\t1\n'
  return 0
}

# Memoized: _hi_session_env asks once and _hi_fallback_prompt asks again for
# each of the two arms _hi_remote_suffix generates, and $DOMAIN is fixed for
# the run - each miss walked the colors file and ~/.ssh/config over again.
function _hi_target_color() {
  [ "${_HI_TARGET_COLOR_MEMO+x}" = x ] ||
    _HI_TARGET_COLOR_MEMO="$(_hi_resolve_color hostname "${DOMAIN##*@}")"
  printf '%s\n' "$_HI_TARGET_COLOR_MEMO"
}

function _hi_overlay_files() {
  local f
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    [ -f "$_HI_CONFIG_DIR/$f" ] && printf '%s\n' "$f"
  done
  return 0
}

function _hi_has_overlay() {
  [ -n "$(_hi_overlay_files)" ]
}

function _hi_overlay_tar() {
  local -a present=()
  _hi_read_lines present < <(_hi_overlay_files)
  ((${#present[@]})) || return 0
  tar czf - -h -C "$_HI_CONFIG_DIR" "${present[@]}"
}

function _hi_payload_tar() {
  tar czf - -h -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/hi.d/}"
}

# The walker's rc 2 means "known host, no tag"; only 1 means not in the config.
function _hi_is_ssh_host() {
  _hi_ssh_host_tag "$1" >/dev/null 2>&1
  [ $? -ne 1 ]
}

function _hi_is_container_running() {
  command -v "$1" >/dev/null 2>&1 &&
    [ "$("$1" container inspect -f '{{.State.Running}}' "$2" 2>/dev/null)" = true ]
}

# docker and podman are identical for this
function _hi_is_docker_container() { _hi_is_container_running docker "$1"; }
function _hi_is_podman_container() { _hi_is_container_running podman "$1"; }

function _hi_is_nomad_alloc() {
  command -v nomad >/dev/null 2>&1 &&
    [ "$(nomad alloc status -t '{{.ClientStatus}}' "$1" 2>/dev/null)" = running ]
}

# multi-container pods need `-c <name>`, which isn't passed through - kubectl
# warns and uses the first container rather than failing.
function _hi_is_k8s_pod() {
  command -v kubectl >/dev/null 2>&1 &&
    [ "$(kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]
}

# The backend roster, in resolution order:
# "<name>|<what a target resolves as>|<liveness probe>|<predicate>".
# _hi's dispatch walks name and predicate; scripts/doctor.sh probes and
# prints the other columns. One list, so a backend added here reaches the
# dispatch and both halves of `hi --doctor` together - doctor's own copy of
# this chain had already drifted from the dispatch once.
_HI_BACKENDS=(
  "docker|docker container|docker ps -q|_hi_is_docker_container"
  "podman|podman container|podman ps -q|_hi_is_podman_container"
  "nomad|nomad allocation|nomad job status|_hi_is_nomad_alloc"
  "kube|kubernetes pod|kubectl get pods -o name|_hi_is_k8s_pod"
)

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@"
# GLOSSARY: sh -c wrapping - fish-shaped login shells, and quoting over %q
function _hi_ssh_sh() {
  local script="$1"
  shift
  # shellcheck disable=SC2029 # the script is ours to expand, here, on purpose
  ssh "$@" "${SSHARGS[@]}" "$DOMAIN" "sh -c '${script//\'/\'\\\'\'}'"
}

# _hi_ctl_open <persist-secs> [ssh-opts...] - a fresh ControlMaster socket
# into the caller's ctl_path/ctl_opts, so an install probe and the session
# that follows multiplex one authentication; _hi_ctl_close tears it down
function _hi_ctl_open() {
  ctl_path="$(mktemp -u -t hi.cm.XXXXXX)"
  ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o "ControlPersist=$1")
  shift
  ctl_opts+=("$@")
}

function _hi_ctl_close() {
  ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1 || true
  rm -f "$ctl_path" 2>/dev/null || true
}

# Prints the path of a permanent hi.d on $DOMAIN, if any
# shellcheck disable=SC2016 # the probe's variables are the target's to expand
function _hi_remote_root() {
  local out
  out="$(_hi_ssh_sh '_r="$HOME/hi.d"; [ -x "$_r/hi.sh" ] && [ -f "$_r/common/paths.sh" ] && printf "%s" "$_r"' \
    "$@" -o ConnectTimeout=5 2>/dev/null)" || out=""
  printf '%s' "$out"
}

function _hi_copy_time() {
  awk -v now="$(_hi_now)" -v a="$1" -v b="$2" -v c="$3" 'BEGIN { printf "%.3f", (now - a) - (c - b) }'
}

# GLOSSARY: strict-mode bracketing
function _hi_bootloader() {
  cat <<EOF
source \$_HI_ROOT/load.sh
set +euo pipefail
${CMDARG:-load}
EOF
}

# The no-bash target's rc: every line valid in sh, zsh *and* fish at once.
# GLOSSARY: fallback rc - the three-shell subset, and why each line is there
# With --aliases-only <dir>, the container fallback's shape: that path ships
# aliases.sh alone into <dir> - no tree, so nothing to source paths.sh or
# settings.sh from, and no $_HI_ROOT in the environment
function _hi_fallback_rc() {
  local t aliases_dir=""
  [ "${1:-}" = --aliases-only ] && aliases_dir="$2"
  printf 'export _HI_REMOTE_SESSION=1\n'
  # the toggle list is core.sh's _HI_TOGGLES, so a new toggle can't be missed
  # here (unset + `set -u` on a bash-less target was exactly that failure)
  for t in "${_HI_TOGGLES[@]}"; do
    [ "$t" = _HI_REMOTE_SESSION ] || printf 'export %s=0\n' "$t"
  done
  if [ -n "$aliases_dir" ]; then
    # the client verdicts the ssh preamble would have exported ride the rc
    # instead on this path
    printf 'export _HI_ASCII=%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
    [ -n "${NO_COLOR:-}" ] && printf 'export NO_COLOR=1\n'
    printf '. %s/aliases.sh 2>/dev/null\n' "$aliases_dir"
  else
    # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
    printf 'export _HI_CONFIG_DIR=$_HI_ROOT/config\n'
    # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
    printf '[ -f $_HI_ROOT/config/settings.sh ] && . $_HI_ROOT/config/settings.sh\n'
    # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
    printf '. $_HI_ROOT/common/paths.sh 2>/dev/null\n. $_HI_ROOT/misc/aliases.sh 2>/dev/null\n'
  fi
  [ -n "${CMDARG:-}" ] && printf '%s\n' "$CMDARG"
  return 0
}

# The fallback-shell probe both transports interpolate: one sh loop over
# $_HI_SHELL_LADDER, running $1 (with $_hi_s naming the hit) at the first
# shell found. Emitted on the client, so the loop's shape can't drift between
# the transports the way the ladder itself once did.
function _hi_ladder_probe() {
  # shellcheck disable=SC2016 # $_hi_s is the target's to expand, on purpose
  printf 'for _hi_s in %s; do command -v "$_hi_s" >/dev/null 2>&1 && { %s; break; }; done' \
    "$_HI_SHELL_LADDER" "$1"
}

# A prompt for the bash-less tiers (sh, ash, dash, ksh, mksh - fish and zsh
# get their own rc), baked on the client; $1 = "git" adds the live segment
# only the ksh/mksh arm of _hi_remote_suffix asks for.
# GLOSSARY: split-quoted prompt segment - why baked, and the quoting trick
# shellcheck disable=SC2016 # $_hi_u, the segment and the separator are the target's to expand
function _hi_fallback_prompt() {
  local host="${DOMAIN##*@}" nc git=""
  [ "${_HI_DISABLE_PROMPT:-0}" = 1 ] && return 0
  # the fragment closes the double-quoted run, adds a single-quoted one, and
  # reopens it - "…"'$(_hi_ksh_git)'" …" is one word to the shell
  [ "${1:-}" = git ] && git="\"'\$(_hi_ksh_git)'\""
  # _hi_color_escape already emits real escapes; only $NC is a literal to expand
  printf -v nc '%b' "$NC"
  printf '_hi_u=$(id -un 2>/dev/null || echo "${USER:-?}")\n'
  printf 'PS1=" %s${_hi_u}%s@%s%s%s%s %s "\n' \
    "$(_hi_user_escape)" "$nc" "$(_hi_color_escape "$(_hi_target_color)")" \
    "$host" "$nc" "$git" "$(_hi_prompt_end SH)"
}

function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# base64 length of <n> bytes: four chars per three-byte group, rounded up.
# Divide-then-multiply is the formula, not a slip - n * 4 / 3 loses the padding.
function _hi_armored_len() {
  # shellcheck disable=SC2017
  printf '%s' "$((($1 + 2) / 3 * 4))"
}

# What a fresh session puts on the wire, without connecting (doctor.sh and the
# README badge both quote it); no overlay counted - which files ride is a
# question about a target.
#
# It assembles the real script through the same _hi_remote_middle/_preamble/
# _suffix that _say_hi uses, rather than summing the three armored streams:
# summing them is cheaper, but it silently omitted the shell boilerplate those
# streams are wrapped in, and reported ~6KB under what the connect line printed
# for the same session. A number on a badge has to be the number the user sees,
# so this pays one base64 of the payload to be exact.
function _hi_wire_bytes() {
  local hi_esc="" nc_esc="" overlay_line="" launcher bootloader tree script
  local size="$_HI_SIZE_TOKEN"
  # the size token still stands in here exactly as it does in _say_hi, so this
  # counts what _say_hi counts before it substitutes the figure back in
  local DOMAIN="${DOMAIN:-target}"
  # $_HI_LAUNCHER, not $0 - reached by *sourcing*, where $0 is the sourcer;
  # _say_hi keeps $0 because there it is the running, shipped copy
  launcher="$($_HI_ARMOR <"$_HI_LAUNCHER")"
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_tar | $_HI_ARMOR)"
  script="$(_hi_remote_preamble)
$(_hi_remote_middle)
$(_hi_remote_suffix)"
  printf '%s' "${#script}"
}

# the same figure for humans; the bench suite takes the bytes instead, so the
# README badge is checked against a number and not against a rounded string
function _hi_wire_estimate() {
  _hi_human_bytes "$(_hi_wire_bytes)"
}

function _hi_file_bytes() {
  wc -c <"$1" | tr -d ' '
}

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

# core.sh's ladder, plus the diagnostic the header's cell has no room for:
# which half was missing when there is no answer.
function _hi_version() {
  local v
  v="$(_hi_release_or_describe)"
  if [ -n "$v" ]; then
    printf '%s\n' "$v"
  elif [ -d "$_HI_ROOT/.git" ]; then
    printf 'unknown (git would not answer)\n'
  else
    printf 'unknown (no stamp, no git)\n'
  fi
}

# _hi_env_each <printf-format> - _hi_session_env's NAME<TAB>value pairs through
# <format>, which gets the name and the value in that order. Both transports
# render the same stream, differing only in the shape they need it in, so the
# tab contract is stated here once rather than in two loops that must agree.
function _hi_env_each() {
  local n v
  while IFS=$'\t' read -r n v; do
    # shellcheck disable=SC2059 # the format is ours, not user data
    printf "$1" "$n" "$v"
  done < <(_hi_session_env)
}

function _hi_env_exports() {
  _hi_env_each '      export %s="%s"\n'
}

# The bit both _say_hi branches need first; tmux lines settle only "asked
# for?" - the rest is load.sh's question. Everything expands on the client:
# no backtick or unescaped $( ) below, not even inside a comment.
function _hi_remote_preamble() {
  cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
$(_hi_env_exports)
      # GLOSSARY: TERM fallback probe - unknown TERM swapped for xterm-256color
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
# GLOSSARY: bash --rcfile -i - the flag order, and fish's -C arm
function _hi_remote_suffix() {
  # shellcheck disable=SC2016 # _hi_armored_line's destinations are the target's to expand
  cat <<REMOTE
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      if command -v bash >/dev/null 2>&1; then
        bash --rcfile "\$_hi_rc_dir/hi.bashrc" -i
      else
        _hi_fallback=sh
        $(_hi_ladder_probe '_hi_fallback="$_hi_s"')
        printf '%s no bash on [$DOMAIN], dropping into plain %s w/ aliases only %s\n' "$hi_esc" "\$_hi_fallback" "$nc_esc" >&2
        $(_hi_fallback_rc | _hi_armored_line '>' '"$_hi_rc_dir/.hi_fallback_rc"')
        case "\$_hi_fallback" in
        zsh)
          cp "\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_rc_dir/.zshrc"
          ZDOTDIR="\$_hi_rc_dir" zsh -i
          ;;
        fish) fish -C "\$(cat "\$_hi_rc_dir/.hi_fallback_rc")" ;;
        # ksh/mksh read \$ENV as sh does, sharing the rc; on top they get
        # shells/ksh.sh and the live git segment (both expand \$( ) at prompt
        # time, which busybox ash below cannot). Header stays bash-only.
        ksh | mksh)
          printf '%s\n' '. \$_HI_ROOT/shells/ksh.sh' >> "\$_hi_rc_dir/.hi_fallback_rc"
          $(_hi_fallback_prompt git | _hi_armored_line '>>' '"$_hi_rc_dir/.hi_fallback_rc"')
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        # sh/dash/ash; the prompt is appended here, not in the shared rc,
        # which also feeds fish (no PS1) and zsh (different \$ escape)
        *)
          $(_hi_fallback_prompt | _hi_armored_line '>>' '"$_hi_rc_dir/.hi_fallback_rc"')
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        esac
      fi
REMOTE
}

# The disposable-tree half of the script: unpack the three armored streams into
# a fresh /tmp root. Reads $hi_esc/$nc_esc/$size and the three stream variables
# from its caller, the way _hi_remote_suffix already reads $hi_esc/$nc_esc -
# so that _say_hi and _hi_wire_estimate assemble one shape, not two that have
# to be kept in step. (The permanent-install branch stays inline in _say_hi:
# nothing else builds it.)
# shellcheck disable=SC2016 # the destinations are the target's to expand
function _hi_remote_middle() {
  cat <<REMOTE
      export _HI_HOME=\$(mktemp -d -t $(_hi_whoami).hi.XXXXXX) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_HOME/hi.d
      export _HI_CONFIG_DIR=\$_HI_ROOT/config
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
}

# Connect, copy hi.d over, hand off to load.sh. Everything up to the bash
# branch is plain POSIX under one `sh -c` (GLOSSARY: sh -c wrapping)
function _say_hi() {
  local size hi_esc nc_esc script middle boot_tmp remote_root tmp_root ctl_path ec=0
  local launcher="" bootloader="" tree="" overlay_line=""
  local -a ctl_opts

  # only this path armors (containers stream via their CLI); no base64 probe
  # needed - a target without one fails the one-liner loudly on its own
  command -v base64 >/dev/null 2>&1 || {
    _hi_cecho >&2 "hi requires base64 on [$(_hi_hostname)] to reach an ssh target, but it is not installed. Aborting..." "$RED"
    return 1
  }

  printf -v hi_esc '%b' "$YELLOW"
  printf -v nc_esc '%b' "$NC"

  # multiplex the install-probe and the real session over one ssh connection
  _hi_ctl_open 30
  remote_root="$(_hi_remote_root "${ctl_opts[@]}")"

  if [ -n "$remote_root" ]; then
    tmp_root="${remote_root%/hi.d}"
    # shellcheck disable=SC2016 # _hi_armored_line's destination is the target's to expand
    middle="$(
      cat <<REMOTE
      export _HI_HOME="$tmp_root"
      export _HI_ROOT="$remote_root"
      _hi_rc_dir="\$(dirname "\$0")"
      printf '%s %s%s' "$hi_esc" "$nc_esc" "-> local hi.d install"
      $(_hi_bootloader | _hi_armored_line '>' '"$_hi_rc_dir/hi.bashrc"')
      export _HI_CONNECT_PREFIX="-> local hi.d install"
REMOTE
    )"
  else
    launcher="$($_HI_ARMOR <"$0")"
    bootloader="$(_hi_bootloader | $_HI_ARMOR)"
    tree="$(_hi_payload_tar | $_HI_ARMOR)"
    # second, tiny stream: the overlay lives outside the tree, so it cannot
    # ride the payload; omitted entirely when empty. It lands in its own
    # config/ beside misc/ - never over it - and _HI_CONFIG_DIR points there,
    # not at the login user's ~/.config/hi.d
    # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
    if _hi_has_overlay; then
      overlay_line="mkdir -p \"\$_HI_ROOT/config\"
$(_hi_overlay_tar | _hi_armored_line '|' 'tar mxzf - -C "$_HI_ROOT/config"')"
    fi
    # not known yet: the figure counts the assembled script, and everything
    # above is part of it, so it can only be measured once that exists
    size="$_HI_SIZE_TOKEN"
    middle="$(_hi_remote_middle)"
  fi

  script="$(_hi_remote_preamble)
$middle
$(_hi_remote_suffix)"

  # the connection's true byte count: the script goes over the wire as it
  # stands, its three streams already armored one apiece
  # $_HI_SIZE_TOKEN holds a same-width place, honest to a few bytes
  if [ -z "$remote_root" ]; then
    size="$(_hi_human_bytes "${#script}")"
    script="${script//$_HI_SIZE_TOKEN/$size}"
  fi

  # -u: a name only, never a local file - the directory it names is created on
  # the *target* by the mkdir below (which fails loudly if the name is taken)
  boot_tmp="$(mktemp -u -t hi.boot.XXXXXX)"

  # The bootloader rides stdin of the first of two calls on one connection;
  # the write doubles as the POSIX-shell probe that selects the PowerShell
  # fallback, and `command -v base64` keeps a target that cannot decode the
  # streams inside the script on that same fallback rather than half-landing.
  # It travels as the plain script: stdin is a pipe, so it needs no armor of
  # its own - only the three streams *inside* it do, and armoring the whole
  # thing again cost a third of every session's bytes for nothing.
  # GLOSSARY: stdin transport - the argv cap, and why it must be two calls
  # shellcheck disable=SC2029 # $boot_tmp is ours to expand, into the target's shell
  if printf '%s\n' "$script" | ssh "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
    "sh -c 'command -v base64 >/dev/null 2>&1 && mkdir -m 700 $boot_tmp && cat > $boot_tmp/bootloader'" 2>/dev/null; then
    # shellcheck disable=SC2029
    ssh -t "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      "sh $boot_tmp/bootloader; rm -rf $boot_tmp" || ec=$?
  else
    ssh -t "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
      powershell -NoLogo -NoExit -Command \
      "Write-Host 'hi from PowerShell - no bash or sh on this host, hi.d colors/aliases are unavailable' -ForegroundColor Yellow" || ec=$?
  fi

  _hi_ctl_close
  return "$ec"
}

# Four backends share this: docker, podman (drop-in CLI), nomad, kube
# _say_hi_container <label> <errlog> <copy_start>
function _say_hi_container() {
  local label="$1" tmp="$2" copy_start="$3"
  local shell_end root fallback exit_code shell_secs size prefix tarball env_kv
  local ksh_git=""
  local -a probe cp attach
  case "$label" in
  docker | podman)
    probe=("$label" exec "$DOMAIN")
    cp=("$label" exec -i "$DOMAIN")
    attach=("$label" exec -it "$DOMAIN")
    ;;
  nomad)
    probe=(nomad alloc exec -i=false -t=false "$DOMAIN")
    cp=(nomad alloc exec -i=true -t=false "$DOMAIN")
    # explicit -t=true: nomad's stdin-is-a-tty auto-detect lands wrong on a
    # shared/wrapped pty and then hangs the exec outright
    attach=(nomad alloc exec -i=true -t=true "$DOMAIN")
    ;;
  kube)
    probe=(kubectl exec "$DOMAIN" --)
    cp=(kubectl exec -i "$DOMAIN" --)
    attach=(kubectl exec -it "$DOMAIN" --)
    ;;
  esac

  root="/tmp/$(_hi_whoami).hi.log.$$"
  shell_end="$(_hi_now)"

  # no bash on the target means no fancy stuff, just our aliases
  if ! "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>"$tmp"; then
    # shellcheck disable=SC2016 # the probe's $_hi_s is the target's to expand
    fallback=$("${probe[@]}" sh -c "$(_hi_ladder_probe 'echo "$_hi_s"')" 2>"$tmp")
    [ -n "$fallback" ] || return 1
    _hi_cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW"

    if ! "${cp[@]}" sh -c "mkdir -p '$root' && cat > '$root/aliases.sh'" <"$_HI_ALIASES" 2>"$tmp"; then
      _hi_cecho " failed to copy aliases.sh into [$DOMAIN]" "$BRRED"
      "${attach[@]}" "$fallback"
      return $?
    fi

    # ksh/mksh get the live git segment, as they do on the ssh path - but that
    # path already has the whole tree on the target, and this one ships
    # aliases.sh alone, so the segment has to be copied too
    case "$fallback" in
    ksh | mksh)
      "${cp[@]}" sh -c "cat > '$root/ksh.sh'" <"$_HI_ROOT/shells/ksh.sh" 2>"$tmp" &&
        ksh_git=1
      ;;
    esac

    # the shared fallback rc in its aliases-only shape (full toggle list,
    # client verdicts, aliases.sh, CMDARG on its own raw line), plus the
    # POSIX prompt for the shells that can parse it - the same rule as the
    # ssh path's `*)` arm, applied while the file is being written rather
    # than in a second `exec` round trip afterwards
    {
      _hi_fallback_rc --aliases-only "$root"
      if [ -n "$ksh_git" ]; then
        # the source line lands after the rc's verdict exports, which is what
        # shells/ksh.sh reads for its glyphs and colors
        printf '. %s/ksh.sh\n' "$root"
        _hi_fallback_prompt git
      else
        case "$fallback" in
        zsh | fish) ;;
        *) _hi_fallback_prompt ;;
        esac
      fi
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

  # staged to a file so the announced size is the one actually sent
  tarball="$tmp.tar.gz"
  if ! _hi_payload_tar >"$tarball"; then
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

  if _hi_has_overlay &&
    ! _hi_overlay_tar |
    "${cp[@]}" sh -c "mkdir -p '$root/hi.d/config' && tar mxzf - -C '$root/hi.d/config'" 2>"$tmp"; then
    _hi_cecho " failed to copy your hi.d config overlay into [$DOMAIN], using defaults" "$YELLOW"
  fi

  "${cp[@]}" sh -c "cat > '$root/hi.d/hi.sh' && chmod +x '$root/hi.d/hi.sh'" <"$0"
  _hi_bootloader | "${cp[@]}" sh -c "cat > '$root/hi.d/hi.bashrc'"

  # _HI_CLEANUP marks this tree as disposable for load.sh's clean_all - the
  # `rm -rf "$root"` below is the client-side belt to its braces. The shared
  # client-derived vars come from _hi_session_env; the tree paths and timing
  # are this transport's own.
  env_kv="$(_hi_env_each " %s='%s'")"
  "${attach[@]}" sh -c "export$env_kv _HI_HOME='$root' _HI_ROOT='$root/hi.d' _HI_CONFIG_DIR='$root/hi.d/config' _HI_CLEANUP='$root' _HI_COPY_TIME='$(_hi_copy_time "$copy_start" "$_HI_SHELL_START" "$shell_end")' _HI_CONNECT_PREFIX='$prefix'; exec bash --rcfile '$root/hi.d/hi.bashrc'"
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
    # for the target
    -B | -b | -c | -D | -E | -e | -F | -I | -i | -J | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
      [ "$#" -ge 2 ] || {
        _hi_cecho "hi: $1 needs a value" "$RED" >&2
        exit 1
      }
      SSHARGS+=("$1" "$2")
      shift
      ;;
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

# `${!array[@]}` rather than a counter incremented in lockstep with the loop:
# the index is what pairs a row with its pid, so index on it. (bash 3.0+, and
# not one of the bash-4 forms the lint suite greps for.)
function _hi_resolve_backend() {
  local target="$1" i
  local -a pids=()
  for i in "${!_HI_BACKENDS[@]}"; do
    "${_HI_BACKENDS[i]##*|}" "$target" &
    pids+=("$!")
  done
  for i in "${!_HI_BACKENDS[@]}"; do
    if wait "${pids[i]}"; then
      printf '%s' "${_HI_BACKENDS[i]%%|*}"
      return 0
    fi
  done
  return 0
}

function _hi() {
  local copy_start tmp exit_code errors backend

  [ -d "$_HI_ROOT" ] || {
    _hi_cecho "No such directory: $_HI_ROOT" "$RED" >&2
    exit 1
  }

  copy_start="$(_hi_now)"
  tmp="$(mktemp -t hi.log.XXXXXX)"
  # shellcheck disable=SC2016 # $tmp is resolved when the trap fires
  _hi_on_exit 'rm -f "$tmp"'

  _hi_parse "$@"
  _HI_SHELL_START="$(_hi_now)"
  # shellcheck disable=SC2094 # $tmp rides as an argument
  {
    backend=""
    if ! _hi_is_ssh_host "$DOMAIN"; then
      backend="$(_hi_resolve_backend "$DOMAIN")"
    fi
    if [ -n "$backend" ]; then
      _say_hi_container "$backend" "$tmp" "$copy_start"
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

# sourcing this file defines its functions
# without connecting to anything, for testing
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# hi's own flags, dispatched on $1 alone: _hi_parse hands every other -flag
# to ssh, so anything hi answers itself has to be caught before it.
case "${1:-}" in
# `hi -h`/`--help`, caught before the ssh pass-through (which once answered
# with ssh's usage block, for a tool that is not ssh). A bare `hi` still
# execs ssh on purpose, so `hi -V` and friends behave as they do there.
-h | --help)
  cat <<EOF
$_HI_USAGE

Copies your hi.d to <target> and hands you an identical shell session there -
header, colors, git prompt, aliases, vim/nano/tmux configs - then strips it all
back out when the session ends. With [command ...], runs that instead, the way
ssh does.

<target> is resolved in this order, first match wins:
  1. a Host in ~/.ssh/config (or any name ssh can reach)
  2. a running docker container, by name or ID
  3. a running podman container
  4. a running nomad allocation, by ID or prefix
  5. a kubernetes pod, in whatever context/namespace kubectl points at

hi's own options:
  -h, --help            this text
      --version         the version: stamped at packaging time, or git describe
      --doctor [target] a read-only pre-flight report instead of connecting -
                        the local tree, the config overlay, every backend
                        probed and timed, and with a target, which backend the
                        name resolves to plus an ssh reachability check
      --tmux            run the session inside a named tmux on the target, so a
                        dropped connection detaches instead of losing the work.
                        Needs a permanent hi.d there. May appear anywhere
                        before the target.
      --no-tmux         turn that back off when settings.sh made it the default

Everything else is passed to ssh unchanged - -p, -i, -J, -o and the rest behave
exactly as they do there. Only the first non-option word is the target;
everything after it is the remote command.

Configuration lives outside this tree, in \${XDG_CONFIG_HOME:-\$HOME/.config}/hi.d/
so it survives an upgrade. See \`man hi\` and the README for all of it.
EOF
  exit 0
  ;;
--doctor)
  shift
  [ -f "$_HI_DOCTOR" ] && exec "$_HI_DOCTOR" "$@"
  _hi_cecho "hi --doctor needs the full hi.d checkout - not available in a hi session" "$RED" >&2
  exit 1
  ;;
--version)
  _hi_version
  exit 0
  ;;
esac

_hi "$@"
