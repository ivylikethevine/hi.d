#!/bin/sh

setup_hi() {
  chmod +x ~/.hi.d/hi.sh
  # sudo ln ~/.hi.d/hi.sh /usr/bin/hi

  diff --color=always -w -u ~/.hi.d/stubs/bashrc ~/.bashrc
  append ~/.hi.d/stubs/bashrc ~/.bashrc

  diff --color=always -w -u ~/.hi.d/stubs/zshrc ~/.zshrc
  append ~/.hi.d/stubs/zshrc ~/.zshrc

  diff --color=always -w -u ~/.hi.d/stubs/config.fish ~/.config/fish/config.fish
  append ~/.hi.d/stubs/config.fish ~/.config/fish/config.fish

  if [ ! -f ~/.nanorc ]; then
    ln ~/.hi.d/nano.rc ~/.nanorc
  fi

  if [ ! -f ~/.vimrc ]; then
    ln ~/.hi.d/vim.rc ~/.vimrc
  fi
}

append() {
  local input="$1"
  local output="$2"
  cat "$1" | grep -vxF -f "$2" >> "$2"
}

setup_hi
