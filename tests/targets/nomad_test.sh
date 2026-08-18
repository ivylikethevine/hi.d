#!/bin/bash
# Boots a throwaway `nomad agent -dev` (single-node, server+client, its own
# temp data dir) and drives hi.sh's real nomad path (_say_hi_container) over
# actual `nomad alloc exec` against jobs running under nomad's docker task
# driver.
# Only two cases are covered here, not the full zsh/fish fallback matrix
# docker_test.sh/podman_test.sh run: _say_hi_container's fallback logic past
# the initial `command -v bash` probe is identical code for every backend and
# is already proven there, so this only needs to prove nomad's own probe/cp/
# attach argument shapes work - once with bash present, once without.
# Everything is ephemeral (its own data dir, agent process, jobs) and bound to
# 127.0.0.1 only. Skips cleanly if nomad or docker isn't installed/reachable
# (the dev agent's docker task driver needs a real docker daemon).
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_NOMAD_PID=""
declare -a _HI_JOBS=()

function _hi_nomad_cleanup() {
  local j
  for j in "${_HI_JOBS[@]:-}"; do
    [ -n "$j" ] && nomad job stop -purge "$j" >/dev/null 2>&1 || true
  done
  if [ -n "$_HI_NOMAD_PID" ] && kill -0 "$_HI_NOMAD_PID" 2>/dev/null; then
    kill "$_HI_NOMAD_PID" 2>/dev/null
    wait "$_HI_NOMAD_PID" 2>/dev/null
  fi
}

_HI_TEST_MARKER="HI_NOMAD_TEST_OK"

# first running allocation ID for a job, once it has one
function _hi_first_running_alloc() {
  nomad job allocs -t \
    '{{range .}}{{if eq .ClientStatus "running"}}{{.ID}}{{"\n"}}{{end}}{{end}}' \
    "$1" 2>/dev/null | head -1
}

function _hi_dump_alloc_status() {
  _hi_cecho " |  nomad alloc status $alloc:" "$YELLOW"
  nomad alloc status "$alloc" 2>&1 | sed 's/^/      /'
}

function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local job jobfile alloc ok=0

  job="hi-nomadtest-$label-$$"
  jobfile="$_HI_WORKDIR/$label.nomad.hcl"
  _hi_h3 "Testing driver shape: [$label]"

  cat >"$jobfile" <<EOF
job "$job" {
  datacenters = ["dc1"]
  type        = "service"

  group "hitest" {
    count = 1
    task "hitest" {
      driver = "docker"
      config {
        image   = "$image"
        command = "sleep"
        args    = ["infinity"]
      }
      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
EOF

  if ! nomad job run -detach "$jobfile" >"$_HI_WORKDIR/$label.run.log" 2>&1; then
    _hi_cecho " | failed to submit job (see $_HI_WORKDIR/$label.run.log)" "$RED"
    return 1
  fi
  _HI_JOBS+=("$job")
  _hi_cecho " | Job: $job (image: $image)"

  if ! alloc="$(_hi_poll_value 80 0.25 _hi_first_running_alloc "$job")"; then
    _hi_cecho " | Allocation never reported running" "$RED"
    return 1
  fi
  _hi_cecho " | Allocation: $alloc"

  _hi_exec_case "$label" "nomad path" "$_HI_TEST_MARKER" "$timeout_s" "$alloc" "$cmd" _hi_dump_alloc_status && ok=1
  nomad job stop -purge "$job" >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

function run_nomad_test() {
  _hi_require nomad
  _hi_require_backend docker "not installed (nomad's dev agent needs it for the docker task driver)"
  _hi_workdir nomadtest _hi_nomad_cleanup

  _hi_h1 "Testing hi's nomad path against a throwaway dev agent"

  # An agent on the well-known 4646 collides with any real nomad on this
  # machine, and its cleanup would then purge that agent's jobs rather than
  # its own. Take three consecutive free ports instead - dev mode needs http,
  # rpc and serf - the same way the ssh fixtures let docker pick an ephemeral
  # one. NOMAD_ADDR is exported so every nomad call in this suite, hi.sh's
  # backend probe included, reaches this agent and not another.
  local port_base
  port_base="$(_hi_free_port_base 3)" ||
    _hi_stand_down "no free ports" "couldn't find three free ports for the dev agent, skipping"
  cat >"$_HI_WORKDIR/agent.hcl" <<EOF
ports {
  http = $port_base
  rpc  = $((port_base + 1))
  serf = $((port_base + 2))
}
EOF

  _hi_h2 "Starting nomad agent -dev on port $port_base"
  nomad agent -dev -data-dir="$_HI_WORKDIR/data" -log-level=WARN \
    -config="$_HI_WORKDIR/agent.hcl" \
    >"$_HI_WORKDIR/agent.log" 2>&1 &
  _HI_NOMAD_PID=$!
  export NOMAD_ADDR="http://127.0.0.1:$port_base"

  function _hi_nomad_alive() { kill -0 "$_HI_NOMAD_PID" 2>/dev/null; }
  if ! _hi_poll_bool -a _hi_nomad_alive 60 0.5 nomad node status; then
    _hi_stand_down "nomad dev agent never came up" \
      "Nomad dev agent never came up (see $_HI_WORKDIR/agent.log), skipping"
  fi
  _hi_cecho " | Dev agent up: $NOMAD_ADDR" "$GREEN"

  _hi_pty_stdin force "no python3 to give the launcher its own pty - nomad alloc exec's attach may not get a real pty, results may be unreliable"

  _hi_backend_pair_cases nomad "driver shape"
}

run_nomad_test
