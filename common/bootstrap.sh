#!/bin/bash
# shared entry point for every bash/zsh consumer: locate hi.d and load
# paths.sh + colors.sh. Sourcing this twice in one process is a no-op, so
# scripts that source each other can each require it. Callers use:
#   source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"
# fish sources common/paths.sh directly instead.
: "${_HI_TMPDIR:=$HOME}"
export _HI_TMPDIR
# shellcheck source=./paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"
