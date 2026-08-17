#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite
# (shellcheck, shfmt, the bash-3.2 grep) reads it - a `run:` block inside a
# composite action is code nothing here would otherwise lint. The version
# arrives as $SHELLCHECK_VERSION from the action's env block.
set -euo pipefail
: "${SHELLCHECK_VERSION:?set by action.yml}"

# upstream's asset naming: linux.x86_64 / darwin.aarch64 / darwin.x86_64
case "$(uname -s).$(uname -m)" in
Linux.x86_64) asset="linux.x86_64" ;;
Darwin.arm64) asset="darwin.aarch64" ;;
Darwin.x86_64) asset="darwin.x86_64" ;;
*)
  echo "no shellcheck asset mapping for $(uname -s).$(uname -m)" >&2
  exit 1
  ;;
esac
curl -sSfL -o /tmp/shellcheck.tar.xz \
  "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.${asset}.tar.xz"
tar -xJf /tmp/shellcheck.tar.xz -C /tmp "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
sudo mkdir -p /usr/local/bin
sudo mv "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck
rm -rf /tmp/shellcheck.tar.xz "/tmp/shellcheck-v${SHELLCHECK_VERSION}"
shellcheck --version
