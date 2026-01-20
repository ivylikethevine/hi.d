#!/bin/bash

if command -v "cloc" &>/dev/null; then
  if [ ! -d /home/"$USER"/.sshrc.d/reports ]; then
    mkdir /home/"$USER"/.sshrc.d/reports
  fi
  cloc . >/home/"$USER"/.sshrc.d/reports/cloc.txt
else
  echo "cloc is not installed"
fi

 find . -type f -name '*.sh' -exec shellcheck -a -x {} \; >/home/"$USER"/.sshrc.d/reports/shellcheck.txt
