#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite reads it
# (see setup-shellcheck/install.sh). $SHFMT_VERSION comes from the env block.
set -euo pipefail
: "${SHFMT_VERSION:?set by action.yml}"

curl -sSfL -o /tmp/shfmt \
  "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64"
chmod +x /tmp/shfmt
sudo mv /tmp/shfmt /usr/local/bin/shfmt
shfmt --version
