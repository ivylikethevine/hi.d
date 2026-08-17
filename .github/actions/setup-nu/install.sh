#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite reads it
# (see setup-shellcheck/install.sh). $NU_VERSION comes from the env block.
set -euo pipefail
: "${NU_VERSION:?set by action.yml}"

curl -sSfL -o /tmp/nu.tar.gz \
  "https://github.com/nushell/nushell/releases/download/${NU_VERSION}/nu-${NU_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
tar -xzf /tmp/nu.tar.gz -C /tmp "nu-${NU_VERSION}-x86_64-unknown-linux-gnu/nu"
sudo mv "/tmp/nu-${NU_VERSION}-x86_64-unknown-linux-gnu/nu" /usr/local/bin/nu
rm -rf /tmp/nu.tar.gz "/tmp/nu-${NU_VERSION}-x86_64-unknown-linux-gnu"
nu --version
