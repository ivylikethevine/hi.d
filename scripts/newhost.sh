#!/bin/bash
set -eou pipefail

# TODO: Handle changing keys, etc.
newhost() {
  local remote_host
  remote_host="${1:-}"
  local config_file="$HOME/.ssh/config"

  if ! grep -q "^Host $remote_host" "$config_file"; then
    echo "Host $remote_host not found in $config_file"
    return 1
  fi

  local local_host
  local_host=$(hostname)
  local key_name="$local_host-to-$remote_host"
  if [ ! -d "$HOME/.ssh/per-host/" ]; then
    mkdir "$HOME/.ssh/per-host/"
  fi

  local key_path="$HOME/.ssh/per-host/$key_name"

  echo "Generating SSH key for $remote_host..."
  ssh-keygen -t ed25519 -f "$key_path" -N "" -P '' -C "$key_name"
  echo "Key generated at $key_path"

  echo "Copying key to $remote_host..."
  ssh-copy-id -f -i "$key_path" "$remote_host"

  echo "Editing local ssh config for $remote_host..."
  local identity_file="\  IdentityFile $key_path"
  local host_section_start
  host_section_start=$(grep -n "^Host $remote_host" "$config_file" | cut -d: -f1)

  sed -i "$((host_section_start + 1))a $identity_file" "$config_file"
  echo "Added IdentityFile entry to SSH config for host $remote_host"
}

newhost "$@"
