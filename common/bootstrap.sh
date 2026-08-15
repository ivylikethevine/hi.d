#!/bin/bash
# shared entry point for scripts
# `: "${X:=default}"` assigns only when X is unset, so a value an outer layer
# already exported (hi.sh on the client, load.sh on the target) survives
: "${_HI_HOME:=$HOME}"
export _HI_HOME
: "${_HI_DISABLE_LOCAL:=0}"
export _HI_DISABLE_LOCAL
: "${_HI_REMOTE_SESSION:=0}"
export _HI_REMOTE_SESSION
# The six feature toggles, defaulted so reading one is never an error.
# shells/aliases.sh and shells/config.fish read them bare - they can't use
# ${X:-0}, since fish has no such expansion and sources both - so an unset
# toggle is fatal under `set -u`. (That is what broke `hi <target> <command>`
# until hi.sh's bootloader stopped leaving strict mode on.)
# Defaulted, never assigned: $_HI_SETTINGS is sourced next and paths.sh's
# local-only gate right after, and both still have to be able to win.
: "${_HI_DISABLE_HEADER:=0}"
: "${_HI_DISABLE_PROMPT:=0}"
: "${_HI_DISABLE_PERSONAL:=0}"
: "${_HI_DISABLE_GIT_STATUS:=0}"
: "${_HI_DISABLE_EDITORS:=0}"
: "${_HI_DISABLE_ALIASES:=0}"
export _HI_DISABLE_HEADER _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL
export _HI_DISABLE_GIT_STATUS _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES
# where the user's config overlay lives. paths.sh resolves settings/colors/
# packages against it but can't derive it (fish has no ${X:-y}), so every entry
# point sets it; `:=` leaves an outer layer's value alone the way $_HI_HOME above
# is left alone, which is what lets hi.sh point a target at its own copy.
: "${_HI_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/hi.d}"
export _HI_CONFIG_DIR
# the settings scripts/install.sh writes, ahead of paths.sh because its
# local-only gate reads them (see the note by that gate). $_HI_SETTINGS isn't
# defined yet - it comes *from* paths.sh - so both candidates are spelled out
# here, overlay first, exactly as paths.sh will resolve them a moment later.
# shellcheck source=../misc/settings.sh disable=SC1091 # gitignored, may not exist
if [ -f "$_HI_CONFIG_DIR/settings.sh" ]; then
  . "$_HI_CONFIG_DIR/settings.sh"
elif [ -f "$_HI_HOME/hi.d/misc/settings.sh" ]; then
  . "$_HI_HOME/hi.d/misc/settings.sh"
fi
# shellcheck source=./paths.sh
source "$_HI_HOME/hi.d/common/paths.sh"
# Not exported: it tells shared.sh the preamble above already ran, so it can
# skip re-sourcing settings.sh and paths.sh. A child process (fish's
# `bash -c "source $_HI_SHARED"`) doesn't inherit it and so still runs them.
_hi_bootstrapped=1
# shellcheck source=./shared.sh
command -v _hi_cecho >/dev/null || source "$_HI_SHARED"
