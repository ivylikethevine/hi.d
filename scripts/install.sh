#!/bin/bash
# Points the local shells at hi.d's configs and links hi.sh onto $PATH.
# Safe to re-run: it repairs the lines it owns and leaves everything else alone.
set -euo pipefail

_HI_FEATURES_ONLY=""
_HI_CHECK_CONFIGS_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
  --features-only)
    _HI_FEATURES_ONLY=1
    shift
    ;;
  --check-configs)
    _HI_CHECK_CONFIGS_ONLY=1
    shift
    ;;
  -h | --help)
    cat <<'EOF'
Usage: install.sh [--features-only] [--check-configs]

Wires up the local shells to source this hi.d checkout and links hi.sh onto
PATH. Safe to re-run any time - it repairs its own lines and leaves
everything else alone. The install location is always wherever this script
lives (hi.d's parent directory), not a path you pass in - hi.d installs in
place.

  --features-only  Skip the shell rc wiring and the hi.sh symlink - just
                   re-run the feature toggle prompts. This is what
                   `hi_configure` calls once hi.d is installed.
  --check-configs  Only run the pre-install validation of your existing
                   ~/.bashrc, ~/.zshrc and ~/.config/fish/config.fish -
                   skip everything else. This is what `hi_check_configs`
                   calls.
EOF
    exit 0
    ;;
  *)
    echo "install.sh: unrecognized argument: $1" >&2
    echo "Usage: install.sh [--features-only] [--check-configs]" >&2
    exit 1
    ;;
  esac
done

# Locate hi.d relative to this script (resolving symlinks) - hi.d's parent
# directory is always the install dir, since this installs in place.
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"
  _HI_SELF="$(readlink "$_HI_SELF")"
  [[ $_HI_SELF == /* ]] || _HI_SELF="$_HI_SELF_DIR/$_HI_SELF"
done
_HI_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)"
export _HI_HOME

# shellcheck source=../common/bootstrap.sh
source "$_HI_HOME/hi.d/common/bootstrap.sh"
# shellcheck source=../common/header.sh
source "$_HI_HEADER"
# shellcheck source=../common/git_prompt.sh
source "$_HI_GIT_PROMPT"

_HI_MARKER="# added by hi during install"
_HI_LINK="/usr/bin/hi"

# Rewrite the block of hi-managed lines (tagged with $_HI_MARKER) in $target to
# be exactly $@, leaving any other user content untouched. This both installs
# the sourcing on a fresh machine and repairs it if hi.d has since moved -
# stale lines pointing at an old location are replaced, not left dangling
# alongside new ones. Empty arguments are skipped.
function config_shell() {
  local name="$1" target="$2" line existing desired="" tmpfile
  shift 2
  _hi_h2 "Checking $name"

  mkdir -p "$(dirname "$target")"
  touch "$target"
  for line in "$@"; do
    [ -n "$line" ] && desired+="$(printf '%-45s %s' "$line" "$_HI_MARKER")"$'\n'
  done

  existing="$(grep -F "$_HI_MARKER" "$target" || true)"
  if [ "$existing" = "${desired%$'\n'}" ]; then
    _hi_cecho " local $name up to date :)" "$GREEN"
    return 0
  fi

  _hi_cecho " local $name out of date, updating..." "$YELLOW"
  tmpfile="$(mktemp -t hi.append.XXXXXX)"
  grep -vF "$_HI_MARKER" "$target" >"$tmpfile" || true
  printf '%s' "$desired" >>"$tmpfile"
  mv "$tmpfile" "$target"
  _hi_cecho " local $name updated :)" "$GREEN"
}

# Only emit an _HI_HOME export when hi.d isn't at $HOME/hi.d - every consumer
# already defaults _HI_HOME to $HOME, so the common case stays free of it.
function tmpdir_line() {
  [ "$_HI_HOME" = "$HOME" ] && return 0
  case "$1" in
  fish) printf 'set -gx _HI_HOME "%s"' "$_HI_HOME" ;;
  *) printf 'export _HI_HOME="%s"' "$_HI_HOME" ;;
  esac
}

# true if "export $1=$3" (default off-value: 1) isn't currently present in
# $2 - i.e. the setting is at its enabled default. Used to default each
# prompt below to whatever was chosen last time this ran. hi's own
# _HI_DISABLE_* vars use 1 for "off"; common/header.sh's older per-line
# toggles use 0 instead, hence the third argument.
function setting_enabled() {
  local var="$1" target="$2" off="${3:-1}"
  ! grep -qE "^export $var=$off" "$target" 2>/dev/null
}

# Ask a yes/no question about one setting, defaulting to its current state in
# $3 (target file, checked via setting_enabled with off-value $4). $5, if
# given, is a zero-arg function whose output is boxed as a live preview,
# printed after the question text (see show_preview) - so the question reads
# first and the preview illustrates the answer, not the other way round.
# Non-interactive runs (no tty - piped into bash, run from a script, etc.)
# silently keep whatever is already configured instead of hanging on a
# prompt nobody can answer, and skip the preview entirely since nothing will
# be shown before the question is auto-answered anyway.
function ask_setting() {
  local var="$1" question="$2" target="$3" off="${4:-1}" preview="${5:-}" default hint reply=""
  setting_enabled "$var" "$target" "$off" && default=y || default=n
  if [ ! -t 0 ]; then
    [ "$default" = y ]
    return
  fi
  hint="Y/n"
  [ "$default" = n ] && hint="y/N"
  printf '%s\n' "$question"
  [ -n "$preview" ] && show_preview "$preview"
  read -r -p " [$hint] " reply || reply=""
  [ -z "$reply" ] && reply="$default"
  [[ "$reply" =~ ^[Yy] ]]
}

# visible width of $1 - the printable character count once ANSI SGR color
# codes are stripped out, needed to size/pad show_preview's box since the
# raw string length color escapes inflate is meaningless for alignment.
# extglob is needed for the +(...) pattern below; toggled on just for this
# substitution and restored to whatever it was before, rather than left on
# for the rest of the script.
function _hi_visible_len() {
  local stripped restore=0
  shopt -q extglob || { shopt -s extglob; restore=1; }
  stripped="${1//$'\e'\[+([0-9;])m/}"
  ((restore)) && shopt -u extglob
  printf '%s' "${#stripped}"
}

# Run $@ and box whatever it writes to stdout, labeled "preview" - a live
# render using hi's own real functions (not a hypothetical example), sized to
# its own longest line rather than the terminal width, since previews range
# from one short colored line to full_check's wrapped multi-line block.
function show_preview() {
  [ -t 0 ] || return 0
  local out label="─ preview " content_w=0 len line pad top bottom fill_top fill_bottom
  local -a lines
  out="$("$@" 2>/dev/null)" || true
  [ -n "$out" ] || return 0
  mapfile -t lines <<<"$out"
  for line in "${lines[@]}"; do
    len="$(_hi_visible_len "$line")"
    ((len > content_w)) && content_w=$len
  done
  printf -v fill_top '%*s' $((content_w + 2 - ${#label})) ''
  printf -v fill_bottom '%*s' $((content_w + 2)) ''
  top="┌${label}${fill_top// /─}┐"
  bottom="└${fill_bottom// /─}┘"
  _hi_cecho "   $top" "$NC"
  for line in "${lines[@]}"; do
    len="$(_hi_visible_len "$line")"
    pad=$((content_w - len))
    printf '   │ %s%*s │\n' "$line" "$pad" ""
  done
  _hi_cecho "   $bottom" "$NC"
}

# banner() needs an arg, so wrap it to match every other preview function's
# zero-arg signature that ask_setting's $5 expects
function _hi_banner_preview() { banner Connected; }

# sample "user@host cwd" line, colored exactly like shells/bash.sh's real
# HI_PS1 (see _hi_user_escape/_hi_host_escape/_hi_at_color), just with the
# literal current user/host/cwd instead of \u/\h/\w
function _hi_prompt_preview() {
  local cwd="${PWD/#$HOME/\~}"
  printf '%b\n' " $(_hi_user_escape)$(whoami)$(_hi_at_color)@$(_hi_host_escape)$(_hi_hostname)$NC $BRBLUE$cwd$NC"
}

# the real git prompt segment, rendered against hi.d's own checkout (always a
# git repo) so the preview reflects this machine's actual git status instead
# of a made-up example; _HI_DISABLE_GIT_STATUS is unset for the call since a
# previously-disabled toggle would otherwise make _hi_git_prompt return empty
function _hi_git_status_preview() {
  (cd "$_HI_ROOT" 2>/dev/null && unset _HI_DISABLE_GIT_STATUS && _hi_git_prompt)
}

# what `nano`/`vim` actually resolve to with the override on
function _hi_editors_preview() {
  printf 'nano -> nano --rcfile %s\n' "$_HI_NANORC"
  printf 'vim  -> %s -u %s\n' "$(command -v nvim || command -v vim)" "$_HI_VIMRC"
}

# alias count plus a handful of names, read straight from shells/aliases.sh
# rather than duplicating its fallthrough logic here
function _hi_aliases_preview() {
  local names count
  names="$(grep -oE '^alias [A-Za-z0-9_]+=' "$_HI_ALIASES" | sed -E 's/^alias //; s/=$//')"
  count="$(printf '%s\n' "$names" | wc -l)"
  printf '%s personal aliases, e.g.: %s, ...\n' "$count" "$(printf '%s\n' "$names" | head -6 | paste -sd, -)"
}

# Prompt for the optional pieces of hi's shell config and write _HI_DISABLE_*
# lines for whichever ones were turned off into common/paths.sh - the one
# file every shell (including fish) sources, so the choice applies locally
# and on every host hi.d gets copied to.
function config_features() {
  local target="$_HI_ROOT/common/paths.sh"
  local dis_header="" dis_prompt="" dis_personal="" dis_git="" dis_editors="" dis_aliases="" dis_local=""
  _hi_h2 "Choosing features"
  ask_setting _HI_DISABLE_HEADER \
    " Enable the connect/disconnect header (system info, git identity, package check)?" \
    "$target" 1 _hi_banner_preview ||
    dis_header="export _HI_DISABLE_HEADER=1"
  ask_setting _HI_DISABLE_PROMPT \
    " Enable the colored user@host prompt?" "$target" 1 _hi_prompt_preview ||
    dis_prompt="export _HI_DISABLE_PROMPT=1"
  ask_setting _HI_DISABLE_PERSONAL \
    " Enable personal shell settings (history size, keybindings, completion tweaks)?" "$target" 1 "" ||
    dis_personal="export _HI_DISABLE_PERSONAL=1"
  ask_setting _HI_DISABLE_GIT_STATUS \
    " Enable git status in the prompt?" "$target" 1 _hi_git_status_preview ||
    dis_git="export _HI_DISABLE_GIT_STATUS=1"
  ask_setting _HI_DISABLE_EDITORS \
    " Enable the vim/nano config overrides?" "$target" 1 _hi_editors_preview ||
    dis_editors="export _HI_DISABLE_EDITORS=1"
  ask_setting _HI_DISABLE_ALIASES \
    " Enable the personal aliases in shells/aliases.sh (sudo, cat/eza, git, docker, pacman/apt, etc)?" \
    "$target" 1 _hi_aliases_preview ||
    dis_aliases="export _HI_DISABLE_ALIASES=1"
  ask_setting _HI_DISABLE_LOCAL \
    " Enable all of the above on this machine (the one hi.d is installed on), not just when you hi elsewhere?" \
    "$target" 1 "" ||
    dis_local="export _HI_DISABLE_LOCAL=1"
  config_shell "feature toggles" "$target" \
    "$dis_header" "$dis_prompt" "$dis_personal" "$dis_git" "$dis_editors" "$dis_aliases" "$dis_local"
}

# Prompt for the header's optional detail lines and write _HI_HEADER_*=0
# lines for whichever are turned off into common/header.sh, where they're
# already documented and checked. Skipped entirely if the header itself is
# off, since asking about its pieces would be moot.
function config_header_details() {
  local target="$_HI_ROOT/common/header.sh"
  local dis_ts="" dis_sys="" dis_id="" dis_chk=""
  if ! setting_enabled _HI_DISABLE_HEADER "$_HI_ROOT/common/paths.sh" 1; then
    return 0
  fi
  _hi_h2 "Choosing header details"
  ask_setting _HI_HEADER_TIMESTAMP " Show the timestamp line?" "$target" 0 timestamp ||
    dis_ts="export _HI_HEADER_TIMESTAMP=0"
  ask_setting _HI_HEADER_SYSINFO " Show the system info line (OS, CPU, RAM)?" "$target" 0 system_info ||
    dis_sys="export _HI_HEADER_SYSINFO=0"
  ask_setting _HI_HEADER_IDENTITY " Show the git identity/docker/ssh key line?" "$target" 0 identity ||
    dis_id="export _HI_HEADER_IDENTITY=0"
  ask_setting _HI_HEADER_CHECK " Show the installed-packages check?" "$target" 0 full_check ||
    dis_chk="export _HI_HEADER_CHECK=0"
  config_shell "header details" "$target" "$dis_ts" "$dis_sys" "$dis_id" "$dis_chk"
}

# Ask for the header/banner's terminal width and write it into
# common/shared.sh, where _HI_MAX_WIDTH is already documented and read.
# Entering nothing keeps whatever's already configured; entering 80 (shared.
# sh's own built-in default) clears the override instead of writing it out.
function config_max_width() {
  local target="$_HI_ROOT/common/shared.sh" current value reply=""
  current=$(grep -oE '^export _HI_MAX_WIDTH=[0-9]+' "$target" 2>/dev/null | cut -d= -f2)
  value="${current:-80}"
  if [ -t 0 ]; then
    read -r -p " Terminal width for the header/banner? [$value] " reply || reply=""
    if [ -n "$reply" ]; then
      if [[ "$reply" =~ ^[0-9]+$ ]]; then
        value="$reply"
      else
        _hi_cecho " not a number, leaving width at $value" "$YELLOW"
      fi
    fi
  fi
  [ "$value" = 80 ] && value=""
  config_shell "terminal width" "$target" "${value:+export _HI_MAX_WIDTH=$value}"
}

# Runs $shell's syntax-check flag against an existing rc file (without
# executing it) and reports what it finds. Skipped silently when $shell
# isn't installed or $target doesn't exist/is empty - nothing to validate.
function check_one_config() {
  local label="$1" target="$2" shell="$3" out
  shift 3
  command -v "$shell" >/dev/null 2>&1 || return 0
  [ -s "$target" ] || return 0
  if out="$("$@" "$target" 2>&1)"; then
    _hi_cecho " $label ($target) looks valid :)" "$GREEN"
    return 0
  fi
  _hi_cecho " $label ($target) has issues:" "$RED"
  printf '%s\n' "$out" | sed 's/^/   /'
  return 1
}

# Validates whatever of ~/.bashrc, ~/.zshrc and ~/.config/fish/config.fish
# already exist, before install.sh's own lines get appended to them. Returns
# non-zero if anything failed so callers can decide what to do about it.
function check_shell_configs() {
  _hi_h2 "Checking existing shell configs"
  local bad=0
  check_one_config bash "$_HI_HOME_BASHRC" bash bash -n || bad=1
  check_one_config zsh "$_HI_HOME_ZSHRC" zsh zsh -n || bad=1
  check_one_config "config.fish" "$_HI_HOME_FISH_CONFIG" fish fish --no-execute || bad=1
  return $bad
}

# Gate the install on check_shell_configs: if issues turn up, ask whether to
# proceed anyway. Non-interactive runs (no tty) continue automatically rather
# than hang on a prompt nobody can answer - same convention as ask_setting.
function config_validate_shells() {
  check_shell_configs && return 0
  _hi_cecho " found issues in your existing shell config(s) above" "$YELLOW"
  if [ ! -t 0 ]; then
    _hi_cecho " non-interactive run, continuing anyway" "$YELLOW"
    return 0
  fi
  local reply=""
  read -r -p " Continue installing anyway? [y/N] " reply || reply=""
  [[ "$reply" =~ ^[Yy] ]] && return 0
  _hi_cecho " aborting install" "$RED"
  exit 1
}

function config_hi() {
  _hi_h2 "Checking hi.sh"
  chmod +x "$_HI_LAUNCHER"
  if [ "$(readlink "$_HI_LINK" 2>/dev/null)" = "$_HI_LAUNCHER" ]; then
    _hi_cecho " $_HI_LINK already points at $_HI_LAUNCHER :)" "$GREEN"
    return 0
  fi
  _hi_cecho " Linking $_HI_LINK -> $_HI_LAUNCHER... [password required]" "$BLUE"
  sudo ln -sfn "$_HI_LAUNCHER" "$_HI_LINK"
}

# lets tests/install_test.sh `source` this file to reach the functions above
# (config_shell, ask_setting, ...) without running the real install below -
# config_hi's sudo call in particular has no business firing from a test
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

if [ -n "$_HI_CHECK_CONFIGS_ONLY" ]; then
  _hi_h1 "Checking existing shell configs!"
  _hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | login shell: ${SHELL##*/}" "$BLUE"
  check_shell_configs
  exit $?
fi

if [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Configuring hi.sh features!"
else
  _hi_h1 "Installing (or reinstalling) hi.sh!"
fi
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | login shell: ${SHELL##*/}" "$BLUE"

if [ -z "$_HI_FEATURES_ONLY" ]; then
  config_validate_shells
fi

config_features
config_header_details
config_max_width

if [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Features updated!"
  exit 0
fi

config_shell bashrc "$_HI_HOME_BASHRC" \
  "$(tmpdir_line sh)" \
  '[[ $- != *i* ]] && return' \
  "source \"$_HI_BASHRC\""

config_shell zshrc "$_HI_HOME_ZSHRC" \
  "$(tmpdir_line sh)" \
  "source \"$_HI_ZSHRC\""

config_shell config.fish "$_HI_HOME_FISH_CONFIG" \
  "$(tmpdir_line fish)" \
  'if status is-interactive' \
  "  source \"$_HI_FISH_CONFIG\"" \
  'end'

config_hi

_hi_h1 "Installed!"
