#!/bin/bash
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies hi.d to the target and chainloads load.sh there.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# $_HI_HOME is the directory *containing* hi.d, derived from this script rather
# than guessed. The symlink walk is what makes that work from $_HI_LINK:
# /usr/bin/hi points at <prefix>/hi.d/hi.sh, and the unresolved path answers
# /usr. GLOSSARY: HI.33
if [ -z "${_HI_HOME:-}" ]; then
  _hi_self="${BASH_SOURCE[0]}"
  while [ -L "$_hi_self" ]; do
    _hi_self_dir="$(cd -P "$(dirname "$_hi_self")" && pwd)"
    _hi_self="$(readlink "$_hi_self")"
    [[ $_hi_self == /* ]] || _hi_self="$_hi_self_dir/$_hi_self"
  done
  _HI_HOME="$(cd -P "$(dirname "$_hi_self")/.." && pwd)"
  unset _hi_self _hi_self_dir
fi
export _HI_HOME
# Checked before the source, because bash's own "No such file or directory"
# names a path nobody typed - which is what a tree that is not laid out as
# $_HI_HOME/hi.d looks like. No _hi_cecho: core.sh is the file that's gone.
[ -r "$_HI_HOME/hi.d/common/core.sh" ] || {
  echo "hi: no hi.d at $_HI_HOME/hi.d - set _HI_HOME to the directory that holds it" >&2
  exit 1
}
# shellcheck source=./common/core.sh
source "$_HI_HOME/hi.d/common/core.sh"

_HI_RELEASE="${_HI_RELEASE:-}"

# The synopsis, kept identical to docs/hi.1's .SH SYNOPSIS
_HI_USAGE="Usage: hi [ssh-options] <target> [command ...]"

# What ships to a target - an allow list instead of a deny list. hi.sh is in it
# so a disposable session has a launcher to relay onward with; carrying it in
# the gzipped tar costs ~14KB of wire, against ~41KB armored on its own.
_HI_PAYLOAD=(common misc shells load.sh hi.sh)

# The user's config overlay, by the names it lands under in the target's
# config/ - a second stream, since it lives outside the tree. It gets a
# directory of its own rather than being unpacked over misc/: aliases.sh is
# additive, and the shipped misc/aliases.sh sources $_HI_CONFIG_DIR/aliases.sh
# last, so landing them in one place would make it source itself forever.
_HI_OVERLAY_FILES=(settings.sh colors packages tmux.conf aliases.sh)

# What a bash-less target falls back to, best first: core.sh's $_HI_SHELL_TREE
# minus bash (a missing bash is this ladder's precondition), derived rather
# than spelled out so the two orderings cannot drift. ksh/mksh need no arm of
# their own in _hi_remote_suffix - they read $ENV as sh does; dash and ash are
# here to be *preferred* over a `sh` that may be either.
export _HI_SHELL_LADDER="${_HI_SHELL_TREE//bash /}"

# Stands in for the connect line's size until the script carrying it is
# assembled and measured (see _say_hi); wider than any answer it can produce.
_HI_SIZE_TOKEN="@@SIZE@@"

# GLOSSARY: HI.17 - why base64 over openssl, the -d/-D ladder, and the
# `tr` fold $_HI_UNARMOR puts in front of the decode (armor that arrived as an
# argv word could be space-folded; the stdin transport needs no fold)
_HI_ARMOR="base64"
_HI_UNARMOR_RAW="{ base64 -d 2>/dev/null || base64 -D; }"
_HI_UNARMOR="tr -s ' ' '\n' | $_HI_UNARMOR_RAW"

function _hi_armored_line() {
  printf 'echo "%s" | %s %s %s' "$($_HI_ARMOR)" "$_HI_UNARMOR" "$1" "$2"
}

# The client-derived env both transports export into the session, one
# NAME<TAB>value pair per line: the ssh preamble renders `export NAME="v"`,
# the container path folds them into one `sh -c "export ..."` string
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

# Memoized: _hi_session_env asks once and _hi_fallback_prompt again for each of
# _hi_remote_suffix's two arms, and $DOMAIN is fixed for the run - each miss
# walked the colors file and ~/.ssh/config again.
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
# _hi's dispatch walks name and predicate; scripts/doctor.sh probes and prints
# the other columns. One list, so a backend added here reaches the dispatch and
# both halves of `hi --doctor` together.
_HI_BACKENDS=(
  "docker|docker container|docker ps -q|_hi_is_docker_container"
  "podman|podman container|podman ps -q|_hi_is_podman_container"
  "nomad|nomad allocation|nomad job status|_hi_is_nomad_alloc"
  "kube|kubernetes pod|kubectl get pods -o name|_hi_is_k8s_pod"
)

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@"
# GLOSSARY: HI.18 - fish-shaped login shells, and quoting over %q
function _hi_ssh_sh() {
  local script="$1"
  shift
  # shellcheck disable=SC2029 # the script is ours to expand, here, on purpose
  ssh "$@" "${SSHARGS[@]}" "$DOMAIN" "sh -c '${script//\'/\'\\\'\'}'"
}

# _hi_ctl_open <persist-secs> [ssh-opts...] - a fresh ControlMaster socket into
# the caller's ctl_path/ctl_opts, so the install probe and the session that
# follows multiplex one authentication; _hi_ctl_close tears it down
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

# The sh script _hi_remote_root runs on the target: the path of a permanent
# hi.d there, or nothing. Candidates come from what install.sh wrote into the
# login rc files, read as *files* (`sh -c` over ssh sources none of them),
# then $HOME/hi.d. Its own function so a suite can run it without an ssh hop.
# GLOSSARY: HI.33 - the candidate order, the two seds, and what `--tmux` gets
# out of it
function _hi_remote_root_probe() {
  cat <<'PROBE'
_c=$(for _f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish" /etc/profile.d/hi.d.sh; do
  [ -f "$_f" ] && sed -n -e 's/^[[:space:]]*export  *_HI_HOME=//p' -e 's/^[[:space:]]*set -gx  *_HI_HOME  *//p' "$_f"
done | sed -e 's/^"\([^"]*\)".*$/\1/' -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//')
IFS='
'
for _h in $_c "$HOME"; do
  [ -n "$_h" ] && [ -x "$_h/hi.d/hi.sh" ] && [ -f "$_h/hi.d/common/paths.sh" ] && {
    printf "%s" "$_h/hi.d"
    exit 0
  }
done
PROBE
}

# Prints the path of a permanent hi.d on $DOMAIN, if any
function _hi_remote_root() {
  local out
  out="$(_hi_ssh_sh "$(_hi_remote_root_probe)" \
    "$@" -o ConnectTimeout=5 2>/dev/null)" || out=""
  printf '%s' "$out"
}

function _hi_copy_time() {
  awk -v now="$(_hi_now)" -v a="$1" -v b="$2" -v c="$3" 'BEGIN { printf "%.3f", (now - a) - (c - b) }'
}

# GLOSSARY: HI.15
function _hi_bootloader() {
  cat <<EOF
source \$_HI_ROOT/load.sh
set +euo pipefail
${CMDARG:-load}
EOF
}

# The no-bash target's rc: every line valid in sh, zsh *and* fish at once.
# GLOSSARY: HI.20 - the three-shell subset, and why each line is there.
# With --aliases-only <dir>, the container fallback's shape: that path ships
# aliases.sh alone into <dir>, with no tree and no $_HI_ROOT to source from.
function _hi_fallback_rc() {
  local t aliases_dir=""
  [ "${1:-}" = --aliases-only ] && aliases_dir="$2"
  printf 'export _HI_REMOTE_SESSION=1\n'
  # core.sh's _HI_TOGGLES, so a new toggle can't be missed here: an unset
  # toggle under `set -u` breaks a bash-less target outright
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
# $_HI_SHELL_LADDER running $1 (with $_hi_s naming the hit) at the first shell
# found. Emitted on the client, so its shape can't drift between transports.
function _hi_ladder_probe() {
  # shellcheck disable=SC2016 # $_hi_s is the target's to expand, on purpose
  printf 'for _hi_s in %s; do command -v "$_hi_s" >/dev/null 2>&1 && { %s; break; }; done' \
    "$_HI_SHELL_LADDER" "$1"
}

# A prompt for the bash-less tiers (sh, ash, dash, ksh, mksh - fish and zsh get
# their own rc), baked on the client; $1 = "git" adds the live segment only
# _hi_remote_suffix's ksh/mksh arm asks for.
# GLOSSARY: HI.21 - why baked, and the quoting trick
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

# What a fresh session puts on the wire, without connecting (doctor.sh and the
# README badge both quote it); no overlay counted - which files ride is a
# question about a target. It assembles the real script through the same
# _preamble/_middle/_suffix _say_hi uses rather than summing the armored
# streams: summing skips the boilerplate they are wrapped in and reads ~6KB
# low. A badge has to show the number the user sees, so this pays one base64.
function _hi_wire_bytes() {
  local hi_esc="" nc_esc="" overlay_line="" bootloader tree script
  local size="$_HI_SIZE_TOKEN"
  # the token stands in exactly as in _say_hi, so this counts what _say_hi
  # counts before it substitutes the figure back in
  local DOMAIN="${DOMAIN:-target}"
  bootloader="$(_hi_bootloader | $_HI_ARMOR)"
  tree="$(_hi_payload_tar | $_HI_ARMOR)"
  script="$(_hi_remote_preamble)
$(_hi_remote_middle)
$(_hi_remote_suffix)"
  printf '%s' "${#script}"
}

# the same figure for humans; the bench suite takes the bytes, so the README
# badge is checked against a number and not a rounded string
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

# core.sh's ladder, plus the diagnostic the header's cell has no room for
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
# <format>, name then value. Both transports render the same stream in
# different shapes, so the tab contract is stated once, not in two loops.
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

# The bit both _say_hi branches need first; tmux lines settle only "asked for?"
# - the rest is load.sh's question. Everything expands on the client: no
# backtick or unescaped $( ) below, not even inside a comment.
function _hi_remote_preamble() {
  cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
$(_hi_env_exports)
      # GLOSSARY: HI.22 - unknown TERM swapped for xterm-256color
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

# What both _say_hi branches need once their setup is done: report copy time,
# then hand off to bash or to the best fallback shell. Expects \$_hi_rc_dir to
# point at wherever hi.bashrc/.hi_fallback_rc lives.
# GLOSSARY: HI.23 - the flag order, and fish's -C arm
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
        # time, which busybox ash cannot). Header stays bash-only.
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

# The disposable-tree half of the script: unpack the armored streams into a
# fresh /tmp root. Reads $hi_esc/$nc_esc/$size and the stream variables from
# its caller, as _hi_remote_suffix reads $hi_esc/$nc_esc, so _say_hi and
# _hi_wire_estimate assemble one shape rather than two kept in step. (The
# permanent-install branch stays inline in _say_hi; nothing else builds it.)
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
  local bootloader="" tree="" overlay_line=""
  local -a ctl_opts

  # only this path armors (containers stream via their CLI); a target with no
  # base64 fails the one-liner loudly on its own
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
    bootloader="$(_hi_bootloader | $_HI_ARMOR)"
    tree="$(_hi_payload_tar | $_HI_ARMOR)"
    # second, tiny stream: the overlay lives outside the tree, so it cannot
    # ride the payload, and is omitted when empty. It lands in its own config/
    # beside misc/, with _HI_CONFIG_DIR pointing there.
    # shellcheck disable=SC2016 # $_HI_ROOT is the target's to expand
    if _hi_has_overlay; then
      overlay_line="mkdir -p \"\$_HI_ROOT/config\"
$(_hi_overlay_tar | _hi_armored_line '|' 'tar mxzf - -C "$_HI_ROOT/config"')"
    fi
    # not known yet: the figure counts the assembled script, so it can only be
    # measured once that exists
    size="$_HI_SIZE_TOKEN"
    middle="$(_hi_remote_middle)"
  fi

  script="$(_hi_remote_preamble)
$middle
$(_hi_remote_suffix)"

  # the connection's true byte count: the script goes over the wire as it
  # stands, its streams already armored. $_HI_SIZE_TOKEN held a same-width
  # place, so the figure is honest to a few bytes.
  if [ -z "$remote_root" ]; then
    size="$(_hi_human_bytes "${#script}")"
    script="${script//$_HI_SIZE_TOKEN/$size}"
  fi

  # -u: a name only, never a local file - the directory is created on the
  # *target* by the mkdir below, which fails loudly if the name is taken
  boot_tmp="$(mktemp -u -t hi.boot.XXXXXX)"

  # The bootloader rides stdin of the first of two calls on one connection. The
  # write doubles as the POSIX-shell probe that selects the PowerShell fallback,
  # and `command -v base64` keeps a target that cannot decode the inner streams
  # on that same fallback rather than half-landing. It travels as the plain
  # script: stdin is a pipe, so only the streams *inside* it need armor -
  # armoring the whole thing again cost a third of every session for nothing.
  # GLOSSARY: HI.19 - the argv cap, and why it must be two calls
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

# _say_hi_container <label> <errlog> <copy_start> - docker, podman, nomad, kube
function _say_hi_container() {
  local label="$1" tmp="$2" copy_start="$3"
  local shell_end root fallback exit_code size prefix tarball env_kv
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
    # explicit -t=true: nomad's stdin-is-a-tty guess lands wrong on a wrapped
    # pty and then hangs the exec outright
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

    # ksh/mksh get the live git segment as on the ssh path - but that path has
    # the whole tree there, and this one ships aliases.sh alone, so the segment
    # has to be copied too
    case "$fallback" in
    ksh | mksh)
      "${cp[@]}" sh -c "cat > '$root/ksh.sh'" <"$_HI_ROOT/shells/ksh.sh" 2>"$tmp" &&
        ksh_git=1
      ;;
    esac

    # the shared fallback rc in its aliases-only shape, plus the POSIX prompt
    # for the shells that can parse it - the ssh path's `*)` rule, applied
    # while the file is written rather than in a second `exec` round trip
    {
      _hi_fallback_rc --aliases-only "$root"
      if [ -n "$ksh_git" ]; then
        # after the rc's verdict exports, which shells/ksh.sh reads for its
        # glyphs and colors
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

  # staged to a file so the announced size is the one actually sent
  tarball="$tmp.tar.gz"
  if ! _hi_payload_tar >"$tarball"; then
    _hi_cecho " failed to archive hi.d for [$DOMAIN]" "$BRRED"
    return 1
  fi
  size="$(_hi_human_bytes "$(_hi_file_bytes "$tarball")")"
  # just the size, the way the ssh path's prefix already reads: the shell-probe
  # timing and the "-> bash ($label)" it prefixed are gone, the backend having
  # stopped being news. The size stays - it is what the README badge tracks.
  prefix=" $size"
  echo -ne " $size"

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

  # hi.sh rides the payload tar unpacked above, mode and all - no separate copy
  _hi_bootloader | "${cp[@]}" sh -c "cat > '$root/hi.d/hi.bashrc'"

  # _HI_CLEANUP marks the tree disposable for load.sh's clean_all; the
  # `rm -rf "$root"` below is the client-side belt to it. Shared vars come from
  # _hi_session_env; the tree paths and timing are this transport's own.
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
    # every ssh option taking a separate value, so it is never read as the target
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

# `${!array[@]}`, not a counter kept in lockstep: the index is what pairs a row
# with its pid. (bash 3.0+, not one of the bash-4 forms the lint suite greps.)
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

# The scripts/ entry points, reached as `hi --flag` rather than through the
# hi_* aliases these replaced. Each needs the full checkout: the payload ships
# neither scripts/ nor tests/, so on a target - or in a packaged install - the
# file is simply absent, and the flag has to name which command wanted it
# rather than failing as a missing path. $_HI_NO_CHECKOUT is that sentence,
# exported by paths.sh so this file and the docs share one wording.
function _hi_run_script() {
  local flag="$1" script="$2"
  shift 2
  [ -f "$script" ] && exec "$script" "$@"
  _hi_cecho "hi $flag $_HI_NO_CHECKOUT" "$RED" >&2
  exit 1
}

set +euo pipefail # the connection paths below run against unknown hosts, where a probe that fails is normal, not fatal

# sourcing this file defines its functions without connecting, for testing
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

# hi's own flags, dispatched on $1 alone: _hi_parse hands every other -flag to
# ssh, so anything hi answers itself has to be caught first.
case "${1:-}" in
# caught before the ssh pass-through, so this answers for hi rather than
# handing back ssh's usage block. A bare `hi` still execs ssh, so `hi -V` and
# friends behave as they do there.
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

hi's local sub-commands, which act on this machine instead of connecting. They
need the full hi.d checkout, so inside a hi session each says so and stops:
      --install          install or repair hi.d's lines in your shell rc files
      --uninstall        take those lines back out again
      --configure        revisit the feature toggles, leaving the rc wiring be
      --check-configs    re-run just the shell rc syntax validation
      --overlay-init     make the config overlay a git repo, in place
      --update           git pull in the hi.d checkout
      --color-preview    what every ssh host and your user resolve to, in color
      --packages-preview the package-priority legend, as the header prints it
      --test             run the test suite

Everything else is passed to ssh unchanged - -p, -i, -J, -o and the rest behave
exactly as they do there. Only the first non-option word is the target;
everything after it is the remote command.

Configuration lives outside this tree, in \${XDG_CONFIG_HOME:-\$HOME/.config}/hi.d/
so it survives an upgrade. See \`man hi\` and the README for all of it.
EOF
  exit 0
  ;;
--install)
  shift
  _hi_run_script --install "$_HI_INSTALL" "$@"
  ;;
--uninstall)
  shift
  _hi_run_script --uninstall "$_HI_UNINSTALL" "$@"
  ;;
--configure)
  shift
  _hi_run_script --configure "$_HI_INSTALL" --features-only "$@"
  ;;
--check-configs)
  shift
  _hi_run_script --check-configs "$_HI_INSTALL" --check-configs "$@"
  ;;
--overlay-init)
  shift
  _hi_run_script --overlay-init "$_HI_INSTALL" --overlay-init "$@"
  ;;
--color-preview)
  shift
  _hi_run_script --color-preview "$_HI_COLOR_PREVIEW" "$@"
  ;;
--doctor)
  shift
  _hi_run_script --doctor "$_HI_DOCTOR" "$@"
  ;;
--test)
  shift
  _hi_run_script --test "$_HI_TEST_RUN" "$@"
  ;;
# .git as the test: absent from payloads and packaged installs alike, so this
# is the one local command that cannot borrow $_HI_NO_CHECKOUT's wording
--update)
  shift
  [ -d "$_HI_ROOT/.git" ] || {
    _hi_cecho "hi --update: $_HI_NO_GIT" "$RED" >&2
    exit 1
  }
  exec git -C "$_HI_ROOT" pull "$@"
  ;;
# The full preview lives in scripts/, which targets do not get; there this
# falls back to the check itself, out of the shipped common/header.sh.
--packages-preview)
  shift
  [ -f "$_HI_PACKAGES_PREVIEW" ] && exec "$_HI_PACKAGES_PREVIEW" "$@"
  exec bash -c 'source "$1" && full_check' hi "$_HI_HEADER"
  ;;
--version)
  _hi_version
  exit 0
  ;;
esac

_hi "$@"
