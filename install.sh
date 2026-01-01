#!/bin/sh

# Override sshrc with custom hi script
function setup_hi() {
  sudo mv /usr/bin/sshrc /usr/bin/sshrc.bak
  chmod +x ~/.sshrc.d/hi.sh
  sudo ln ~/.sshrc.d/hi.sh /usr/bin/sshrc # TODO: Fix how this is undone after a git pull...
}

# for each of the stubs in the stubs directory, diff it against the local version (but only
# for the parts of the local files that have the sshrc-start and end flags)
function check_stubs() {
}

# use sshrc.d configs for source tracking
function link_configs() {
  sudo ln ~/.sshrc.d/nano.rc ~/.nanorc
  sudo ln ~/.sshrc.d/vim.rc ~/.vimrc
}
