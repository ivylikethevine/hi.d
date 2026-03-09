#!/bin/bash
# Define input and output files
hi_root=${HI_ROOT:-~}
GROUP_COLORS="$hi_root/.hi.d/scripts/group_colors"
HOST_OUTPUT_FILE="$hi_root/.hi.d/common/host_colors"
USER_OUTPUT_FILE="$hi_root/.hi.d/common/user_colors"

if [ -f "$HOST_OUTPUT_FILE" ]; then
  rm "$HOST_OUTPUT_FILE"
  touch "$HOST_OUTPUT_FILE"
  echo "# hostname color_bash color_fish" >> "$HOST_OUTPUT_FILE"
  # ensure we show current hostname as purple, since we don't have ourself in our own ssh config
  printf '%s\n' "$(hostname),\e[0;35m,brmagenta" >> "$HOST_OUTPUT_FILE"
fi

if [ -f "$USER_OUTPUT_FILE" ]; then
  rm "$USER_OUTPUT_FILE"
  touch "$USER_OUTPUT_FILE"
  echo "# username color_bash color_fish" >> "$USER_OUTPUT_FILE"
fi

declare -A type_map bash_map fish_map tag_map
while IFS=',' read -r type sshtag color_bash color_fish; do
  [[ -z "$type" ]] && continue
  [[ "$type" =~ "#" ]] && continue
  type_map["$sshtag"]="$type"
  bash_map["$sshtag"]="$color_bash"
  fish_map["$sshtag"]="$color_fish"
  tag_map["$sshtag-$type"]="$sshtag"
done < "$GROUP_COLORS"

# hostname colors
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
    [[ -z "${type_map[$current]}" ]] && continue
    if [[ "${type_map[$current]}" =~ hostname ]]; then
      echo "$host,${bash_map[$current]},${fish_map[$current]}" >> "$HOST_OUTPUT_FILE"
    fi
  fi
  prev_line="$line"
done < "$config_file"

# username colors
for tag in "${tag_map[@]}"; do
  echo "from [${type_map[*]}] select $tag -> $tag,${bash_map[$tag]},${fish_map[$tag]}"
  if [[ "${type_map[$tag]}" =~ username ]]; then
    echo "$tag,${bash_map[$tag]},${fish_map[$tag]}" >> "$USER_OUTPUT_FILE"
  fi
done

exit 0
