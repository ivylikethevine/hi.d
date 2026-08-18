#!/bin/bash
# The install half of ./action.yml, in a real file so the repo's own lint suite
# (shellcheck, shfmt, the bash-3.2 grep) reads it - a `run:` block inside a
# composite action is code nothing here would otherwise lint, and this one
# curls, untars and sudo mvs.
#
# Two subcommands, because actions/cache needs the version as an expression
# before the install step runs:
#   resolve   write the effective version to $GITHUB_OUTPUT
#   install   download it and put it on PATH
set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${HI_TOOL:?set by action.yml}"

# the row is captured first rather than read straight from a here-string: a
# failing command substitution inside `read <<<` is not the read's status, so
# an unknown tool would print its error and still exit 0
_hi_row="$(_hi_tool_row "$HI_TOOL")" || exit 1
IFS='|' read -r _ _hi_pin _hi_kind _hi_url _hi_verify _ <<<"$_hi_row"

# an explicit `version:` input wins over the manifest's pin; empty means "use
# the pin", which is what every call site passes
_hi_version="${HI_TOOL_VERSION:-}"
[ -n "$_hi_version" ] || _hi_version="$_hi_pin"

case "${1:-}" in
resolve)
  : "${GITHUB_OUTPUT:?set by the runner}"
  printf 'version=%s\n' "$_hi_version" >>"$GITHUB_OUTPUT"
  exit 0
  ;;
install) ;;
*)
  echo "setup-tool: expected 'resolve' or 'install', got '${1:-}'" >&2
  exit 1
  ;;
esac

# %a: only shellcheck ships more than one asset, because it is the only tool
# installed on macOS as well. Resolved before %v so a version can never look
# like an asset slug.
case "$_hi_url" in
*%a*)
  case "$(uname -s).$(uname -m)" in
  Linux.x86_64) _hi_asset="linux.x86_64" ;;
  Darwin.arm64) _hi_asset="darwin.aarch64" ;;
  Darwin.x86_64) _hi_asset="darwin.x86_64" ;;
  *)
    echo "setup-tool: no $HI_TOOL asset mapping for $(uname -s).$(uname -m)" >&2
    exit 1
    ;;
  esac
  _hi_url="${_hi_url//%a/$_hi_asset}"
  ;;
esac
_hi_url="${_hi_url//%v/$_hi_version}"

_hi_tmp="$(mktemp -d)"
trap 'rm -rf "$_hi_tmp"' EXIT

case "$_hi_kind" in
raw)
  curl -sSfL -o "$_hi_tmp/$HI_TOOL" "$_hi_url"
  chmod +x "$_hi_tmp/$HI_TOOL"
  _hi_bin="$_hi_tmp/$HI_TOOL"
  ;;
tar.gz | tar.xz)
  curl -sSfL -o "$_hi_tmp/archive" "$_hi_url"
  # extract whole and then look, rather than naming a member: the layouts here
  # are flat, versioned-dir and arch-subdir, and a stale member path fails hard
  # on a version bump where a search does not
  case "$_hi_kind" in
  tar.gz) tar -xzf "$_hi_tmp/archive" -C "$_hi_tmp" ;;
  tar.xz) tar -xJf "$_hi_tmp/archive" -C "$_hi_tmp" ;;
  esac
  _hi_bin="$(find "$_hi_tmp" -type f -name "$HI_TOOL" -perm -u+x | head -1)"
  [ -n "$_hi_bin" ] || {
    echo "setup-tool: no executable named $HI_TOOL inside $_hi_url" >&2
    exit 1
  }
  ;;
*)
  echo "setup-tool: unknown kind '$_hi_kind' for $HI_TOOL" >&2
  exit 1
  ;;
esac

sudo mkdir -p /usr/local/bin
sudo mv "$_hi_bin" "/usr/local/bin/$HI_TOOL"

# the verify column is a flag, word-split on purpose - minisign's is -v
# shellcheck disable=SC2086
"$HI_TOOL" $_hi_verify
