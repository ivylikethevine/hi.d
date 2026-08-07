#!/bin/bash
# shared entry point for scripts
: "${_HI_TMPDIR:=$HOME}"
export _HI_TMPDIR
# shellcheck source=./paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"
