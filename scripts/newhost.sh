#!/bin/bash
set -eou pipefail

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

# TODO: Handle changing existings keys, adding entirely new hosts, etc.
newhost() {
  local remote_host
  remote_host="${1:-}"
  cecho "~~~~~ Creating key for $remote_host ~~~~~" "$BRGREEN"

  local config_file="$HOME/.ssh/config"
  cecho "=== Reading $config_file for $remote_host ===" "$BRCYAN"

  if ! grep -q "^Host $remote_host" "$config_file"; then
    cecho "Host $remote_host not found in $config_file" "$RED"
    return 1
  else
    cecho "Host found!" "$BRBLUE"
  fi

  local local_host
  local_host=$(hostname)
  local key_name="$local_host-to-$remote_host"
  if [ ! -d "$HOME/.ssh/per-host/" ]; then
    mkdir "$HOME/.ssh/per-host/"
  fi
  local key_path="$HOME/.ssh/per-host/$key_name"
  cecho "=== Generating SSH key at $key_path ===" "$CYAN"
  ssh-keygen -t ed25519 -f "$key_path" -N "" -P '' -C "$key_name"
  cecho "Key generated at $key_path" "$GREEN"

  cecho "== Copying key from $local_host to $remote_host... ==="
  ssh-copy-id -f -i "$key_path" "$remote_host"

  cecho "Editing $local_host's ssh config for $remote_host..." "$CYAN"
  local identity_file="\  IdentityFile $key_path"
  local host_section_start
  host_section_start=$(grep -n "^Host $remote_host" "$config_file" | cut -d: -f1)

  sed -i "$((host_section_start + 1))a $identity_file" "$config_file"
  cecho "Added IdentityFile entry to SSH config for host $remote_host at line $host_section_start" "$BRBLUE"

  cecho "~~~~~ Key created & installed! ~~~~~ " "$BRGREEN"
}

newhost "$@"
