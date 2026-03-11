#!/bin/bash

# TODO: Swap to cecho
unlink_hi() {
  cd /home/"$USER"/.hi.d/ || exit 1
  rm -rf .git
  rm .gitignore
  rm README.md

  rm /home/"$USER"/.hi.d/common/user_colors
  rm /home/"$USER"/.hi.d/common/host_colors
  rm /home/"$USER"/.hi.d/local/group_colors

  echo "Anonymizing host colors"
  cat <<'EOF' >> /home/"$USER"/.hi.d/common/host_colors
# hostname color_bash color_fish
192.168.1.1,\e[0;31m,brred
EOF

  echo "Anonymizing user colors"
  cat <<'EOF' >> /home/"$USER"/.hi.d/common/user_colors
# username color_bash color_fish
root,\e[0;31m,red
EOF

  chown -R "$USER:$USER" /home/"$USER"/.hi.d
}

unlink_hi
