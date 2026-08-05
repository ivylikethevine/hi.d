#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/bootstrap.sh
source "$_HI_TMPDIR/hi.d/common/bootstrap.sh"

command -v openssl >/dev/null 2>&1 || {
  cecho >&2 "hi requires openssl to be installed on [$(_hi_hostname)], but it is not. Aborting..." "$RED"
  exit 1
}

# This will autogenerate the colors if we don't have any yet.
if [ ! -f "$_HI_HOST_COLORS" ] || [ ! -f "$_HI_USER_COLORS" ]; then
  # shellcheck source=./scripts/colorgen.sh
  source "$_HI_COLORGEN"
  initial_colorgen
fi

# Unify as many parts of the process as possible
export _HI_EXCLUDE=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh --exclude hi.bashrc --exclude data/group_config --exclude .zed)
export _HI_TR_CMD="tr -s ' ' '\n'"
export _HI_OPENSSL_CMD="openssl enc -base64"
export _HI_OPENSSL_CHECK="command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on [$DOMAIN], but it is not. Aborting.\"; exit 1; }"
export _HI_TRAP="trap 'rm -rf \$_HI_CLEANUP' exit"
export _HI_SHELL_START

function _hi_shell_elapsed() {
  echo "$2 $1" | awk '{ printf "shell: %.3fs ", $1 - $2 }'
}

function _hi_copy_time() {
  echo "$(_hi_now) $1" "$2" "$3" | awk '{ printf "%.3f\n", ($1 - $2) - ($4 - $3) }'
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

# Connect to remote host, determine shell, then copy hi.d & run load.sh.
# This could be removed if we required all targets to run bash as the login shell.
# This part takes usually 0.5-2s, which is noticeable and quite annoying.
# Ideally, we could stay on the target if we have login bash, reducing the overall
# connection for most connections, but I haven't figured that out yet.
function _say_hi() {
  local remote_shell tmp shell_end_time

  tmp="/tmp/$(date +%s).hi"

  remote_shell=$(ssh "$DOMAIN" '
    if [ -n "$SHELL" ]; then
      basename "$SHELL"
    elif command -v getent >/dev/null 2>&1; then
      getent passwd "$(id -un)" | awk -F: "{ print \$NF }" | xargs basename
    elif command -v dscl >/dev/null 2>&1; then
      dscl . -read ~/ UserShell 2>/dev/null | awk "{ print \$2 }" | xargs basename
    else
      awk -F: -v u="$(id -un)" "\$1==u{print \$NF}" /etc/passwd | xargs basename
    fi
  ' 2>"$tmp")

  if [ "$remote_shell" = "" ]; then
    cecho " $(cat "$tmp")" "$BRRED"
    exit 1
  fi

  shell_end_time="$(_hi_now)"
  cecho " $(_hi_shell_elapsed "$_HI_SHELL_START" "$shell_end_time")" "$BLUE" 1

  if [ "$remote_shell" = "zsh" ]; then
    _HI_TRAP="TRAPEXIT() { rm -rf \$_HI_CLEANUP; }"
  fi

  echo -ne "$YELLOW-> $remote_shell$NC $(du -sh "${_HI_EXCLUDE[@]}" "$_HI_LINUX_FLAGS" "$_HI_ROOT" | awk '{ print $1 }')"
  ssh -t "$DOMAIN" "$SSHARGS" "
      $_HI_OPENSSL_CHECK
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

function _say_hi_docker() {
  local shell_end_time tmp has_bash fallback_shell container_tmpdir container_root hi_bashrc exit_code

  tmp="/tmp/$(date +%s).hi"

  has_bash=$(docker exec "$DOMAIN" sh -c 'command -v bash' 2>"$tmp")
  shell_end_time="$(_hi_now)"

  if [ -z "$has_bash" ]; then
    fallback_shell=$(docker exec "$DOMAIN" sh -c '
      for s in zsh fish sh; do command -v "$s" >/dev/null 2>&1 && { echo "$s"; break; }; done
    ' 2>"$tmp")
    if [ -z "$fallback_shell" ]; then
      cecho " $(cat "$tmp")" "$BRRED"
      return 1
    fi
    cecho " no bash in [$DOMAIN], skipping hi config -> plain $fallback_shell" "$YELLOW"
    docker exec -it "$DOMAIN" "$fallback_shell"
    return $?
  fi

  cecho " $(_hi_shell_elapsed "$_HI_SHELL_START" "$shell_end_time")" "$BLUE" 1

  container_tmpdir="/tmp/$(whoami).hi.$$"
  container_root="$container_tmpdir/hi.d"

  echo -ne "$YELLOW-> bash (docker)$NC $(du -sh "${_HI_EXCLUDE[@]}" "$_HI_LINUX_FLAGS" "$_HI_ROOT" | awk '{ print $1 }')"

  if ! tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d | docker exec -i "$DOMAIN" sh -c "mkdir -p '$container_tmpdir' && tar mxzf - -C '$container_tmpdir'"; then
    cecho " failed to copy hi.d into [$DOMAIN]" "$BRRED"
    docker exec "$DOMAIN" rm -rf "$container_tmpdir" >/dev/null 2>&1
    return 1
  fi

  docker cp "$0" "$DOMAIN:$container_root/hi.sh"

  hi_bashrc="$tmp.bashrc"
  {
    _hi_bootstrap_rc "export _HI_COPY_TIME='$(_hi_copy_time "$copy_start_time" "$_HI_SHELL_START" "$shell_end_time")'"
    echo "$CMDARG"
  } >"$hi_bashrc"
  docker cp "$hi_bashrc" "$DOMAIN:$container_root/hi.bashrc"
  rm -f "$hi_bashrc"

  docker exec -it -e "_HI_TMPDIR=$container_tmpdir" -e "_HI_ROOT=$container_root" "$DOMAIN" bash --rcfile "$container_root/hi.bashrc"
  exit_code=$?

  docker exec "$DOMAIN" rm -rf "$container_tmpdir" >/dev/null 2>&1
  return $exit_code
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
      trap 'rm -rf $tmp' exit
    else
      # shellcheck disable=SC2329
      TRAPEXIT() { rm -rf "$tmp"; }
    fi

    _hi_parse "$@"
    _HI_SHELL_START="$(_hi_now)"
    if ! _hi_is_ssh_host "$DOMAIN" && _hi_is_docker_container "$DOMAIN"; then
      _say_hi_docker 2>"$tmp"
    else
      _say_hi 2>"$tmp"
    fi

    exit_code="$?"
    errors="$(cat "$tmp")"
    rm -rf "$tmp"

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
# _run -> _hi_parse -> _say_hi | _say_hi_docker
