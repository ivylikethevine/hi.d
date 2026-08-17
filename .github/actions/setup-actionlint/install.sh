#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite reads it
# (see setup-shellcheck/install.sh). $ACTIONLINT_VERSION comes from the env
# block.
set -euo pipefail
: "${ACTIONLINT_VERSION:?set by action.yml}"

curl -sSfL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" |
  tar xz -C /tmp actionlint
sudo mv /tmp/actionlint /usr/local/bin/actionlint
actionlint --version
