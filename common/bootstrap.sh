#!/bin/bash
# shared entry point for scripts
: "${_HI_HOME:=$HOME}"
export _HI_HOME
# shellcheck source=./paths.sh
source "$_HI_HOME/hi.d/common/paths.sh"
# shellcheck source=./shared.sh
command -v _hi_cecho >/dev/null || source "$_HI_SHARED"
