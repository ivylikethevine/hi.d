#!/bin/bash

HI_TMPDIR=${HI_TMPDIR:-~}
# shellcheck source=./common/paths.sh
source "$HI_TMPDIR/.hi.d/common/paths.sh"
# shellcheck source=./common/aliases.sh
source "$_HI_ALIASES_PATH"

if ! command cecho 2>/dev/null; then
  # shellcheck source=./../common/prompt_colors.sh
  source "$_HI_PROMPT_COLORS_PATH"
fi

declare -A host_or_user bash_colors fish_colors

function cleanup() {
  cecho "Re-creating: $_HI_HOST_COLOR_FILE ===" "$YELLOW"
  if [ -f "$_HI_HOST_COLOR_FILE" ]; then
    rm "$_HI_HOST_COLOR_FILE"
    touch "$_HI_HOST_COLOR_FILE"
    printf '%s\n' "# hostname color_bash color_fish" >> "$_HI_HOST_COLOR_FILE"
    printf '%s\n' "$(hostname),\e[0;35m,brmagenta" >> "$_HI_HOST_COLOR_FILE"
    cecho "Generated color entries for: $(wc -l "$_HI_HOST_COLOR_FILE" | awk '{ print $1 }') hosts" "$GREEN"
  else
    cecho "Already detected, skipping..."
  fi

  cecho "Re-creating: $_HI_USER_COLOR_FILE ===" "$YELLOW"
  if [ -f "$_HI_USER_COLOR_FILE" ]; then
    rm "$_HI_USER_COLOR_FILE"
    touch "$_HI_USER_COLOR_FILE"
    printf '%s\n' "# username color_bash color_fish" >> "$_HI_USER_COLOR_FILE"
    printf '%s\n' "root,\e[0;31m,red" >> "$_HI_USER_COLOR_FILE"
    cecho "Generated color entries for: $(wc -l "$_HI_USER_COLOR_FILE" | awk '{ print $1 }') users" "$GREEN"
  else
    cecho "Already detected, skipping..."
  fi

  cecho "Generating: $_HI_GROUP_COLORS ===" "$YELLOW"
  if [ ! -f "$_HI_GROUP_COLORS" ]; then
    touch "$_HI_GROUP_COLORS"
    {
      printf '%s\n' "# hosttag tag color_bash color_fish";
      printf '%s\n' "hosttag,laptop,\e[0;35m,brmagenta";
      printf '%s\n' "# username name color_bash color_fish";
      printf '%s\n' "username,root,\e[0;31m,red";
      printf '%s\n' "# hostname name color_bash color_fish";
      printf '%s\n' "hostname,meow,\e[0;31m,red";
    } >> "$_HI_GROUP_COLORS"
    cecho "Generated entries for: $(grep -c \, "$_HI_GROUP_COLORS" | awk '{ print $1 }') groups" "$GREEN"
  else
    cecho "Already detected, skipping..." "$CYAN"
  fi
}

function read_colors() {
  cecho "Reading group color config from: $_HI_GROUP_COLORS ===" "$YELLOW"
  while IFS=',' read -r type tag color_bash color_fish; do
    [[ -z "$type" ]] && continue
    [[ "$type" =~ "#" ]] && continue
    host_or_user["$tag"]="$type"
    bash_colors["$tag"]="$color_bash"
    fish_colors["$tag"]="$color_fish"
    if [ "$type" = 'hostname' ]; then
      printf '%s\n' "$tag,${color_bash},${color_fish}" >> "$_HI_HOST_COLOR_FILE"
    elif [ "$type" = 'username' ]; then
      printf '%s\n' "$tag,${color_bash},${color_fish}" >> "$_HI_USER_COLOR_FILE"
    fi
  done < "$_HI_GROUP_COLORS"
  cecho "Generated color entries for: $(wc -l "$_HI_USER_COLOR_FILE" | awk '{ print $1 }') users" "$GREEN"
}

function ssh_hosts() {
  cecho "Reading ssh hosts from: $_HI_SSH_CONFIG_FILE ===" "$YELLOW"
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
        printf '%s\n' "$host,${bash_colors[$current]},${fish_colors[$current]}" >> "$_HI_HOST_COLOR_FILE"
      fi
    fi
    prev_line="$line"
  done < "$_HI_SSH_CONFIG_FILE"
  cecho "Generated color entries for: $(wc -l "$_HI_HOST_COLOR_FILE" | awk '{ print $1 }') hosts" "$GREEN"
}

function colorgen() {
  cecho "Generating user & host colors for hi.sh!" "$BRPURPLE"
  cleanup
  read_colors
  ssh_hosts
  cecho "Colors generated!" "$BRGREEN"
  return 0
}

colorgen
