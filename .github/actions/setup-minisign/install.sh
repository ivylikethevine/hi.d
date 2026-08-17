#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite reads it
# (see setup-shellcheck/install.sh). $MINISIGN_VERSION comes from the env
# block; note minisign's tags carry no leading v.
set -euo pipefail
: "${MINISIGN_VERSION:?set by action.yml}"

curl -sSfL -o /tmp/minisign.tar.gz \
  "https://github.com/jedisct1/minisign/releases/download/${MINISIGN_VERSION}/minisign-${MINISIGN_VERSION}-linux.tar.gz"
tar -xzf /tmp/minisign.tar.gz -C /tmp
sudo mv /tmp/minisign-linux/x86_64/minisign /usr/local/bin/minisign
minisign -v
