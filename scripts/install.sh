#!/bin/bash
# Points the local shells at hi.d's configs and links hi.sh onto $PATH.
# Safe to re-run: it repairs the lines it owns and leaves everything else alone.
set -euo pipefail

_HI_DIR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
  --dir)
    [ $# -ge 2 ] || {
      echo "install.sh: --dir requires a path" >&2
      exit 1
    }
    _HI_DIR_ARG="$2"
    shift 2
    ;;
  --dir=*)
    _HI_DIR_ARG="${1#--dir=}"
    shift
    ;;
  -h | --help)
    cat <<'EOF'
Usage: install.sh [--dir <install-dir>]

Wires up the local shells to source this hi.d checkout and links hi.sh onto
PATH. Safe to re-run any time - it repairs its own lines and leaves
everything else alone.

  --dir <path>  Make the install location explicit instead of relying on
                wherever this script happens to be running from. hi.d must
                already be checked out at <path>/hi.d - this doesn't move
                or copy anything, it just states (and validates) the
                location, which does not have to be $HOME.
EOF
    exit 0
    ;;
  *)
    echo "install.sh: unrecognized argument: $1" >&2
    echo "Usage: install.sh [--dir <install-dir>]" >&2
    exit 1
    ;;
  esac
done

# Locate hi.d relative to this script (resolving symlinks).
_HI_SELF="${BASH_SOURCE[0]}"
while [ -L "$_HI_SELF" ]; do
  _HI_SELF_DIR="$(cd -P "$(dirname "$_HI_SELF")" && pwd)"
  _HI_SELF="$(readlink "$_HI_SELF")"
  [[ $_HI_SELF == /* ]] || _HI_SELF="$_HI_SELF_DIR/$_HI_SELF"
done
_HI_AUTO_HOME="$(cd -P "$(dirname "$_HI_SELF")/../.." && pwd)" # hi.d's parent, usually $HOME

if [ -n "$_HI_DIR_ARG" ]; then
  mkdir -p "$_HI_DIR_ARG"
  _HI_HOME="$(cd -P "$_HI_DIR_ARG" && pwd)"
  if [ "$_HI_HOME" != "$_HI_AUTO_HOME" ]; then
    echo "install.sh: --dir $_HI_DIR_ARG doesn't match where hi.d is actually checked out ($_HI_AUTO_HOME/hi.d)." >&2
    echo "This installs in place - move (or re-clone) hi.d so it lives at $_HI_HOME/hi.d, then re-run." >&2
    exit 1
  fi
else
  _HI_HOME="$_HI_AUTO_HOME"
fi
export _HI_HOME

# shellcheck source=../common/bootstrap.sh
source "$_HI_HOME/hi.d/common/bootstrap.sh"

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
# $3 (target file, checked via setting_enabled with off-value $4). Non-
# interactive runs (no tty - piped into bash, run from a script, etc.)
# silently keep whatever is already configured instead of hanging on a
# prompt nobody can answer.
function ask_setting() {
  local var="$1" question="$2" target="$3" off="${4:-1}" default hint reply=""
  setting_enabled "$var" "$target" "$off" && default=y || default=n
  if [ ! -t 0 ]; then
    [ "$default" = y ]
    return
  fi
  hint="Y/n"
  [ "$default" = n ] && hint="y/N"
  read -r -p "$question [$hint] " reply || reply=""
  [ -z "$reply" ] && reply="$default"
  [[ "$reply" =~ ^[Yy] ]]
}

# Prompt for the optional pieces of hi's shell config and write _HI_DISABLE_*
# lines for whichever ones were turned off into common/paths.sh - the one
# file every shell (including fish) sources, so the choice applies locally
# and on every host hi.d gets copied to.
function config_features() {
  local target="$_HI_ROOT/common/paths.sh"
  local dis_header="" dis_prompt="" dis_personal="" dis_git="" dis_editors=""
  _hi_h2 "Choosing features"
  ask_setting _HI_DISABLE_HEADER \
    " Enable the connect/disconnect header (system info, git identity, package check)?" "$target" ||
    dis_header="export _HI_DISABLE_HEADER=1"
  ask_setting _HI_DISABLE_PROMPT \
    " Enable the colored user@host prompt?" "$target" ||
    dis_prompt="export _HI_DISABLE_PROMPT=1"
  ask_setting _HI_DISABLE_PERSONAL \
    " Enable personal shell settings (history size, keybindings, completion tweaks)?" "$target" ||
    dis_personal="export _HI_DISABLE_PERSONAL=1"
  ask_setting _HI_DISABLE_GIT_STATUS \
    " Enable git status in the prompt?" "$target" ||
    dis_git="export _HI_DISABLE_GIT_STATUS=1"
  ask_setting _HI_DISABLE_EDITORS \
    " Enable the vim/nano config overrides?" "$target" ||
    dis_editors="export _HI_DISABLE_EDITORS=1"
  config_shell "feature toggles" "$target" \
    "$dis_header" "$dis_prompt" "$dis_personal" "$dis_git" "$dis_editors"
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
  ask_setting _HI_HEADER_TIMESTAMP " Show the timestamp line?" "$target" 0 ||
    dis_ts="export _HI_HEADER_TIMESTAMP=0"
  ask_setting _HI_HEADER_SYSINFO " Show the system info line (OS, CPU, RAM)?" "$target" 0 ||
    dis_sys="export _HI_HEADER_SYSINFO=0"
  ask_setting _HI_HEADER_IDENTITY " Show the git identity/docker/ssh key line?" "$target" 0 ||
    dis_id="export _HI_HEADER_IDENTITY=0"
  ask_setting _HI_HEADER_CHECK " Show the installed-packages check?" "$target" 0 ||
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

# _hi_cecho " ~~~~~ Installing (or reinstalling) hi.sh! ~~~~~" "$BRGREEN"
_hi_h1 "Installing (or reinstalling) hi.sh!"
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | login shell: ${SHELL##*/}" "$BLUE"

config_features
config_header_details
config_max_width

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
