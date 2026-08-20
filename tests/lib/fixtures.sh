#!/bin/bash
# World-building for a case: fake and real PATHs, git and settings fixtures, a
# scratch tree, and the string helpers that read what came back out.
#
# Part of the tests/test_lib.sh harness; sourced by it, never on its own.
# GLOSSARY: HI.30
# shellcheck disable=SC2329

# _hi_strip_ansi <text> - the palette taken back out, for suites asserting on
# geometry or plain content. The inverse of _hi_rendered, and one home for a
# regex that was hand-written in six suites, where a silent stop-matching is
# the failure mode.
function _hi_strip_ansi() {
  local out="$1" restore=0
  shopt -q extglob || {
    shopt -s extglob
    restore=1
  }
  out="${out//$'\e'\[*([0-9;])m/}"
  ((restore)) && shopt -u extglob
  printf '%s' "$out"
}

# _hi_table_is_rectangular <text> - every line of every boxed table in <text>
# is the same printed width. Both preview suites assert it through this one
# function, so they cannot segment tables differently. A table is a run of
# adjacent lines starting with `+` or `|`, so blank lines and prose between
# two tables separate them without being measured.
function _hi_table_is_rectangular() {
  local line stripped width=0 len seen=0
  while IFS= read -r line; do
    stripped="$(_hi_strip_ansi "$line")"
    case "$stripped" in
    [+\|]*)
      len=${#stripped}
      if [ "$width" -eq 0 ]; then
        width=$len
        seen=1
      elif [ "$len" -ne "$width" ]; then
        return 1
      fi
      ;;
    # anything else ends the current table; the next run measures itself afresh,
    # since two tables in one output need not share a width
    *) width=0 ;;
    esac
  done <<<"$1"
  [ "$seen" -eq 1 ]
}

# _hi_check_requires <bin> <label> <predicate...> - _hi_check, unless <bin> is
# missing, in which case the case counts as SKIPPED. The guard lives here, not
# inside the case body, where a `return 0` would report a green OK for a case
# that never ran.
function _hi_check_requires() {
  local bin="$1"
  shift
  if command -v "$bin" >/dev/null 2>&1; then
    _hi_check "$@"
  else
    _hi_skip "$1" "no $bin"
  fi
}

# _hi_fake_path <name> <bin...> - a $_HI_WORKDIR/<name> directory of no-op
# executables, printed - for suites that prove a resolution ladder
# ("candidate X is missing, does it fall through to Y") against a PATH they
# control rather than against whatever this machine has. Built once per name:
# the callers ask for the same set many times over.
function _hi_fake_path() {
  local dir="$_HI_WORKDIR/$1" bin
  shift
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    for bin in "$@"; do
      printf '%s\n' '#!/bin/sh' 'exit 0' >"$dir/$bin"
      chmod +x "$dir/$bin"
    done
  fi
  printf '%s' "$dir"
}

# _hi_real_path <name> <tool...> - the real-binary half of _hi_fake_path, same
# build-once-per-name contract: a $_HI_WORKDIR/<name> directory of symlinks to
# the named tools as this machine resolves them, printed. For suites that
# replace $PATH outright and still need a few real tools on it. A tool the
# machine doesn't have is skipped, so the caller's cases fail (or skip) on the
# missing tool itself rather than on the toolbox build.
function _hi_real_path() {
  local dir="$_HI_WORKDIR/$1" tool
  shift
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    for tool in "$@"; do
      command -v "$tool" >/dev/null 2>&1 && ln -sf "$(command -v "$tool")" "$dir/$tool"
    done
  fi
  printf '%s' "$dir"
}

# _hi_git_fixture - a fresh one-commit repo on a branch literally named "main"
# (forced via symbolic-ref, so git's initial-branch config can't decide it),
# printed. Built once per suite as a template, then copied per call: every
# caller wants the identical starting point, and one `cp -r` is one process
# where building from scratch is six git invocations. Each call still gets its
# own private directory, so nothing leaks between cases - only the setup cost
# is shared. The template holds one clean tracked file.txt; cases wanting
# another branch or a dirty tree arrange that themselves.
function _hi_git_fixture() {
  local dir template="$_HI_WORKDIR/git-template"
  if [ ! -d "$template" ]; then
    mkdir -p "$template"
    git -C "$template" init -q
    git -C "$template" symbolic-ref HEAD refs/heads/main
    git -C "$template" config user.email test@example.com
    git -C "$template" config user.name "Test"
    printf 'one\n' >"$template/file.txt"
    git -C "$template" add file.txt
    git -C "$template" commit -q -m initial
  fi
  dir="$(mktemp -d "$_HI_WORKDIR/repo.XXXXXX")"
  cp -r "$template/." "$dir/"
  printf '%s' "$dir"
}

# _hi_probe_shims <dir> [running-name] - fake docker/podman/nomad/kubectl in
# <dir>, each answering only the exact invocations hi.sh's backend predicates
# make (plus docker/podman's bare `ps`, doctor.sh's liveness probe) and
# failing anything else, so a changed command shape shows up as a failing
# predicate rather than a silently passing test. The target named
# <running-name> (default "yes") is running; anything else is not. The argv
# shapes spelled out here are the suite-side statement of that contract - one
# home, next to _hi_probe_cmd, rather than a copy per suite.
function _hi_probe_shims() {
  local dir="$1" running="${2:-yes}"
  mkdir -p "$dir"

  cat >"$dir/docker" <<EOF
#!/bin/sh
[ "\$1" = ps ] && exit 0
[ "\$1 \$2 \$3" = "container inspect -f" ] || exit 1
case "\$5" in $running) printf 'true\n' ;; *) printf 'false\n' ;; esac
EOF

  # podman is a drop-in for docker in hi.sh, so the shim is the same file
  cp "$dir/docker" "$dir/podman"

  cat >"$dir/nomad" <<EOF
#!/bin/sh
[ "\$1 \$2 \$3" = "alloc status -t" ] || exit 1
case "\$5" in $running) printf 'running\n' ;; *) printf 'pending\n' ;; esac
EOF

  cat >"$dir/kubectl" <<EOF
#!/bin/sh
[ "\$1 \$2 \$4" = "get pod -o" ] || exit 1
case "\$3" in $running) printf 'Running\n' ;; *) printf 'Pending\n' ;; esac
EOF

  chmod +x "$dir/docker" "$dir/podman" "$dir/nomad" "$dir/kubectl"
}

# _hi_alias_probe <shell> <name> [NAME=VALUE ...] - "yes"/"no": does sourcing
# paths.sh then aliases.sh in a real <shell> leave alias (fish: function)
# <name> defined? The fish-vs-POSIX dialect split lives here once rather than
# per suite. _HI_CLEANUP is scrubbed so the runner's own session state can't
# decide a tree-lifetime-gated alias; extra NAME=VALUE pairs ride the env.
function _hi_alias_probe() {
  local shell="$1" name="$2" script
  shift 2
  if [ "$shell" = fish ]; then
    script="source $_HI_ROOT/common/paths.sh; source $_HI_ALIASES; functions -q -- $name; and echo yes; or echo no"
  else
    script=". $_HI_ROOT/common/paths.sh; . $_HI_ALIASES; alias $name >/dev/null 2>&1 && echo yes || echo no"
  fi
  env -u _HI_CLEANUP _HI_HOME="$_HI_HOME" "$@" "$shell" -c "$script" 2>/dev/null
}

# _hi_scratch_tree <name> <dir...> - a throwaway hi.d under $_HI_WORKDIR/<name>
# holding copies of the named top-level directories, and prints the _HI_HOME
# that points at it. What a "minimal shipped tree" needs is one edit here
# rather than one per suite that stands one up.
function _hi_scratch_tree() {
  local name="$1" root="$_HI_WORKDIR/$1/hi.d" dir
  shift
  mkdir -p "$root"
  for dir in "$@"; do cp -r "$_HI_ROOT/$dir" "$root/"; done
  printf '%s' "$_HI_WORKDIR/$name"
}

# _hi_settings_fixture <name> <fn...> - run <fn...> with $_HI_ROOT,
# $_HI_CONFIG_DIR and $_HI_SETTINGS pointed at throwaway paths under
# $_HI_WORKDIR/<name>. scripts/install.sh's writers (config_shell,
# ensure_settings_shebang) and its uninstall half (strip_settings) all reach for
# those three, which in a real run are this very checkout and the developer's
# own overlay - the same shadowing load_test.sh's _hi_clean_all wrapper does
# before letting clean_all near $_HI_ROOT.
#
# The scratch overlay is deliberately a *different* directory from the scratch
# tree's misc/, so "writes land outside the tree" is something the tests can see
# rather than assume.
function _hi_settings_fixture() {
  local dir="$_HI_WORKDIR/$1"
  local _HI_ROOT="$dir" _HI_CONFIG_DIR="$dir/config"
  local _HI_SETTINGS="$dir/config/settings.sh"
  mkdir -p "$dir/common" "$dir/misc" "$dir/config"
  shift
  "$@" >/dev/null
}

# where _hi_settings_fixture's run writes, as the assertions see it
function _hi_fixture_settings() { printf '%s' "$_HI_WORKDIR/$1/config/settings.sh"; }

# The suites' small <key> -> <value> maps (which shell image built, where a
# binary is), as a newline-separated "<key>=<value>" string in a plain variable:
# associative arrays are bash 4 and macOS still ships bash 3.2, where `local -A`
# is a fatal "invalid option". _hi_kv_set appends and _hi_kv_get returns the
# *last* value set for a key, so re-setting one wins with no rewriting.
_HI_KV_NL=$'\n'

# _hi_kv_set <var> <key> <value> - eval, because bash 3.2 has no namerefs; the
# caller's `local` is reachable through bash's dynamic scoping either way.
function _hi_kv_set() {
  local _hi_kv_var="$1" _hi_kv_key="$2" _hi_kv_value="$3"
  eval "$_hi_kv_var=\"\${$_hi_kv_var:-}\$_hi_kv_key=\$_hi_kv_value\$_HI_KV_NL\""
}

# _hi_kv_get <var> <key> - print the value, non-zero if the key was never set
function _hi_kv_get() {
  local _hi_kv_var="$1" _hi_kv_key="$2" _hi_kv_store _hi_kv_entry found="" rc=1
  eval "_hi_kv_store=\${$_hi_kv_var:-}"
  while IFS= read -r _hi_kv_entry; do
    [ "${_hi_kv_entry%%=*}" = "$_hi_kv_key" ] || continue
    found="${_hi_kv_entry#*=}"
    rc=0
  done <<<"$_hi_kv_store"
  printf '%s' "$found"
  return "$rc"
}

# _hi_transcript_is_clean <label> <transcript-file> - fail if the session
# printed shell error noise.
#
# The assertion the bash 3.2 cases need, because a bash-4-only builtin on an old
# bash is rarely *fatal*: `mapfile ... && count=${#lines[@]}` just stops that
# one AND-list, `shopt -s globstar` complains and carries on, and load() has
# already turned `set -e` back off by the time the header runs. The session
# still comes up and every marker still lands - it simply spits
# "mapfile: command not found" at the user on every connect, which is the actual
# bug reported from macOS and the thing no other check here would notice.
_HI_SHELL_ERROR_RE='command not found|invalid option|unbound variable|bad substitution|syntax error|not a valid identifier'

function _hi_transcript_is_clean() {
  local label="$1" file="$2" hits
  hits="$(grep -nE "$_HI_SHELL_ERROR_RE" "$file" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    _hi_align " | [$label] -- transcript is free of shell errors" "OK" "$GREEN"
    return 0
  fi
  _hi_h3 " | [$label] -- FAILED: the session printed shell errors" "$RED"
  printf '%s\n' "$hits" | sed 's/^/      /'
  _hi_note_failure "[$label] transcript has shell errors"
  return 1
}

function _hi_rendered() {
  printf '%b' "$1"
}

function _hi_has_rendered() {
  local needle
  printf -v needle '%b' "$2"
  [[ "$1" == *"$needle"* ]]
}
