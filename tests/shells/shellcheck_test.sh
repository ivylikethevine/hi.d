#!/bin/bash
# The repo's lint gate. shellcheck covers every *.sh file; on top of that, every
# file a non-bash shell parses for itself is run through that shell's own syntax
# checker (`zsh -n` / `fish --no-execute`) - see $_HI_NATIVE_LINT below. Without
# that second half, shells/zsh.zsh and shells/config.fish are checked by nothing
# at all, and the files fish and zsh share with sh are only ever checked as sh.
# Two more halves ride along when their tool is installed (and skip yellow when
# not): shfmt as a formatting gate, and checkbashisms over the #!/bin/sh files.
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# "<file>:<shell>:<flag...>", one per file/shell pair shellcheck's own reading
# doesn't cover. Skipped with a warning when that shell isn't installed: these
# supplement the gate rather than being it, unlike the shellcheck run below,
# whose absence is a hard failure.
# (A comment line here must never *begin* with the word shellcheck - that reads
# as a directive and fails the very lint this file runs.)
#
# Two kinds of entry. shells/zsh.zsh and shells/config.fish are not shell the
# linter can parse at all, so their own shell's syntax checker (`zsh -n` /
# `fish --no-execute`, the same two scripts/install.sh runs against the user's
# rc files) is the only thing checking them.
#
# The rest are files shellcheck *does* read - as sh or bash - that another shell
# also sources for real, so they have to parse in both. misc/aliases.sh and
# common/paths.sh are the two fish sources directly, and the failure mode there
# is silent: a perfectly good `${X:-0}` is a fish parse error that aborts the
# whole file, taking every alias (or every path) with it. zsh reaches
# common/core.sh, common/git_prompt.sh and both of those through shells/zsh.zsh.
_HI_NATIVE_LINT=(
  "shells/zsh.zsh:zsh:-n"
  "shells/config.fish:fish:--no-execute"
  "misc/aliases.sh:fish:--no-execute"
  "common/paths.sh:fish:--no-execute"
  "misc/aliases.sh:zsh:-n"
  "common/paths.sh:zsh:-n"
  "common/core.sh:zsh:-n"
  "common/git_prompt.sh:zsh:-n"
)

# Syntax-check the files above, returning how many failed. Adds its files to
# $_HI_LINT_TOTAL so the suite's reported tally covers everything it checked,
# not just the shellcheck half.
function lint_native() {
  local entry file shell flag out bad=0
  for entry in "${_HI_NATIVE_LINT[@]}"; do
    IFS=: read -r file shell flag <<<"$entry"
    if ! command -v "$shell" >/dev/null 2>&1; then
      _hi_skip " | $file" "no $shell to check it with"
      continue
    fi
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if out="$("$shell" "$flag" "$_HI_ROOT/$file" 2>&1)"; then
      _hi_cecho " | $file ($shell $flag): OK" "$GREEN"
    else
      _hi_cecho " | $file ($shell $flag): FAILED" "$RED"
      printf '%s\n' "$out" | sed 's/^/      /'
      _hi_note_failure "$file ($shell $flag)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

# The bash-4-only constructs, as "<pattern>|<what it is>". macOS still ships
# bash 3.2 and hi has to run there, but shellcheck can't help: every one of
# these is valid bash, just not valid *old* bash, and most of them fail loudly
# at runtime rather than at parse time (see tests/targets/ssh_test.sh's bash32
# cases for the same rule enforced end-to-end against a real 3.2).
#
# The last entry isn't a version issue at all - ${!a[@]+...} is a trap in both
# directions: bash 3.2 quietly expands it to nothing whatever the array holds,
# and bash 5 reads it as an indirect reference and dies. Plain "${!a[@]}" is
# already empty-safe and is what to write instead.
# shellcheck disable=SC2016 # these are regexes and prose, not expansions
_HI_BASH32_LINT=(
  '\bmapfile\b|\breadarray\b|mapfile/readarray (bash 4) - use _hi_read_lines'
  '\b(declare|local|typeset)[[:space:]]+-[a-zA-Z]*A\b|associative arrays (bash 4)'
  '\b(declare|local|typeset)[[:space:]]+-[a-zA-Z]*n\b|namerefs (bash 4.3)'
  '\$\{[A-Za-z_][A-Za-z_0-9]*(\[[^]]*\])?(,,?|\^\^?)\}|case conversion (bash 4)'
  '\bwait[[:space:]]+-n\b|wait -n (bash 4.3)'
  '\$\{![A-Za-z_][A-Za-z_0-9]*\[[@*]\][+:-]|${!a[@]+...} - use a plain "${!a[@]}"'
)

# One file's text with the $_HI_BASH32_LINT table above blanked out - the
# patterns and their descriptions name the very constructs they look for, so
# this file would otherwise report itself. Blanked rather than deleted so the
# line numbers in a real hit still point at the right line.
function _hi_lint_source_lines() {
  awk '/^_HI_BASH32_LINT=\(/ { inside = 1 }
       inside { print ""; if (/^\)/) inside = 0; next }
       { print }' "$1"
}

# Flag every match outside a comment. Comments are excluded on purpose: half of
# these constructs are *named* in the notes explaining why they aren't used.
function lint_bash32() {
  local entry pattern what file hits bad=0 i blanks="$_HI_WORKDIR/bash32"
  _hi_h2 "Checking for bash-4-only constructs (macOS ships bash 3.2)"
  # blank each file once, not once per pattern - the awk pass is the expensive
  # half of this loop and its output is identical for every pattern
  mkdir -p "$blanks"
  i=0
  for file in "${_HI_SH_FILES[@]}"; do
    _hi_lint_source_lines "$file" >"$blanks/$i"
    i=$((i + 1))
  done
  for entry in "${_HI_BASH32_LINT[@]}"; do
    pattern="${entry%|*}"
    what="${entry##*|}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    hits=""
    i=0
    for file in "${_HI_SH_FILES[@]}"; do
      hits+="$(grep -nE "$pattern" "$blanks/$i" | grep -v ':[[:space:]]*#' |
        sed "s|^|${file#"$_HI_ROOT/"}:|" || true)"
      i=$((i + 1))
    done
    if [ -z "$hits" ]; then
      _hi_cecho " | no $what: OK" "$GREEN"
      continue
    fi
    _hi_cecho " | $what: FOUND" "$RED"
    printf '%s\n' "$hits" | sed 's/^/      /'
    _hi_note_failure "bash-4 construct: $what"
    bad=$((bad + 1))
  done
  return "$bad"
}

# The formatter as a lint: shfmt -d over the same file list shellcheck reads
# (so dist/ stays excluded). The 2-space style comes from .editorconfig, which
# shfmt picks up when invoked with no style flags. Skips yellow when shfmt is
# absent; CI pins one via .github/actions/setup-shfmt so the gate runs there.
function lint_shfmt() {
  local out
  _hi_h2 "Checking formatting (shfmt -d, style from .editorconfig)"
  if ! command -v shfmt >/dev/null 2>&1; then
    _hi_skip "shfmt" "not installed"
    return 0
  fi
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  if out="$(shfmt -d "${_HI_SH_FILES[@]}" 2>&1)"; then
    _hi_cecho " | shfmt $(shfmt --version): every file already formatted: OK" "$GREEN"
  else
    _hi_cecho " | shfmt: files need reformatting (fix with: shfmt -w .)" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    _hi_note_failure "shfmt formatting (fix with: shfmt -w .)"
    return 1
  fi
}

# Bashisms in the #!/bin/sh files slip past the main linter (they are valid
# bash, and not every POSIX deviation is flagged when checking as sh), and
# common/paths.sh really is sourced by dash/busybox sh on minimal targets -
# checkbashisms covers exactly that shebang list (first line only: the test
# files embed '#!/bin/sh' inside the shim scripts they generate). Skips yellow
# when absent; CI installs a pinned copy via .github/actions/setup-checkbashisms.
function lint_checkbashisms() {
  local file rel out bad=0
  _hi_h2 "Checking the #!/bin/sh files for bashisms (checkbashisms)"
  if ! command -v checkbashisms >/dev/null 2>&1; then
    _hi_skip "checkbashisms" "not installed"
    return 0
  fi
  for file in "${_HI_SH_FILES[@]}"; do
    head -1 "$file" | grep -q '^#!/bin/sh' || continue
    rel="${file#"$_HI_ROOT/"}"
    _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
    if out="$(checkbashisms "$file" 2>&1)"; then
      _hi_cecho " | $rel: OK" "$GREEN"
    else
      _hi_cecho " | $rel: FAILED" "$RED"
      printf '%s\n' "$out" | sed 's/^/      /'
      _hi_note_failure "$rel (checkbashisms)"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}

# Every GLOSSARY tag in the tree has to name a real `## ` heading in
# docs/GLOSSARY.md: the tags are how shipped files point at an explanation
# without carrying it, and a renamed entry would otherwise strand its tags
# silently. A tag is one entry name with optional prose after it, or two
# names joined with ` + `; each name must prefix-match some heading. Markdown
# files are excluded from the sweep - the docs *talk about* the convention.
function lint_glossary_tags() {
  local pat='# GLOSSARY' glossary="$_HI_ROOT/docs/GLOSSARY.md"
  local headings tags line tag part h ok bad=0
  _hi_h2 "Checking GLOSSARY tags against docs/GLOSSARY.md"
  _HI_LINT_TOTAL=$((_HI_LINT_TOTAL + 1))
  _hi_read_lines headings < <(sed -n 's/^## //p' "$glossary")
  _hi_read_lines tags < <(grep -rn "${pat}: " "$_HI_ROOT" \
    --exclude-dir=.git --exclude-dir=dist --exclude='*.md' 2>/dev/null || true)
  for line in "${tags[@]}"; do
    [ -n "$line" ] || continue
    tag="${line#*"${pat}": }"
    while IFS= read -r part; do
      ok=""
      for h in "${headings[@]}"; do
        case "$part" in "$h"*) ok=1 ;; esac
      done
      if [ -z "$ok" ]; then
        _hi_cecho " | unknown entry in ${line%%:*}: $part" "$RED"
        _hi_note_failure "GLOSSARY tag: $part"
        bad=$((bad + 1))
      fi
    done <<<"${tag//" + "/$'\n'}"
  done
  [ "$bad" -eq 0 ] && _hi_cecho " | every tag names a real entry: OK" "$GREEN"
  return "$bad"
}

function run_shellcheck() {
  # deliberately *not* _hi_require: every other suite skips cleanly when its
  # backend is missing, but this one is the lint gate - a missing shellcheck
  # means the check didn't run, which must not read as a pass.
  if ! command -v shellcheck >/dev/null 2>&1; then
    _hi_cecho "shellcheck is not installed" "$RED"
    exit 1
  fi

  # dist/ alongside .git: packaging/mkpkg.sh stages a *copy* of the tree
  # there, so a run after a local package build would lint every file twice -
  # inflating the count and reporting each finding against a path that is not
  # the source of it.
  _hi_read_lines _HI_SH_FILES < <(find "$_HI_ROOT" -name '*.sh' \
    -not -path '*/.git/*' -not -path "$_HI_ROOT/dist/*" | sort)
  # bin/hi is sh with no .sh suffix (basher links it by filename), so the
  # find above cannot see it - named here or it escapes every lint
  _HI_SH_FILES+=("$_HI_ROOT/bin/hi")
  _HI_LINT_TOTAL="${#_HI_SH_FILES[@]}"
  _HI_SKIPPED=0

  _hi_h1 "Running shellcheck on ${#_HI_SH_FILES[@]} files"
  _hi_h2 "Version: $(shellcheck --version | awk '/^version:/ {print $2}')"

  _hi_cecho "$(printf ' | %s\n' "${_HI_SH_FILES[@]}")" "$BLUE"

  _hi_workdir shellchecktest
  _HI_SC_LOG="$_HI_WORKDIR/shellcheck.log"

  _HI_T0="$(_hi_now)"

  _HI_SC_FAILED=0
  shellcheck -x -Calways -S style "${_HI_SH_FILES[@]}" | tee "$_HI_SC_LOG"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    # -Calways leaves ANSI codes in $_HI_SC_LOG (needed for the live colorized
    # stream above), so they have to be stripped before "^In " can match
    _HI_SC_FAILED=$(sed 's/\x1b\[[0-9;]*m//g' "$_HI_SC_LOG" | grep -oE '^In .* line [0-9]+:' | sed -E 's/^In (.*) line [0-9]+:/\1/' | sort -u | wc -l)
    _hi_note_failure "shellcheck: $_HI_SC_FAILED file(s) with findings"
  fi

  _hi_h2 "Syntax-checking the files shellcheck can't parse"
  _HI_NATIVE_FAILED=0
  lint_native || _HI_NATIVE_FAILED=$?

  _HI_BASH32_FAILED=0
  lint_bash32 || _HI_BASH32_FAILED=$?

  _HI_SHFMT_FAILED=0
  lint_shfmt || _HI_SHFMT_FAILED=$?

  _HI_CB_FAILED=0
  lint_checkbashisms || _HI_CB_FAILED=$?

  _HI_GLOSSARY_FAILED=0
  lint_glossary_tags || _HI_GLOSSARY_FAILED=$?

  _HI_LINT_FAILED=$((_HI_SC_FAILED + _HI_NATIVE_FAILED + _HI_BASH32_FAILED + _HI_SHFMT_FAILED + _HI_CB_FAILED + _HI_GLOSSARY_FAILED))
  _hi_report_counts "$_HI_LINT_TOTAL" "$_HI_LINT_FAILED" "$_HI_SKIPPED"

  local skipped=""
  [ "$_HI_SKIPPED" -gt 0 ] && skipped=", $_HI_SKIPPED skipped"
  if [ "$_HI_LINT_FAILED" -eq 0 ]; then
    _hi_h1 "Found no issues ($_HI_LINT_TOTAL files$skipped, $(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$BRGREEN"
  else
    _hi_h1 "Found issues: $_HI_LINT_FAILED/$_HI_LINT_TOTAL files$skipped ($(_hi_elapsed "$_HI_T0" "$(_hi_now)")s)" "$RED"
    exit "$_HI_LINT_FAILED"
  fi
}

run_shellcheck
