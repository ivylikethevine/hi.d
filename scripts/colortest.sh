#!/bin/bash
# preview what every ssh host & every known user resolve to, rendered in that
# actual color, plus why (override/hosttag/default) - handy when tuning
# misc/colors. Run via `hi_colors`.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_TMPDIR:-$HOME}/hi.d/common/bootstrap.sh"

# human-readable reason a name got the color it did: an exact override (tagged
# with which type it was, since username and hostname overrides both just say
# "override" otherwise), the hosttag it inherited, or the deterministic default
function _hi_color_source() {
  local type="$1" name="$2" tag
  if _hi_override_color "$type" "$name" >/dev/null 2>&1; then
    printf 'override:%s' "$type"
    return
  fi
  if [[ "$type" = hostname ]] && tag=$(_hi_ssh_host_tag "$name") && _hi_override_color hosttag "$tag" >/dev/null 2>&1; then
    printf 'tag:%s' "$tag"
    return
  fi
  printf 'default'
}

# every username with a known color: the current user plus any "username,..."
# overrides, deduped
function _hi_known_users() {
  local users=() cur_type cur_name
  users+=("$(whoami)")
  if [[ -f "$_HI_COLORS" ]]; then
    while IFS=',' read -r cur_type cur_name _; do
      [[ "$cur_type" = "username" ]] || continue
      users+=("$cur_name")
    done <"$_HI_COLORS"
  fi
  printf '%s\n' "${users[@]}" | awk '!seen[$0]++'
}

function _hi_list_colors() {
  local name color source user user_color user_escape host_escape
  local hosts=() users=()

  while IFS= read -r name; do users+=("$name"); done < <(_hi_known_users)

  _hi_cecho "~~~~~ hi.sh color preview ~~~~~" "$BRGREEN"
  echo

  printf "%-16s %-10s %-18s %s\n" "ITEM" "TYPE" "SOURCE" "COLOR"
  printf "%-16s %-10s %-18s %s\n" "----" "----" "------" "-----"

  color=$(_hi_user_color)
  source=$(_hi_color_source username "$(whoami)")
  printf "%-16s %-10s %-18s " "$(whoami)" "username" "$source"
  _hi_cecho "$color" "$(_hi_color_escape "$color")"

  if [[ ! -f "$_HI_SSH_CONFIG" ]]; then
    _hi_cecho "No ssh config found at $_HI_SSH_CONFIG" "$RED"
    return
  fi

  while IFS=$'\t' read -r name _; do
    hosts+=("$name")
    color=$(_hi_resolve_color hostname "$name")
    source=$(_hi_color_source hostname "$name")
    host_escape=$(_hi_color_escape "$color")
    printf "%-16s %-10s %-18s " "$name" "hostname" "$source"
    _hi_cecho "$color" "$host_escape" 1
    for user in "${users[@]}"; do
      user_color=$(_hi_resolve_color username "$user")
      user_escape=$(_hi_color_escape "$user_color")
      # mirrors HI_PS1 in shells/bash.sh: the "@" is yellow, same as a live
      # ssh session, since that's what connecting to one of these hosts is
      printf '%b' "  ${user_escape}${user}${NC}${YELLOW}@${NC}${host_escape}${name}${NC}"
    done
    echo
  done < <(sh "$_HI_TARGETS" ssh)
}

_hi_list_colors
