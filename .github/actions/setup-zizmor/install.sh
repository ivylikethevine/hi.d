#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite reads it
# (see setup-shellcheck/install.sh). $ZIZMOR_VERSION comes from the env block.
set -euo pipefail
: "${ZIZMOR_VERSION:?set by action.yml}"

curl -sSfL "https://github.com/zizmorcore/zizmor/releases/download/v${ZIZMOR_VERSION}/zizmor-x86_64-unknown-linux-gnu.tar.gz" |
  tar xz -C /tmp
sudo mv "$(find /tmp -maxdepth 2 -name zizmor -type f | head -1)" /usr/local/bin/zizmor
zizmor --version
