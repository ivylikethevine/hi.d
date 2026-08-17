#!/bin/bash
# The install half of ./action.yml, in a real file so the lint suite reads it
# (see setup-shellcheck/install.sh). $DEVSCRIPTS_TAG comes from the env block.
set -euo pipefail
: "${DEVSCRIPTS_TAG:?set by action.yml}"

curl -sSfL -o /tmp/checkbashisms \
  "https://salsa.debian.org/debian/devscripts/-/raw/${DEVSCRIPTS_TAG}/scripts/checkbashisms.pl"
chmod +x /tmp/checkbashisms
sudo mv /tmp/checkbashisms /usr/local/bin/checkbashisms
checkbashisms --version
