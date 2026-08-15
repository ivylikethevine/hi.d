#!/bin/bash
# Points the local shells at hi.d's configs and links hi.sh onto $PATH.
# Safe to re-run: it repairs the lines it owns and leaves everything else alone.
set -euo pipefail

_HI_FEATURES_ONLY=""
_HI_CHECK_CONFIGS_ONLY=""
_HI_ASSUME_YES=0
# one `shift` after the case, not one per arm: an arm added without its own was
# an infinite loop
while [ $# -gt 0 ]; do
  case "$1" in
  --features-only) _HI_FEATURES_ONLY=1 ;;
  --check-configs) _HI_CHECK_CONFIGS_ONLY=1 ;;
  -y | --yes) _HI_ASSUME_YES=1 ;;
  -h | --help)
    cat <<'EOF'
Usage: install.sh [--features-only] [--check-configs] [--yes]

Wires up the local shells to source this hi.d checkout and links hi.sh onto
PATH. Safe to re-run any time - it repairs its own lines and leaves
everything else alone. The install location is always wherever this script
lives (hi.d's parent directory), not a path you pass in - hi.d installs in
place.

Note: this needs sudo to link hi.sh into /usr/bin, and every prompt keeps
its current setting when there is no tty to answer on.

  --features-only  Skip the shell rc wiring and the hi.sh symlink - just
                   re-run the feature toggle prompts. This is what
                   `hi_configure` calls once hi.d is installed.
  --check-configs  Only run the pre-install validation of your existing
                   ~/.bashrc, ~/.zshrc and ~/.config/fish/config.fish -
                   skip everything else. This is what `hi_check_configs`
                   calls.
  -y, --yes        Install even if that validation finds problems. Without
                   it, a non-interactive run stops rather than rewriting
                   shell configs that don't parse.
EOF
    exit 0
    ;;
  *)
    echo "install.sh: unrecognized argument: $1" >&2
    echo "Usage: install.sh [--features-only] [--check-configs] [--yes]" >&2
    exit 1
    ;;
  esac
  shift
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

# $_HI_MARKER/$_HI_LINK (common/paths.sh) and config_shell/strip_marker
# (common/rcfile.sh) are shared with scripts/uninstall.sh, which has to
# recognise exactly what this writes.
# shellcheck source=../common/rcfile.sh
source "$_HI_ROOT/common/rcfile.sh"

# Only emit an _HI_HOME export when hi.d isn't at $HOME/hi.d; every consumer
# already defaults it to $HOME.
function tmpdir_line() {
  [ "$_HI_HOME" = "$HOME" ] && return 0
  case "$1" in
  fish) printf 'set -gx _HI_HOME "%s"' "$_HI_HOME" ;;
  *) printf 'export _HI_HOME="%s"' "$_HI_HOME" ;;
  esac
}

# Answers this run has already taken, keyed by variable name - fresher than
# $_HI_SETTINGS, which still holds the previous run's. Both they and the
# file-backed default are read through setting_off below, so there is one
# accessor rather than three readers of the same store.
declare -A _HI_SETTING_PENDING=()

# true if $1 is turned off - this run's answer if it has one, otherwise
# "export $1=$3" being present in $2. hi's own _HI_DISABLE_* vars use 1 for
# "off"; common/header.sh's older per-line toggles use 0, hence the third
# argument.
function setting_off() {
  local var="$1" target="$2" off="${3:-1}"
  if [ -n "${_HI_SETTING_PENDING[$var]+x}" ]; then
    [ "${_HI_SETTING_PENDING[$var]}" = "$off" ]
    return
  fi
  grep -qE "^export $var=$off" "$target" 2>/dev/null
}

function setting_enabled() {
  ! setting_off "$@"
}

# Ask a yes/no question about one setting, defaulting to its current state.
# $5, if given, is a zero-arg function whose output is boxed as a live preview
# after the question text, so the question reads first and the preview
# illustrates the answer. Non-interactive runs (no tty) keep whatever is
# already configured rather than hanging on a prompt nobody can answer, and
# skip the preview since the question is auto-answered.
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

# visible width of $1: printable characters once ANSI SGR codes are stripped,
# since the raw length color escapes inflate is meaningless for alignment.
# extglob is needed for the +(...) pattern and restored to whatever it was,
# rather than left on for the rest of the script.
function _hi_visible_len() {
  local stripped restore=0
  shopt -q extglob || { shopt -s extglob; restore=1; }
  stripped="${1//$'\e'\[+([0-9;])m/}"
  ((restore)) && shopt -u extglob
  printf '%s' "${#stripped}"
}

# Run $@ and box what it writes to stdout - a live render using hi's own
# functions, sized to its longest line rather than the terminal width, since
# previews range from one short colored line to full_check's wrapped block.
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

# banner() takes an arg, so wrap it to the zero-arg signature ask_setting's $5
# expects. _HI_HEADER_BANNER is unset for the call (in a subshell), or a
# previously-disabled toggle would render an empty preview of the very thing
# being asked about.
function _hi_banner_preview() { (unset _HI_HEADER_BANNER && banner Connected); }

# sample "user@host cwd" line, colored like shells/bash.sh's real HI_PS1, with
# the literal current user/host/cwd instead of \u/\h/\w
function _hi_prompt_preview() {
  local cwd="${PWD/#$HOME/\~}"
  printf '%b\n' " $(_hi_user_escape)$(whoami)$(_hi_at_color)@$(_hi_host_escape)$(_hi_hostname)$NC $BRBLUE$cwd$NC"
}

# the real git prompt segment against hi.d's own checkout (always a git repo),
# so the preview shows this machine's actual status. _HI_DISABLE_GIT_STATUS is
# unset for the call, or a previously-disabled toggle makes it return empty.
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

# Every setting the config_* groups decide on, written to $_HI_SETTINGS in one
# go at the bottom of this file: config_shell rewrites the *whole* marker block
# in its target, so one call per group against one file would each wipe the
# others. An ordered array rather than the map above, because config_shell
# compares what it would write against what is there to decide whether the file
# is up to date - so the write order has to be stable across runs.
declare -a _HI_SETTING_LINES=()

# The two prompt groups as tables: <var>|<off-value>|<preview-fn>|<question>,
# in the order they are asked and written. Adding a setting is one row.
_HI_FEATURE_PROMPTS=(
  "_HI_DISABLE_HEADER|1|_hi_banner_preview| Enable the connect/disconnect header (system info, git identity, package check)?"
  "_HI_DISABLE_PROMPT|1|_hi_prompt_preview| Enable the colored user@host prompt?"
  "_HI_DISABLE_PERSONAL|1|| Enable personal shell settings (history size, keybindings, completion tweaks)?"
  "_HI_DISABLE_GIT_STATUS|1|_hi_git_status_preview| Enable git status in the prompt?"
  "_HI_DISABLE_EDITORS|1|_hi_editors_preview| Enable the vim/nano config overrides?"
  "_HI_DISABLE_ALIASES|1|_hi_aliases_preview| Enable the personal aliases in shells/aliases.sh (sudo, cat/eza, git, docker, pacman/apt, etc)?"
  "_HI_DISABLE_LOCAL|1|| Enable all of the above on this machine (the one hi.d is installed on), not just when you hi elsewhere?"
)

_HI_HEADER_PROMPTS=(
  "_HI_HEADER_BANNER|0|_hi_banner_preview| Show the connect/disconnect banner line?"
  "_HI_HEADER_TIMESTAMP|0|timestamp| Show the timestamp line?"
  "_HI_HEADER_SYSINFO|0|system_info| Show the system info line (OS, CPU, RAM)?"
  "_HI_HEADER_IDENTITY|0|identity| Show the git identity/docker/ssh key line?"
  "_HI_HEADER_CHECK|0|full_check| Show the installed-packages check?"
)

# Ask every row of the table named by $1, recording the off-value for whichever
# ones were turned off.
function ask_prompt_group() {
  local -n rows="$1"
  local row var off preview question target="$_HI_SETTINGS"
  for row in "${rows[@]}"; do
    IFS='|' read -r var off preview question <<<"$row"
    ask_setting "$var" "$question" "$target" "$off" "$preview" && continue
    _HI_SETTING_PENDING["$var"]="$off"
    _HI_SETTING_LINES+=("export $var=$off")
  done
}

# Prompt for the optional pieces of hi's shell config. $_HI_SETTINGS is sourced
# by every shell (including fish) ahead of common/paths.sh, so the choice
# applies locally and on every host hi.d gets copied to.
function config_features() {
  _hi_h2 "Choosing features"
  ask_prompt_group _HI_FEATURE_PROMPTS
}

# Prompt for the header's optional detail lines. Skipped entirely if the header
# itself is off, since asking about its pieces would be moot - and that reads
# the answer config_features just took, not the file, which still holds the old
# one.
function config_header_details() {
  setting_off _HI_DISABLE_HEADER "$_HI_SETTINGS" 1 && return 0
  _hi_h2 "Choosing header details"
  ask_prompt_group _HI_HEADER_PROMPTS
}

# Ask for the header/banner's terminal width. Entering nothing keeps whatever's
# already configured; entering 80 (common/shared.sh's own built-in default,
# via ${_HI_MAX_WIDTH:-80}) clears the override instead of writing it out.
function config_max_width() {
  local target="$_HI_SETTINGS" current value reply=""
  current="$(grep -oE '^export _HI_MAX_WIDTH=[0-9]+' "$target" 2>/dev/null | cut -d= -f2)"
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
  _HI_SETTING_LINES+=("${value:+export _HI_MAX_WIDTH=$value}")
}

# $_HI_SETTINGS is hi's own file, not one of the user's rc files, and it holds
# nothing but `export NAME=value` lines - so it gets a real `#!/bin/sh` line 1,
# which every shell that sources it (sh, bash, zsh, fish) reads as a comment
# and which lets editors, `file` and shellcheck see a POSIX sh script rather
# than an anonymous fragment. Any other shebang is replaced rather than left
# alongside: dash and fish both source this, so sh is the only correct one.
# config_shell rewrites only its own marker-tagged block, so this line stays.
function ensure_settings_shebang() {
  local shebang='#!/bin/sh' first="" tmpfile
  mkdir -p "$(dirname "$_HI_SETTINGS")"
  if [ -f "$_HI_SETTINGS" ]; then
    IFS= read -r first <"$_HI_SETTINGS" || first=""
  fi
  [ "$first" = "$shebang" ] && return 0

  tmpfile="$(mktemp -t hi.settings.XXXXXX)"
  printf '%s\n' "$shebang" >"$tmpfile"
  if [ -f "$_HI_SETTINGS" ]; then
    case "$first" in
    '#!'*) tail -n +2 "$_HI_SETTINGS" >>"$tmpfile" ;;
    *) cat "$_HI_SETTINGS" >>"$tmpfile" ;;
    esac
  fi
  mv "$tmpfile" "$_HI_SETTINGS"
}

# Runs $@'s syntax-check flag against an existing rc file (without executing it)
# and reports what it finds. Skipped silently when the shell isn't installed or
# $target is missing/empty. The shell is read off the front of $@ rather than
# passed twice, which every call site had to keep in agreement.
function check_one_config() {
  local label="$1" target="$2" out
  shift 2
  command -v "$1" >/dev/null 2>&1 || return 0
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
  check_one_config bash "$_HI_HOME_BASHRC" bash -n || bad=1
  check_one_config zsh "$_HI_HOME_ZSHRC" zsh -n || bad=1
  check_one_config "config.fish" "$_HI_HOME_FISH_CONFIG" fish --no-execute || bad=1
  return $bad
}

# Gate the install on check_shell_configs. Unlike ask_setting, a
# non-interactive run does *not* wave this through: install.sh rewrites the
# very files that failed to parse and nobody is watching. --yes decides up front.
function config_validate_shells() {
  check_shell_configs && return 0
  _hi_cecho " found issues in your existing shell config(s) above" "$YELLOW"
  if [ "$_HI_ASSUME_YES" = 1 ]; then
    _hi_cecho " --yes given, continuing anyway" "$YELLOW"
    return 0
  fi
  if [ ! -t 0 ]; then
    _hi_cecho " non-interactive run and the configs above look broken - aborting" "$RED"
    _hi_cecho " re-run with --yes to install over them anyway" "$YELLOW"
    exit 1
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

# lets tests/scripts/install_test.sh `source` this file to reach the functions above
# (config_shell, ask_setting, ...) without running the real install below -
# config_hi's sudo call in particular has no business firing from a test
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

if [ -n "$_HI_CHECK_CONFIGS_ONLY" ]; then
  _hi_h1 "Checking existing shell configs!"
elif [ -n "$_HI_FEATURES_ONLY" ]; then
  _hi_h1 "Configuring hi.sh features!"
else
  _hi_h1 "Installing (or reinstalling) hi.sh!"
fi
_hi_cecho " | hi_home: $_HI_HOME | hi_root: $_HI_ROOT | login shell: ${SHELL##*/}" "$BLUE"

if [ -n "$_HI_CHECK_CONFIGS_ONLY" ]; then
  check_shell_configs
  exit $?
fi

if [ -z "$_HI_FEATURES_ONLY" ]; then
  config_validate_shells
fi

config_features
config_header_details
config_max_width
# One write for all three groups above, for the reason _HI_SETTING_LINES
# documents: config_shell rewrites the whole marker block in its target, so
# three separate calls against one file would each wipe the other two.
ensure_settings_shebang
config_shell settings "$_HI_SETTINGS" "${_HI_SETTING_LINES[@]}"

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
