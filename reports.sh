#!/bin/bash

if command -v "cloc" &>/dev/null; then
  cloc . > ./reports/cloc.txt
else
  echo "cloc is not installed"
fi

shellcheck -a -x $(find . -type f -name "*.sh") > ./reports/shellcheck.txt
