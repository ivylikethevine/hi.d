#!/bin/sh

function setup_hi() {
  sudo mv /usr/bin/sshrc /usr/bin/sshrc.bak
  chmod +x ~/.sshrc.d/hi.sh
  sudo ln ~/.sshrc.d/hi.sh /usr/bin/sshrc
}

function check_stubs() {
  # for each of the stubs in the stubs directory, diff it against the local version (but only
  # for the parts of the local files that have the sshrc-start and end flags)
}
