#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
sshrc_exclude="--exclude .git --exclude .gitignore --exclude README.md \
  --exclude stubs --exclude reports --exclude scripts \
  --exclude *.pem --exclude *.pub --exclude *.rsa --exclude *.key"
start=$(date +%s.%N)

# shellcheck disable=SC2086
# shellcheck disable=SC2046
# shellcheck disable=SC2027
# shellcheck disable=SC1078
# shellcheck disable=SC1079
function hi() {
  local SSHHOME=${SSHHOME:=~}

  echo -ne "\r $(du -sh $sshrc_exclude --apparent-size ~/.sshrc.d | awk '{ print $1 }') "
  if [ -d "$SSHHOME"/.sshrc.d ]; then
    local files=".sshrc.d"
    local SIZE=0
    SIZE=$(tar cfz - -h -C "$SSHHOME" $sshrc_exclude $files | wc -c)
    if [ "$SIZE" -gt 65536 ]; then
      echo >&2 $'.sshrc.d and .sshrc files must be less than 64kb\ncurrent size: '"$SIZE"' bytes'
      exit 1
    fi
    local DIVIDER="$"
    if [ "$SHELL" = "/usr/bin/fish" ]; then
      DIVIDER=""
    fi
    local TR_COMMAND="tr -s ' ' $DIVIDER'\n'"
    local OPENSSL_COMMAND="openssl enc -base64"
    ssh -t "$DOMAIN" "$SSHARGS" "
            command -v openssl >/dev/null 2>&1 || { echo >&2 \"sshrc requires openssl to be installed on the server, but it's not. Aborting.\"; exit 1; }
            export SSHHOME=\$(mktemp -d -t .$(whoami).sshrc.XXXX)
            export SSHRCCLEANUP=\$SSHHOME
            trap \"rm -rf \$SSHRCCLEANUP; exit\" exit
            echo $DIVIDER'"$(cat "$0" | $OPENSSL_COMMAND)"' | $TR_COMMAND | $OPENSSL_COMMAND -d > \$SSHHOME/sshrc
            chmod +x \$SSHHOME/sshrc

            echo $DIVIDER'"$(
      cat <<'EOF' | $OPENSSL_COMMAND
                if [ -r /etc/profile ]; then source /etc/profile; fi
                if [ -r ~/.bash_profile ]; then source ~/.bash_profile
                elif [ -r ~/.bash_login ]; then source ~/.bash_login
                elif [ -r ~/.profile ]; then source ~/.profile
                fi
                export PATH=$PATH:$SSHHOME
                source $SSHHOME/.sshrc.d/load.sh;
EOF
    )"' | $TR_COMMAND | $OPENSSL_COMMAND -d > \$SSHHOME/sshrc.bashrc

            echo $DIVIDER'"$(
      cat <<'EOF' | $OPENSSL_COMMAND
#!/usr/bin/env bash
                exec bash --rcfile <(echo '
                [ -r /etc/profile ] && source /etc/profile
                if [ -r ~/.bash_profile ]; then source ~/.bash_profile
                elif [ -r ~/.bash_login ]; then source ~/.bash_login
                elif [ -r ~/.profile ]; then source ~/.profile
                fi
                source '$SSHHOME'/.sshrc.d/load.sh;
                export PATH=$PATH:'$SSHHOME'
                ') "$@"
EOF
    )"' | $TR_COMMAND | $OPENSSL_COMMAND -d > \$SSHHOME/bashsshrc
            chmod +x \$SSHHOME/bashsshrc
            echo $DIVIDER'"$(tar czf - -h -C "$SSHHOME" $sshrc_exclude $files | $OPENSSL_COMMAND)"' | $TR_COMMAND | $OPENSSL_COMMAND -d | tar mxzf - -C \$SSHHOME
            export SSHHOME=\$SSHHOME
            echo \"$CMDARG\" >> \$SSHHOME/sshrc.bashrc
            echo \"copy_time='$(echo "$(date +%s.%N) $start" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$SSHHOME/.sshrc.d/load.sh
            echo \"sshrc_exclude='$sshrc_exclude'\" >> \$SSHHOME/.sshrc.d/load.sh
            bash --rcfile \$SSHHOME/sshrc.bashrc
            "
  else
    echo "No such file: $SSHHOME/.sshrc" >&2
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

command -v openssl >/dev/null 2>&1 || {
  echo >&2 "hi requires openssl to be installed locally, but it's not. Aborting."
  exit 1
}

# TODO: Better handle various ssh errors
# # identify broken pipe/timeout
# # better resolve failed ssh hosts
hi_parse "$@"
if ! hi "$@"; then
  echo -e "\n\033[01;31m=======================================\033[00;0m"
  echo -e "\033[01;33mhi failed, falling back to sh + ssh...\033[00;0m"
  echo -e "\033[01;31m=======================================\033[00;0m\n"
  ssh "$@"
fi
