#!/bin/bash
sshrc_exclude="--exclude .git --exclude .gitignore \
  --exclude README.md --exclude hi.sh --exclude install.sh \
  --exclude stubs --exclude reports.sh --exclude reports \
  --exclude tests \
  --exclude *.pem --exclude *.pub --exclude *.rsa --exclude *.key"
start=$(date +%s.%N)

# ignore warnings about quotes - shellcheck is confused because of the horrors below but fixing it breaks the functionality so :(

function sshrc() {
  local SSHHOME=${SSHHOME:=~}

  echo -ne "\r $(du -sh $sshrc_exclude --apparent-size ~/.sshrc.d | awk '{ print $1 }') "
  if [ -f "$SSHHOME"/.sshrc ]; then
    local files=.sshrc
    if [ -d "$SSHHOME"/.sshrc.d ]; then
      files="$files .sshrc.d"
    fi
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
                source $SSHHOME/.sshrc;
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
                source '$SSHHOME'/.sshrc;
                export PATH=$PATH:'$SSHHOME'
                ') "$@"
EOF
    )"' | $TR_COMMAND | $OPENSSL_COMMAND -d > \$SSHHOME/bashsshrc
            chmod +x \$SSHHOME/bashsshrc
            echo $DIVIDER'"$(tar czf - -h -C "$SSHHOME" $sshrc_exclude $files | $OPENSSL_COMMAND)"' | $TR_COMMAND | $OPENSSL_COMMAND -d | tar mxzf - -C \$SSHHOME
            export SSHHOME=\$SSHHOME
            echo \"$CMDARG\" >> \$SSHHOME/sshrc.bashrc
            echo \"copy_time () { echo \"copy: $(echo "$(date +%s.%N) $start" | awk '{ printf "%.3f\n", $1 - $2 }')s\"; } \" >> \$SSHHOME/.sshrc.d/load.sh
            echo \"sshrc_exclude='$sshrc_exclude'\" >> \$SSHHOME/.sshrc.d/load.sh
            bash --rcfile \$SSHHOME/sshrc.bashrc
            "
  else
    echo "No such file: $SSHHOME/.sshrc" >&2
    exit 1
  fi
}

function sshrc_parse() {
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
  echo >&2 "sshrc requires openssl to be installed locally, but it's not. Aborting."
  exit 1
}

sshrc_parse "$@"

if ! sshrc "$@"; then
  echo -e "\n\033[01;31m=======================================\033[00;0m"
  echo -e "\033[01;33msshrc failed, falling back to sh + ssh...\033[00;0m"
  echo -e "\033[01;31m=======================================\033[00;0m\n"
  # aliases=$(sed '/# end sh-compatible aliases/Q' ~/.sshrc.d/aliases.sh | tr '\n' '; ' | tr ';' ';;')
  # copy to .profile? .shrc?
  # ssh -t "$DOMAIN" $SSHARGS "sh -i <<<'$aliases'"
  ssh "$@"
fi
