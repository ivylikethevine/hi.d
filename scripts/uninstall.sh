#!/bin/bash
# Reverses scripts/install.sh: strips hi's marker-tagged lines from the local
# shell rc files and removes the /usr/bin/hi symlink if it points at this
# hi.d. Leaves the hi.d checkout itself in place - delete that yourself
# (rm -rf it) once you're done with it.
set -euo pipefail

_HI_DIR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
  --dir)
    [ $# -ge 2 ] || {
      echo "uninstall.sh: --dir requires a path" >&2
      exit 1
    }
    _HI_DIR_ARG="$2"
    shift 2
    ;;
  --dir=*)
    _HI_DIR_ARG="${1#--dir=}"
    shift
    ;;
  -h | --help)
    cat <<'EOF'
Usage: uninstall.sh [--dir <install-dir>]

Strips hi's lines back out of ~/.bashrc, ~/.zshrc and
~/.config/fish/config.fish, and removes /usr/bin/hi if it points at this
hi.d. Safe to re-run any time. hi.d itself is left in place - remove it
yourself (rm -rf) once you're done with it.

  --dir <path>  State explicitly which install this is undoing instead of
                auto-detecting it from where this script lives.
EOF
    exit 0
    ;;
  *)
    echo "uninstall.sh: unrecognized argument: $1" >&2
    echo "Usage: uninstall.sh [--dir <install-dir>]" >&2
    exit 1
    ;;
  esac
done

# Locate hi.d relative to this script (resolving symlinks) - same as install.sh
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"
  _HI_SELF="$(readlink "$_HI_SELF")"
  [[ $_HI_SELF == /* ]] || _HI_SELF="$_HI_SELF_DIR/$_HI_SELF"
done
_HI_AUTO_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"

if [ -n "$_HI_DIR_ARG" ]; then
  _HI_HOME="$(cd -P "$_HI_DIR_ARG" && pwd)"
  if [ "$_HI_HOME" != "$_HI_AUTO_HOME" ]; then
    echo "uninstall.sh: --dir $_HI_DIR_ARG doesn't match where hi.d is actually checked out ($_HI_AUTO_HOME/hi.d)." >&2
    exit 1
  fi
else
  _HI_HOME="$_HI_AUTO_HOME"
fi
export _HI_HOME

# shellcheck source=../common/bootstrap.sh
source "$_HI_HOME/hi.d/common/bootstrap.sh"

# $_HI_MARKER and $_HI_LINK come from common/paths.sh, and strip_marker from
# common/rcfile.sh alongside the config_shell it is the inverse of - this file
# used to define all three itself, so recognising what install.sh wrote
# depended on two copies of a string staying identical.
# shellcheck source=../common/rcfile.sh
source "$_HI_ROOT/common/rcfile.sh"

# The other half of being install's inverse: drop the settings file it wrote.
function strip_settings() {
  _hi_h2 "Checking settings"
  if [ -f "$_HI_SETTINGS" ]; then
    rm -f "$_HI_SETTINGS"
    _hi_cecho " removed ${_HI_SETTINGS#"$_HI_ROOT/"} :)" "$GREEN"
  else
    _hi_cecho " no ${_HI_SETTINGS#"$_HI_ROOT/"} to remove :)" "$GREEN"
  fi
}

function unlink_hi() {
  _hi_h2 "Checking hi.sh"
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" != "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK doesn't point at this hi.d, leaving it alone" "$GREEN"
    return 0
  fi
  _hi_cecho " Unlinking $_HI_LINK... [password required]" "$BLUE"
  sudo rm -f "$_HI_LINK"
}

# lets tests/scripts/uninstall_test.sh `source` this file to reach strip_marker/
# unlink_hi without running the real uninstall below - unlink_hi's sudo call
# in particular has no business firing from a test
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

_hi_h1 "Uninstalling hi.sh!"
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT" "$BLUE"

strip_marker bashrc "$_HI_HOME_BASHRC"
strip_marker zshrc "$_HI_HOME_ZSHRC"
strip_marker config.fish "$_HI_HOME_FISH_CONFIG"

strip_settings

unlink_hi

_hi_h1 "Uninstalled!"
_hi_cecho " | hi.d itself is still at $_HI_ROOT - rm -rf it yourself if you're done with it" "$BLUE"
