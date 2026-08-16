#!/bin/bash
# Drift guards for packaging/. Every channel has to describe the same install,
# and three of them describe it in a language that cannot call scripts/
# install.sh - a PKGBUILD calls it, but nfpm reads YAML and a Homebrew formula
# is Ruby. So the facts get repeated, and repeated facts drift. These are the
# assertions that catch that, offline: no nfpm, no makepkg, no network.
#
# What is deliberately NOT here: building a real .deb or a real .pkg.tar.zst.
# That needs the toolchains and belongs in the verification runbook
# (packaging/README.md), not in the fast group.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

set -- # install.sh reads "$@" for its own args; make sure it sees none
# shellcheck source=../../scripts/install.sh
source "$_HI_INSTALL"

_HI_PKG_DIR="$_HI_ROOT/packaging"
_HI_NFPM="$_HI_PKG_DIR/nfpm/nfpm.yaml"
_HI_FORMULA="$_HI_PKG_DIR/homebrew/hi.d.rb"
_HI_PKGBUILD="$_HI_PKG_DIR/aur/hi.d/PKGBUILD"
_HI_PKGBUILD_GIT="$_HI_PKG_DIR/aur/hi.d-git/PKGBUILD"
_HI_RELEASE_WF="$_HI_ROOT/.github/workflows/release.yml"

# bump.sh's functions (sha256_of, b2_of, rewrite, write/check_manifests) -
# inert under its source guard, and its derived paths equal the ones above
# shellcheck source=../../packaging/bump.sh
source "$_HI_PKG_DIR/bump.sh"

# The staging root every packager builds from, laid down exactly the way
# packaging/package.sh lays it down. Prints the DESTDIR.
function stage_fixture() {
  local dest="$_HI_WORKDIR/stage"
  local _HI_PREFIX="/usr/share" DESTDIR="$dest"
  mkdir -p "$dest"
  install_tree >/dev/null
  printf '%s' "$dest"
}

# --- nfpm.yaml vs install_tree ------------------------------------------------

# Every `src:` in nfpm.yaml that reads out of dist/staging has to be something
# install_tree actually produced, or the package silently ships without it.
function test_nfpm_staging_sources_all_exist() {
  local dest src rel bad=0
  dest="$(stage_fixture)"
  while IFS= read -r src; do
    rel="${src#./dist/staging}"
    [ -e "$dest$rel" ] || {
      _hi_cecho "   missing from the staged tree: $rel" "$RED"
      bad=1
    }
  done < <(sed -n 's|^ *- src: \./dist/staging\(.*\)$|./dist/staging\1|p' "$_HI_NFPM")
  [ "$bad" -eq 0 ]
}

# ...and the manifest has to actually reference the staging root at all. A
# rename of dist/staging that updated package.sh but not nfpm.yaml would leave
# every assertion above vacuously true.
function test_nfpm_references_the_staging_root() {
  [ "$(grep -c 'src: \./dist/staging' "$_HI_NFPM")" -ge 2 ]
}

# the symlink nfpm declares must be the one install_tree makes, target and all
function test_nfpm_symlink_matches_install_tree() {
  local dest declared actual
  dest="$(stage_fixture)"
  declared="$(sed -n 's|^ *- src: \(/usr/share/hi.d/hi.sh\)$|\1|p' "$_HI_NFPM" | head -1)"
  actual="$(readlink "$dest/usr/bin/hi")"
  [ -n "$declared" ] && [ "$declared" = "$actual" ]
}

# no $DESTDIR may leak into a link target - it does not exist at runtime
function test_nfpm_symlink_target_is_absolute_and_unstaged() {
  ! grep -qE '^ *- src: \./dist/staging.*hi\.sh$' "$_HI_NFPM"
}

# --- the Homebrew formula vs _HI_PACKAGE_CONTENTS -----------------------------

# The formula cannot call install.sh (install_tree hardcodes /usr/bin and
# /etc/profile.d, neither of which exists in a brew prefix), so it repeats the
# content list in Ruby. This is the assertion that keeps the copy honest.
function test_formula_file_list_matches_package_contents() {
  local expected actual
  expected="$(printf '%s\n' "${_HI_PACKAGE_CONTENTS[@]}" | LC_ALL=C sort)"
  # The quoted strings in the (libexec/"hi.d").install call, which wraps over
  # several lines. Bounded by "the last line that does not end in a comma"
  # rather than by a blank line: the next statement is chmod 0755,
  # libexec/"hi.d/hi.sh", and swallowing that put a phantom entry in the list.
  # "hi.d" itself is the destination directory, not a content, so it is dropped.
  actual="$(awk '/\(libexec\/"hi\.d"\)\.install/ { inside = 1 }
                 inside { print; if (!/,[[:space:]]*$/) exit }' "$_HI_FORMULA" |
    grep -oE '"[^"]+"' | tr -d '"' | grep -v '^hi\.d$' | LC_ALL=C sort)"
  [ "$expected" = "$actual" ]
}

# the tree has to land in a directory called hi.d, or $_HI_HOME/hi.d misses it
function test_formula_installs_into_a_hi_d_directory() {
  grep -qF '(libexec/"hi.d").install' "$_HI_FORMULA"
}

# hi.sh never locates itself, so a bare symlink on PATH would resolve the tree
# against $HOME. The wrapper exporting _HI_HOME is load-bearing.
function test_formula_ships_a_wrapper_that_exports_hi_home() {
  # `bin/"hi"` has to be written, not symlinked, and what it writes has to set
  # _HI_HOME. Checked on code lines only - the comment above it in the formula
  # explains the choice by naming bin.install_symlink, and a bare grep for that
  # string reads its own documentation as a violation.
  grep -qF '(bin/"hi").write' "$_HI_FORMULA" &&
    grep -qF 'export _HI_HOME="#{libexec}"' "$_HI_FORMULA" &&
    ! grep -vE '^\s*#' "$_HI_FORMULA" | grep -qF 'bin.install_symlink'
}

# the caveats must not tell people to run an install that will fail on macOS
function test_formula_caveats_use_no_link() {
  grep -qF 'install.sh --no-link' "$_HI_FORMULA"
}

# --- the PKGBUILDs ------------------------------------------------------------
#
# The needles below are makepkg's variables ($pkgdir, $srcdir, $pkgver) quoted
# as literal text to grep a PKGBUILD for - expanding them here is exactly what
# must not happen.
# shellcheck disable=SC2016

# Both must drive install.sh rather than copying by hand: the artifact's starter
# PKGBUILD copied `common shells misc load.sh hi.sh` inline and had already
# drifted - it omits scripts/, without which a packaged install has no
# hi_install for its users to run.
function test_pkgbuilds_call_install_sh() {
  local f
  for f in "$_HI_PKGBUILD" "$_HI_PKGBUILD_GIT"; do
    grep -qF 'scripts/install.sh" --prefix /usr/share' "$f" || return 1
    grep -qF 'DESTDIR="$pkgdir"' "$f" || return 1
  done
}

# install.sh resolves $_HI_HOME as <checkout>/.. and then wants $_HI_HOME/hi.d,
# so each PKGBUILD has to arrange for a $srcdir/hi.d - by symlink in the
# versioned one, by the `hi.d::` source alias in the git one.
# shellcheck disable=SC2016 # makepkg's variables as literal text, see above
function test_pkgbuilds_give_install_sh_a_hi_d_named_checkout() {
  grep -qF 'ln -sfn "$srcdir/$pkgname-$pkgver" "$srcdir/hi.d"' "$_HI_PKGBUILD" &&
    grep -qF 'source=("hi.d::git+' "$_HI_PKGBUILD_GIT"
}

# a VCS package that does not conflict with the versioned one gets both installed
function test_git_pkgbuild_provides_and_conflicts() {
  grep -qF "provides=('hi.d')" "$_HI_PKGBUILD_GIT" &&
    grep -qF "conflicts=('hi.d')" "$_HI_PKGBUILD_GIT"
}

# --- versions agree across channels -------------------------------------------

function test_pkgbuild_and_formula_agree_on_the_version() {
  local pkgver
  pkgver="$(sed -n 's/^pkgver=//p' "$_HI_PKGBUILD" | head -1)"
  [ -n "$pkgver" ] && grep -qF "v$pkgver.tar.gz" "$_HI_FORMULA"
}

function test_srcinfo_agrees_with_its_pkgbuild() {
  local pkgver
  pkgver="$(sed -n 's/^pkgver=//p' "$_HI_PKGBUILD" | head -1)"
  grep -qF "pkgver = $pkgver" "$_HI_PKG_DIR/aur/hi.d/.SRCINFO"
}

# --- the release workflow -----------------------------------------------------

# The manual approval gate. `environment:` on the publishing job is what makes
# GitHub hold it for a reviewer; losing that line silently turns a tag push into
# an unattended publish, which is exactly the thing it exists to prevent.
function test_release_workflow_gates_publishing() {
  grep -qE '^ *environment: release' "$_HI_RELEASE_WF"
}

# ...and nothing outside that gated job may touch `gh release`
function test_only_the_gated_job_publishes() {
  local before
  # everything above the publish: job must be free of release uploads
  before="$(sed -n '1,/^  publish:/p' "$_HI_RELEASE_WF")"
  ! printf '%s' "$before" | grep -qE 'gh release (create|upload)'
}

function test_release_workflow_only_runs_on_tags() {
  grep -qE '^ *- "v\*"' "$_HI_RELEASE_WF" && ! grep -qE '^ *(branches|pull_request):' "$_HI_RELEASE_WF"
}

# bump.sh --check is the tag/manifest gate; the build must not skip it
function test_release_workflow_verifies_the_manifests() {
  grep -qF 'packaging/bump.sh --check' "$_HI_RELEASE_WF"
}

# --- the scripts themselves ---------------------------------------------------

# the version of record has to exist where package.sh reads it back from;
# the actual plumbing is covered by test_package_sh_version_flag_wins
function test_package_sh_reads_the_version_from_the_pkgbuild() {
  [ -n "$(sed -n 's/^pkgver=//p' "$_HI_PKGBUILD" | head -1)" ]
}

function test_bump_check_rejects_a_version_the_manifests_do_not_carry() {
  ! "$_HI_PKG_DIR/bump.sh" --check 999.999.999 >/dev/null 2>&1
}

# --- bump.sh's write path, offline --------------------------------------------
#
# Fixture manifests (in packaging/'s own layout) plus a local tarball stand in
# for the GitHub download; each case runs in a subshell so the fixture
# _HI_PKG_DIR can't leak into the drift guards above.

function bump_fixture() {
  local dir="$_HI_WORKDIR/bump"
  rm -rf "$dir"
  mkdir -p "$dir/aur/hi.d" "$dir/homebrew" "$dir/src"
  cp "$_HI_PKG_DIR/aur/hi.d/PKGBUILD" "$dir/aur/hi.d/PKGBUILD"
  cp "$_HI_PKG_DIR/aur/hi.d/.SRCINFO" "$dir/aur/hi.d/.SRCINFO"
  cp "$_HI_PKG_DIR/homebrew/hi.d.rb" "$dir/homebrew/hi.d.rb"
  printf 'hello\n' >"$dir/src/file"
  tar -czf "$dir/src.tar.gz" -C "$dir" src
}

# subshell preamble: re-source bump.sh with _HI_PKG_DIR at the fixture, so its
# derived paths follow; $_HI_TB is the stand-in tarball
function _hi_bump_env() {
  _HI_PKG_DIR="$_HI_WORKDIR/bump"
  _HI_TB="$_HI_WORKDIR/bump/src.tar.gz"
  _HI_VERSION=9.9.9
  # shellcheck source=../../packaging/bump.sh
  source "$_HI_ROOT/packaging/bump.sh"
}

# ...and with a completed write, which most cases start from
function _hi_bump_written() {
  _hi_bump_env
  write_manifests "$_HI_TB" >/dev/null 2>&1
}

function test_bump_write_rewrites_pkgver_and_b2sums() {
  bump_fixture
  (
    _hi_bump_written
    grep -q '^pkgver=9\.9\.9$' "$_HI_PKGBUILD" &&
      grep -qF "b2sums=('$(b2_of "$_HI_TB")')" "$_HI_PKGBUILD"
  )
}

function test_bump_write_rewrites_formula_url_and_sha256() {
  bump_fixture
  (
    _hi_bump_written
    grep -qF 'v9.9.9.tar.gz' "$_HI_FORMULA" &&
      grep -qF "sha256 \"$(sha256_of "$_HI_TB")\"" "$_HI_FORMULA"
  )
}

# the no-makepkg path (any non-Arch box, incl. the release runner) has to fix
# all three lines the AUR reads out of .SRCINFO, not just pkgver
function test_bump_srcinfo_fallback_rewrites_the_three_lines() {
  bump_fixture
  (
    _hi_bump_env
    rewrite_srcinfo_lines feedbeef
    grep -qF 'pkgver = 9.9.9' "$_HI_SRCINFO" &&
      grep -qF 'source = hi.d-9.9.9.tar.gz::' "$_HI_SRCINFO" &&
      grep -qF 'v9.9.9.tar.gz' "$_HI_SRCINFO" &&
      grep -qF 'b2sums = feedbeef' "$_HI_SRCINFO" &&
      grep -q $'^\tpkgver' "$_HI_SRCINFO" # the leading tab survived the sed
  )
}

function test_bump_check_passes_after_a_write() {
  bump_fixture
  (
    _hi_bump_written
    check_manifests >/dev/null 2>&1
  )
}

# corrupt one .SRCINFO line after a good write; --check has to catch it
function _hi_bump_check_rejects() {
  bump_fixture
  (
    _hi_bump_written
    rewrite "$_HI_SRCINFO" "$1"
    ! check_manifests >/dev/null 2>&1
  )
}

function test_bump_check_catches_stale_srcinfo_b2sums() {
  _hi_bump_check_rejects 's/^\([[:space:]]*\)b2sums = .*/\1b2sums = 1111/'
}

function test_bump_check_catches_stale_srcinfo_source() {
  _hi_bump_check_rejects 's|^\([[:space:]]*\)source = .*|\1source = hi.d-0.0.1.tar.gz::x/v0.0.1.tar.gz|'
}

# a wrong tool or wrong output field shows up as a wrong constant
function test_bump_sha256_matches_a_known_vector() {
  local f="$_HI_WORKDIR/vector"
  printf 'hello\n' >"$f"
  [ "$(sha256_of "$f")" = "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03" ]
}

# the two b2 implementations (coreutils b2sum, openssl fallback) must agree,
# or a bump on a mac writes a sum makepkg then rejects. Guarded on b2sum at
# the registration; openssl is a hard client requirement already.
function test_bump_b2_fallback_agrees_with_b2sum() {
  local f="$_HI_WORKDIR/vector2"
  printf 'hello\n' >"$f"
  [ "$(b2_of "$f")" = "$(openssl dgst -blake2b512 "$f" | awk '{ print $NF }')" ]
}

# mode read via ls's first field - stat's flags differ GNU/BSD
# shellcheck disable=SC2012 # the path is a fixture this suite just wrote
function test_bump_rewrite_preserves_file_mode() {
  local f="$_HI_WORKDIR/modefix" before
  printf 'pkgver=0\n' >"$f"
  chmod 604 "$f"
  before="$(ls -l "$f" | awk '{ print $1 }')"
  rewrite "$f" 's/^pkgver=.*/pkgver=1.2.3/'
  [ "$(ls -l "$f" | awk '{ print $1 }')" = "$before" ]
}

# --- package.sh, offline half ---------------------------------------------------

function test_package_sh_stage_only_needs_no_nfpm() {
  local out="$_HI_WORKDIR/pkgdist"
  "$_HI_PKG_DIR/package.sh" --stage-only --outdir "$out" >/dev/null 2>&1 &&
    [ -f "$out/staging/usr/share/hi.d/hi.sh" ]
}

function test_package_sh_version_flag_wins() {
  local out
  out="$("$_HI_PKG_DIR/package.sh" --version 7.7.7 --stage-only --outdir "$_HI_WORKDIR/pkgdist2" 2>&1)"
  [[ "$out" == *"Packaging hi.d 7.7.7"* ]]
}

function test_package_sh_rejects_unknown_arguments() {
  ! "$_HI_PKG_DIR/package.sh" --bogus >/dev/null 2>&1
}

# a checkout not named hi.d (CI paths, worktrees) gets the shim
function test_staged_launcher_shims_a_misnamed_checkout() {
  ln -sfn "$_HI_ROOT" "$_HI_WORKDIR/checkout"
  (
    set -- # package.sh reads "$@" when executed; make sure sourcing sees none
    # shellcheck source=../../packaging/package.sh
    source "$_HI_PKG_DIR/package.sh"
    _HI_ROOT="$_HI_WORKDIR/checkout"
    _HI_DIST="$_HI_WORKDIR/pkgdist3"
    out="$(staged_launcher)"
    [ "$out" = "$_HI_DIST/shim/hi.d/scripts/install.sh" ] && [ -x "$out" ]
  )
}

function test_release_workflow_uploads_sha256sums() {
  # package.sh writes it (the artifact list's single home); the workflow only
  # has to carry it as an artifact and attach it to the release
  grep -q 'SHA256SUMS' "$_HI_PKG_DIR/package.sh" &&
    [ "$(grep -c 'SHA256SUMS' "$_HI_RELEASE_WF")" -ge 2 ]
}

function run_packaging_tests() {
  _hi_workdir packagingtest

  _hi_h1 "Testing packaging/"

  _hi_suite_begin

  _hi_h2 "Testing: nfpm.yaml against install_tree"
  _hi_check "Every staged src exists" test_nfpm_staging_sources_all_exist
  _hi_check "References the staging root" test_nfpm_references_the_staging_root
  _hi_check "Symlink matches install_tree's" test_nfpm_symlink_matches_install_tree
  _hi_check "Link target carries no staging prefix" test_nfpm_symlink_target_is_absolute_and_unstaged

  _hi_h2 "Testing: the Homebrew formula"
  _hi_check "File list matches _HI_PACKAGE_CONTENTS" test_formula_file_list_matches_package_contents
  _hi_check "Installs into a hi.d/ directory" test_formula_installs_into_a_hi_d_directory
  _hi_check "Wrapper exports _HI_HOME" test_formula_ships_a_wrapper_that_exports_hi_home
  _hi_check "Caveats point at --no-link" test_formula_caveats_use_no_link

  _hi_h2 "Testing: the PKGBUILDs"
  _hi_check "Both call install.sh --prefix" test_pkgbuilds_call_install_sh
  _hi_check "Both give it a hi.d-named checkout" test_pkgbuilds_give_install_sh_a_hi_d_named_checkout
  _hi_check "hi.d-git provides/conflicts hi.d" test_git_pkgbuild_provides_and_conflicts

  _hi_h2 "Testing: versions agree"
  _hi_check "PKGBUILD and formula agree" test_pkgbuild_and_formula_agree_on_the_version
  _hi_check ".SRCINFO agrees with its PKGBUILD" test_srcinfo_agrees_with_its_pkgbuild

  _hi_h2 "Testing: release.yml"
  _hi_check "Publishing sits behind an environment" test_release_workflow_gates_publishing
  _hi_check "Only the gated job publishes" test_only_the_gated_job_publishes
  _hi_check "Runs on tags only" test_release_workflow_only_runs_on_tags
  _hi_check "Verifies the manifests against the tag" test_release_workflow_verifies_the_manifests

  _hi_h2 "Testing: package.sh / bump.sh"
  _hi_check "package.sh takes its version from the PKGBUILD" test_package_sh_reads_the_version_from_the_pkgbuild
  _hi_check "bump.sh --check rejects a mismatch" test_bump_check_rejects_a_version_the_manifests_do_not_carry

  _hi_h2 "Testing: bump.sh's write path (offline)"
  _hi_check "Rewrites pkgver and b2sums" test_bump_write_rewrites_pkgver_and_b2sums
  _hi_check "Rewrites formula url and sha256" test_bump_write_rewrites_formula_url_and_sha256
  _hi_check ".SRCINFO fallback rewrites all three lines" test_bump_srcinfo_fallback_rewrites_the_three_lines
  _hi_check "--check passes after a write" test_bump_check_passes_after_a_write
  _hi_check "--check catches stale .SRCINFO b2sums" test_bump_check_catches_stale_srcinfo_b2sums
  _hi_check "--check catches a stale .SRCINFO source" test_bump_check_catches_stale_srcinfo_source
  _hi_check "sha256 matches a known vector" test_bump_sha256_matches_a_known_vector
  _hi_check_requires b2sum "b2 fallback agrees with b2sum" test_bump_b2_fallback_agrees_with_b2sum
  _hi_check "rewrite preserves the file mode" test_bump_rewrite_preserves_file_mode

  _hi_h2 "Testing: package.sh (offline half)"
  _hi_check "--stage-only stages without nfpm" test_package_sh_stage_only_needs_no_nfpm
  _hi_check "--version beats the PKGBUILD's" test_package_sh_version_flag_wins
  _hi_check "Unknown arguments are an error" test_package_sh_rejects_unknown_arguments
  _hi_check "staged_launcher shims a misnamed checkout" test_staged_launcher_shims_a_misnamed_checkout
  _hi_check "release.yml ships SHA256SUMS" test_release_workflow_uploads_sha256sums

  _hi_suite_end "packaging"
}

run_packaging_tests
