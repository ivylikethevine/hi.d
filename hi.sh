#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
hi_exclude="--exclude .git --exclude .gitignore --exclude README.md --exclude stubs --exclude reports --exclude scripts"
start=$(date +%s.%N)

command -v openssl >/dev/null 2>&1 || {
  echo >&2 "hi requires openssl to be installed on $(hostname), but it's not. Aborting."
  exit 1
}

# shellcheck disable=SC2086
# shellcheck disable=SC2046
# shellcheck disable=SC2027
# shellcheck disable=SC1078
# shellcheck disable=SC1079
function hi() {
  local HI_HOME=${HI_HOME:=~}

  echo -ne "\r $(du -sh $hi_exclude --apparent-size ~/.hi.d | awk '{ print $1 }') "
  if [ -d "$HI_HOME"/.hi.d ]; then
    local files=".hi.d"
    local SIZE=0
    SIZE=$(tar cfz - -h -C "$HI_HOME" $hi_exclude $files | wc -c)
    if [ "$SIZE" -gt 65536 ]; then
      echo >&2 $'.hi.d files must be less than 64kb\ncurrent size: '"$SIZE"' bytes'
      exit 1
    fi
    local DIVIDER
    if [ "$SHELL" = "/usr/bin/fish" ] || [ -z "$FISH_VERSION" ]; then
      DIVIDER=""
    else
      DIVIDER="$"
    fi
    local TR_COMMAND="tr -s ' ' $DIVIDER'\n'"
    local OPENSSL_COMMAND="openssl enc -base64"
    ssh -t "$DOMAIN" "$SSHARGS" "
            command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on $DOMAIN, but it's not. Aborting.\"; exit 1; }
            export HI_HOME=\$(mktemp -d -t .$(whoami).hi.XXXX)
            export HI_CLEANUP=\$HI_HOME
            trap \"rm -rf \$HI_CLEANUP; exit\" exit
            echo $DIVIDER'"$(cat "$0" | $OPENSSL_COMMAND)"' | $TR_COMMAND | $OPENSSL_COMMAND -d > \$HI_HOME/hi
            chmod +x \$HI_HOME/hi

            echo $DIVIDER'"$(
      cat <<'EOF' | $OPENSSL_COMMAND
                if [ -r /etc/profile ]; then source /etc/profile; fi
                if [ -r ~/.bash_profile ]; then source ~/.bash_profile
                elif [ -r ~/.bash_login ]; then source ~/.bash_login
                elif [ -r ~/.profile ]; then source ~/.profile
                fi
                export PATH=$PATH:$HI_HOME
                source $HI_HOME/.hi.d/load.sh;
EOF
    )"' | $TR_COMMAND | $OPENSSL_COMMAND -d > \$HI_HOME/hi.bashrc

            echo $DIVIDER'"$(
      cat <<'EOF' | $OPENSSL_COMMAND
#!/usr/bin/env bash
                exec bash --rcfile <(echo '
                [ -r /etc/profile ] && source /etc/profile
                if [ -r ~/.bash_profile ]; then source ~/.bash_profile
                elif [ -r ~/.bash_login ]; then source ~/.bash_login
                elif [ -r ~/.profile ]; then source ~/.profile
                fi
                source '$HI_HOME'/.hi.d/load.sh;
                export PATH=$PATH:'$HI_HOME'
                ') "$@"
EOF
    )"' | $TR_COMMAND | $OPENSSL_COMMAND -d > \$HI_HOME/bashhi
            chmod +x \$HI_HOME/bashhi
            echo $DIVIDER'"$(tar czf - -h -C "$HI_HOME" $hi_exclude $files | $OPENSSL_COMMAND)"' | $TR_COMMAND | $OPENSSL_COMMAND -d | tar mxzf - -C \$HI_HOME
            export HI_HOME=\$HI_HOME
            echo \"$CMDARG\" >> \$HI_HOME/hi.bashrc
            echo \"export copy_time='$(echo "$(date +%s.%N) $start" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$HI_HOME/.hi.d/load.sh
            echo \"hi_exclude='$hi_exclude'\" >> \$HI_HOME/.hi.d/load.sh
            echo \"load\" >> \$HI_HOME/.hi.d/load.sh
            bash --rcfile \$HI_HOME/hi.bashrc
            "
  else
    echo "No such file: $HI_HOME/.hi" >&2
    exit 1
  fi
}

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

run() {
  tmp="/tmp/$(date +%s).hi"
  touch "$tmp"
  hi_parse "$@"
  hi "$@" 2>"$tmp"
  hi_exit_code="$?"
  hi_errors="$(cat "$tmp")"
  rm "$tmp"
  if [ "$hi_exit_code" -ne 0 ]; then
    echo -ne "\r\r\r\r | "
    if [[ "$hi_errors" == *"Could not resolve hostname"* ]] \
      || [[ "$hi_errors" == *"Broken pipe"* ]] \
      || [[ "$hi_errors" == *"no such identity"* ]] \
      || [[ "$hi_errors" == *"Permission denied"* ]]; then
      echo -e "hi: ${hi_errors#*ssh: }"
    else
      echo -e "hi: $hi_errors"
      echo -e "\n\033[01;31m=======================================\033[00;0m"
      echo -e "\033[01;33mhi failed [code: $hi_exit_code], falling back to ssh...\033[00;0m"
      echo -e "\033[01;31m=======================================\033[00;0m\n"
      ssh "$@"
      exit 1
    fi
  fi
  exit "$hi_exit_code"
}

run "$@"
