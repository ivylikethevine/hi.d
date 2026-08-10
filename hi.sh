#!/bin/bash
# forked from sshrc by Russell Stewart: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies hi.d to the target and chainloads load.sh there.
set -euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

# shellcheck source=./common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

command -v openssl >/dev/null 2>&1 || {
  _hi_cecho >&2 "hi requires openssl on [$(_hi_hostname)], but it is not installed. Aborting..." "$RED"
  exit 1
}

_HI_EXCLUDE=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts
  --exclude hi.sh --exclude hi.bashrc --exclude .zed --exclude .vscode --exclude .shellcheckrc)

# The ssh command line is re-parsed by the remote *login* shell, so every byte
# we send through it is base64-armored and undone on the far side.
_HI_ARMOR="openssl enc -base64"
_HI_UNARMOR="tr -s ' ' '\n' | openssl enc -base64 -d"

function _hi_is_ssh_host() {
  [ -f "$_HI_SSH_CONFIG" ] && sh "$_HI_TARGETS" ssh | grep -qxF "$1"$'\t'ssh
}

function _hi_is_docker_container() {
  command -v docker >/dev/null 2>&1 &&
    [ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}

function _hi_is_nomad_alloc() {
  command -v nomad >/dev/null 2>&1 &&
    [ "$(nomad alloc status -t '{{.ClientStatus}}' "$1" 2>/dev/null)" = running ]
}

# Cheap check for a permanent hi.d already sitting on $DOMAIN (i.e.
# scripts/install.sh has been run there): prints its path if so. Runs over
# the ssh ControlMaster passed in "$@" so this costs no extra authentication
# - _say_hi's real connection right after multiplexes through the same
# socket instead of asking again.
function _hi_remote_root() {
  local out
  out="$(ssh "$@" -o ConnectTimeout=5 "${SSHARGS[@]}" "$DOMAIN" \
    '_r="$HOME/hi.d"; [ -x "$_r/hi.sh" ] && [ -f "$_r/common/paths.sh" ] && printf "%s" "$_r"' 2>/dev/null)" || out=""
  printf '%s' "$out"
}

function _hi_copy_time() {
  echo "$(_hi_now) $1 $2 $3" | awk '{ printf "%.3f\n", ($1 - $2) - ($4 - $3) }'
}

function _hi_bootloader() {
  cat <<EOF
source \$_HI_ROOT/load.sh
${CMDARG:-load}
EOF
}

function _hi_fallback_rc() {
  cat <<EOF
. \$_HI_ROOT/shells/aliases.sh 2>/dev/null
${CMDARG:-}
EOF
}

function _hi_size() {
  _hi_du_size "${_HI_EXCLUDE[@]}"
}

# the bit both _say_hi branches need before anything target-specific happens
function _hi_remote_preamble() {
  cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
      export _HI_TARGET="$DOMAIN"
      export _HI_TARGET_COLOR="$(_hi_resolve_color hostname "$DOMAIN")"
      command -v openssl >/dev/null 2>&1 || { echo >&2 "hi requires openssl on [$DOMAIN], but it is not installed. Aborting."; exit 1; }
REMOTE
}

# the bit both _say_hi branches need once their own setup is done: report copy
# time, then hand off to bash if it's there, or the best fallback shell if not.
# Expects \$_hi_rc_dir to already be set to wherever hi.bashrc/.hi_fallback_rc
# should live for this branch.
function _hi_remote_suffix() {
  cat <<REMOTE
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      if command -v bash >/dev/null 2>&1; then
        bash --rcfile "\$_hi_rc_dir/hi.bashrc"
      else
        _hi_fallback=sh
        for _hi_s in zsh fish sh; do command -v "\$_hi_s" >/dev/null 2>&1 && { _hi_fallback="\$_hi_s"; break; }; done
        printf '%s no bash on [$DOMAIN], dropping into plain %s w/ aliases only %s\n' "$hi_esc" "\$_hi_fallback" "$nc_esc" >&2
        echo "$(_hi_fallback_rc | $_HI_ARMOR)" | $_HI_UNARMOR > "\$_hi_rc_dir/.hi_fallback_rc"
        case "\$_hi_fallback" in
        zsh)
          cp "\$_hi_rc_dir/.hi_fallback_rc" "\$_hi_rc_dir/.zshrc"
          ZDOTDIR="\$_hi_rc_dir" zsh -i
          ;;
        fish) fish -C "source \$_hi_rc_dir/.hi_fallback_rc" ;;
        *) ENV="\$_hi_rc_dir/.hi_fallback_rc" sh -i ;;
        esac
      fi
REMOTE
}

# Connect to the target, copy hi.d over, and hand off to load.sh.
# The payload below is handed to `sh -c` rather than run directly by the login
# shell, since not all of them handle the same syntax - every line up to the
# bash/sh branch at the end is plain POSIX, so `sh` alone is enough to land it.
# Technically, all of hi runs under a single sh sub-process that we start on
# the target, which chainloads bash for the full experience when it's there.
function _say_hi() {
  local size hi_esc nc_esc script middle b64 boot_tmp remote_root tmp_root ctl_path ec=0
  local -a ctl_opts

  hi_esc="$(printf '%b' "$YELLOW")"
  nc_esc="$(printf '%b' "$NC")"

  # multiplex the install-probe and the real session over one ssh connection,
  # so checking for an existing install never costs a second authentication
  ctl_path="$(mktemp -u -t hi.cm.XXXXXX)"
  ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o ControlPersist=30)
  remote_root="$(_hi_remote_root "${ctl_opts[@]}")"

  if [ -n "$remote_root" ]; then
    # scripts/install.sh has already run on the target - load that copy in
    # place instead of shipping a fresh one over, and never delete it
    tmp_root="${remote_root%/hi.d}"
    middle="$(cat <<REMOTE
      export _HI_HOME="$tmp_root"
      export _HI_ROOT="$remote_root"
      _hi_rc_dir="\$(dirname "\$0")"
      printf '%s %s%s' "$hi_esc" "$nc_esc" "-> local hi.d install"
      echo "$(_hi_bootloader | $_HI_ARMOR)" | $_HI_UNARMOR > "\$_hi_rc_dir/hi.bashrc"
      export _HI_CONNECT_PREFIX="-> local hi.d install"
REMOTE
    )"
  else
    size="$(_hi_size)"
    middle="$(cat <<REMOTE
      export _HI_HOME=\$(mktemp -d -t $(whoami).hi.XXXXXX) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_HOME/hi.d
      export _HI_CLEANUP=\$_HI_HOME
      mkdir "\$_HI_ROOT"
      trap 'rm -rf \$_HI_CLEANUP' exit
      _hi_rc_dir="\$_HI_ROOT"
      printf '%s %s%s' "$hi_esc" "$nc_esc" "$size"
      echo "$($_HI_ARMOR <"$0")" | $_HI_UNARMOR > "\$_HI_ROOT/hi.sh"
      chmod +x "\$_HI_ROOT/hi.sh"
      echo "$(_hi_bootloader | $_HI_ARMOR)" | $_HI_UNARMOR > "\$_hi_rc_dir/hi.bashrc"
      echo "$(tar czf - -h -C "$_HI_HOME" "${_HI_EXCLUDE[@]}" hi.d | $_HI_ARMOR)" | $_HI_UNARMOR | tar mxzf - -C "\$_HI_HOME"
      export _HI_CONNECT_PREFIX=" $size"
REMOTE
    )"
  fi

  script="$(_hi_remote_preamble)
$middle
$(_hi_remote_suffix)"

  # base64-armor the whole script, write to a file and run as `sh file`
  # rather than piped into `sh`, so sh's stdin - and hence the nested
  # `bash --rcfile`'s - stays attached to the pty ssh -t allocated, instead
  # of being consumed by the decode pipe.
  b64="$(printf '%s' "$script" | openssl enc -base64 -A)"
  boot_tmp="$(mktemp -t hi.boot.XXXXXX)"

  # shellcheck disable=SC2029
  ssh -t "${ctl_opts[@]}" "${SSHARGS[@]}" "$DOMAIN" \
    "mkdir -m 700 $boot_tmp && echo $b64 | openssl enc -base64 -d -A > $boot_tmp/bootloader && sh $boot_tmp/bootloader; rm -rf $boot_tmp" '||' \
    powershell -NoLogo -NoExit -Command \
    "Write-Host 'hi from PowerShell - no bash or sh on this host, hi.d colors/aliases are unavailable' -ForegroundColor Yellow" || ec=$?

  ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1 || true
  rm -rf "$ctl_path" 2>/dev/null || true
  return "$ec"
}

# both container types use the same style of copying our configurations, but
# they use different syntax for the start (since both are docker containers)
# the fancy syntax lets us re-use one function for both types of containers
# as well as source the aliases.sh file if the container is (likely) minimal
function _say_hi_container() {
  local label="$1" shell_end root fallback exit_code shell_secs size prefix
  local -a probe cp attach
  case "$label" in
  docker)
    probe=(docker exec "$DOMAIN")
    cp=(docker exec -i "$DOMAIN")
    attach=(docker exec -it "$DOMAIN")
    ;;
  nomad)
    probe=(nomad alloc exec -i=false -t=false "$DOMAIN")
    cp=(nomad alloc exec -i=true -t=false "$DOMAIN")
    attach=(nomad alloc exec "$DOMAIN")
    ;;
  esac

  root="/tmp/$(whoami).hi.log.$$"
  shell_end="$(_hi_now)"

  # no bash on the target means no fancy stuff, just our aliases
  if ! "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>"$tmp"; then
    # shellcheck disable=SC2016
    fallback=$("${probe[@]}" sh -c 'for s in zsh fish sh; do command -v "$s" >/dev/null 2>&1 && { echo "$s"; break; }; done' 2>"$tmp")
    [ -n "$fallback" ] || return 1
    _hi_cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW"

    if ! "${cp[@]}" sh -c "mkdir -p '$root' && cat > '$root/aliases.sh'" <"$_HI_ALIASES" 2>"$tmp"; then
      _hi_cecho " failed to copy aliases.sh into [$DOMAIN]" "$BRRED"
      "${attach[@]}" "$fallback"
      return $?
    fi

    # aliases.sh, plus CMDARG (already suffixed with "; exit" by _hi_parse) as
    # its own raw line when running a one-off command instead of a session -
    # not a quoted CLI arg, so it survives quotes/spaces in the user's command
    { printf '. %s/aliases.sh 2>/dev/null\n' "$root"
      [ -n "${CMDARG:-}" ] && printf '%s\n' "$CMDARG"; } |
      "${cp[@]}" sh -c "cat > '$root/.hi_fallback_rc'" 2>"$tmp"

    case "$fallback" in
    zsh)
      "${cp[@]}" sh -c "cp '$root/.hi_fallback_rc' '$root/.zshrc'" 2>"$tmp"
      "${attach[@]}" sh -c "export ZDOTDIR='$root'; exec zsh -i"
      ;;
    fish) "${attach[@]}" fish -C "source $root/.hi_fallback_rc" ;;
    *) "${attach[@]}" sh -c "export ENV='$root/.hi_fallback_rc'; exec $fallback -i" ;;
    esac
    exit_code=$?
    "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
    return $exit_code
  fi

  shell_secs="$(_hi_elapsed "$_HI_SHELL_START" "$shell_end")"
  _hi_cecho " shell: ${shell_secs}s " "$BLUE" 1
  size="$(_hi_size)"
  prefix=" shell: ${shell_secs}s -> bash ($label) $size"
  echo -ne "$YELLOW-> bash ($label)$NC $size"

  # this is a failure state, so we exit early
  if ! tar czf - -h -C "$_HI_HOME" "${_HI_EXCLUDE[@]}" hi.d |
    "${cp[@]}" sh -c "mkdir -p '$root' && tar mxzf - -C '$root'"; then
    _hi_cecho " failed to copy hi.d into [$DOMAIN]" "$BRRED"
    "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
    return 1
  fi

  "${cp[@]}" sh -c "cat > '$root/hi.d/hi.sh' && chmod +x '$root/hi.d/hi.sh'" <"$0"
  _hi_bootloader | "${cp[@]}" sh -c "cat > '$root/hi.d/hi.bashrc'"

  "${attach[@]}" sh -c "export _HI_HOME='$root' _HI_ROOT='$root/hi.d' _HI_COPY_TIME='$(_hi_copy_time "$copy_start" "$_HI_SHELL_START" "$shell_end")' _HI_CONNECT_PREFIX='$prefix'; exec bash --rcfile '$root/hi.d/hi.bashrc'"
  exit_code=$?

  "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
  return $exit_code
}

# split ssh's arguments from the target and any trailing remote command
function _hi_parse() {
  SSHARGS=()
  while [ $# -gt 0 ]; do
    case $1 in
    -b | -c | -D | -E | -e | -F | -I | -i | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
      SSHARGS+=("$1" "$2")
      shift
      ;;
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
  if _hi_is_ssh_host "$DOMAIN"; then
    _say_hi 2>"$tmp"
  elif _hi_is_docker_container "$DOMAIN"; then
    _say_hi_container docker 2>"$tmp"
  elif _hi_is_nomad_alloc "$DOMAIN"; then
    _say_hi_container nomad 2>"$tmp"
  else
    _say_hi 2>"$tmp"
  fi
  exit_code="$?"

  if [ "$exit_code" -ne 0 ]; then
    errors="$(cat "$tmp")"
    echo -ne "\r\r\r\r"
    _hi_cecho "hi failed [code: $exit_code]" "$BRRED"
    _hi_cecho "$errors" "$BRRED"
  fi
  exit "$exit_code"
}

set +euo pipefail # must be disabled after our code (this file is part of the interactive shell - any error would close the session)

_hi "$@"
