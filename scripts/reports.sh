#!/bin/bash

if command -v "cloc" &>/dev/null; then
  if [ ! -d /home/"$USER"/.hi.d/reports ]; then
    mkdir /home/"$USER"/.hi.d/reports
  fi
  cloc . >/home/"$USER"/.hi.d/reports/cloc.log
else
  echo "cloc is not installed"
fi

#  shellcheck disable=SC2046
shellcheck -a -x $(find . -type f -name "*.sh") > ./reports/shellcheck.log
