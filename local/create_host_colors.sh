#!/bin/bash
# Define input and output files
hi_root=${HI_ROOT:-~}
GROUP_COLORS="$hi_root/.hi.d/local/group_colors"
HOST_OUTPUT_FILE="$hi_root/.hi.d/common/host_colors"
USER_OUTPUT_FILE="$hi_root/.hi.d/common/user_colors"

declare -A host_or_user bash_colors fish_colors tag_or_name

cleanup() {
  echo "Creating: $HOST_OUTPUT_FILE"
  if [ -f "$HOST_OUTPUT_FILE" ]; then
    rm "$HOST_OUTPUT_FILE"
    touch "$HOST_OUTPUT_FILE"
    printf '%s\n' "# hostname color_bash color_fish" >> "$HOST_OUTPUT_FILE"
    printf '%s\n' "$(hostname),\e[0;35m,brmagenta" >> "$HOST_OUTPUT_FILE"
  fi

  echo "Creating: $USER_OUTPUT_FILE"
  if [ -f "$USER_OUTPUT_FILE" ]; then
    rm "$USER_OUTPUT_FILE"
    touch "$USER_OUTPUT_FILE"
    printf '%s\n' "# username color_bash color_fish" >> "$USER_OUTPUT_FILE"
    printf '%s\n' "username,root,\e[0;31m,red" >> "$HOST_OUTPUT_FILE"
  fi

  echo "Generating: $GROUP_COLORS [if not found]"
  if [ ! -f "$GROUP_COLORS" ]; then
    touch "$GROUP_COLORS"
    {
      printf '%s\n' "# hostname tag color_bash color_fish";
      printf '%s\n' "hostname,laptop,\e[0;35m,brmagenta";
      printf '%s\n' "# username name color_bash color_fish";
      printf '%s\n' "username,root,\e[0;31m,red";
    } >> "$GROUP_COLORS"
  fi
  echo
}

read_colors() {
  echo "Reading group color config from: $GROUP_COLORS"
  while IFS=',' read -r type tag color_bash color_fish; do
    [[ -z "$type" ]] && continue
    [[ "$type" =~ "#" ]] && continue
    host_or_user["$tag"]="$type"
    bash_colors["$tag"]="$color_bash"
    fish_colors["$tag"]="$color_fish"
    tag_or_name["$tag-$type"]="$tag"
  done < "$GROUP_COLORS"
}

ssh_hosts() {
  echo "Reading ssh hosts from: $HOME/.ssh/config"
  prev_line=""
  config_file="$HOME/.ssh/config"
  while IFS=' ' read -r line; do
    [[ -z "$line" ]] && continue
    if [[ $line =~ ^Host[[:space:]]+([^#]+) ]]; then
      host=${BASH_REMATCH[1]}
      host=${host%%[[:space:]]*}
      tags=()
      if [[ $prev_line =~ Tags[:=]([^\n\r]*) ]]; then
        tags_str=${prev_line#*Tags: }
        tags_str=${tags_str#" "}
        IFS=', ' read -ra tags <<< "$tags_str"
      fi
      current=${tags[0]} # only uses leftmost tag for now :shrug:
      [[ -z "$current" ]] && continue
      [[ -z "${host_or_user[$current]}" ]] && continue
      if [[ "${host_or_user[$current]}" =~ hostname ]]; then
        printf '%s\n' "$host,${bash_colors[$current]},${fish_colors[$current]}" >> "$HOST_OUTPUT_FILE"
      fi
    fi
    prev_line="$line"
  done < "$config_file"
  echo "Generated color entries for: $(wc -l "$HOST_OUTPUT_FILE" | awk '{ print $1 }') hosts"
}

ssh_users() {
  for tag in "${tag_or_name[@]}"; do
    if [[ "${host_or_user[$tag]}" =~ username ]]; then
      printf '%s\n' "$tag,${bash_colors[$tag]},${fish_colors[$tag]}" >> "$USER_OUTPUT_FILE"
    fi
  done
  echo "Generated color entries for: $(wc -l "$USER_OUTPUT_FILE" | awk '{ print $1 }') users"
}

colorgen() {
  cleanup
  read_colors
  ssh_hosts
  ssh_users
  return 0
}

colorgen
