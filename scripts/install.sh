#!/bin/sh

_tmp=$(mktemp -d)

append() {
  if ! test -f "$1"; then
    touch "$1"
  fi
  cat "$1" | grep -vxF -f "$2" > "$_tmp/append.tmp"
  cat "$2" >> "$_tmp/append.tmp"
  mv "$_tmp/append.tmp" "$2"
}

echo
echo "Checking bashrc ========"
cat <<'EOF' >> "$_tmp/bashrc"
# hi-config-start
# If not running interactively, exit
[[ $- != *i* ]] && return
source ~/.hi.d/shells/bash.sh
# hi-config-end
EOF
diff --color=always -w -u "$_tmp"/bashrc ~/.bashrc
append "$_tmp"/bashrc ~/.bashrc

echo
echo "Checking zshrc ========"
cat <<'EOF' >> "$_tmp/zshrc"
# hi-config-start
source ~/.hi.d/shells/zsh.zsh
# hi-config-end
EOF
diff --color=always -w -u "$_tmp"/zshrc ~/.zshrc
append "$_tmp"/zshrc ~/.zshrc

echo
echo "Checking config.fish ========"
cat <<'EOF' >> "$_tmp/config.fish"
# hi-config-start
if status is-interactive
  source ~/.hi.d/shells/config.fish
end
# hi-config-end
EOF
diff --color=always -w -u "$_tmp"/config.fish ~/.config/fish/config.fish
append "$_tmp"/config.fish ~/.config/fish/config.fish

echo
echo "Checking nanorc ========"
if [ ! -f ~/.nanorc ]; then
  # TODO: also enable for root
  ln ~/.hi.d/optional/nano.rc ~/.nanorc
fi

echo
echo "Checking vimrc ========"
if [ ! -f ~/.vimrc ]; then
  # TODO: also enable for root
  ln ~/.hi.d/optional/vim.rc ~/.vimrc
fi

echo
echo "Checking hi.sh ========"
chmod +x ~/.hi.d/hi.sh
# if these are different, delete the /usr/bin/hi, then relink
# use sshpass/prompt for sudo
diff --color=always -w -u ~/.hi.d/hi.sh /usr/bin/hi

rm -rf "$_tmp"
echo "Done!"
