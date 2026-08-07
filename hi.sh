#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc & https://github.com/cdown/sshrc
# Runs on the client - copies hi.d to the target and chainloads load.sh there.
# set -eou pipefail # cannot be enabled (this script is part of the interactive shell - any error would close the session)

# shellcheck source=./common/bootstrap.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"

command -v openssl >/dev/null 2>&1 || {
  cecho >&2 "hi requires openssl on [$(_hi_hostname)], but it is not installed. Aborting..." "$RED"
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

function _hi_copy_time() {
  echo "$(_hi_now) $1 $2 $3" | awk '{ printf "%.3f\n", ($1 - $2) - ($4 - $3) }'
}

function _hi_bootstrap_rc() {
  cat <<EOF
if [ -r /etc/profile ]; then source /etc/profile; fi
if [ -r ~/.bash_profile ]; then source ~/.bash_profile
elif [ -r ~/.bash_login ]; then source ~/.bash_login
elif [ -r ~/.profile ]; then source ~/.profile
fi
export PATH=\$PATH:\$_HI_ROOT
source \$_HI_ROOT/load.sh
${CMDARG:-load}
EOF
}

function _hi_size() {
  # shellcheck disable=SC2086 # unquoted so an empty flag list disappears
  du -sh "${_HI_EXCLUDE[@]}" $_HI_LINUX_FLAGS "$_HI_ROOT" | awk '{ print $1 }'
}

# Connect to the target, copy hi.d over, and hand off to load.sh.
# The payload below is handed to `bash -c` rather than run directly by the
# login shell, since not all of them handle the same syntax. Technically,
# all of hi runs under a single bash sub-process that we start on the target.
function _say_hi() {
  local size hi_esc nc_esc script quoted

  size="$(_hi_size)"
  hi_esc="$(printf '%b' "$YELLOW")"
  nc_esc="$(printf '%b' "$NC")"

  script="$(cat <<REMOTE
      _hi_now() { d=\$(date +%s.%N 2>/dev/null); case "\$d" in *N*|'') date +%s ;; *) printf '%s' "\$d" ;; esac; }
      _hi_t0=\$(_hi_now)
      command -v openssl >/dev/null 2>&1 || { echo >&2 "hi requires openssl on [$DOMAIN], but it is not installed. Aborting."; exit 1; }
      export _HI_TMPDIR=\$(mktemp -d -t $(whoami).hi.XXXXXX) # busybox mktemp needs exactly six X
      export _HI_ROOT=\$_HI_TMPDIR/hi.d
      export _HI_CLEANUP=\$_HI_TMPDIR
      mkdir \$_HI_ROOT
      trap 'rm -rfv \$_HI_CLEANUP' exit
      printf '%s %s%s' "$hi_esc" "$nc_esc" "$size"
      echo "$($_HI_ARMOR <"$0")" | $_HI_UNARMOR > \$_HI_ROOT/hi.sh
      chmod +x \$_HI_ROOT/hi.sh
      echo "$(_hi_bootstrap_rc | $_HI_ARMOR)" | $_HI_UNARMOR > \$_HI_ROOT/hi.bashrc
      echo "$(tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d | $_HI_ARMOR)" | $_HI_UNARMOR | tar mxzf - -C \$_HI_TMPDIR
      export _HI_COPY_TIME=\$(awk -v a="\$_hi_t0" -v b="\$(_hi_now)" 'BEGIN{printf "%.3f", b-a}')
      export _HI_CONNECT_PREFIX="-> $size"
      bash --rcfile \$_HI_ROOT/hi.bashrc
REMOTE
  )"

  # POSIX-single-quote the whole script so any login shell hands it
  # to `bash -c` as one untouched argument.
  quoted="'$(printf '%s' "$script" | sed "s/'/'\\\\''/g")'"

  # shellcheck disable=SC2029
  ssh -t "${SSHARGS[@]}" "$DOMAIN" bash -c "$quoted"
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

  root="/tmp/$(whoami).hi.$$"
  shell_end="$(_hi_now)"

  # no bash on the target means no fancy stuff, just our aliases
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

  # this is a failure state, so we exit early
  if ! tar czf - -h -C "$_HI_TMPDIR" "${_HI_EXCLUDE[@]}" hi.d |
    "${cp[@]}" sh -c "mkdir -p '$root' && tar mxzf - -C '$root'"; then
    cecho " failed to copy hi.d into [$DOMAIN]" "$BRRED"
    "${probe[@]}" rm -rf "$root" >/dev/null 2>&1
    return 1
  fi

  "${cp[@]}" sh -c "cat > '$root/hi.d/hi.sh' && chmod +x '$root/hi.d/hi.sh'" <"$0"
  _hi_bootstrap_rc | "${cp[@]}" sh -c "cat > '$root/hi.d/hi.bashrc'"

  "${attach[@]}" sh -c "export _HI_TMPDIR='$root' _HI_ROOT='$root/hi.d' _HI_COPY_TIME='$(_hi_copy_time "$copy_start" "$_HI_SHELL_START" "$shell_end")' _HI_CONNECT_PREFIX='$prefix'; exec bash --rcfile '$root/hi.d/hi.bashrc'"
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
  _hi_on_exit 'rm -fv "$tmp"'

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
    cecho "hi failed [code: $exit_code]" "$BRRED"
    cecho "$errors" "$BRRED"
  fi
  exit "$exit_code"
}

_run "$@"
