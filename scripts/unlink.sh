#!/bin/bash
set -eou pipefail

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

unlink_hi() {
  cd "$HI_ROOT" || exit 1
  rm -rf .git

  rm .gitignore
  rm README.md

  rm data/.gitkeep
  rm "$_HI_USER_COLORS"
  rm "$_HI_HOST_COLORS"
  rm "$_HI_TRAVEL_CONFIG"
  rm "$_HI_GROUP_CONFIG"

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
  touch "$_HI_GROUP_CONFIG"
  {
    printf '%s\n' "# hosttag tag color_bash color_fish";
  } >> "$_HI_GROUP_CONFIG"

  chown -R "$USER:$USER" "$HI_ROOT"
}

unlink_hi
