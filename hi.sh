#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

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

_HI_LINUX_FLAGS=""
if du --version >/dev/null 2>&1 && du --version | grep -q "GNU coreutils"; then
  # busybox/bsd du (Alpine, macOS, *BSD, etc.) don't support this GNU-only flag
  _HI_LINUX_FLAGS="--apparent-size"
fi
export _HI_LINUX_FLAGS

# Unify as many parts of the process as possible
export _HI_EXCLUDE=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh --exclude hi.bashrc --exclude data/group_config --exclude .zed)
export _HI_TR_CMD="tr -s ' ' '\n'"
export _HI_OPENSSL_CMD="openssl enc -base64"
export _HI_OPENSSL_CHECK="command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on [$DOMAIN], but it is not. Aborting.\"; exit 1; }"
export _HI_TRAP="trap 'rm -rf \$_HI_CLEANUP' exit"

# Connect to remote host, determine shell, then copy hi.d & run load.sh.
# This could be removed if we required all targets to run bash as the login shell.
# This part takes usually 0.5-2s, which is noticeable and quite annoying.
# Ideally, we could stay on the target if we have login bash, reducing the overall
# connection for most connections, but I haven't figured that out yet.
function say_hi() {
  local shell_start_time remote_shell tmp shell_end_time

  shell_start_time="$(_hi_now)"
  tmp="/tmp/$(date +%s).hi"
  # prefer $SHELL (sshd sets it from the target user's account on virtually any
  # unix), then getent (linux/busybox), then dscl (macOS), then an exact-match
  # /etc/passwd read as a last resort for oddball systems with none of those
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
  cecho " $(echo "$shell_end_time $shell_start_time" | awk '{ printf "shell: %.3fs ", $1 - $2 }')" "$BLUE" 1

  if [ "$remote_shell" = "zsh" ]; then
    _HI_TRAP="TRAPEXIT() { rm -rf \$_HI_CLEANUP; }"
  fi

  echo -ne "$YELLOW-> $remote_shell$NC $(du -sh "${_HI_EXCLUDE[@]}" "$_HI_LINUX_FLAGS" ~/.hi.d "$_HI_ROOT" | awk '{ print $1 }')"
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
      export PATH=$PATH:$_HI_ROOT
      source $_HI_ROOT/load.sh
      load
EOF
  )\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d > \$_HI_ROOT/hi.bashrc
      echo \"$(tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d | $_HI_OPENSSL_CMD)\" | $_HI_TR_CMD | $_HI_OPENSSL_CMD -d | tar mxzf - -C \$_HI_TMPDIR
      export _HI_TMPDIR=\$_HI_TMPDIR
      export _HI_ROOT=\$_HI_ROOT
      echo \"$CMDARG\" >> \$_HI_ROOT/hi.bashrc
      echo \"export _HI_COPY_TIME='$(echo "$(_hi_now) $copy_start_time" "$shell_start_time" "$shell_end_time" | awk '{ printf "%.3f\n", ($1 - $2) - ($4 - $3) }')'\" >> \$_HI_ROOT/load.sh
      bash --rcfile \$_HI_ROOT/hi.bashrc
      "
}

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

function run() {
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

    hi_parse "$@"
    say_hi 2>"$tmp"

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

run "$@"
# run -> hi_parse -> say_hi
