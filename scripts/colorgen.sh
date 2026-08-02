#!/bin/bash
# set -eou pipefail

_HI_TMPDIR=${_HI_TMPDIR:-$HOME}
# shellcheck source=./../common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./../common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

function append() {
  local input="${1}"
  local output="${2}"
  local tmp
  tmp="$(mktemp)"

  if ! test -f "$input"; then
    touch "$input"
  fi

  # TODO: Figure out why this line causes set -eou pipefail to crash
  cat "$input" | grep -vxF -f "$output" > "$tmp"
  cat "$output" >> "$tmp"

  mv "$tmp" "$output"
  rm "$input"
}

declare -A host_or_user bash_colors fish_colors

function create_basic_group_colors() {
  local TMP_GROUP_COLORS
  TMP_GROUP_COLORS=$(mktemp)
  touch "$TMP_GROUP_COLORS"
  {
    printf '%s\n' "#username/hostname/hosttag,color_bash,color_fish";
    printf '%s\n' "hosttag,desktop,$GREEN,green";

    printf '%s\n' "username,root,$RED,red";

    printf '%s\n' "hostname,prod,$YELLOW,bryellow";
    printf '%s\n' "hostname,$(hostname),$PURPLE,magenta";

  } >> "$TMP_GROUP_COLORS"

  append "$TMP_GROUP_COLORS" "$_HI_GROUP_CONFIG"

  cecho "Generated entries for: $(grep -c \, "$_HI_GROUP_CONFIG" | awk '{ print $1 }') groups" "$GREEN"
}

function create_basic_host_colors() {
  local TMP_HOST_COLORS
  TMP_HOST_COLORS=$(mktemp)
  touch "$TMP_HOST_COLORS"
  printf '%s\n' "#hostname,color_bash,color_fish" >> "$TMP_HOST_COLORS"
  append "$TMP_HOST_COLORS" "$_HI_HOST_COLORS"

  cecho "Recreated!" "$GREEN"
}

function create_basic_user_colors() {
  local TMP_USER_COLORS
  TMP_USER_COLORS=$(mktemp)
  touch "$TMP_USER_COLORS"
  printf '%s\n' "#username,color_bash,color_fish" >> "$TMP_USER_COLORS"
  append "$TMP_USER_COLORS" "$_HI_USER_COLORS"

  cecho "Recreated!" "$GREEN"
}

function read_group_colors() {
  cecho "=== Reading groups from: $_HI_GROUP_CONFIG ===" "$YELLOW"

  local TMP_USER_COLORS
  local TMP_HOST_COLORS
  TMP_USER_COLORS=$(mktemp)
  TMP_HOST_COLORS=$(mktemp)
  touch "$TMP_USER_COLORS"
  touch "$TMP_HOST_COLORS"

  while IFS=',' read -r type tag color_bash color_fish; do
    [[ -z "$type" ]] && continue
    [[ "$type" =~ "#" ]] && continue
    host_or_user["$tag"]="$type"
    bash_colors["$tag"]="$color_bash"
    fish_colors["$tag"]="$color_fish"
    if [ "$type" = 'hostname' ]; then
      printf '%s\n' "$tag,${color_bash},${color_fish}" >> "$TMP_HOST_COLORS"
    elif [ "$type" = 'username' ]; then
      printf '%s\n' "$tag,${color_bash},${color_fish}" >> "$TMP_USER_COLORS"
    fi
  done < "$_HI_GROUP_CONFIG"

  append "$TMP_USER_COLORS" "$_HI_USER_COLORS"
  append "$TMP_HOST_COLORS" "$_HI_HOST_COLORS"

  cecho "Generated group-based colors for: $(wc -l "$_HI_USER_COLORS" | awk '{ print $1 }') users" "$CYAN"
  cecho "Generated group-based colors for: $(wc -l "$_HI_HOST_COLORS" | awk '{ print $1 }') hosts" "$CYAN"

}

function read_ssh_hosts() {
  cecho "=== Reading ssh hosts from: $_HI_SSH_CONFIG_FILE ===" "$YELLOW"

  local TMP_HOST_COLORS
  TMP_HOST_COLORS=$(mktemp)
  touch "$TMP_HOST_COLORS"

  local prev_line=""
  while IFS=' ' read -r line; do
    [[ -z "$line" ]] && continue
    if [[ $line =~ ^Host[[:space:]]+([^#]+) ]]; then
      local host
      host=${BASH_REMATCH[1]}
      host=${host%%[[:space:]]*}
      local tags=()
      if [[ $prev_line =~ Tags[:=]([^\n\r]*) ]]; then
        local tags_str
        tags_str=${prev_line#*Tags: }
        tags_str=${tags_str#" "}
        if [[ -z ${ZSH_VERSION+x} ]]; then
          IFS=', ' read -ra tags <<< "$tags_str"
        else
          IFS=', ' read -rA tags <<< "$tags_str"
        fi
      fi
      local current
      current=${tags[0]} # only uses leftmost tag for now :shrug:
      [[ -z "$current" ]] && continue
      [[ -z "${host_or_user[$current]+x}" ]] && continue
      if [[ "${host_or_user[$current]}" =~ hosttag ]]; then
        printf '%s\n' "$host,${bash_colors[$current]},${fish_colors[$current]}" >> "$TMP_HOST_COLORS"
      fi
    fi
    prev_line="$line"
  done < "$_HI_SSH_CONFIG_FILE"

  append "$TMP_HOST_COLORS" "$_HI_HOST_COLORS"
  cecho "Generated color entries for: $(wc -l "$_HI_HOST_COLORS" | awk '{ print $1 }') hosts" "$GREEN"
}

function initial_colorgen() {
  rm "$_HI_GROUP_CONFIG"
  colorgen
}

function colorgen() {
  cecho "~~~~~ Generating user & host colors for hi.sh! ~~~~~" "$BRGREEN"

  cecho "=== Re-creating: $_HI_HOST_COLORS ===" "$YELLOW"
  if [ -f "$_HI_HOST_COLORS" ]; then
    create_basic_host_colors
  fi

  cecho "=== Re-creating: $_HI_USER_COLORS ===" "$YELLOW"
  if [ -f "$_HI_USER_COLORS" ]; then
    create_basic_user_colors
  fi

  cecho "=== Generating: $_HI_GROUP_CONFIG ===" "$YELLOW"
  if [ -f "$_HI_GROUP_CONFIG" ]; then
    create_basic_group_colors
  fi

  read_group_colors
  read_ssh_hosts

  cecho "~~~~~ Colors generated! ~~~~~ " "$BRGREEN"
  return 0
}
