#!/bin/bash

if command -v "cloc" &>/dev/null; then
  if [ ! -d ../reports ]; then
    mkdir ../reports
  fi
  cloc . >../reports/cloc.txt
else
  echo "cloc is not installed"
fi

 find . -type f -name '*.sh' -exec shellcheck -a -x {} \; >../reports/shellcheck.txt
