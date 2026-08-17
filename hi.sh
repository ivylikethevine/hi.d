#!/bin/bash
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies hi.d to the target and chainloads load.sh there.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# shellcheck source=./common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"

# The `hi --version` answer: empty in git (checkouts use `git describe`),
# sedded by every packager at build time; the ${...:-} default keeps the env
# seam open for sessions until a stamped literal wins.
_HI_RELEASE="${_HI_RELEASE:-}"

# The synopsis, kept identical to docs/hi.1's .SH SYNOPSIS. Named the way
# scripts/install.sh names its own, so both entry points answer -h in one shape.
_HI_USAGE="Usage: hi [ssh-options] <target> [command ...]"

# What ships to a target - an allow list, not excludes: new tree content
# stays off the wire until it earns a place. (_HI_PACKAGE_CONTENTS answers
# the different "installed copy" question.)
_HI_PAYLOAD=(common misc shells load.sh)

# The user's config overlay, by the names it lands under in the target's
# misc/ - its own second stream, since it lives outside the tree. aliases.sh
# is additive, not a replacement: the shipped shells/aliases.sh sources it
# from $_HI_CONFIG_DIR as its last act, so the user's definitions win.
_HI_OVERLAY_FILES=(settings.sh colors packages tmux.conf aliases.sh)

# GLOSSARY: base64 armor - why base64 over openssl, the -d/-D ladder, the tr
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

# The target's tag and color, memoized: resolution walks ~/.ssh/config and
# three callers want the same answer per run.
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

# True when any overlay exists - asked first, because an empty archive is an
# "unexpected EOF" to tar, and an unconfigured user must pay nothing.
function _hi_has_overlay() {
  local f
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    [ -f "$_HI_CONFIG_DIR/$f" ] && return 0
  done
  return 1
}

# The overlay tar, unpacked over the target's misc/: explicit member names
# rather than GNU --transform, so bsdtar works and members land where
# paths.sh already looks.
function _hi_overlay_tar() {
  local f
  local -a present=()
  for f in "${_HI_OVERLAY_FILES[@]}"; do
    [ -f "$_HI_CONFIG_DIR/$f" ] && present+=("$f")
  done
  ((${#present[@]})) || return 0
  tar czf - -h -C "$_HI_CONFIG_DIR" "${present[@]}"
}

# Reads ~/.ssh/config directly - targets.sh would cost three forks and the
# cache for a static file. Same rule: literal names, no wildcards.
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

# multi-container pods need `-c <name>`, which isn't passed through - kubectl
# warns and uses the first container rather than failing.
function _hi_is_k8s_pod() {
  command -v kubectl >/dev/null 2>&1 &&
    [ "$(kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]
}

# Run <script> on $DOMAIN through `sh -c`, with ssh's own flags in "$@" ahead
# of it - callers write plain sh and never count quotes.
# GLOSSARY: sh -c wrapping - fish-shaped login shells, and quoting over %q
function _hi_ssh_sh() {
  local script="$1"
  shift
  # shellcheck disable=SC2029 # the script is ours to expand, here, on purpose
  ssh "$@" "${SSHARGS[@]}" "$DOMAIN" "sh -c '${script//\'/\'\\\'\'}'"
}

# Prints the path of a permanent hi.d on $DOMAIN, if any; rides the
# ControlMaster in "$@", so it costs no extra authentication.
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

# The $CMDARG shape replaces load() - which would have turned strict mode back
# off - so the middle line must do it, or the user's command runs under -e -u.
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
  cat <<EOF
. \$_HI_ROOT/common/paths.sh 2>/dev/null
. \$_HI_ROOT/shells/aliases.sh 2>/dev/null
${CMDARG:-}
EOF
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
    "$host" "$nc" "$git" "$(_hi_prompt_end SH '\$')"
}

# The tree on disk, uncompressed - not what a session sends (see _hi_wire_size),
# but the right answer to "how big is the thing hi would ship". doctor.sh asks.
function _hi_size() {
  _hi_du_size "${_HI_PAYLOAD[@]/#/$_HI_ROOT/}"
}

# What crosses the connection, measured as *sent* (gzipped, armored) - `du`
# over the source dirs overstated every session.
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

# What a fresh session would put on the wire, without connecting (doctor.sh
# asks); no overlay counted - which files ride is a question about a target.
function _hi_wire_estimate() {
  # $_HI_LAUNCHER, not $0 - reached by *sourcing*, where $0 is the sourcer;
  # _say_hi keeps $0 because there it is the running, shipped copy
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

# the stamp when there is one, `git describe --always` in a checkout, and a
# candid unknown for a stampless tree with no git to ask
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

# The bit both _say_hi branches need first; tmux lines settle only "asked
# for?" - the rest is load.sh's question. Everything expands on the client:
# no backtick or unescaped $( ) below, not even inside a comment.
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
      # the client's no-color choice travels the same way (empty when unset,
      # which is the value https://no-color.org gives no meaning to)
      ${NO_COLOR:+export NO_COLOR=1}
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
        # ksh/mksh read \$ENV as sh does, sharing the rc; on top they get
        # shells/ksh.sh and the live git segment (both expand \$( ) at prompt
        # time, which busybox ash below cannot). Header stays bash-only.
        ksh | mksh)
          printf '%s\n' '. \$_HI_ROOT/shells/ksh.sh' >> "\$_hi_rc_dir/.hi_fallback_rc"
          echo "$(_hi_fallback_prompt git | $_HI_ARMOR)" | $_HI_UNARMOR >> "\$_hi_rc_dir/.hi_fallback_rc"
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        # sh/dash/ash; the prompt is appended here, not in the shared rc,
        # which also feeds fish (no PS1) and zsh (different \$ escape)
        *)
          echo "$(_hi_fallback_prompt | $_HI_ARMOR)" | $_HI_UNARMOR >> "\$_hi_rc_dir/.hi_fallback_rc"
          ENV="\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_fallback" -i
          ;;
        esac
      fi
REMOTE
}

# Connect, copy hi.d over, hand off to load.sh. Everything up to the bash
# branch is plain POSIX under one `sh -c` (GLOSSARY: sh -c wrapping), which
# chainloads bash when it's there.
function _say_hi() {
  local size hi_esc nc_esc script middle b64 boot_tmp remote_root tmp_root ctl_path ec=0
  local launcher="" bootloader="" tree="" overlay="" overlay_line=""
  local -a ctl_opts

  # only this path armors (containers stream via their CLI); no base64 probe
  # needed - a target without one fails the one-liner loudly on its own
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
    # second, tiny stream: the overlay lives outside the tree, so it cannot
    # ride the payload; omitted entirely when empty. _HI_CONFIG_DIR then
    # points at the shipped misc/, not the login user's ~/.config/hi.d.
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

  # the connection's true byte count (armored twice, each armor 4/3): derived
  # arithmetically because the number appears *inside* what it measures -
  # $_HI_SIZE_TOKEN holds a same-width place, honest to a few bytes
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

  # The bootloader rides stdin of the first of two calls on one connection;
  # the write doubles as the POSIX-shell probe that selects the PowerShell
  # fallback below. The `tr` step is dropped here: stdin delivers the armor
  # byte for byte, and folding newlines was the only thing it ever fixed.
  # GLOSSARY: stdin transport - the argv cap, and why it must be two calls
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

# Four backends share this: docker, podman (drop-in CLI), nomad, kube. The
# case below picks the command shape; everything past it is identical.
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

    # aliases.sh plus CMDARG on its own raw line (survives quotes/spaces);
    # toggle defaults lead because this path ships no paths.sh/settings.sh
    # to define them, and no overlay either - nothing here would read it
    {
      printf 'export _HI_DISABLE_EDITORS=0\nexport _HI_DISABLE_ALIASES=0\n'
      printf 'export _HI_ASCII=%s\n' "${_HI_ASCII:-$(_hi_ascii_flag)}"
      # the client's no-color choice, same clause as the ssh preamble's
      [ -n "${NO_COLOR:-}" ] && printf 'export NO_COLOR=1\n'
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

  # staged to a file so the announced size is the one actually sent; no
  # armor - `exec -i` takes raw bytes
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

  # the overlay, a second stream over the misc/ just laid down (see the ssh
  # path); failing to place it is not worth losing the session over
  if _hi_has_overlay &&
    ! _hi_overlay_tar | "${cp[@]}" sh -c "tar mxzf - -C '$root/hi.d/misc'" 2>"$tmp"; then
    _hi_cecho " failed to copy your hi.d config overlay into [$DOMAIN], using defaults" "$YELLOW"
  fi

  "${cp[@]}" sh -c "cat > '$root/hi.d/hi.sh' && chmod +x '$root/hi.d/hi.sh'" <"$0"
  _hi_bootloader | "${cp[@]}" sh -c "cat > '$root/hi.d/hi.bashrc'"

  # _HI_CLEANUP marks this tree as disposable for load.sh's clean_all - the
  # `rm -rf "$root"` below is the client-side belt to its braces
  "${attach[@]}" sh -c "export _HI_TARGET='$DOMAIN' _HI_HOME='$root' _HI_ROOT='$root/hi.d' _HI_CONFIG_DIR='$root/hi.d/misc' _HI_CLEANUP='$root' _HI_COPY_TIME='$(_hi_copy_time "$copy_start" "$_HI_SHELL_START" "$shell_end")' _HI_CONNECT_PREFIX='$prefix' _HI_ASCII='${_HI_ASCII:-$(_hi_ascii_flag)}'${NO_COLOR:+ NO_COLOR='1'} _HI_RELEASE='$(_hi_version)'; exec bash --rcfile '$root/hi.d/hi.bashrc'"
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
    # ssh - unlike --doctor/--version, dispatched on $1 alone below
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
# `hi --doctor [target]` hands off to the pre-flight report. Checkouts and
# packaged installs have scripts/; a hi session on a target does not, and
# says so rather than silently connecting somewhere.
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
