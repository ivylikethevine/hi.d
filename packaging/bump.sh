#!/bin/bash
# Sets the release version across every manifest, with real checksums, so that
# cutting a release is one command rather than four hand-edits that can
# disagree. The version of record is packaging/aur/hi.d/PKGBUILD's pkgver -
# packaging/package.sh reads it back from there.
#
# Two modes:
#   bump.sh <version>            rewrite the manifests (downloads the tarball)
#   bump.sh --check <version>    verify they already say <version>, offline
#
# --check is what CI runs on a tag: the release workflow refuses to build if the
# committed manifests and the tag disagree, rather than quietly rewriting files
# nobody reviewed.
set -euo pipefail

_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"
  _HI_SELF="$(readlink "$_HI_SELF")"
  [[ $_HI_SELF == /* ]] || _HI_SELF="$_HI_SELF_DIR/$_HI_SELF"
done
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"
export _HI_HOME

# shellcheck source=../common/core.sh
source "$_HI_HOME/hi.d/common/core.sh"

# Overridable so the test suite can point them at fixture copies; everything
# real goes through the defaults.
: "${_HI_PKGBUILD:=$_HI_ROOT/packaging/aur/hi.d/PKGBUILD}"
: "${_HI_SRCINFO:=$_HI_ROOT/packaging/aur/hi.d/.SRCINFO}"
: "${_HI_FORMULA:=$_HI_ROOT/packaging/homebrew/hi.d.rb}"
_HI_URL_BASE="https://github.com/ivylikethevine/hi.d/archive"
# what a manifest reads before any release has been cut; --check rejects both
_HI_PLACEHOLDER_SHA="0000000000000000000000000000000000000000000000000000000000000000"
_HI_USAGE="Usage: bump.sh [--check] <version>"

# sha256 and blake2b of $1, each with a non-coreutils fallback so this also runs
# on a mac (no sha256sum, no b2sum) rather than only on the Linux CI box.
function sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

function b2_of() {
  if command -v b2sum >/dev/null 2>&1; then
    b2sum "$1" | awk '{ print $1 }'
  else
    # BLAKE2b-512 is exactly what makepkg's b2sums holds
    openssl dgst -blake2b512 "$1" | awk '{ print $NF }'
  fi
}

# Rewrite one line in place. A temp file rather than `sed -i` (whose in-place
# flag differs BSD/GNU), written back with cat, not mv - mv would put mktemp's
# 0600 on a tracked manifest.
function rewrite() {
  local file="$1" expr="$2" tmp
  tmp="$(mktemp -t hi.bump.XXXXXX)"
  sed "$expr" "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

function check_manifests() {
  local bad=0 pkgver sha b2 srcinfo_b2
  _hi_h2 "Checking the manifests say $_HI_VERSION"

  pkgver="$(sed -n 's/^pkgver=//p' "$_HI_PKGBUILD" | head -1)"
  if [ "$pkgver" = "$_HI_VERSION" ]; then
    _hi_cecho " PKGBUILD pkgver=$pkgver :)" "$GREEN"
  else
    _hi_cecho " PKGBUILD pkgver=$pkgver, expected $_HI_VERSION" "$RED"
    bad=1
  fi

  b2="$(sed -n "s/^b2sums=('\\(.*\\)')/\\1/p" "$_HI_PKGBUILD" | head -1)"
  if [ "$b2" = SKIP ] || [ -z "$b2" ]; then
    _hi_cecho " PKGBUILD b2sums is still SKIP - run bump.sh $_HI_VERSION" "$RED"
    bad=1
  else
    _hi_cecho " PKGBUILD b2sums is a real sum :)" "$GREEN"
  fi

  if grep -qF "v$_HI_VERSION.tar.gz" "$_HI_FORMULA"; then
    _hi_cecho " formula url points at v$_HI_VERSION :)" "$GREEN"
  else
    _hi_cecho " formula url does not point at v$_HI_VERSION" "$RED"
    bad=1
  fi

  sha="$(sed -n 's/^  sha256 "\(.*\)"/\1/p' "$_HI_FORMULA" | head -1)"
  if [ "$sha" = "$_HI_PLACEHOLDER_SHA" ] || [ -z "$sha" ]; then
    _hi_cecho " formula sha256 is still the placeholder - run bump.sh $_HI_VERSION" "$RED"
    bad=1
  else
    _hi_cecho " formula sha256 is a real sum :)" "$GREEN"
  fi

  if grep -qF "pkgver = $_HI_VERSION" "$_HI_SRCINFO"; then
    _hi_cecho " .SRCINFO pkgver=$_HI_VERSION :)" "$GREEN"
  else
    _hi_cecho " .SRCINFO is stale - regenerate with makepkg --printsrcinfo" "$RED"
    bad=1
  fi

  # the AUR consumes .SRCINFO, not the PKGBUILD, so its b2sums/source lines
  # have to be checked too - pkgver alone lets a stale checksum through
  srcinfo_b2="$(sed -n 's/^[[:space:]]*b2sums = //p' "$_HI_SRCINFO" | head -1)"
  if [ -n "$b2" ] && [ "$srcinfo_b2" = "$b2" ]; then
    _hi_cecho " .SRCINFO b2sums matches the PKGBUILD's :)" "$GREEN"
  else
    _hi_cecho " .SRCINFO b2sums does not match the PKGBUILD's - regenerate it" "$RED"
    bad=1
  fi

  if grep -qF "v$_HI_VERSION.tar.gz" "$_HI_SRCINFO"; then
    _hi_cecho " .SRCINFO source points at v$_HI_VERSION :)" "$GREEN"
  else
    _hi_cecho " .SRCINFO source does not point at v$_HI_VERSION" "$RED"
    bad=1
  fi

  return "$bad"
}

function write_manifests() {
  local url tarball sha b2
  # _HI_BUMP_TARBALL: checksum this local file instead of downloading - the
  # test suite's offline path, and an escape hatch when GitHub is unreachable
  if [ -n "${_HI_BUMP_TARBALL:-}" ]; then
    tarball="$_HI_BUMP_TARBALL"
    _hi_h2 "Using the local tarball $tarball"
    [ -f "$tarball" ] || {
      _hi_cecho " no such file: $tarball" "$RED" >&2
      return 1
    }
  else
    url="$_HI_URL_BASE/v$_HI_VERSION.tar.gz"
    tarball="$(mktemp -t hi.tarball.XXXXXX)"
    _hi_on_exit "rm -f '$tarball'"

    _hi_h2 "Fetching $url"
    curl -fsSL -o "$tarball" "$url" || {
      _hi_cecho " could not fetch it - has v$_HI_VERSION been tagged and pushed?" "$RED" >&2
      return 1
    }
  fi
  # both sums from the same bytes, so the two channels can never disagree about
  # what they are checksumming
  sha="$(sha256_of "$tarball")"
  b2="$(b2_of "$tarball")"
  _hi_cecho " sha256 $sha" "$BLUE"
  _hi_cecho " b2     $b2" "$BLUE"

  _hi_h2 "Writing the manifests"
  rewrite "$_HI_PKGBUILD" "s/^pkgver=.*/pkgver=$_HI_VERSION/"
  rewrite "$_HI_PKGBUILD" "s/^b2sums=.*/b2sums=('$b2')/"
  _hi_cecho " $_HI_PKGBUILD :)" "$GREEN"

  rewrite "$_HI_FORMULA" "s|^  url \".*\"|  url \"$_HI_URL_BASE/refs/tags/v$_HI_VERSION.tar.gz\"|"
  rewrite "$_HI_FORMULA" "s/^  sha256 \".*\"/  sha256 \"$sha\"/"
  _hi_cecho " $_HI_FORMULA :)" "$GREEN"

  if command -v makepkg >/dev/null 2>&1; then
    (cd "$(dirname "$_HI_PKGBUILD")" && makepkg --printsrcinfo >.SRCINFO)
    _hi_cecho " $_HI_SRCINFO :)" "$GREEN"
  else
    rewrite_srcinfo_lines "$b2"
    _hi_cecho " $_HI_SRCINFO (pkgver/source/b2sums only - rerun makepkg --printsrcinfo on an Arch box if any other PKGBUILD field changed)" "$YELLOW"
  fi
}

# The no-makepkg fallback (any non-Arch box, incl. the ubuntu release runner):
# the three lines a bump changes are derivable, so rewrite them in place. The
# \([[:space:]]*\) capture keeps .SRCINFO's leading tab.
function rewrite_srcinfo_lines() {
  local b2="$1"
  rewrite "$_HI_SRCINFO" "s/^\\([[:space:]]*\\)pkgver = .*/\\1pkgver = $_HI_VERSION/"
  rewrite "$_HI_SRCINFO" "s|^\\([[:space:]]*\\)source = .*|\\1source = hi.d-$_HI_VERSION.tar.gz::$_HI_URL_BASE/v$_HI_VERSION.tar.gz|"
  rewrite "$_HI_SRCINFO" "s/^\\([[:space:]]*\\)b2sums = .*/\\1b2sums = $b2/"
}

# sourcing stops here (tests reach the functions above) - install.sh's pattern
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

_HI_CHECK_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
  --check) _HI_CHECK_ONLY=1 ;;
  -h | --help)
    cat <<EOF
$_HI_USAGE

Writes <version> (no leading v) into packaging/aur/hi.d/PKGBUILD, its
.SRCINFO, and packaging/homebrew/hi.d.rb, along with the b2sum and sha256
of the matching GitHub release tarball.

  --check   Verify the manifests already agree on <version> and carry real
            checksums, then exit non-zero if not. Touches nothing and needs
            no network. This is the release workflow's gate.

packaging/aur/hi.d-git/ is untouched: its pkgver() derives from the branch.
EOF
    exit 0
    ;;
  -*)
    echo "bump.sh: unrecognized argument: $1" >&2
    echo "$_HI_USAGE" >&2
    exit 1
    ;;
  *) _HI_VERSION="$1" ;;
  esac
  shift
done

[ -n "${_HI_VERSION:-}" ] || {
  echo "bump.sh: a version is required" >&2
  echo "$_HI_USAGE" >&2
  exit 1
}
# v-prefixes belong on the tag, not in pkgver/sha256 lookups; accept either
_HI_VERSION="${_HI_VERSION#v}"

if [ -n "$_HI_CHECK_ONLY" ]; then
  _hi_h1 "Checking manifests for $_HI_VERSION"
  if check_manifests; then
    _hi_h1 "Manifests agree!"
    exit 0
  fi
  _hi_h1 "Manifests disagree" "$RED"
  exit 1
fi

_hi_h1 "Bumping hi.d to $_HI_VERSION"
write_manifests
_hi_h1 "Bumped!"
_hi_cecho " | review the diff, commit it - the release workflow re-derives and verifies the same sums from the tag" "$BLUE"
