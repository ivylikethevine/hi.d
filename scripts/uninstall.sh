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

_HI_MARKER="# added by hi during install"
_HI_LINK="/usr/bin/hi"

# Remove every line tagged with $_HI_MARKER from $target, leaving everything
# else untouched. Mirrors config_shell in install.sh, just with an empty
# desired block.
function strip_marker() {
  local name="$1" target="$2" tmpfile
  _hi_h2 "Checking $name"

  if [ ! -f "$target" ] || ! grep -qF "$_HI_MARKER" "$target"; then
    _hi_cecho " local $name has no hi lines :)" "$GREEN"
    return 0
  fi

  tmpfile="$(mktemp -t hi.uninstall.XXXXXX)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  mv "$tmpfile" "$target"
  _hi_cecho " local $name cleaned :)" "$GREEN"
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

unlink_hi

_hi_h1 "Uninstalled!"
_hi_cecho " | hi.d itself is still at $_HI_ROOT - rm -rf it yourself if you're done with it" "$BLUE"
