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
# GLOSSARY: HI.30
# shellcheck disable=SC2329
set -euo pipefail

: "${_HI_HOME:=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck source=../../common/core.sh
source "$_HI_HOME/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_HI_CLUSTER="hi-kubetest-$$"
_HI_CLUSTER_UP=0

function _hi_kube_cleanup() {
  [ "$_HI_CLUSTER_UP" -eq 1 ] && kind delete cluster --name "$_HI_CLUSTER" >/dev/null 2>&1
  return 0
}

function _hi_pod_running() { [ "$(kubectl get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Running ]; }

# A kind node starts with an empty containerd, so --image-pull-policy=IfNotPresent
# still pulls from the registry the first time a pod wants an image - and
# debian:bookworm-slim did not finish inside the Running poll's budget on CI
# while the 3MB alpine shape did. Pulling both up front moves that wait out of
# the per-pod budget, which is the actual coupling: the poll below should be
# waiting on the scheduler, never on a download.
#
# `crictl pull` in the node rather than `kind load docker-image` from the host:
# kind's loader shells out to `ctr images import --all-platforms`, which fails
# ("content digest ...: not found") wherever docker's image store holds a
# multi-platform index without every platform's blobs - true of this dev box and
# not something a test should be fragile about. crictl talks to the node's own
# containerd and needs nothing from the host's docker at all.
#
# Best-effort throughout: a failure here is a slow pod, not a broken suite, and
# the widened poll covers it.
function _hi_kube_preload_images() {
  local node image
  local -a nodes=()
  _hi_read_lines nodes < <(kind get nodes --name "$_HI_CLUSTER" 2>/dev/null)
  [ "${#nodes[@]}" -gt 0 ] || {
    _hi_cecho " | No nodes to preload, leaving the images to the pods" "$YELLOW"
    return 0
  }
  for node in "${nodes[@]}"; do
    for image in "$_HI_PAIR_IMAGE_BASH" "$_HI_PAIR_IMAGE_SH"; do
      if docker exec "$node" crictl pull "$image" >>"$_HI_WORKDIR/preload.log" 2>&1; then
        _hi_cecho " | Preloaded $image" "$GREEN"
      else
        _hi_cecho " | Could not preload $image, leaving it to the pod" "$YELLOW"
      fi
    done
  done
  return 0
}

function _hi_run_case() {
  local label="$1" image="$2" cmd="$3" timeout_s="${4:-30}"
  local name ok=0

  name="hi-kubetest-$label"
  _hi_h3 "Testing shape: [$label]"

  if ! kubectl run "$name" --image="$image" --image-pull-policy=IfNotPresent \
    --restart=Never --command -- sleep infinity >"$_HI_WORKDIR/$label.run.log" 2>&1; then
    _hi_dump_log "Failed to create pod:" "$_HI_WORKDIR/$label.run.log"
    return 1
  fi
  _hi_cecho " | Pod: $name (image: $image)"

  # 120s, not the 20s this used to allow: the preload makes Running arrive in a
  # couple of seconds, and this is the budget for the run where it didn't work.
  if ! _hi_poll_bool 240 0.5 _hi_pod_running "$name"; then
    kubectl describe pod "$name" >"$_HI_WORKDIR/$label.describe.log" 2>&1 || true
    _hi_dump_log "Pod never reported Running:" "$_HI_WORKDIR/$label.describe.log"
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
    _hi_dump_log "Kind cluster never came up:" "$_HI_WORKDIR/kind.log" "$YELLOW"
    _hi_stand_down "kind cluster never came up"
  fi
  _HI_CLUSTER_UP=1
  _hi_cecho " | Cluster up" "$GREEN"

  if ! _hi_poll_bool 40 0.5 kubectl get serviceaccount default; then
    _hi_stand_down "no default ServiceAccount" \
      "default ServiceAccount never showed up, skipping"
  fi

  _hi_kube_preload_images

  _HI_TEST_MARKER="HI_KUBE_TEST_OK"

  _hi_pty_stdin auto "no tty and no python3 to fake one - kubectl exec -it will fail outright, results may be unreliable"

  _hi_backend_pair_cases kube "shape"
}

run_kube_test
