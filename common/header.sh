#!/bin/bash
# The banner hi prints on connect/disconnect, and the fish greeting prints
# locally - one implementation for every shell (fish shells out to bash here).
# The packages check at the bottom of it (full_check, over misc/packages) lives
# here too: the header is its only caller, and `hi_packages_preview` reaches it
# by sourcing this file.
set -euo pipefail

# shellcheck source=./core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"

function header_row() {
  local cell out=""
  for cell in "$@"; do out+="$NC | $cell"; done
  printf '%b\n' "$out$NC"
}

function timestamp() {
  header_row "$BRBLUE$(date -u "$_HI_HUMAN_CENTRIC_DATE")  " "  $BRYELLOW$(date "$_HI_HUMAN_CENTRIC_DATE")"
}

function system_info() {
  local kernel arch os cpus ram base_mhz boost_mhz
  read -r kernel arch <<<"$(uname -sm)"
  kernel=$(_hi_sanitize "$kernel")
  arch=$(_hi_sanitize "$arch")
  local base_freq_path="/sys/devices/system/cpu/cpu0/cpufreq/base_frequency"
  local max_freq_path="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
  local scaling_freq_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
  if [ -f "$_HI_LINUX_RELEASE" ]; then
    # also covers WSL - it's a real Linux kernel with its own /etc/os-release
    os=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' "$_HI_LINUX_RELEASE")
    # every probe below ends in `|| true`: a stripped-down target (debian-slim
    # has no procps, alpine no lscpu) must fall through to the "?" placeholders
    # rather than abort the caller under `set -e`/pipefail
    cpus=$(nproc 2>/dev/null || true)
    # straight at the file free(1) itself reads, rather than free | awk
    ram=$(awk '/^MemTotal:/ { printf "%.0fG", $2 / 1048576 }' /proc/meminfo 2>/dev/null || true)
    # base clock: try the model name first (eg "... @ 2.80GHz") - AMD chips (Ryzen/EPYC) don't
    # print one, so fall back to cpufreq's base_frequency (Intel P-State / amd-pstate only)
    base_mhz=$(awk -F'@ *' '/model name/ && NF>1 { gsub(/GHz.*/, "", $2); printf "%.0f", $2 * 1000; exit }' /proc/cpuinfo 2>/dev/null || true)
    # `read < file`, not $(cat file): the redirect fails silently on a missing
    # file and read is a builtin, so a miss costs no fork
    local khz=0
    if [ -z "$base_mhz" ] && [ -f "$base_freq_path" ]; then
      read -r khz <"$base_freq_path" 2>/dev/null || khz=0
      base_mhz=$((khz / 1000))
      ((base_mhz)) || base_mhz=""
    fi
    # boost/max clock: cpufreq first (works for any driver that exposes it), falling back to lscpu
    if [ -f "$max_freq_path" ] && [ -f "$scaling_freq_path" ]; then
      read -r khz <"$scaling_freq_path" 2>/dev/null || khz=0
    fi
    boost_mhz=$((khz / 1000))
    ((boost_mhz)) || boost_mhz=$(lscpu 2>/dev/null | awk -F: '/CPU max MHz/ { gsub(/ /, "", $2); printf "%.0f", $2 }' || true)
  elif [[ "$kernel" == MINGW* || "$kernel" == MSYS* || "$kernel" == CYGWIN* ]]; then
    # git-bash/MSYS2/Cygwin on native Windows - no /etc/os-release, no sysctl
    os="Windows ($kernel)"
    cpus="${NUMBER_OF_PROCESSORS:-?}"
    ram=$(wmic ComputerSystem get TotalPhysicalMemory 2>/dev/null |
      awk 'NR==2 && $1 ~ /^[0-9]+$/ { printf "%.0fG", $1 / 1073741824 }' || true)
    # wmic only exposes the rated (base) clock; turbo/boost isn't queryable this way
    base_mhz=$(wmic cpu get MaxClockSpeed 2>/dev/null | awk 'NR==2 && $1 ~ /^[0-9]+$/ { print $1 }' || true)
  else
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
    cpus=$(sysctl -n hw.ncpu 2>/dev/null || true)
    ram=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%.0fG", $1 / 1073741824 }' || true)
    # Apple Silicon doesn't expose either clock via sysctl; only Intel Macs get a value here
    base_mhz=$(sysctl -n hw.cpufrequency 2>/dev/null | awk '{ printf "%.0f", $1 / 1000000 }' || true)
  fi
  os=$(_hi_sanitize "$os")
  header_row "$PURPLE$arch" "$GREEN$os" "${YELLOW}Cores: ${cpus:-?}" \
    "${CYAN}RAM: ${ram:-?}" "${BRBLUE}CPU: ${base_mhz:-?}/${boost_mhz:-?} MHz"
}

# git identity (domain masked), running containers, nomad jobs, kube pods and
# ssh key counts. Probes go through _hi_probe (common/core.sh): this is on the
# connect path with the user waiting, so a dead daemon must not hang it.
function identity() {
  local email="" domain user_part bullets containers="No docker/podman :(" jobs="" pods="" authorized=0 public=0
  local -a lines cells
  local container_bin
  command -v git &>/dev/null && email=$(git config --get user.email 2>/dev/null || true)
  email=$(_hi_sanitize "$email")
  if [ -n "$email" ]; then
    domain=${email#*@}
    printf -v bullets '%*s' "${#domain}" ''
    user_part="$YELLOW${email%%@*}@${bullets// /●}"
  else
    user_part="${YELLOW}No Git ID Found..."
  fi
  container_bin="$(command -v docker || command -v podman || true)"
  if [ -n "$container_bin" ]; then
    # 2>/dev/null so a daemon that's down reports its error to itself rather
    # than into the middle of the header
    _hi_read_lines lines < <(_hi_probe "$container_bin" container ls -q 2>/dev/null)
    containers="Containers: ${#lines[@]}"
  fi
  if command -v nomad &>/dev/null; then
    _hi_read_lines lines < <(_hi_probe nomad job status 2>/dev/null)
    lines=("${lines[@]:1}") # drop the header row
    jobs="Jobs: ${#lines[@]}"
  fi
  # kube is a target hi can connect to (hi.sh's _hi_is_k8s_pod), so it belongs
  # on the same count line as the other three
  if command -v kubectl &>/dev/null; then
    _hi_read_lines lines < <(_hi_probe kubectl get pods --field-selector=status.phase=Running \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    pods="Pods: ${#lines[@]}"
  fi
  [ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && _hi_read_lines lines <"$_HI_SSH_AUTHORIZED_KEYS" && authorized=${#lines[@]}
  [ -d "$_HI_SSH_DIR" ] && _hi_read_lines lines < <(find "$_HI_SSH_DIR" -type f -name "*.pub") && public=${#lines[@]}
  cells=("$user_part" "$BLUE$containers")
  [ -n "$jobs" ] && cells+=("$CYAN$jobs")
  [ -n "$pods" ] && cells+=("$CYAN$pods")
  cells+=("${RED}Auth: $authorized" "${PURPLE}Pub: $public")
  header_row "${cells[@]}"
}

# "~~~ <label> [host] ~~~", prefixed with hi.d's local change count
# this whole line is always _HI_MAX_WIDTH columns, regardless of other factors
function banner() {
  [[ "${_HI_HEADER_BANNER:-1}" == 0 ]] && return 0
  local label="$1" color="${2:-$BRGREEN}" changes="" prefix="${3:-}" changes_w=0
  # `git status --short` over the checkout costs ~10ms and banner runs twice a
  # session (connect, then load.sh on disconnect) for a number that cannot have
  # changed in between. Compute it once and keep it.
  if [ -d "$_HI_ROOT/.git" ]; then
    if [ -z "${_HI_BANNER_CHANGES+x}" ]; then
      local -a lines
      _hi_read_lines lines < <(git -C "$_HI_ROOT" status --short 2>/dev/null)
      _HI_BANNER_CHANGES="${#lines[@]}"
    fi
    changes="$BRYELLOW$_HI_BANNER_CHANGES ↑ "
    # columns counted, not ${#}-measured (GLOSSARY: bytes vs columns):
    # digits + "␣↑␣", with ↑ one column wide
    changes_w=$((${#_HI_BANNER_CHANGES} + 3))
  fi
  local host tildes start_len end_len start_tildes end_tildes width left core
  host="$(_hi_sanitize "$(_hi_hostname)")"
  width=${_HI_MAX_WIDTH:-80}
  tildes=$((width - 6 - changes_w - ${#label} - ${#host} - ${#prefix}))
  ((tildes < 4)) && tildes=4
  # split so "label [host]" lands at the center with at least 1 tilde on the left
  left=$((${#prefix} + 1 + changes_w))
  core=$((${#label} + ${#host} + 4))
  start_len=$((width / 2 - left - core / 2))
  ((start_len < 1)) && start_len=1
  ((start_len > tildes - 1)) && start_len=$((tildes - 1))
  end_len=$((tildes - start_len))
  _hi_repeat start_tildes "$start_len" '~'
  _hi_repeat end_tildes "$end_len" '~'
  printf '%b\n' " $changes$color$start_tildes $label ${NC}[$(_hi_host_escape)$host$NC]$color $end_tildes$NC"
}

function hi_header() {
  [[ "${_HI_DISABLE_HEADER:-0}" == 1 ]] && return 0
  banner "$@"
  [[ "${_HI_HEADER_TIMESTAMP:-1}" == 0 ]] || timestamp
  [[ "${_HI_HEADER_SYSINFO:-1}" == 0 ]] || system_info
  [[ "${_HI_HEADER_IDENTITY:-1}" == 0 ]] || identity
  [[ "${_HI_HEADER_CHECK:-1}" == 0 ]] || full_check
}

# --- the packages check -----------------------------------------------------
# Reads misc/packages and prints which of them are installed, sorting by priority.

# priority, lowest to highest (more can be added)
# 0 nice-to-haves (netstat, distro tools)
# 1 second line (git, curl, ping)
# 2 first line (sed, awk, bc)
# 3 runtimes (python, node, dotnet)
# 4 favorites (eza, bat)
# 5 workflow-defining (asdf, direnv)
_HI_YES=("$BRBLUE" "$BRBLUE" hide "$GREEN" "$BRGREEN" "$BRGREEN")
_HI_NO=(hide "$BRYELLOW" "$YELLOW" hide hide "$BRRED")

# named so the suite matches these same bytes - a lookalike literal can
# differ in codepoint while looking identical in an editor
_HI_MARK_OK="✓"  # installed, and it was the preferred name
_HI_MARK_ALT="~" # installed, but via a fallback alternative
_HI_MARK_NO="✗"  # not installed

# For each "cmd:priority[,...]", pick the installed package with the
# highest priority (or the first package if none are installed), then apply the
# proper color and mark it as installed or missing (or hide it as per above)
function check_line() {
  local pair cmd priority color best best_priority best_idx=0 idx=0 found=0 symbol rendered
  # word-split on the local IFS rather than `read -ra <<<`, whose here-string is
  # a pipe (or temp file on bash < 5.1) per package line - ~30 per header
  local IFS=','
  # shellcheck disable=SC2206 # deliberate split on IFS; the file has no globs
  local -a pairs=($1)
  unset IFS
  best="${pairs[0]%:*}"
  best_priority="${pairs[0]#*:}"

  for pair in "${pairs[@]}"; do
    cmd="${pair%:*}"
    priority="${pair#*:}"
    if command -v "$cmd" &>/dev/null && ((found == 0 || priority > best_priority)); then
      best="$cmd"
      best_priority="$priority"
      best_idx=$idx
      found=1
    fi
    ((++idx))
  done

  if ((found)); then
    color="${_HI_YES[best_priority]:-$NC}"
    if ((best_idx == 0)); then symbol="$GREEN$_HI_MARK_OK"; else symbol="$YELLOW$_HI_MARK_ALT$NC"; fi
  else
    color="${_HI_NO[best_priority]:-$NC}"
    symbol="$RED$_HI_MARK_NO"
  fi
  rendered="$color $best $symbol"
  [[ "$color" == hide ]] || visible+=("$best_priority"$'\x1f'"$((${#best} + 5))"$'\x1f'"$rendered")
}

# print sorted package results limited by _HI_MAX_WIDTH
function full_check() {
  local line priority width_item rendered count=0 width=0
  local -a visible=() # appended to by check_line
  while IFS=$' ' read -r line; do
    [[ "$line" == *#* || -z "$line" ]] || check_line "$line"
  done <"$_HI_PACKAGES"
  ((${#visible[@]})) || return 0

  # GLOSSARY: LC_ALL=C sort - numeric key over opaque bytes; unpinned, BSD
  # sort under UTF-8 printed *nothing* and the whole check rendered empty.
  while IFS=$'\x1f' read -r priority width_item rendered; do
    if ((count == 0)) || ((width + width_item > ${_HI_MAX_WIDTH:-80})); then # start of a row
      ((count == 0)) || printf '\n'
      printf ' '
      width=1
    fi
    printf '%b' "$NC|${rendered} $NC"
    width=$((width + width_item))
    ((++count))
  done < <(printf '%s\n' "${visible[@]}" | LC_ALL=C sort -t $'\x1f' -k1,1nr -s)
  printf '\n'
}
