#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client: copies hi.d to the target (ssh host, docker container or
# nomad alloc) and chainloads load.sh there.
# set -eou pipefail # cannot be enabled (this script is part of the interactive shell - any error would close the session)
# _run -> _hi_parse -> _say_hi | _say_hi_engine

# shellcheck source=./common/bootstrap.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"

command -v openssl >/dev/null 2>&1 || {
  cecho >&2 "hi requires openssl on [$(_hi_hostname)], but it is not installed. Aborting..." "$RED"
  exit 1
}

# nothing here is needed on the target (or would be stale there)
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

# time spent copying = everything but the remote shell probe
function _hi_copy_time() {
  echo "$(_hi_now) $1 $2 $3" | awk '{ printf "%.3f\n", ($1 - $2) - ($4 - $3) }'
}

# The rc bash reads on the target: the host's own profile first, then hi's, and
# finally either the command the user passed (`hi host 'cmd'`, just like ssh) or
# an interactive session. $1 is how long the copy took, for load's timing line.
# $2 is the plain text of the "shell: ...s -> ... <size>" line already printed
# on the client, so the target's Connected banner can pick up where it left off.
function _hi_bootstrap_rc() {
  cat <<EOF
if [ -r /etc/profile ]; then source /etc/profile; fi
if [ -r ~/.bash_profile ]; then source ~/.bash_profile
elif [ -r ~/.bash_login ]; then source ~/.bash_login
elif [ -r ~/.profile ]; then source ~/.profile
fi
export PATH=\$PATH:\$_HI_ROOT
export _HI_COPY_TIME='$1'
export _HI_CONNECT_PREFIX='$2'
source \$_HI_ROOT/load.sh
${CMDARG:-load}
EOF
}

function _hi_size() {
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  du -sh "${_HI_EXCLUDE[@]}" $_HI_LINUX_FLAGS "$_HI_ROOT" | awk '{ print $1 }'
}

# Connect to remote host, determine shell, then copy hi.d & run load.sh.
# This could be removed if we required all targets to run bash as the login shell.
# This part takes usually 0.5-2s, which is noticeable and quite annoying.
# Ideally, we could stay on the target if we have login bash, reducing the overall
# connection for most connections, but I haven't figured that out yet.
function _say_hi() {
  local remote_shell trap_cmd shell_end shell_secs size prefix

  # This command line is parsed by the user's login shell, so it must stay free
  # of bash/sh-specific syntax (e.g. if/fi), or it breaks on login shells with a
  # different grammar (e.g. fish uses if/end). The script itself goes over stdin,
  # where `bash -s` reads and runs it.
  remote_shell=$(
    ssh "${SSHARGS[@]}" "$DOMAIN" bash -s 2>"$tmp" <<'EOF'
    if [ -n "$SHELL" ]; then
      basename "$SHELL"
    elif command -v getent >/dev/null 2>&1; then
      getent passwd "$(id -un)" | awk -F: '{ print $NF }' | xargs basename
    elif command -v dscl >/dev/null 2>&1; then
      dscl . -read ~/ UserShell 2>/dev/null | awk '{ print $2 }' | xargs basename
    else
      awk -F: -v u="$(id -un)" '$1==u{print $NF}' /etc/passwd | xargs basename
    fi
EOF
  )
  [ -n "$remote_shell" ] || return 1

  shell_end="$(_hi_now)"
  shell_secs="$(_hi_elapsed "$_HI_SHELL_START" "$shell_end")"
  cecho " shell: ${shell_secs}s " "$BLUE" 1

  trap_cmd="trap 'rm -rfv \$_HI_CLEANUP' exit"
  [ "$remote_shell" = zsh ] && trap_cmd="TRAPEXIT() { rm -rfv \$_HI_CLEANUP; }"

  size="$(_hi_size)"
  prefix=" shell: ${shell_secs}s -> $remote_shell $size"
  echo -ne "$YELLOW-> $remote_shell$NC $size"
  # shellcheck disable=SC2029 # the client-side expansions here are the point
  ssh -t "${SSHARGS[@]}" "$DOMAIN" "
      command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl on [$DOMAIN], but it is not installed. Aborting.\"; exit 1; }
      export _HI_TMPDIR=\$(mktemp -d -t $(whoami).hi.XXXXXX) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_TMPDIR/hi.d
      export _HI_CLEANUP=\$_HI_TMPDIR
      mkdir \$_HI_ROOT
      $trap_cmd
      echo \"$($_HI_ARMOR <"$0")\" | $_HI_UNARMOR > \$_HI_ROOT/hi.sh
      chmod +x \$_HI_ROOT/hi.sh
      echo \"$(_hi_bootstrap_rc "$(_hi_copy_time "$copy_start" "$_HI_SHELL_START" "$shell_end")" "$prefix" | $_HI_ARMOR)\" | $_HI_UNARMOR > \$_HI_ROOT/hi.bashrc
      echo \"$(tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d | $_HI_ARMOR)\" | $_HI_UNARMOR | tar mxzf - -C \$_HI_TMPDIR
      bash --rcfile \$_HI_ROOT/hi.bashrc
      "
}

# Docker/nomad session. Both engines are driven purely through three exec
# prefixes (probe: no tty/stdin, cp: stdin only, attach: tty+stdin), so all
# copying goes through `sh -c "cat > path"` and all env vars are set via a
# `sh -c "export ...; exec ..."` wrapper - the one interface both support.
function _say_hi_engine() {
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

  root="/tmp/$(whoami).hi.$$"
  shell_end="$(_hi_now)"

  # no bash on the target means no hi config - fall back to the best plain
  # shell there, with just our aliases sourced into it
  if ! "${probe[@]}" sh -c 'command -v bash' >/dev/null 2>"$tmp"; then
    # shellcheck disable=SC2016
    fallback=$("${probe[@]}" sh -c 'for s in zsh fish sh; do command -v "$s" >/dev/null 2>&1 && { echo "$s"; break; }; done' 2>"$tmp")
    [ -n "$fallback" ] || return 1
    cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback w/ aliases" "$YELLOW"

    if ! "${cp[@]}" sh -c "mkdir -p '$root' && cat > '$root/aliases.sh'" <"$_HI_ALIASES" 2>"$tmp"; then
      cecho " failed to copy aliases.sh into [$DOMAIN]" "$BRRED"
      "${attach[@]}" "$fallback"
      return $?
    fi

    case "$fallback" in
    zsh)
      "${probe[@]}" sh -c "echo '. $root/aliases.sh 2>/dev/null' > '$root/.zshrc'" 2>"$tmp"
      "${attach[@]}" sh -c "export ZDOTDIR='$root'; exec zsh"
      ;;
    fish) "${attach[@]}" fish -C "source $root/aliases.sh 2>/dev/null" ;;
    *) "${attach[@]}" sh -c "export ENV='$root/aliases.sh'; exec $fallback" ;;
    esac
    exit_code=$?
    "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
    return $exit_code
  fi

  shell_secs="$(_hi_elapsed "$_HI_SHELL_START" "$shell_end")"
  cecho " shell: ${shell_secs}s " "$BLUE" 1
  size="$(_hi_size)"
  prefix=" shell: ${shell_secs}s -> bash ($label) $size"
  echo -ne "$YELLOW-> bash ($label)$NC $size"

  if ! tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d |
    "${cp[@]}" sh -c "mkdir -p '$root' && tar mxzf - -C '$root'"; then
    cecho " failed to copy hi.d into [$DOMAIN]" "$BRRED"
    "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
    return 1
  fi

  "${cp[@]}" sh -c "cat > '$root/hi.d/hi.sh' && chmod +x '$root/hi.d/hi.sh'" <"$0"
  _hi_bootstrap_rc "$(_hi_copy_time "$copy_start" "$_HI_SHELL_START" "$shell_end")" "$prefix" |
    "${cp[@]}" sh -c "cat > '$root/hi.d/hi.bashrc'"

  "${attach[@]}" sh -c "export _HI_TMPDIR='$root' _HI_ROOT='$root/hi.d'; exec bash --rcfile '$root/hi.d/hi.bashrc'"
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

function _run() {
  local copy_start tmp exit_code errors

  [ -d "$_HI_ROOT" ] || {
    cecho "No such directory: $_HI_ROOT" "$RED" >&2
    exit 1
  }

  copy_start="$(_hi_now)"
  tmp="$(mktemp -t hi.XXXXXX)"
  # shellcheck disable=SC2016 # $tmp is resolved when the trap fires
  _hi_on_exit 'rm -f "$tmp"'

  _hi_parse "$@"
  _HI_SHELL_START="$(_hi_now)"
  if _hi_is_ssh_host "$DOMAIN"; then
    _say_hi 2>"$tmp"
  elif _hi_is_docker_container "$DOMAIN"; then
    _say_hi_engine docker 2>"$tmp"
  elif _hi_is_nomad_alloc "$DOMAIN"; then
    _say_hi_engine nomad 2>"$tmp"
  else
    _say_hi 2>"$tmp"
  fi
  exit_code="$?"

  if [ "$exit_code" -ne 0 ]; then
    errors="$(cat "$tmp")"
    echo -ne "\r\r\r\r"
    cecho "hi failed [code: $exit_code]" "$BRRED"
    cecho "$errors" "$BRRED"
  fi
  exit "$exit_code"
}

_run "$@"
