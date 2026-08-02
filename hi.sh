#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

command -v openssl >/dev/null 2>&1 || {
  cecho >&2 "hi requires openssl to be installed on [$(hostname)], but it is not. Aborting..." "$RED"
  exit 1
}

# This will autogenerate the colors if we don't have any yet.
if [ ! -f "$_HI_HOST_COLORS" ] || [ ! -f "$_HI_USER_COLORS" ]; then
  # shellcheck source=./scripts/colorgen.sh
  source "$_HI_COLORGEN"
  initial_colorgen
fi

# Unify as many parts of the process as possible
export _HI_EXCLUDE=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh --exclude hi.bashrc --exclude data/group_config --exclude .zed --exclude data/.gitkeep --exclude wip)
export _HI_TR_CMD="tr -s ' ' '\n'"
export _HI_OPENSSL_CMD="openssl enc -base64"
export _HI_OPENSSL_CHECK="command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on [$DOMAIN], but it is not. Aborting.\"; exit 1; }"
export _HI_TRAP="trap 'rm -rf \$_HI_CLEANUP' exit"

# Parse ssh arguments
function hi_parse() {
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

# Connect to remote host, determine shell, then copy hi.d & run load.sh.
# This could be removed if we required all targets to run bash as the login shell.
# This part takes usually 0.5-2s, which is noticeable and quite annoying.
# Ideally, we could stay on the target if we have login bash, reducing the overall
# connection for most connections, but I haven't figured that out yet.
function say_hi() {
  local shell_start_time
  local remote_shell
  local tmp
  local shell_end_time
  local linux_flags=""

  shell_start_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  tmp="/tmp/$(date +%s).hi"
  remote_shell=$(ssh "$DOMAIN" '[ ! -f /etc/os-release ] && dscl . -read ~/ UserShell 2>/dev/null | awk "{ print \$2 }" | xargs basename || cat /etc/passwd | grep -e $(whoami) | xargs basename' 2>"$tmp")

  if [ "$remote_shell" = "" ]; then
    cecho " $(cat "$tmp")" "$BRRED"
    exit 1
  fi

  shell_end_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  cecho " $(echo "$shell_end_time $shell_start_time" | awk '{ printf "shell: %.3fs ", $1 - $2 }')" "$BLUE" 1

  if [ -f /etc/os-release ]; then
    linux_flags="--apparent-size"
  fi

  if [ "$remote_shell" = "zsh" ]; then
    _HI_TRAP="TRAPEXIT() { rm -rf \$_HI_CLEANUP; }"
  fi

  echo -ne "$YELLOW-> $remote_shell$NC $(du -sh "${_HI_EXCLUDE[@]}" $linux_flags ~/.hi.d "$_HI_ROOT" | awk '{ print $1 }')"
  say_hi_inner "$@" 2>"$tmp"
}


# Bash & Fish shell both work with this command
function say_hi_inner() {
  ssh -t "$DOMAIN" "$SSHARGS" "
      $_HI_OPENSSL_CHECK
      export _HI_TMPDIR=\$(mktemp -d -t $(whoami).hi.XXXX)
      mkdir \$_HI_TMPDIR/hi.d
      export _HI_ROOT=\$_HI_TMPDIR/hi.d
      export _HI_CLEANUP=\$_HI_TMPDIR
      $_HI_TRAP
      echo \"$(cat "$0" | $_HI_OPENSSL_CMD)\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d > \$_HI_ROOT/hi.sh
      chmod +x \$_HI_ROOT/hi.sh
      echo \"$(
    cat <<'EOF' | $_HI_OPENSSL_CMD
      if [ -r /etc/profile ]; then source /etc/profile; fi
      if [ -r ~/.bash_profile ]; then source ~/.bash_profile
      elif [ -r ~/.bash_login ]; then source ~/.bash_login
      elif [ -r ~/.profile ]; then source ~/.profile
      fi
      export PATH=$PATH:${_HI_ROOT+x}
      source $_HI_ROOT/load.sh
      load
EOF
  )\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d > \$_HI_ROOT/hi.bashrc
      echo \"$(tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d | $_HI_OPENSSL_CMD)\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d | tar mxzf - -C \$_HI_TMPDIR
      export _HI_TMPDIR=\$_HI_TMPDIR
      export _HI_ROOT=\$_HI_ROOT
      echo \"$CMDARG\" >> \$_HI_ROOT/hi.bashrc
      echo \"export hi_copy_time='$(echo "$(perl -MTime::HiRes=time -e 'printf "%.3f", time') $copy_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$_HI_ROOT/load.sh
      bash --rcfile \$_HI_ROOT/hi.bashrc
      "
}

# Check dependencies, start to say hi, handle errors (both hi & ssh)
function run() {
  local copy_start_time
  local tmp
  local _exit_code
  local _errors

  if [ -d "$_HI_ROOT" ]; then
    # TODO: sh doesn't have perl :/
    copy_start_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
    tmp="/tmp/$(date +%s).hi"
    if [[ -z ${ZSH_VERSION+x} ]]; then
      trap 'rm -rf $tmp' exit
    else
      # shellcheck disable=SC2329
      TRAPEXIT() { rm -rf "$tmp"; }
    fi

    hi_parse "$@"
    say_hi "$@" 2>"$tmp"

    _exit_code="$?"
    _errors="$(cat "$tmp")"

    if [ "$_exit_code" -ne 0 ]; then
      echo -ne "\r\r\r\r"
      cecho "hi failed [code: $_exit_code], falling back to ssh..." "$BRRED"
      cecho "$_errors" "$BRRED"
      ssh "$@"
      exit 1
    fi
    exit "$_exit_code"

  else
    cecho "No such directory: $_HI_ROOT" "$RED" >&2
    exit 1
  fi
}

run "$@"
