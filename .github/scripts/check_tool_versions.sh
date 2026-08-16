#!/bin/bash
# The gap .github/dependabot.yml documents: dependabot moves the SHA-pinned
# `uses:` but cannot see the curl-installed tools inside the setup-* composite
# actions. This prints each action's pinned default next to the upstream's
# latest release and exits non-zero if any differ - the tool-versions workflow
# runs it on a schedule, and it runs standalone from a checkout too:
#
#   .github/scripts/check_tool_versions.sh
#
# Updating still happens by editing the action's `version:` default by hand;
# this only makes the drift visible instead of remembered.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# "<action>|<kind>|<project>" - kind github asks the GitHub releases API,
# kind gitlab asks a GitLab tags API (checkbashisms pins a devscripts tag on
# salsa). Comparison strips a leading v from both sides, so it doesn't matter
# which convention the pin or the upstream uses.
_HI_TOOLS=(
  "setup-shellcheck|github|koalaman/shellcheck"
  "setup-shfmt|github|mvdan/sh"
  "setup-actionlint|github|rhysd/actionlint"
  "setup-zizmor|github|zizmorcore/zizmor"
  "setup-nfpm|github|goreleaser/nfpm"
  "setup-checkbashisms|gitlab|debian%2Fdevscripts"
)

function _hi_pinned() {
  sed -n 's/^    default: *"\([^"]*\)".*/\1/p' ".github/actions/$1/action.yml" | head -1
}

function _hi_latest() {
  local kind="$1" project="$2"
  case "$kind" in
  github)
    curl -sSf "https://api.github.com/repos/$project/releases/latest" |
      sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
    ;;
  gitlab)
    # backport tags (debian/2.26.9_bpo...) ride alongside the v* releases on
    # salsa; only the v* ones are what the pin means
    curl -sSf "https://salsa.debian.org/api/v4/projects/$project/repository/tags?per_page=20" |
      tr ',' '\n' | sed -n 's/.*"name":"\(v[0-9][^"]*\)".*/\1/p' | head -1
    ;;
  esac
}

bad=0
for entry in "${_HI_TOOLS[@]}"; do
  IFS='|' read -r action kind project <<<"$entry"
  pinned="$(_hi_pinned "$action")"
  latest="$(_hi_latest "$kind" "$project")"
  if [ -z "$latest" ]; then
    printf '%-22s %-12s (could not read the upstream release)\n' "$action" "$pinned"
    continue
  fi
  if [ "${pinned#v}" = "${latest#v}" ]; then
    printf '%-22s %-12s current\n' "$action" "$pinned"
  else
    printf '%-22s %-12s OUTDATED (latest: %s)\n' "$action" "$pinned" "$latest"
    # surfaces in the workflow run's summary and annotations when run by CI
    [ -n "${GITHUB_ACTIONS:-}" ] &&
      printf '::warning title=%s outdated::pinned %s, latest %s - bump the default in .github/actions/%s/action.yml\n' \
        "$action" "$pinned" "$latest" "$action"
    bad=$((bad + 1))
  fi
done

exit "$bad"
