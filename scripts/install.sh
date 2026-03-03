#!/bin/sh

setup_hi() {
  chmod +x ~/.hi.d/hi.sh
  sudo ln ~/.hi.d/hi.sh /usr/bin/hi
}

# for each of the stubs in the stubs directory, diff it against the local version (but only
# for the parts of the local files that have the hi-start and end flags)
check_stubs() {
  diff --color=always -w -u ~/.hi.d/stubs/bashrc ~/.bashrc
  diff --color=always -w -u ~/.hi.d/stubs/zshrc ~/.zshrc
  diff --color=always -w -u ~/.hi.d/stubs/config.fish ~/.config/fish/config.fish
  # also need to check permissions on these files!
}

# use hi.d configs for source tracking
link_configs() {
  sudo ln ~/.hi.d/nano.rc ~/.nanorc
  sudo ln ~/.hi.d/vim.rc ~/.vimrc
}

# TODO: Detect asdf, then list plugins, versions, and default/system versions used (or missing!)

check_stubs
