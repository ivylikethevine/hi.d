#!/bin/bash
# Boots a throwaway `nomad agent -dev` (single-node, server+client, its own
# temp data dir) and drives hi.sh's real nomad path (_say_hi_container) over
# actual `nomad alloc exec` against jobs running under nomad's docker task
# driver. This proves the nomad-specific command shapes in _say_hi_container
# (`nomad alloc exec -i=false -t=false` for the probe, `-i=true -t=false` for
# copying, plain `nomad alloc exec` for the interactive attach) - previously
# untested, unlike docker/podman's equivalent branches.
# Only two cases are covered here, not the full zsh/fish fallback matrix
# docker_test.sh/podman_test.sh run: _say_hi_container's fallback logic past
# the initial `command -v bash` probe is identical code for every backend and
# is already proven there, so this only needs to prove nomad's own probe/cp/
# attach argument shapes work - once with bash present, once without.
# Everything is ephemeral (its own data dir, agent process, jobs) and bound to
# 127.0.0.1 only. Skips cleanly if nomad or docker isn't installed/reachable
# (the dev agent's docker task driver needs a real docker daemon). Needs
# network access the first time it runs, to pull the task images.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

command -v nomad >/dev/null 2>&1 || { _hi_cecho "nomad not installed, skipping" "$YELLOW"; exit 0; }
command -v docker >/dev/null 2>&1 || { _hi_cecho "docker not installed, skipping (nomad's dev agent needs it for the docker task driver)" "$YELLOW"; exit 0; }
docker info >/dev/null 2>&1 || { _hi_cecho "docker daemon not reachable, skipping" "$YELLOW"; exit 0; }

_HI_WORKDIR="$(mktemp -d -t hi.nomadtest.XXXXXX)"
_HI_NOMAD_PID=""
declare -a _HI_JOBS=()

# shellcheck disable=SC2329 # trap function is never invoked directly
function _hi_cleanup() {
  local j
  export NOMAD_ADDR="http://127.0.0.1:4646"
  for j in "${_HI_JOBS[@]:-}"; do
    [ -n "$j" ] && nomad job stop -purge "$j" >/dev/null 2>&1
  done
  if [ -n "$_HI_NOMAD_PID" ] && kill -0 "$_HI_NOMAD_PID" 2>/dev/null; then
    kill "$_HI_NOMAD_PID" 2>/dev/null
    wait "$_HI_NOMAD_PID" 2>/dev/null
  fi
  rm -rf "$_HI_WORKDIR"
}
_hi_on_exit _hi_cleanup
_hi_h1 "Testing hi's nomad path against a throwaway dev agent"

# -dev binds every listener to 127.0.0.1 and turns on every built-in task
# driver (docker included, auto-detected since the daemon is reachable) -
# nothing here touches a real cluster
_hi_h2 "starting nomad agent -dev (data dir: $_HI_WORKDIR/data, log: $_HI_WORKDIR/agent.log)"
nomad agent -dev -data-dir="$_HI_WORKDIR/data" -log-level=WARN \
  >"$_HI_WORKDIR/agent.log" 2>&1 &
_HI_NOMAD_PID=$!
export NOMAD_ADDR="http://127.0.0.1:4646"

_HI_AGENT_UP=0
for ((i = 0; i < 60; i++)); do
  nomad node status >/dev/null 2>&1 && { _HI_AGENT_UP=1; break; }
  kill -0 "$_HI_NOMAD_PID" 2>/dev/null || break # agent died - no point polling further
  sleep 0.5
done
if [ "$_HI_AGENT_UP" -ne 1 ]; then
  _hi_cecho "nomad dev agent never came up (see $_HI_WORKDIR/agent.log), skipping" "$YELLOW"
  exit 0
fi
_hi_cecho " | dev agent up: $NOMAD_ADDR" "$GREEN"

# --- the actual per-driver-shape test ------------------------------------
_HI_MARKER="HI_NOMAD_TEST_OK"
# shellcheck disable=2016 # this expands later
_HI_CMD_BASH='test -f "$_HI_ROOT/hi.sh" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo '"$_HI_MARKER"
# shellcheck disable=2016 # this expands later
_HI_CMD_FALLBACK='alias sudo >/dev/null 2>&1 && echo '"$_HI_MARKER"

# nomad alloc exec's interactive attach needs a tty. Unlike docker_test.sh/
# podman_test.sh (which only fake one when our own stdin isn't already a real
# tty), this one wraps unconditionally: the launcher below runs backgrounded
# and polled by this same script, so if it just inherited our real stdin
# directly (e.g. running this from an actual interactive terminal, like
# `hi_test_nomad` would), it would be sharing one live pty between two
# processes at once - this script's own poll loop and nomad's exec session.
# nomad's tty handling doesn't tolerate that (it fails outright with "not a
# terminal" once forced on, or silently never completes the exec if left to
# its own auto-detection) where docker/podman/kubectl happen to cope fine.
# Always handing the launcher a fresh, dedicated pty of its own - never
# shared with this script's polling loop - sidesteps the whole class of
# problem regardless of what our own stdin happens to be.
exec 3<&0
declare -a _HI_PTY_WRAP=()
if command -v python3 >/dev/null 2>&1; then
  _HI_PTY_WRAP=(python3 -c 'import pty, sys; sys.exit(pty.spawn(sys.argv[1:]))')
else
  _hi_cecho " | no python3 to give the launcher its own pty - nomad alloc exec's attach may not get a real pty, results may be unreliable" "$YELLOW"
fi

_HI_FAILED=0

# polls until the job has a running allocation, printing its ID once found
function _hi_wait_for_alloc() {
  local job="$1" i alloc
  for ((i = 0; i < 80; i++)); do
    alloc="$(nomad job allocs -t \
      '{{range .}}{{if eq .ClientStatus "running"}}{{.ID}}{{"\n"}}{{end}}{{end}}' \
      "$job" 2>/dev/null | head -1)"
    [ -n "$alloc" ] && { printf '%s' "$alloc"; return 0; }
    sleep 0.25
  done
  return 1
}

function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local job jobfile alloc out_file out exit_code=0 i pid

  job="hi-nomadtest-$label-$$"
  jobfile="$_HI_WORKDIR/$label.nomad.hcl"
  _hi_h3 "Testing driver shape: $label"

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
  _hi_cecho " | job: $job (image: $image)"

  if ! alloc="$(_hi_wait_for_alloc "$job")"; then
    _hi_cecho " | allocation never reported running" "$RED"
    return 1
  fi
  _hi_cecho " | allocation: $alloc"

  out_file="$_HI_WORKDIR/$label.out"
  _hi_cecho " | running: $_HI_LAUNCHER $alloc $cmd"
  # backgrounded so a hung fallback can't wedge the whole test suite
  "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" "$alloc" "$cmd" <&3 >"$out_file" 2>&1 &
  pid=$!
  for ((i = 0; i < timeout_s * 4; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    _hi_h3 " | $label -- TIMED OUT after ${timeout_s}s, killing"
    # a bare "TIMED OUT" says nothing about whether the alloc itself was
    # still healthy at the time - dump nomad's own view (task events, restart
    # count, driver failures) so a hang here is diagnosable after the fact
    # instead of a dead end
    _hi_cecho " |  nomad alloc status $alloc:" "$YELLOW"
    nomad alloc status "$alloc" 2>&1 | sed 's/^/      /'
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    exit_code=124
  else
    wait "$pid" 2>/dev/null || exit_code=$?
  fi

  out="$(cat "$out_file" 2>/dev/null)"
  if printf '%s' "$out" | grep -q "$_HI_MARKER"; then
    _hi_cecho " | $label -- nomad path OK" "$GREEN"
  else
    _hi_h3 " | $label -- FAILED (exit $exit_code)"
    printf '%s\n' "$out" | sed 's/^/      /'
    _HI_FAILED=1
  fi

  nomad job stop -purge "$job" >/dev/null 2>&1
}

_hi_run_case bash debian:bookworm-slim "$_HI_CMD_BASH" || _HI_FAILED=1
_hi_run_case sh alpine:3.20 "$_HI_CMD_FALLBACK" || _HI_FAILED=1

if [ "$_HI_FAILED" -eq 0 ]; then
  _hi_h1 "hi's nomad path survived every driver shape tested"
else
  _hi_h1 "hi's nomad path FAILED for one or more cases"
fi

exit "$_HI_FAILED"
