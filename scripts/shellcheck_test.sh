#!/bin/bash
# Runs shellcheck over every *.sh file in the repo (zsh/fish configs are
# skipped - shellcheck doesn't support their syntax) and reports the total.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

if ! command -v shellcheck >/dev/null 2>&1; then
  _hi_cecho "shellcheck is not installed" "$RED"
  exit 1
fi


mapfile -t _HI_SH_FILES < <(find "$_HI_ROOT" -name '*.sh' -not -path '*/.git/*' | sort)

_hi_h1 "Running shellcheck on ${#_HI_SH_FILES[@]} files"
_hi_h2 "shellcheck version: $(shellcheck --version | awk '/^version:/ {print $2}')"

_hi_cecho "$(printf ' | %s\n' "${_HI_SH_FILES[@]}")" "$YELLOW"

if shellcheck -x -Calways -S style "${_HI_SH_FILES[@]}"; then
  _hi_h1 "shellcheck found no issues"
else
  _hi_h1 "shellcheck found issues"
  exit 1
fi
