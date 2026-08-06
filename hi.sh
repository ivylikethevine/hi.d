#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# https://github.com/cdown/sshrc/tree/master
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/bootstrap.sh
source "$_HI_TMPDIR/hi.d/common/bootstrap.sh"

command -v openssl >/dev/null 2>&1 || {
  cecho >&2 "hi requires openssl to be installed on [$(_hi_hostname)], but it is not. Aborting..." "$RED"
  exit 1
}

export _HI_EXCLUDE=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh --exclude hi.bashrc --exclude .zed)
export _HI_TR_CMD="tr -s ' ' '\n'"
export _HI_OPENSSL_CMD="openssl enc -base64"
export _HI_TRAP="trap 'rm -rfv \$_HI_CLEANUP' exit"
export _HI_SHELL_START

function _hi_shell_elapsed() {
  echo "$2 $1" | awk '{ printf "shell: %.3fs ", $1 - $2 }'
}

function _hi_copy_time() {
  echo "$(_hi_now) $1" "$2" "$3" | awk '{ printf "%.3f\n", ($1 - $2) - ($4 - $3) }'
}

function _hi_is_ssh_host() {
  local host="$1"
  [ -f "$_HI_SSH_CONFIG_FILE" ] || return 1
  awk -v h="$host" '
    tolower($1) == "host" {
      for (i = 2; i <= NF; i++) if ($i == h) { found=1; exit }
    }
    END { exit !found }
  ' "$_HI_SSH_CONFIG_FILE"
}

function _hi_is_docker_container() {
  local name="$1"
  command -v docker >/dev/null 2>&1 || return 1
  [ "$(docker container inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = "true" ]
}

function _hi_is_nomad_alloc() {
  local name="$1"
  command -v nomad >/dev/null 2>&1 || return 1
  [ "$(nomad alloc status -t '{{.ClientStatus}}' "$name" 2>/dev/null)" = "running" ]
}

function _hi_bootstrap_rc() {
  local extra="${1:-}"
  cat <<EOF
if [ -r /etc/profile ]; then source /etc/profile; fi
if [ -r ~/.bash_profile ]; then source ~/.bash_profile
elif [ -r ~/.bash_login ]; then source ~/.bash_login
elif [ -r ~/.profile ]; then source ~/.profile
fi
export PATH=\$PATH:\$_HI_ROOT
source \$_HI_ROOT/load.sh
$extra
load
EOF
}

# Connect to remote host, determine shell, then copy hi.d & run load.sh.
# This could be removed if we required all targets to run bash as the login shell.
# This part takes usually 0.5-2s, which is noticeable and quite annoying.
# Ideally, we could stay on the target if we have login bash, reducing the overall
# connection for most connections, but I haven't figured that out yet.
function _say_hi() {
  local remote_shell tmp shell_end_time

  tmp="/tmp/$(date +%s).hi"

  # The remote command line ("bash -s") is parsed by the user's login shell,
  # so it must stay free of any bash/sh-specific syntax (e.g. if/fi), or it
  # breaks on login shells with different grammar (e.g. fish uses if/end).
  # The actual script is sent over stdin, where bash -s reads and runs it.
  remote_shell=$(
    ssh "$DOMAIN" bash -s 2>"$tmp" <<'EOF'
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

  if [ "$remote_shell" = "" ]; then
    cecho " $(cat "$tmp")" "$BRRED"
    rm -rfv "$tmp"
    exit 1
  fi

  shell_end_time="$(_hi_now)"
  cecho " $(_hi_shell_elapsed "$_HI_SHELL_START" "$shell_end_time")" "$BLUE" 1

  if [ "$remote_shell" = "zsh" ]; then
    _HI_TRAP="TRAPEXIT() { rm -rfv \$_HI_CLEANUP; }"
  fi

  echo -ne "$YELLOW-> $remote_shell$NC $(du -sh "${_HI_EXCLUDE[@]}" "$_HI_LINUX_FLAGS" "$_HI_ROOT" | awk '{ print $1 }')"
  ssh -t "$DOMAIN" "$SSHARGS" "
      command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on [$DOMAIN], but it is not. Aborting.\"; exit 1; }
      export _HI_TMPDIR=\$(mktemp -d -t $(whoami).hi.XXXX)
      mkdir \$_HI_TMPDIR/hi.d
      export _HI_ROOT=\$_HI_TMPDIR/hi.d
      export _HI_CLEANUP=\$_HI_TMPDIR
      $_HI_TRAP
      echo \"$(cat "$0" | $_HI_OPENSSL_CMD)\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d > \$_HI_ROOT/hi.sh
      chmod +x \$_HI_ROOT/hi.sh
      echo \"$(_hi_bootstrap_rc | $_HI_OPENSSL_CMD)\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d > \$_HI_ROOT/hi.bashrc
      echo \"$(tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d | $_HI_OPENSSL_CMD)\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d | tar mxzf - -C \$_HI_TMPDIR
      export _HI_TMPDIR=\$_HI_TMPDIR
      export _HI_ROOT=\$_HI_ROOT
      echo \"$CMDARG\" >> \$_HI_ROOT/hi.bashrc
      echo \"export _HI_COPY_TIME='$(_hi_copy_time "$copy_start_time" "$_HI_SHELL_START" "$shell_end_time")'\" >> \$_HI_ROOT/load.sh
      bash --rcfile \$_HI_ROOT/hi.bashrc
      "
}

# Shared docker/nomad session logic. Both engines are driven purely through
# three exec-prefix arrays (probe: no tty/stdin, cp: stdin only, attach: tty+stdin),
# so all copying goes through `sh -c "cat > path"` and all env vars are set via
# a `sh -c "export ...; exec ..."` wrapper - the one interface both engines support.
function _say_hi_remote() {
  local label="$1"
  local -n probe="$2" cp="$3" attach="$4"
  local shell_end_time tmp has_bash fallback_shell container_tmpdir container_root hi_bashrc exit_code container_aliases container_zdotdir

  tmp="/tmp/$(date +%s).hi"
  has_bash=$("${probe[@]}" sh -c 'command -v bash' 2>"$tmp")
  shell_end_time="$(_hi_now)"

  if [ -z "$has_bash" ]; then
    # shellcheck disable=SC2016
    fallback_shell=$("${probe[@]}" sh -c '
      for s in zsh fish sh; do command -v "$s" >/dev/null 2>&1 && { echo "$s"; break; }; done
    ' 2>"$tmp")
    if [ -z "$fallback_shell" ]; then
      cecho " $(cat "$tmp")" "$BRRED"
      rm -rfv "$tmp"
      return 1
    fi
    cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback_shell w/ aliases" "$YELLOW"

    container_aliases="/tmp/.hi_aliases.$$"
    if ! "${cp[@]}" sh -c "cat > '$container_aliases'" <"$_HI_ROOT/shells/aliases.sh" 2>"$tmp"; then
      cecho " failed to copy aliases.sh into [$DOMAIN]" "$BRRED"
      rm -rfv "$tmp"
      "${attach[@]}" "$fallback_shell"
      return $?
    fi

    case "$fallback_shell" in
    zsh)
      container_zdotdir="/tmp/.hi_zdotdir.$$"
      "${probe[@]}" sh -c "mkdir -p '$container_zdotdir' && echo '. $container_aliases 2>/dev/null' > '$container_zdotdir/.zshrc'" 2>"$tmp"
      "${attach[@]}" sh -c "export ZDOTDIR='$container_zdotdir'; exec zsh"
      exit_code=$?
      "${probe[@]}" rm -rfv "$container_zdotdir" >/dev/null 2>&1
      ;;
    fish)
      "${attach[@]}" fish -C "source $container_aliases 2>/dev/null"
      exit_code=$?
      ;;
    *)
      "${attach[@]}" sh -c "export ENV='$container_aliases'; exec $fallback_shell"
      exit_code=$?
      ;;
    esac

    "${probe[@]}" rm -fv "$container_aliases" >/dev/null 2>&1
    rm -rfv "$tmp"
    return $exit_code
  fi

  cecho " $(_hi_shell_elapsed "$_HI_SHELL_START" "$shell_end_time")" "$BLUE" 1

  container_tmpdir="/tmp/$(whoami).hi.$$"
  container_root="$container_tmpdir/hi.d"

  echo -ne "$YELLOW-> bash ($label)$NC $(du -sh "${_HI_EXCLUDE[@]}" "$_HI_LINUX_FLAGS" "$_HI_ROOT" | awk '{ print $1 }')"

  if ! tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d | "${cp[@]}" sh -c "mkdir -p '$container_tmpdir' && tar mxzf - -C '$container_tmpdir'"; then
    cecho " failed to copy hi.d into [$DOMAIN]" "$BRRED"
    "${probe[@]}" rm -rfv "$container_tmpdir" >/dev/null 2>&1
    return 1
  fi

  "${cp[@]}" sh -c "cat > '$container_root/hi.sh'" <"$0"
  "${probe[@]}" chmod +x "$container_root/hi.sh" >/dev/null 2>&1

  hi_bashrc="$tmp.bashrc"
  {
    _hi_bootstrap_rc "export _HI_COPY_TIME='$(_hi_copy_time "$copy_start_time" "$_HI_SHELL_START" "$shell_end_time")'"
    echo "$CMDARG"
  } >"$hi_bashrc"
  "${cp[@]}" sh -c "cat > '$container_root/hi.bashrc'" <"$hi_bashrc"
  rm -fv "$hi_bashrc"

  "${attach[@]}" sh -c "export _HI_TMPDIR='$container_tmpdir' _HI_ROOT='$container_root'; exec bash --rcfile '$container_root/hi.bashrc'"
  exit_code=$?

  "${probe[@]}" rm -rfv "$container_tmpdir" >/dev/null 2>&1
  return $exit_code
}

function _say_hi_docker() {
  # shellcheck disable=SC2034 # read via nameref in _say_hi_remote
  local -a exec_probe=(docker exec "$DOMAIN")
  # shellcheck disable=SC2034
  local -a exec_cp=(docker exec -i "$DOMAIN")
  # shellcheck disable=SC2034
  local -a exec_attach=(docker exec -it "$DOMAIN")
  _say_hi_remote docker exec_probe exec_cp exec_attach
}

function _say_hi_nomad() {
  # shellcheck disable=SC2034 # read via nameref in _say_hi_remote
  local -a exec_probe=(nomad alloc exec -i=false -t=false "$DOMAIN")
  # shellcheck disable=SC2034
  local -a exec_cp=(nomad alloc exec -i=true -t=false "$DOMAIN")
  # shellcheck disable=SC2034
  local -a exec_attach=(nomad alloc exec "$DOMAIN")
  _say_hi_remote nomad exec_probe exec_cp exec_attach
}

# Parse ssh arguments
function _hi_parse() {
  while [[ -n ${1+x} ]]; do
    case $1 in
    -b | -c | -D | -E | -e | -F | -I | -i | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
      SSHARGS="$SSHARGS $1 $2"
      shift
      ;;
    -*)
      SSHARGS="$SSHARGS $1"
      ;;
    *)
      if [ -z ${DOMAIN+x} ]; then
        DOMAIN="$1"
      else
        local SEMICOLON=""
        SEMICOLON=$([[ "$*" = *[![:space:]]* ]] && echo '; ')
        CMDARG="$*$SEMICOLON exit"
        return
      fi
      ;;
    esac
    shift
  done
  if [ -z "$DOMAIN" ]; then
    ssh "$SSHARGS"
    exit 1
  fi
}

function _run() {
  local copy_start_time tmp exit_code errors

  if [ -d "$_HI_ROOT" ]; then
    copy_start_time="$(_hi_now)"
    tmp="/tmp/$(date +%s).hi"
    if [[ -z ${ZSH_VERSION+x} ]]; then
      trap 'rm -rfv $tmp' exit
    else
      # shellcheck disable=SC2329
      TRAPEXIT() { rm -rfv "$tmp"; }
    fi

    _hi_parse "$@"
    _HI_SHELL_START="$(_hi_now)"
    if ! _hi_is_ssh_host "$DOMAIN" && _hi_is_docker_container "$DOMAIN"; then
      _say_hi_docker 2>"$tmp"
    elif ! _hi_is_ssh_host "$DOMAIN" && _hi_is_nomad_alloc "$DOMAIN"; then
      _say_hi_nomad 2>"$tmp"
    else
      _say_hi 2>"$tmp"
    fi

    exit_code="$?"
    if [ -f "$tmp" ]; then
      errors="$(cat "$tmp")"
      rm -rfv "$tmp"
    fi

    if [ "$exit_code" -ne 0 ]; then
      echo -ne "\r\r\r\r"
      cecho "hi failed [code: $exit_code]" "$BRRED"
      cecho "$errors" "$BRRED"
    fi
    exit "$exit_code"
  else
    cecho "No such directory: $_HI_ROOT" "$RED" >&2
    exit 1
  fi
}

_run "$@"
# _run -> _hi_parse -> _say_hi | _say_hi_docker | _say_hi_nomad
