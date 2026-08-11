#!/bin/bash
# preview what every ssh host & every known user resolve to, rendered in that
# actual color, plus why (override/hosttag/default) - handy when tuning
# misc/colors. Run via `hi_colors`.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

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
# overrides, deduped. LOCALUSER is excluded - it's not a real name to preview,
# it gets its own row in the users table further down instead
function _hi_known_users() {
  local users=() cur_type cur_name
  users+=("$(whoami)")
  if [[ -f "$_HI_COLORS" ]]; then
    while IFS=',' read -r cur_type cur_name _; do
      [[ "$cur_type" = "username" && "$cur_name" != "LOCALUSER" ]] || continue
      users+=("$cur_name")
    done <"$_HI_COLORS"
  fi
  printf '%s\n' "${users[@]}" | awk '!seen[$0]++'
}

# every "usertag,<tag>,..." tag with a color override, deduped
function _hi_known_usertags() {
  local cur_type cur_name
  [[ -f "$_HI_COLORS" ]] || return 0
  while IFS=',' read -r cur_type cur_name _; do
    [[ "$cur_type" = "usertag" ]] || continue
    printf '%s\n' "$cur_name"
  done <"$_HI_COLORS" | awk '!seen[$0]++'
}

# every username the hosts table's PREVIEW column renders: every known real
# user, plus the "example" identities from the users table - the current
# username (standing in for LOCALUSER, since that's never a real login name)
# and each usertag name
function _hi_preview_users() {
  local tag
  {
    _hi_known_users
    _hi_override_color username LOCALUSER >/dev/null 2>&1 && printf '%s\n' "$(whoami)"
    while IFS= read -r tag; do
      _hi_override_color usertag "$tag" >/dev/null 2>&1 && printf '%s\n' "$tag"
    done < <(_hi_known_usertags)
  } | awk '!seen[$0]++'
}

# total plain-text width of a preview cell for a group of hostnames: every
# user gets "user@host" padded to user_width, joined by two spaces
function _hi_group_preview_width() {
  local h n=$# pw=0
  for h in "$@"; do pw=$((pw + user_width + 1 + ${#h})); done
  printf '%s' $((pw + 2 * (n - 1)))
}

function _hi_hbar() {
  local seg="+" w
  for w in "$@"; do
    seg+="$(printf '%*s' $((w + 2)) '' | tr ' ' '-')+"
  done
  printf '%s\n' "$seg"
}

# users table: every known real user with a non-default color, plus LOCALUSER
# and every usertag override as its own "example" row
function _hi_print_users_table() {
  local user tag source color_name name_escape
  local users=() usertags=()
  local w_item=9 w_color=5 w_source=6
  local localuser_color=""

  while IFS= read -r user; do users+=("$user"); done < <(_hi_known_users)
  while IFS= read -r tag; do usertags+=("$tag"); done < <(_hi_known_usertags)

  for color_name in "${_HI_COLOR_NAMES[@]}"; do
    ((${#color_name} > w_color)) && w_color=${#color_name}
  done
  for user in "${users[@]}" LOCALUSER "${usertags[@]}"; do
    ((${#user} > w_item)) && w_item=${#user}
  done
  for user in "${users[@]}"; do
    source=$(_hi_color_source username "$user")
    ((${#source} > w_source)) && w_source=${#source}
  done
  source="local:username"
  ((${#source} > w_source)) && w_source=${#source}
  for tag in "${usertags[@]}"; do
    source="usertag:$tag"
    ((${#source} > w_source)) && w_source=${#source}
  done

  _hi_hbar "$w_item" "$w_color" "$w_source"
  printf '| %-*s | %-*s | %-*s |\n' "$w_item" "USER" "$w_color" "COLOR" "$w_source" "SOURCE"
  _hi_hbar "$w_item" "$w_color" "$w_source"

  for user in "${users[@]}"; do
    source=$(_hi_color_source username "$user")
    [[ "$source" = default ]] && continue
    color_name=$(_hi_resolve_color username "$user")
    name_escape=$(_hi_color_escape "$color_name")
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_item" "$user")${NC}"
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_color" "$color_name")${NC}"
    printf '| %b |\n' "${name_escape}$(printf '%-*s' "$w_source" "$source")${NC}"
  done

  if localuser_color=$(_hi_override_color username LOCALUSER 2>/dev/null); then
    name_escape=$(_hi_color_escape "$localuser_color")
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_item" "LOCALUSER")${NC}"
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_color" "$localuser_color")${NC}"
    printf '| %b |\n' "${name_escape}$(printf '%-*s' "$w_source" "local:username")${NC}"
  fi

  for tag in "${usertags[@]}"; do
    color_name=$(_hi_override_color usertag "$tag") || continue
    name_escape=$(_hi_color_escape "$color_name")
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_item" "$tag")${NC}"
    printf '| %b ' "${name_escape}$(printf '%-*s' "$w_color" "$color_name")${NC}"
    printf '| %b |\n' "${name_escape}$(printf '%-*s' "$w_source" "usertag:$tag")${NC}"
  done

  _hi_hbar "$w_item" "$w_color" "$w_source"
}

# hosts table: a LOCALHOSTNAME row (the current machine) followed by every
# ssh-config host grouped by the color it'd actually render with. PREVIEW
# combines every real known user plus the "example" users from the users
# table (LOCALUSER, each usertag) against that host's name(s)
function _hi_print_hosts_table() {
  local name color_name source user user_color user_escape name_escape key
  local cur_line sep candidate idx idx2 li total_lines itemtext previewtext
  local tag has_usertag
  local user_width=0 pw pad_preview local_hostname
  local preview_users=() group_order=() group_names=() item_lines=()
  local -A group_hosts group_source group_color group_tag
  local has_localhostname=false localhostname_color=""

  while IFS= read -r name; do preview_users+=("$name"); done < <(_hi_preview_users)
  for user in "${preview_users[@]}"; do
    ((${#user} > user_width)) && user_width=${#user}
  done

  # group hosts that share a type+source AND the actual resolved color, so
  # only hosts that would render identically collapse into one row
  if [[ -f "$_HI_SSH_CONFIG" ]]; then
    while IFS=$'\t' read -r name _; do
      source=$(_hi_color_source hostname "$name")
      tag=$(_hi_ssh_host_tag "$name" 2>/dev/null) || tag=""
      has_usertag=false
      [[ -n "$tag" ]] && _hi_override_color usertag "$tag" >/dev/null 2>&1 && has_usertag=true
      # skip hosts that wouldn't render any differently from a bare `hi`
      [[ "$source" = default && "$has_usertag" = false ]] && continue
      color_name=$(_hi_resolve_color hostname "$name")
      # tag is part of the key (not just source/color) since it changes which
      # users get colored via usertag, even when the hostname cell looks identical
      key="$source"$'\x1f'"$color_name"$'\x1f'"$tag"
      if [[ -z "${group_hosts[$key]+x}" ]]; then
        group_order+=("$key")
        group_source[$key]="$source"
        group_color[$key]="$color_name"
        group_tag[$key]="$tag"
      fi
      group_hosts[$key]+="${group_hosts[$key]:+ }$name"
    done < <(sh "$_HI_TARGETS" ssh)
  fi

  local w_item=24 w_color=5 w_source=6 w_preview=7
  for name in "${_HI_COLOR_NAMES[@]}"; do
    ((${#name} > w_color)) && w_color=${#name}
  done

  # LOCALHOSTNAME gets its own row further down (see below) - measure its
  # SOURCE label here too
  if localhostname_color=$(_hi_override_color hostname LOCALHOSTNAME 2>/dev/null); then
    has_localhostname=true
    source="local:hostname"
    ((${#source} > w_source)) && w_source=${#source}
    local_hostname=$(_hi_local_hostname)
    ((${#local_hostname} > w_item)) && w_item=${#local_hostname}
    pw=$(_hi_group_preview_width "$local_hostname")
    ((pw > w_preview)) && w_preview=$pw
  fi

  for key in "${group_order[@]}"; do
    source="${group_source[$key]}"
    ((${#source} > w_source)) && w_source=${#source}
    read -ra group_names <<< "${group_hosts[$key]}"
    pw=$(_hi_group_preview_width "${group_names[@]}")
    ((pw > w_preview)) && w_preview=$pw
  done

  _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"
  printf '| %-*s | %-*s | %-*s | %-*s |\n' \
    "$w_item" "HOST" "$w_color" "COLOR" "$w_source" "SOURCE" "$w_preview" "PREVIEW"
  _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"

  if [[ "$has_localhostname" = true ]]; then
    name_escape=$(_hi_color_escape "$localhostname_color")
    total_lines=${#preview_users[@]}
    ((total_lines > 0)) || total_lines=1

    for ((li = 0; li < total_lines; li++)); do
      if ((li == 0)); then
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_item" "$local_hostname")${NC}"
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_color" "$localhostname_color")${NC}"
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_source" "local:hostname")${NC}"
      else
        printf '| %-*s ' "$w_item" ""
        printf '| %-*s ' "$w_color" ""
        printf '| %-*s ' "$w_source" ""
      fi

      if ((li < ${#preview_users[@]})); then
        user="${preview_users[li]}"
        user_color=$(_hi_resolve_color username "$user" "")
        user_escape=$(_hi_color_escape "$user_color")
        # pad after the hostname so every row's plain-text width matches
        # pad_preview below, regardless of that user's name length
        previewtext="${user_escape}${user}${NC}${YELLOW}@${NC}${name_escape}${local_hostname}$(printf '%*s' $((user_width - ${#user})) '')${NC}"
        pad_preview=$((w_preview - $(_hi_group_preview_width "$local_hostname")))
        printf '| %b%*s |\n' "$previewtext" "$pad_preview" ""
      else
        printf '| %*s |\n' "$w_preview" ""
      fi
    done

    _hi_hbar "$w_item" "$w_color" "$w_source" "$w_preview"
  fi

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
    pw=$(_hi_group_preview_width "${group_names[@]}")
    pad_preview=$((w_preview - pw))

    total_lines=${#item_lines[@]}
    ((${#preview_users[@]} > total_lines)) && total_lines=${#preview_users[@]}

    for ((li = 0; li < total_lines; li++)); do
      if ((li < ${#item_lines[@]})); then
        itemtext="${item_lines[li]}"
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_item" "$itemtext")${NC}"
      else
        printf '| %-*s ' "$w_item" ""
      fi

      if ((li == 0)); then
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_color" "$color_name")${NC}"
        printf '| %b ' "${name_escape}$(printf '%-*s' "$w_source" "$source")${NC}"
      else
        printf '| %-*s ' "$w_color" ""
        printf '| %-*s ' "$w_source" ""
      fi

      if ((li < ${#preview_users[@]})); then
        user="${preview_users[li]}"
        user_color=$(_hi_resolve_color username "$user" "${group_tag[$key]}")
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

_hi_print_users_table
printf '\n'
_hi_print_hosts_table
