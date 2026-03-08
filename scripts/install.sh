#!/bin/sh

append() {
  cat "$1" | grep -vxF -f "$2" >> "$2"
}

_tmp=$(mktemp -d)

cat <<'EOF' >> "$_tmp/bashrc"
# hi-config start
# If not running interactively, exit
[[ $- != *i* ]] && return
source ~/.hi.d/bash.sh
# hi-config end
EOF
diff --color=always -w -u $_tmp/bashrc ~/.bashrc
append $_tmp/bashrc ~/.bashrc

cat <<'EOF' >> "$_tmp/zshrc"
# hi-config
source ~/.hi.d/zsh.zsh
# hi-config end
EOF
diff --color=always -w -u $_tmp/zshrc ~/.zshrc
append $_tmp/zshrc ~/.zshrc

cat <<'EOF' >> "$_tmp/config.fish"
# hi-config start
if status is-interactive
  source ~/.hi.d/config.fish
end
# hi-config end
EOF
diff --color=always -w -u $_tmp/config.fish ~/.config/fish/config.fish
append $_tmp/config.fish ~/.config/fish/config.fish

if [ ! -f ~/.nanorc ]; then
  # TODO: also enable for root
  ln ~/.hi.d/optional/nano.rc ~/.nanorc
fi

if [ ! -f ~/.vimrc ]; then
  # TODO: also enable for root
  ln ~/.hi.d/optional/im.rc ~/.vimrc
fi

chmod +x ~/.hi.d/hi.sh
# if these are different, delete the /usr/bin/hi, then relink
# use sshpass/prompt for sudo
diff --color=always -w -u ~/.hi.d/hi.sh /usr/bin/hi

rm -rf $_tmp
