#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc

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
  # # On local machines, ~/.hi.d has our configs.
  # # On remote machines, we need to go to /tmp/.(whoami).hi.XXXX/.hi.d
  local hi_root=${HI_ROOT:=~}
  local hi_exclude=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh)

  if [ ! -f "$hi_root"/.hi.d/common/host_colors ] || [ ! -f "$hi_root"/.hi.d/common/user_colors ]; then
    # shellcheck source=./scripts/create_host_colors.sh
    source "$hi_root/.hi.d/scripts/create_host_colors.sh"
    # This will autogenerate the colors if we don't have any yet.
  fi

  if [ -d "$hi_root"/.hi.d ]; then
    echo -ne "\r $(du -sh "${hi_exclude[@]}" --apparent-size ~/.hi.d | awk '{ print $1 }') "
    local files=".hi.d"
    local size=0
    size="$(tar cfz - -h -C "$hi_root" "${hi_exclude[@]}" $files | wc -c)"
    if [ "$size" -gt 65536 ]; then
      echo >&2 $'.hi.d files must be less than 64kb. Current size: '"$size"' bytes'
      return 10
    fi
    local TR_CMD="tr -s ' ' '\n'"
    local OPENSSL_CMD="openssl enc -base64"
    ssh -t "$DOMAIN" "$SSHARGS" "
            command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on $DOMAIN, but it is not. Aborting.\"; exit 1; }
            export HI_ROOT=\$(mktemp -d -t .$(whoami).hi.XXXX)
            export HI_CLEANUP=\$HI_ROOT
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
                source $HI_ROOT/.hi.d/load.sh
EOF
    )\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.bashrc
            echo \"$(tar czf - -h -C "$hi_root" "${hi_exclude[@]}" $files | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d | tar mxzf - -C \$HI_ROOT
            export HI_ROOT=\$HI_ROOT
            echo \"$CMDARG\" >> \$HI_ROOT/hi.bashrc
            echo \"export copy_time='$(echo "$(date +%s.%N) $copy_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$HI_ROOT/.hi.d/load.sh
            echo \"load\" >> \$HI_ROOT/.hi.d/load.sh
            bash --rcfile \$HI_ROOT/hi.bashrc
            "
  else
    echo "No such directory: $hi_root/.hi.d" >&2
    return 1
  fi
}

function run() {
  copy_start_time=$(date +%s.%N)

  command -v openssl >/dev/null 2>&1 || {
    echo >&2 "hi requires openssl to be installed on $(hostname), but it is not. Aborting."
    exit 1
  }

  tmp="/tmp/$(date +%s).hi"

  hi_parse "$@"
  say_hi "$@" 2>"$tmp"

  local _exit_code="$?"
  local _errors
  _errors="$(cat "$tmp")"

  rm "$tmp"

  if [ "$_exit_code" -ne 0 ]; then
    echo -ne "\r\r\r\r"
    if [[ "$_errors" == *"Could not resolve hostname"* ]] \
      || [[ "$_errors" == *"Broken pipe"* ]] \
      || [[ "$_errors" == *"no such identity"* ]] \
      || [[ "$_errors" == *"Permission denied"* ]]; then
      echo -e "| hi: ${_errors#*ssh: }"
    else
      echo -e "\033[01;31m=======================================\033[00;0m"
      echo -e "\033[01;33mhi failed [code: $_exit_code], falling back to ssh...\033[00;0m"
      echo -e "\033[01;33m[$_errors]\033[00;0m"
      echo -e "\033[01;31m=======================================\033[00;0m\n"
      ssh "$@"
      exit 1
    fi
  fi
  exit "$_exit_code"
}

run "$@"
