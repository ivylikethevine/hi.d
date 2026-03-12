#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc

HI_ROOT=${HI_TMPDIR:-~}/.hi.d
HI_TMPDIR=${HI_TMPDIR:-~}
HI_ROOT=${HI_TMPDIR:-~}/.hi.d
hi_exclude=(--exclude README.md --exclude .git --exclude .gitignore --exclude local --exclude hi.sh)

function hi_parse() {
  while [[ -n $1 ]]; do
    case $1 in
    -b | -c | -D | -E | -e | -F | -I | -i | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
      SSHARGS="$SSHARGS $1 $2"
      shift
      ;;
    -*)
      SSHARGS="$SSHARGS $1"
      ;;
    *)
      if [ -z "$DOMAIN" ]; then
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
  if [ ! -f "$HI_ROOT"/common/host_colors ] || [ ! -f "$HI_ROOT"/common/user_colors ]; then
    # shellcheck source=./local/create_host_colors.sh
    source "$HI_ROOT/local/create_host_colors.sh"
    # This will autogenerate the colors if we don't have any yet.
  fi

  if [ -d "$HI_ROOT" ]; then
    cecho "\r $(du -sh "${hi_exclude[@]}" --apparent-size "$HI_ROOT" | awk '{ print $1 }') " "$CYAN" 1
    local size=0
    size="$(tar cfz - -h -C "${hi_exclude[@]}" .hi.d | wc -c)"
    if [ "$size" -gt 65536 ]; then
      cecho >&2 $'.hi.d files must be less than 64kb. Current size: '"$size"' bytes' "$RED"
      return 10
    fi
    local TR_CMD="tr -s ' ' '\n'"
    local OPENSSL_CMD="openssl enc -base64"
    ssh -t "$DOMAIN" "$SSHARGS" "
            command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on [$DOMAIN], but it is not. Aborting.\"; exit 1; }
            export HI_TMPDIR=\$(mktemp -d -t .$(whoami).hi.XXXX)
            mkdir \$HI_TMPDIR/.hi.d
            export HI_ROOT=\$HI_TMPDIR/.hi.d
            export HI_CLEANUP=\$HI_TMPDIR
            trap \"rm -rf \$HI_CLEANUP; exit\" exit
            echo \"$(cat "$0" | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi
            chmod +x \$HI_ROOT/hi
            echo \"$(
      cat <<'EOF' | $OPENSSL_CMD
                if [ -r /etc/profile ]; then source /etc/profile; fi
                if [ -r ~/.bash_profile ]; then source ~/.bash_profile
                elif [ -r ~/.bash_login ]; then source ~/.bash_login
                elif [ -r ~/.profile ]; then source ~/.profile
                fi
                export PATH=$PATH:$HI_ROOT
                source $HI_ROOT/load.sh
                load
EOF
    )\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.bashrc
            echo \"$(tar czf - -h -C "$HI_TMPDIR" "${hi_exclude[@]}" .hi.d | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d | tar mxzf - -C \$HI_TMPDIR
            export HI_TMPDIR=\$HI_TMPDIR
            export HI_ROOT=\$HI_ROOT
            echo \"$CMDARG\" >> \$HI_ROOT/hi.bashrc
            echo \"export hi_copy_time='$(echo "$(date +%s.%N) $copy_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$HI_ROOT/load.sh
            bash --rcfile \$HI_ROOT/hi.bashrc
            "
  else
    cecho "No such directory: $HI_ROOT" "$RED" >&2
    return 1
  fi
}

function run() {
  copy_start_time=$(date +%s.%N)

  if ! command cecho 2>/dev/null; then
    # shellcheck source=./common/prompt_colors.sh
    source "$HI_ROOT/common/prompt_colors.sh"
  fi

  command -v openssl >/dev/null 2>&1 || {
    cecho >&2 "hi requires openssl to be installed on [$(hostname)], but it is not. Aborting..." "$RED"
    exit 1
  }

  tmp="/tmp/$(date +%s).hi"
  trap 'rm $tmp &>/dev/null' exit

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
      cecho "==============================================================================" "$BRYELLOW"
      cecho "hi failed [code: $_exit_code], falling back to ssh..." "$BRRED"
      cecho "$_errors" "$BRRED"
      cecho "==============================================================================" "$BRYELLOW"
      ssh "$@"
      exit 1
    fi
  fi
  exit "$_exit_code"
}

run "$@"
