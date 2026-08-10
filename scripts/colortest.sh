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

# a "+----+----+" style divider sized to the given column widths
function _hi_hbar() {
  local seg="+" w
  for w in "$@"; do
    seg+="$(printf '%*s' $((w + 2)) '' | tr ' ' '-')+"
  done
  printf '%s\n' "$seg"
}

function _hi_list_colors() {
  local name color_name source user user_color user_escape name_escape key
  local cur_line sep candidate idx idx2 li total_lines itemtext previewtext
  local user_width=0 pw pad_preview n h
  local users=() group_order=() group_names=() item_lines=()
  local -A group_hosts group_source group_color

  while IFS= read -r name; do users+=("$name"); done < <(_hi_known_users)
  for user in "${users[@]}"; do
    ((${#user} > user_width)) && user_width=${#user}
  done

  # group hosts that share a type+source AND the actual resolved color, so
  # only hosts that would render identically collapse into one row - e.g.
  # two "default" hosts whose names hash to different colors stay separate
  if [[ -f "$_HI_SSH_CONFIG" ]]; then
    while IFS=$'\t' read -r name _; do
      source=$(_hi_color_source hostname "$name")
      [[ "$source" = default ]] && continue
      color_name=$(_hi_resolve_color hostname "$name")
      key="$source"$'\x1f'"$color_name"
      if [[ -z "${group_hosts[$key]+x}" ]]; then
        group_order+=("$key")
        group_source[$key]="$source"
        group_color[$key]="$color_name"
      fi
      group_hosts[$key]+="${group_hosts[$key]:+ }$name"
    done < <(sh "$_HI_TARGETS" ssh)
  fi

  # column widths: ITEM/COLOR are fixed to a size that comfortably fits any
  # name/palette entry, SOURCE and PREVIEW stretch to fit whatever content
  # this run actually produced, so the right-hand border never gets blown out
  local w_item=24 w_color=5 w_source=6 w_preview=7
  for name in "${_HI_COLOR_NAMES[@]}"; do
    ((${#name} > w_color)) && w_color=${#name}
  done
  for user in "${users[@]}"; do
    source=$(_hi_color_source username "$user")
    ((${#source} > w_source)) && w_source=${#source}
  done
  for key in "${group_order[@]}"; do
    source="${group_source[$key]}"
    ((${#source} > w_source)) && w_source=${#source}
    read -ra group_names <<< "${group_hosts[$key]}"
    n=${#group_names[@]}
    pw=0
    for h in "${group_names[@]}"; do pw=$((pw + user_width + 1 + ${#h})); done
    pw=$((pw + 2 * (n - 1)))
    ((pw > w_preview)) && w_preview=$pw
  done

  _hi_h1 "hi.sh color preview"

  _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"
  printf '| %-*s | %-*s | %-*s | %-*s |\n' \
    "$w_item" "ITEM" "$w_color" "COLOR" "$w_source" "SOURCE" "$w_preview" "PREVIEW"
  _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"

  for user in "${users[@]}"; do
    source=$(_hi_color_source username "$user")
    [[ "$source" = default ]] && continue
    color_name=$(_hi_resolve_color username "$user")
    name_escape=$(_hi_color_escape "$color_name")
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_item" "$user")${NC}"
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_color" "$color_name")${NC}"
    printf '| %-*s ' "$w_source" "$source"
    printf '| %*s |\n' "$w_preview" ""
  done

  _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"

  if [[ ! -f "$_HI_SSH_CONFIG" ]]; then
    _hi_cecho "No ssh config found at $_HI_SSH_CONFIG" "$RED"
    return
  fi

  for key in "${group_order[@]}"; do
    source="${group_source[$key]}"
    color_name="${group_color[$key]}"
    name_escape=$(_hi_color_escape "$color_name")
    read -ra group_names <<< "${group_hosts[$key]}"

    # wrap the name list within the ITEM column instead of overflowing it
    item_lines=()
    cur_line=""
    for idx in "${!group_names[@]}"; do
      name="${group_names[idx]}"
      sep=""
      ((idx < ${#group_names[@]} - 1)) && sep=", "
      candidate="${cur_line}${name}${sep}"
      if ((${#cur_line} > 0 && ${#candidate} > w_item)); then
        item_lines+=("$cur_line")
        cur_line="${name}${sep}"
      else
        cur_line="$candidate"
      fi
    done
    [[ -n "$cur_line" ]] && item_lines+=("$cur_line")

    # every preview line in this group has identical plain-text width (users
    # are right-padded to user_width) so one pad amount covers the whole group
    n=${#group_names[@]}
    pw=0
    for h in "${group_names[@]}"; do pw=$((pw + user_width + 1 + ${#h})); done
    pw=$((pw + 2 * (n - 1)))
    pad_preview=$((w_preview - pw))

    total_lines=${#item_lines[@]}
    ((${#users[@]} > total_lines)) && total_lines=${#users[@]}

    for ((li = 0; li < total_lines; li++)); do
      if ((li < ${#item_lines[@]})); then
        itemtext="${item_lines[li]}"
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_item" "$itemtext")${NC}"
      else
        printf '| %-*s ' "$w_item" ""
      fi

      if ((li == 0)); then
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_color" "$color_name")${NC}"
        printf '| %-*s ' "$w_source" "$source"
      else
        printf '| %-*s ' "$w_color" ""
        printf '| %-*s ' "$w_source" ""
      fi

      if ((li < ${#users[@]})); then
        user="${users[li]}"
        user_color=$(_hi_resolve_color username "$user")
        user_escape=$(_hi_color_escape "$user_color")
        previewtext=""
        for idx2 in "${!group_names[@]}"; do
          ((idx2 > 0)) && previewtext+='  '
          # pad after the hostname so the next column lands at the same spot
          # in every user row beneath it, regardless of that user's name
          # length; mirrors HI_PS1 in shells/bash.sh - the "@" is yellow,
          # same as a live ssh session, since that's what connecting to one
          # of these hosts is
          previewtext+="${user_escape}${user}${NC}${YELLOW}@${NC}${name_escape}${group_names[idx2]}$(printf '%*s' $((user_width - ${#user})) '')${NC}"
        done
        printf '| %b%*s |\n' "$previewtext" "$pad_preview" ""
      else
        printf '| %*s |\n' "$w_preview" ""
      fi
    done

    _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"
  done
}

_hi_list_colors
