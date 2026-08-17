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
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_CLUSTER="hi-kubetest-$$"
_HI_CLUSTER_UP=0

function _hi_kube_cleanup() {
  [ "$_HI_CLUSTER_UP" -eq 1 ] && kind delete cluster --name "$_HI_CLUSTER" >/dev/null 2>&1
  return 0
}

function _hi_pod_running() { [ "$(kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]; }

function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local name ok=0

  name="hi-kubetest-$label"
  _hi_h3 "Testing shape: [$label]"

  if ! kubectl run "$name" --image="$image" --image-pull-policy=IfNotPresent \
    --restart=Never --command -- sleep infinity >"$_HI_WORKDIR/$label.run.log" 2>&1; then
    _hi_cecho " | Failed to create pod (see $_HI_WORKDIR/$label.run.log)" "$RED"
    return 1
  fi
  _hi_cecho " | Pod: $name (image: $image)"

  if ! _hi_poll_bool 80 0.25 _hi_pod_running "$name"; then
    _hi_cecho " | Pod never reported Running" "$RED"
    kubectl delete pod "$name" --now >/dev/null 2>&1
    return 1
  fi

  _hi_exec_case "$label" "kube path" "$_HI_TEST_MARKER" "$timeout_s" "$name" "$cmd" && ok=1
  kubectl delete pod "$name" --now >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

function run_kube_test() {
  _hi_require kind
  _hi_require kubectl
  _hi_require_backend docker "not installed (kind needs it to run cluster nodes)"

  _hi_workdir kubetest _hi_kube_cleanup
  export KUBECONFIG="$_HI_WORKDIR/kubeconfig"
  _hi_h1 "Testing hi's kube path against a throwaway kind cluster"

  _hi_h2 "Creating kind cluster $_HI_CLUSTER"
  if ! kind create cluster --name "$_HI_CLUSTER" --kubeconfig "$KUBECONFIG" \
    >"$_HI_WORKDIR/kind.log" 2>&1; then
    _hi_stand_down "kind cluster never came up" \
      "Kind cluster never came up (see $_HI_WORKDIR/kind.log), skipping"
  fi
  _HI_CLUSTER_UP=1
  _hi_cecho " | Cluster up" "$GREEN"

  if ! _hi_poll_bool 40 0.5 kubectl get serviceaccount default; then
    _hi_stand_down "no default ServiceAccount" \
      "default ServiceAccount never showed up, skipping"
  fi

  _HI_TEST_MARKER="HI_KUBE_TEST_OK"

  _hi_pty_stdin auto "no tty and no python3 to fake one - kubectl exec -it will fail outright, results may be unreliable"

  _hi_suite_begin

  _hi_case _hi_run_case bash debian:bookworm-slim "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
  _hi_case _hi_run_case sh alpine:3.20 "$(_hi_probe_cmd "$_HI_TEST_MARKER" fallback)"

  _hi_suite_end "" \
    "hi's kube path survived every shape tested ($_HI_TOTAL cases)" \
    "hi's kube path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_kube_test
