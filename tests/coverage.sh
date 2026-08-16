#!/bin/bash
# Line coverage for the bash suites via kcov - a dev tool to run occasionally,
# deliberately not wired into CI. The point is finding which arms of
# scripts/install.sh and packaging/bump.sh the ~500 fast cases never touch,
# not gating on a number.
#
# Usage: tests/coverage.sh [outdir] [runner args...]
#   outdir       where kcov writes its report (default: $TMPDIR/hi.d-coverage)
#   runner args  passed straight to test_runner.sh (default: --group fast -
#                the e2e groups need real backends and add little coverage of
#                the client-side scripts)
#
# Lives in tests/ on purpose: tests/ ships in neither the ssh payload
# ($_HI_PAYLOAD) nor the OS packages ($_HI_PACKAGE_CONTENTS), and a coverage
# harness has no business on a target.
set -euo pipefail

if [ -z "${_HI_HOME:-}" ]; then
  _HI_HOME="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export _HI_HOME
# shellcheck source=../common/core.sh
source "$_HI_HOME/hi.d/common/core.sh"

if ! command -v kcov >/dev/null 2>&1; then
  _hi_cecho " | coverage: kcov not installed - skipping (it is a dev-only tool; see your package manager)" "$YELLOW"
  exit 0
fi

_HI_COV_DIR="${1:-${TMPDIR:-/tmp}/hi.d-coverage}"
shift 2>/dev/null || true
[ $# -gt 0 ] || set -- --group fast
mkdir -p "$_HI_COV_DIR"

# kcov traces the runner and every bash child, so one invocation covers all
# suites; tests/ itself is excluded from the report - the product is the
# subject, not the harness
kcov --include-path="$_HI_HOME/hi.d" \
  --exclude-path="$_HI_HOME/hi.d/tests" \
  "$_HI_COV_DIR" \
  "$_HI_HOME/hi.d/tests/test_runner.sh" "$@"

_hi_cecho " | coverage: report in $_HI_COV_DIR/index.html" "$GREEN"

# the headline numbers for the two scripts the roadmap cares about, straight
# from kcov's merged JSON (percent_covered is a quoted string in there)
_HI_COV_JSON="$_HI_COV_DIR/kcov-merged/coverage.json"
[ -f "$_HI_COV_JSON" ] || _HI_COV_JSON="$(find "$_HI_COV_DIR" -name coverage.json 2>/dev/null | head -1)"
if [ -n "$_HI_COV_JSON" ] && [ -f "$_HI_COV_JSON" ]; then
  awk -F'"' '
    /"file"/ { file = $4 }
    /"percent_covered"/ && (file ~ /install\.sh$/ || file ~ /bump\.sh$/) {
      printf " |   %s: %s%%\n", file, $4
    }' "$_HI_COV_JSON"
fi
