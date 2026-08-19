#!/bin/bash
# Shared plumbing for packaging/'s entry points (bump.sh, mkpkg.sh): locate
# the tree, source core.sh, and hold the primitives each script used to carry
# its own copy of. scripts/install.sh keeps its own locator and _hi_write_back
# on purpose - it ships in packages *without* packaging/, so it cannot source
# this file; that boundary-forced copy is documented there.

# Locate hi.d relative to the script that sourced this file, resolving
# symlinks - BASH_SOURCE[1] is that script, and packaging/ is one level down
# from the tree root, so the home is its ../../.
_HI_SELF="${BASH_SOURCE[1]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"
  _HI_SELF="$(readlink "$_HI_SELF")"
  [[ $_HI_SELF == /* ]] || _HI_SELF="$_HI_SELF_DIR/$_HI_SELF"
done
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"
export _HI_HOME

# shellcheck source=../common/core.sh
source "$_HI_HOME/hi.d/common/core.sh"

# sha256 lines ("<sum>  <file>" per argument) and single-file sha256/blake2b,
# each with a non-coreutils fallback so these also run on a mac (no sha256sum,
# no b2sum) rather than only on the Linux CI box.
function sha256_lines() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$@"
  else
    shasum -a 256 -- "$@"
  fi
}

function sha256_of() {
  sha256_lines "$1" | awk '{ print $1 }'
}

function b2_of() {
  if command -v b2sum >/dev/null 2>&1; then
    b2sum "$1" | awk '{ print $1 }'
  else
    # BLAKE2b-512 is exactly what makepkg's b2sums holds
    openssl dgst -blake2b512 "$1" | awk '{ print $NF }'
  fi
}

# rewrite <file> <sed-expr>... - core.sh's _hi_rewrite under the name packaging/
# has always called it. The implementation moved there when load.sh's clean_all
# needed the same thing (it was reaching for `sed -i` and sniffing the userland
# to pick the flag); the reasons for the shape - a temp file, and cat rather
# than mv so the target keeps its mode - are written up beside it.
function rewrite() { _hi_rewrite "$@"; }

# The version of record lives in the versioned PKGBUILD (bump.sh writes it
# there); reading it back rather than keeping copies is what stops the
# channels disagreeing. Reads $1, defaulting to the caller's $_HI_PKGBUILD.
function pkgbuild_version() {
  local file="${1:-$_HI_PKGBUILD}" v
  v="$(sed -n 's/^pkgver=//p' "$file" | head -1)"
  [ -n "$v" ] || {
    _hi_cecho " no pkgver= in $file" "$RED" >&2
    return 1
  }
  printf '%s' "$v"
}
