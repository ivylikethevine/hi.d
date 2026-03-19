#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# set -eou pipefail

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"
if [ ! -f "$_HI_HOST_COLORS" ] || [ ! -f "$_HI_USER_COLORS" ]; then
  # shellcheck source=./scripts/colorgen.sh
  source "$_HI_COLORGEN"
  # This will autogenerate the colors if we don't have any yet.
  initial_colorgen
fi

command -v openssl >/dev/null 2>&1 || {
  cecho >&2 "hi requires openssl to be installed on [$(hostname)], but it is not. Aborting..." "$RED"
  exit 1
}

hi_exclude=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh --exclude hi.bashrc --exclude data/group_config --exclude .zed --exclude data/.gitkeep --exclude wip)

# TODO: Use travel_config when on remote hosts
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

function say_hi() {
  if [ -d "$HI_ROOT" ]; then
    local TR_CMD="tr -s ' ' '\n'"
    # TODO: Handle issue with fish-shell and the ZSH_VERSION trap branching...
    # Should be able to determine login shell by grepping /etc/passwd for username, then can branch properly?
    # local shellname
    # shellname=$(cat /etc/passwd | grep -e "$USER" | xargs basename)
    local OPENSSL_CMD="openssl enc -base64"
    ssh -t "$DOMAIN" "$SSHARGS" "
            command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on [$DOMAIN], but it is not. Aborting.\"; exit 1; }
            export HI_TMPDIR=\$(mktemp -d -t $(whoami).hi.XXXX)
            mkdir \$HI_TMPDIR/hi.d
            export HI_ROOT=\$HI_TMPDIR/hi.d
            export HI_CLEANUP=\$HI_TMPDIR
            if [[ -z \${ZSH_VERSION+x} ]]; then
              trap 'rm -rf \$HI_CLEANUP' exit
            else
              TRAPEXIT() { rm -rf \$HI_CLEANUP; }
            fi
            echo \"$(cat "$0" | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.sh
            chmod +x \$HI_ROOT/hi.sh
            echo \"$(
      cat <<'EOF' | $OPENSSL_CMD
                if [ -r /etc/profile ]; then source /etc/profile; fi
                if [ -r ~/.bash_profile ]; then source ~/.bash_profile
                elif [ -r ~/.bash_login ]; then source ~/.bash_login
                elif [ -r ~/.profile ]; then source ~/.profile
                fi
                export PATH=$PATH:${HI_ROOT+x}
                source $HI_ROOT/load.sh
                load
EOF
    )\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.bashrc
            echo \"$(tar czf - -h -C "$HI_TMPDIR" "${hi_exclude[@]}" hi.d | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d | tar mxzf - -C \$HI_TMPDIR
            export HI_TMPDIR=\$HI_TMPDIR
            export HI_ROOT=\$HI_ROOT
            echo \"$CMDARG\" >> \$HI_ROOT/hi.bashrc
            echo \"export hi_copy_time='$(echo "$(perl -MTime::HiRes=time -e 'printf "%.3f", time') $copy_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$HI_ROOT/load.sh
            bash --rcfile \$HI_ROOT/hi.bashrc
            "
  else
    cecho "No such directory: $HI_ROOT" "$RED" >&2
    return 1
  fi
}

function run() {
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

  local _exit_code="$?"
  local _errors
  _errors="$(cat "$tmp")"

  if [ "$_exit_code" -ne 0 ]; then
    echo -ne "\r\r\r\r"
    if [[ "$_errors" == *"Could not resolve hostname"* ]] \
      || [[ "$_errors" == *"Broken pipe"* ]] \
      || [[ "$_errors" == *"no such identity"* ]] \
      || [[ "$_errors" == *"Permission denied"* ]]; then
      cecho "| hi: ${_errors#*ssh: }" "$RED"
    else
      cecho "hi failed [code: $_exit_code], falling back to ssh..." "$BRRED"
      cecho "$_errors" "$BRRED"
      ssh "$@"
      exit 1
    fi
  fi
  exit "$_exit_code"
}

run "$@"
