#!/bin/bash
# Boots a throwaway kind (Kubernetes-in-docker) cluster and drives hi.sh's
# real kube path (_say_hi_container) over actual `kubectl exec` against pods
# running on it. This proves the kube-specific command shapes added to
# _say_hi_container (`kubectl exec POD --` for the probe, `-i ... --` for
# copying, `-it ... --` for the interactive attach, the `--` separating
# kubectl's own flags from the remote command).
# Only two cases are covered, not the full zsh/fish fallback matrix
# docker_test.sh/podman_test.sh run: _say_hi_container's fallback logic past
# the initial `command -v bash` probe is identical code for every backend and
# is already proven there, so this only needs to prove kubectl exec's own
# argument shapes work - once with bash present, once without.
# The cluster gets its own throwaway kubeconfig (never ~/.kube/config) so
# nothing here touches a real cluster context. Needs network access - once
# for kind's own node image, and every run for the two tiny test images,
# pulled from inside the kind node itself rather than loaded from the host's
# docker daemon (`kind load docker-image` chokes on this host's docker
# installation: its containerd-backed image store keeps multi-platform
# manifest-list metadata around even for a single-platform pull, and kind's
# `ctr images import --all-platforms` then fails looking for blobs of
# platforms that were never actually pulled).
# Skips cleanly if kind/kubectl/docker aren't installed/reachable.
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=./test_lib.sh
source "$_HI_TEST_LIB"

command -v kind >/dev/null 2>&1 || { _hi_cecho "kind not installed, skipping" "$YELLOW"; exit 0; }
command -v kubectl >/dev/null 2>&1 || { _hi_cecho "kubectl not installed, skipping" "$YELLOW"; exit 0; }
command -v docker >/dev/null 2>&1 || { _hi_cecho "docker not installed, skipping (kind needs it to run cluster nodes)" "$YELLOW"; exit 0; }
docker info >/dev/null 2>&1 || { _hi_cecho "docker daemon not reachable, skipping" "$YELLOW"; exit 0; }

_HI_WORKDIR="$(mktemp -d -t hi.kubetest.XXXXXX)"
_HI_CLUSTER="hi-kubetest-$$"
export KUBECONFIG="$_HI_WORKDIR/kubeconfig"
_HI_CLUSTER_UP=0

# shellcheck disable=SC2329 # trap function is never invoked directly
function _hi_cleanup() {
  [ "$_HI_CLUSTER_UP" -eq 1 ] && kind delete cluster --name "$_HI_CLUSTER" >/dev/null 2>&1
  rm -rf "$_HI_WORKDIR"
}
_hi_on_exit _hi_cleanup
_hi_h1 "Testing hi's kube path against a throwaway kind cluster"

_hi_h2 "creating kind cluster $_HI_CLUSTER (kubeconfig: $KUBECONFIG, log: $_HI_WORKDIR/kind.log)"
if ! kind create cluster --name "$_HI_CLUSTER" --kubeconfig "$KUBECONFIG" \
  >"$_HI_WORKDIR/kind.log" 2>&1; then
  _hi_cecho "kind cluster never came up (see $_HI_WORKDIR/kind.log), skipping" "$YELLOW"
  exit 0
fi
_HI_CLUSTER_UP=1
_hi_cecho " | cluster up" "$GREEN"

# kind reports the cluster ready as soon as the API server answers, but the
# controller-manager hasn't necessarily created the default namespace's
# `default` ServiceAccount yet - a pod submitted before it exists is rejected
# outright ("error looking up service account default/default: ... not
# found"), so wait for it rather than race the pod creation below against it
if ! _hi_poll_bool 40 0.5 kubectl get serviceaccount default; then
  _hi_cecho "default ServiceAccount never showed up, skipping" "$YELLOW"
  exit 0
fi

# --- the actual per-shape test -------------------------------------------
_HI_MARKER="HI_KUBE_TEST_OK"
# shellcheck disable=2016 # this expands later
_HI_CMD_BASH='test -f "$_HI_ROOT/hi.sh" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo '"$_HI_MARKER"
# shellcheck disable=2016 # this expands later
_HI_CMD_FALLBACK='alias sudo >/dev/null 2>&1 && echo '"$_HI_MARKER"

# same reasoning as docker_test.sh/podman_test.sh: kubectl exec -it refuses a
# tty unless our own stdin already looks like one, which isn't true once this
# runs headless/backgrounded - fake one via fd 3 the same way (see
# docker_test.sh for the long version of why fd 3 specifically, not fd 0)
exec 3<&0
_hi_pty_wrap 3 auto "no tty and no python3 to fake one - kubectl exec -it will fail outright, results may be unreliable"

_HI_FAILED=0
_HI_TOTAL=0

# polls until the pod itself reports Running, so the real test isn't racing
# the scheduler/kubelet
# shellcheck disable=SC2329 # invoked indirectly, via _hi_poll_bool's "$@"
function _hi_pod_running() { [ "$(kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]; }

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local name out_file out exit_code=0 i pid t0 t1 ok=1

  name="hi-kubetest-$label"
  _hi_h3 "Testing shape: $label"
  t0="$(_hi_now)"

  if ! kubectl run "$name" --image="$image" --image-pull-policy=IfNotPresent \
    --restart=Never --command -- sleep infinity >"$_HI_WORKDIR/$label.run.log" 2>&1; then
    _hi_cecho " | failed to create pod (see $_HI_WORKDIR/$label.run.log)" "$RED"
    return 1
  fi
  _hi_cecho " | pod: $name (image: $image)"

  if ! _hi_poll_bool 80 0.25 _hi_pod_running "$name"; then
    _hi_cecho " | pod never reported Running" "$RED"
    kubectl delete pod "$name" --now >/dev/null 2>&1
    return 1
  fi

  out_file="$_HI_WORKDIR/$label.out"
  _hi_cecho " | running: $_HI_LAUNCHER $name $cmd"
  # backgrounded so a hung fallback can't wedge the whole test suite
  "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" "$name" "$cmd" <&3 >"$out_file" 2>&1 &
  pid=$!
  for ((i = 0; i < timeout_s * 4; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    _hi_h3 " | $label -- TIMED OUT after ${timeout_s}s, killing"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    exit_code=124
  else
    wait "$pid" 2>/dev/null || exit_code=$?
  fi
  t1="$(_hi_now)"

  out="$(cat "$out_file" 2>/dev/null)"
  if printf '%s' "$out" | grep -q "$_HI_MARKER"; then
    _hi_cecho " | $label -- kube path OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
  else
    _hi_h3 " | $label -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)"
    printf '%s\n' "$out" | sed 's/^/      /'
    ok=0
  fi

  kubectl delete pod "$name" --now >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

_hi_case _hi_run_case bash debian:bookworm-slim "$_HI_CMD_BASH"
_hi_case _hi_run_case sh alpine:3.20 "$_HI_CMD_FALLBACK"

if [ "$_HI_FAILED" -eq 0 ]; then
  _hi_h1 "hi's kube path survived every shape tested ($_HI_TOTAL cases)"
else
  _hi_h1 "hi's kube path FAILED: $_HI_FAILED/$_HI_TOTAL cases" "$RED"
fi

exit "$_HI_FAILED"
