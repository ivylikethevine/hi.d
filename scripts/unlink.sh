#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/prompt_colors.sh
command -v cecho >/dev/null || source "$_HI_PROMPT_COLORS"

unlink_hi() {
  cd "$HI_ROOT" || exit 1
  rm -rf .git

  rm .gitignore
  rm README.md

  rm "$_HI_USER_COLORS"
  rm "$_HI_HOST_COLORS"
  rm "$_HI_TRAVEL_CONFIG"
  rm "$_HI_GROUP_COLORS"

  echo "Anonymizing host colors"
  cat <<'EOF' >> "$_HI_HOST_COLORS"
# hostname color_bash color_fish
192.168.1.1,\e[0;31m,brred
EOF

  echo "Anonymizing user colors"
  cat <<'EOF' >> "$_HI_USER_COLORS"
# username color_bash color_fish
root,\e[0;31m,red
EOF

echo "Anonymizing group colors"
  touch "$_HI_GROUP_COLORS"
  {
    printf '%s\n' "# hosttag tag color_bash color_fish";
    printf '%s\n' "hosttag,laptop,\e[0;35m,brmagenta";
    printf '%s\n' "# username name color_bash color_fish";
    printf '%s\n' "username,root,\e[0;31m,red";
    printf '%s\n' "# hostname name color_bash color_fish";
    printf '%s\n' "hostname,meow,\e[0;31m,red";
  } >> "$_HI_GROUP_COLORS"

  chown -R "$USER:$USER" "$HI_ROOT"
}

unlink_hi
