#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite reads it
# (see setup-shellcheck/install.sh). $NFPM_VERSION comes from the env block.
set -euo pipefail
: "${NFPM_VERSION:?set by action.yml}"

curl -sSfL -o /tmp/nfpm.tar.gz \
  "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz"
tar -xzf /tmp/nfpm.tar.gz -C /tmp nfpm
sudo mv /tmp/nfpm /usr/local/bin/nfpm
nfpm --version
