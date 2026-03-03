#!/bin/sh

setup_hi() {
  mv ~/sshrc.d ~/.hi.d
  mv ~/.sshrc.d ~/.hi.d
  chmod +x ~/.hi.d/hi.sh
  sudo ln ~/.hi.d/hi.sh /usr/bin/hi

  diff --color=always -w -u ~/.hi.d/stubs/bashrc ~/.bashrc
  cat ~/.hi.d/stubs/bashrc >> ~/.bashrc

  diff --color=always -w -u ~/.hi.d/stubs/zshrc ~/.zshrc
  cat ~/.hi.d/stubs/zshrc >> ~/.zshrc

  diff --color=always -w -u ~/.hi.d/stubs/config.fish ~/.config/fish/config.fish
  cat ~/.hi.d/stubs/config.fish >> ~/.config/fish/config.fish

  sudo ln ~/.hi.d/nano.rc ~/.nanorc
  sudo ln ~/.hi.d/vim.rc ~/.vimrc
}

setup_hi
