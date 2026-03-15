#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

declare -A host_or_user bash_colors fish_colors

function create_basic_group_colors() {
  touch "$_HI_GROUP_COLORS"
  {
    printf '%s\n' "#username/hostname/hosttag,color_bash,color_fish";
    printf '%s\n' "hosttag,desktop,$GREEN,green";

    printf '%s\n' "username,root,$RED,red";
    printf '%s\n' "username,$USER,$CYAN,blue"

    printf '%s\n' "hostname,prod,$YELLOW,yellow";
    printf '%s\n' "hostname,$(hostname),$PURPLE,magenta";

  } >> "$_HI_GROUP_COLORS"
  cecho "Generated entries for: $(grep -c \, "$_HI_GROUP_COLORS" | awk '{ print $1 }') groups" "$GREEN"
}

function create_basic_host_colors() {
  touch "$_HI_HOST_COLORS"
  {
    printf '%s\n' "#hostname,color_bash,color_fish";
    # printf '%s\n' "prod,$YELLOW,yellow";
    # printf '%s\n' "$(hostname),$PURPLE,magenta";
  } >> "$_HI_HOST_COLORS"

  cecho "Recreated!" "$GREEN"
}

function create_basic_user_colors() {
  touch "$_HI_USER_COLORS"
  {
    printf '%s\n' "#username,color_bash,color_fish";
    # printf '%s\n' "root,$RED,red";
    # printf '%s\n' "$USER,$CYAN,green"
  } >> "$_HI_USER_COLORS"

  cecho "Recreated!" "$GREEN"
}

function read_group_colors() {
  cecho "=== Reading groups from: $_HI_GROUP_COLORS ===" "$YELLOW"
  while IFS=',' read -r type tag color_bash color_fish; do
    [[ -z "$type" ]] && continue
    [[ "$type" =~ "#" ]] && continue
    host_or_user["$tag"]="$type"
    bash_colors["$tag"]="$color_bash"
    fish_colors["$tag"]="$color_fish"
    if [ "$type" = 'hostname' ]; then
      printf '%s\n' "$tag,${color_bash},${color_fish}" >> "$_HI_HOST_COLORS"
    elif [ "$type" = 'username' ]; then
      printf '%s\n' "$tag,${color_bash},${color_fish}" >> "$_HI_USER_COLORS"
    fi
  done < "$_HI_GROUP_COLORS"
  cecho "Generated group-based colors for: $(wc -l "$_HI_USER_COLORS" | awk '{ print $1 }') users" "$CYAN"
  cecho "Generated group-based colors for: $(wc -l "$_HI_HOST_COLORS" | awk '{ print $1 }') hosts" "$CYAN"

}

function read_ssh_hosts() {
  cecho "=== Reading ssh hosts from: $_HI_SSH_CONFIG_FILE ===" "$YELLOW"
  prev_line=""
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
      if [[ "${host_or_user[$current]}" =~ hosttag ]]; then
        printf '%s\n' "$host,${bash_colors[$current]},${fish_colors[$current]}" >> "$_HI_HOST_COLORS"
      fi
    fi
    prev_line="$line"
  done < "$_HI_SSH_CONFIG_FILE"
  cecho "Generated color entries for: $(wc -l "$_HI_HOST_COLORS" | awk '{ print $1 }') hosts" "$GREEN"
}

function initial_colorgen() {
  rm "$_HI_GROUP_COLORS"
  colorgen
}

# TODO: fix or switch to append
function dedupe() {
  local input="$1"
  tmp=$(mktemp)
  cat "$input" | uniq -c | awk '{ print $2 }' > "$tmp"
  cp "$tmp" "$input"
  rm "$tmp"
}

function colorgen() {
  cecho "~~~~~ Generating user & host colors for hi.sh! ~~~~~" "$BRGREEN"

  cecho "=== Re-creating: $_HI_HOST_COLORS ===" "$YELLOW"
  if [ -f "$_HI_HOST_COLORS" ]; then
    rm "$_HI_HOST_COLORS"
    create_basic_host_colors
  fi

  cecho "=== Re-creating: $_HI_USER_COLORS ===" "$YELLOW"
  if [ -f "$_HI_USER_COLORS" ]; then
    rm "$_HI_USER_COLORS"
    create_basic_user_colors
  fi

  cecho "=== Generating: $_HI_GROUP_COLORS ===" "$YELLOW"
  if [ -f "$_HI_GROUP_COLORS" ]; then
    create_basic_group_colors
  fi

  read_group_colors
  read_ssh_hosts
  dedupe "$_HI_GROUP_COLORS"
  dedupe "$_HI_USER_COLORS"
  dedupe "$_HI_HOST_COLORS"

  cecho "~~~~~ Colors generated! ~~~~~ " "$BRGREEN"
  return 0
}
