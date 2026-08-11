#!/bin/bash
# shared entry point for scripts
# `: "${X:=default}"` assigns only when X is unset, so a value an outer layer
# already exported (hi.sh on the client, load.sh on the target) survives being
# sourced through again - a plain `X=default` would clobber it.
: "${_HI_HOME:=$HOME}"
export _HI_HOME
: "${_HI_DISABLE_LOCAL:=0}"
export _HI_DISABLE_LOCAL
: "${_HI_REMOTE_SESSION:=0}"
export _HI_REMOTE_SESSION
# shellcheck source=./paths.sh
source "$_HI_HOME/hi.d/common/paths.sh"
# shellcheck source=./shared.sh
command -v _hi_cecho >/dev/null || source "$_HI_SHARED"
