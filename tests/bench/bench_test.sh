#!/bin/bash
# Benchmarks for the product's hot paths - the code every shell start, prompt,
# TAB completion and connect runs - plus the ssh payload's size budget. The
# test suite itself is deliberately NOT benchmarked. Ceilings are generous on
# purpose: the job is to catch a path getting an order of magnitude slower (a
# fork slipping into a loop, a probe losing its timeout), not to flake on a
# busy CI runner. Its own `bench` group, so `--group fast` stays fast.
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's "$@" - which SC2329 can't see. The single-quoted child scripts
# are expanded by the child shell (SC2016).
# shellcheck disable=SC2329,SC2016
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# run <cmd...> in the controlled environment rc_test.sh also uses, so local
# settings and a live backend zoo can't skew a number; probes get 1s
function _hi_bench_env() {
  env -i HOME="$_HI_WORKDIR" TERM=xterm-256color PATH="$PATH" \
    _HI_HOME="$_HI_HOME" _HI_CONFIG_DIR="$_HI_WORKDIR/cfg" \
    _HI_PROBE_TIMEOUT=1 _HI_TARGETS_TTL=5 "$@" </dev/null
}

# _hi_bench <label> <ceiling-ms> <n> <cmd...> - average of n runs against a
# generous ceiling, reported either way so the numbers are in every CI log
function _hi_bench() {
  local label="$1" ceiling="$2" n="$3" i t0 t1 avg
  shift 3
  t0="$(_hi_now)"
  for ((i = 0; i < n; i++)); do "$@" >/dev/null 2>&1 || true; done
  t1="$(_hi_now)"
  avg="$(awk -v a="$t0" -v b="$t1" -v n="$n" 'BEGIN { printf "%.1f", (b - a) * 1000 / n }')"
  if awk -v x="$avg" -v c="$ceiling" 'BEGIN { exit !(x <= c) }'; then
    _hi_cecho " | $label: ${avg}ms avg (ceiling ${ceiling}ms, n=$n): OK" "$GREEN"
  else
    _hi_cecho " | $label: ${avg}ms avg BLEW the ${ceiling}ms ceiling (n=$n)" "$RED"
    return 1
  fi
}

function bench_bash_startup() {
  _hi_bench "bash rc (shells/bash.sh)" 500 10 \
    _hi_bench_env bash -c 'source "$_HI_HOME/hi.d/shells/bash.sh"'
}

function bench_zsh_startup() {
  _hi_bench "zsh rc (shells/zsh.zsh)" 500 10 \
    _hi_bench_env zsh -c 'source "$_HI_HOME/hi.d/shells/zsh.zsh"'
}

function bench_fish_startup() {
  _hi_bench "fish rc (shells/config.fish)" 500 10 \
    _hi_bench_env fish -c 'source $_HI_HOME/hi.d/shells/config.fish'
}

# the connect banner the user watches before getting a shell; backend probes
# are capped at 1s each by the env above
function bench_header() {
  _hi_bench "header (hi_header Online)" 3000 3 \
    _hi_bench_env bash -c 'source "$_HI_HOME/hi.d/common/header.sh"; hi_header Online'
}

# per-prompt cost: many calls inside ONE shell, so the number is the
# function's, not bash's startup
function bench_git_prompt() {
  _hi_bench "git prompt (50 calls, one shell)" 2500 1 \
    _hi_bench_env bash -c '
      source "$_HI_HOME/hi.d/common/core.sh"
      source "$_HI_HOME/hi.d/common/git_prompt.sh"
      cd "$_HI_HOME/hi.d" || exit 1
      for ((i = 0; i < 50; i++)); do _hi_git_prompt out; done'
}

# what every TAB after `hi ` pays: once cold, then against the warm cache
function bench_targets_cold() {
  _hi_bench "targets.sh, cold cache" 2000 3 \
    _hi_bench_env env _HI_TARGETS_TTL=0 sh "$_HI_TARGETS"
}

function bench_targets_warm() {
  _hi_bench_env sh "$_HI_TARGETS" >/dev/null 2>&1 || true # prime the cache
  _hi_bench "targets.sh, warm cache" 500 5 _hi_bench_env sh "$_HI_TARGETS"
}

# The wire budget: the payload built exactly the way hi.sh builds it, against
# a byte ceiling. Catches the payload quietly growing (a new file sneaking
# into $_HI_PAYLOAD's directories, comments ballooning) long before anyone
# notices a slow connect.
function bench_payload_size() {
  local bytes budget=49152
  set -- # hi.sh reads "$@"; make sure it sees none (same as hi_test.sh)
  # shellcheck source=../../hi.sh
  source "$_HI_LAUNCHER"
  bytes="$(tar czf - -h -C "$_HI_HOME" "${_HI_PAYLOAD[@]/#/hi.d/}" | wc -c)"
  if ((bytes <= budget)); then
    _hi_cecho " | payload: $bytes bytes gzipped (budget $budget): OK" "$GREEN"
  else
    _hi_cecho " | payload: $bytes bytes gzipped BLEW the $budget budget" "$RED"
    return 1
  fi
}

function run_bench_tests() {
  _hi_workdir benchtest
  mkdir -p "$_HI_WORKDIR/cfg"

  _hi_suite_begin

  _hi_h1 "Benchmarking hi's hot paths"

  _hi_h2 "Benchmark: shell startup"
  _hi_case bench_bash_startup
  if command -v zsh >/dev/null 2>&1; then _hi_case bench_zsh_startup; else _hi_skip "zsh rc" "no zsh"; fi
  if command -v fish >/dev/null 2>&1; then _hi_case bench_fish_startup; else _hi_skip "fish rc" "no fish"; fi

  _hi_h2 "Benchmark: per-session and per-prompt paths"
  _hi_case bench_header
  _hi_case bench_git_prompt

  _hi_h2 "Benchmark: completion"
  _hi_case bench_targets_cold
  _hi_case bench_targets_warm

  _hi_h2 "Benchmark: the wire"
  _hi_case bench_payload_size

  _hi_suite_end "bench" \
    "Every hot path under its ceiling ($_HI_TOTAL benchmarks)" \
    "$_HI_FAILED/$_HI_TOTAL benchmarks over their ceiling"
}

run_bench_tests
