#!/bin/bash
# hi's pre-flight: one command that answers "why is hi slow or failing
# against this target". Reports the local tree, the config overlay, and every
# backend probed with the same timeout-bounded calls the header and
# completion make - and, given a target, walks the same resolution chain and
# opens the same multiplexed ssh probe a real `hi` would. Read-only
# throughout: nothing here modifies a thing, locally or remotely.
# Run via `hi_doctor` or `hi --doctor [target]`.
#
# SC2317/SC2329: shellcheck follows the `source "$_HI_LAUNCHER"` below into
# hi.sh's trailing `_hi "$@"`, decides that call never returns, and marks
# everything after the source line unreachable - it doesn't model hi.sh's
# BASH_SOURCE guard (same story as tests/shells/hi_test.sh).
# shellcheck disable=SC2317,SC2329
set -euo pipefail

# shellcheck source=../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"

case "${1:-}" in
-h | --help)
  cat <<'EOF'
Usage: doctor.sh [target]

Prints, in order:
  the local tree     where hi.d is, git state, payload size, local shells
  the config overlay settings.sh (and whether every shell can parse it),
                     colors/packages overrides, non-default toggles
  the backends       ssh config, docker, podman, nomad, kubectl - each probed
                     with the same timeout the header and completion use, and
                     timed, so a slow TAB or connect banner names its culprit
  the target         (with an argument) which backend the name resolves to,
                     each check timed - and for an ssh target, a BatchMode
                     connection, the permanent-install probe, and what the
                     remote end has installed

ssh options are not accepted here - the probe uses your ssh config as-is,
which is exactly what completion and the header do.
EOF
  exit 0
  ;;
esac

# hi.sh's source hatch hands over everything this needs without connecting
# anywhere: the backend predicates, _hi_remote_root and $_HI_PAYLOAD.
_HI_DOC_TARGET="${1:-}"
set -- # hi.sh reads "$@" at source time; it must see none
# shellcheck source=../hi.sh
source "$_HI_LAUNCHER"

_HI_DOC_BAD=0

# doctor_row <label> <text> [color] - one aligned finding
function doctor_row() {
  _hi_cecho " | $(printf '%-12s' "$1") $2" "${3:-}"
  [ "${3:-}" = "$RED" ] && _HI_DOC_BAD=$((_HI_DOC_BAD + 1))
  return 0
}

function doctor_local() {
  local branch changes
  _hi_h2 "The local tree"
  doctor_row tree "$_HI_ROOT"
  doctor_row version "$(_hi_version)"
  if [ -d "$_HI_ROOT/.git" ]; then
    branch="$(git -C "$_HI_ROOT" symbolic-ref --short -q HEAD 2>/dev/null || true)"
    changes="$(git -C "$_HI_ROOT" status --short 2>/dev/null | grep -c . || true)"
    doctor_row checkout "git, ${branch:-detached HEAD (a release tag?)}, $changes local change(s)"
  else
    doctor_row checkout "no .git - a package-manager install (hi_update will say so too)"
  fi
  # two numbers because they answer two questions: what leaves this machine
  # (a gzipped tar, base64-armored for the ssh path) and how big the thing is
  # once it lands. The first is the one people mean by "what does hi cost".
  doctor_row payload "$(_hi_wire_estimate) over the wire per ssh session, $(_hi_size) unpacked (${_HI_PAYLOAD[*]})"
  local s have=""
  for s in bash zsh fish; do
    command -v "$s" >/dev/null 2>&1 && have="$have$s "
  done
  doctor_row shells "local: ${have:-none?!}"
}

function doctor_config() {
  local f t v any=0
  _hi_h2 "The config overlay ($_HI_CONFIG_DIR)"
  if [ -f "$_HI_SETTINGS" ]; then
    if ! sh -n "$_HI_SETTINGS" 2>/dev/null; then
      doctor_row settings.sh "does NOT parse as sh - every shell sources this file" "$RED"
    elif command -v fish >/dev/null 2>&1 && ! fish --no-execute "$_HI_SETTINGS" 2>/dev/null; then
      doctor_row settings.sh "parses as sh but NOT as fish - fish sessions lose it" "$RED"
    else
      doctor_row settings.sh "present, parses" "$GREEN"
    fi
  else
    doctor_row settings.sh "none - defaults apply (hi_configure writes one)"
  fi
  for f in colors packages; do
    if [ -f "$_HI_CONFIG_DIR/$f" ]; then
      doctor_row "$f" "overridden ($(grep -c . "$_HI_CONFIG_DIR/$f") lines)"
    else
      doctor_row "$f" "tree default"
    fi
  done
  # whether the overlay has history - hi_overlay_init's optional-and-quiet
  # contract means untracked is a state, not a problem
  if [ -d "$_HI_CONFIG_DIR/.git" ]; then
    doctor_row versioning "tracked ($(git -C "$_HI_CONFIG_DIR" rev-list --count HEAD 2>/dev/null || echo 0) commits)" "$GREEN"
  else
    doctor_row versioning "untracked (hi_overlay_init gives it history)"
  fi
  # only the non-default toggles: a default setup stays one quiet line
  for t in "${_HI_TOGGLES[@]}"; do
    eval "v=\${$t:-0}"
    [ "$v" = 0 ] && continue
    doctor_row toggle "$t=$v" "$YELLOW"
    any=1
  done
  [ "$any" = 1 ] || doctor_row toggles "all defaults (every feature on)"
}

# doctor_backend <name> <cli> <probe...> - installed, answering, and how long
# the answer took; the same _hi_probe ceiling the header and completion use
function doctor_backend() {
  local name="$1" t0 t1 rc=0
  shift
  if ! command -v "$1" >/dev/null 2>&1; then
    doctor_row "$name" "not installed"
    return 0
  fi
  t0="$(_hi_now)"
  _hi_probe "$@" >/dev/null 2>&1 || rc=$?
  t1="$(_hi_now)"
  if [ "$rc" -eq 0 ]; then
    doctor_row "$name" "answering ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
  else
    doctor_row "$name" "installed but not answering after $(_hi_elapsed "$t0" "$t1")s (exit $rc) - completion and the header wait on this every time" "$YELLOW"
  fi
}

function doctor_backends() {
  local hosts t0 t1
  _hi_h2 "Backends (probes capped at ${_HI_PROBE_TIMEOUT:-2}s each, like the header)"
  if [ -f "$_HI_SSH_CONFIG" ]; then
    hosts="$(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) { if ($i ~ /^#/) break; if ($i !~ /[*?]/) n++ } } END { print n + 0 }' "$_HI_SSH_CONFIG")"
    doctor_row ssh "$hosts literal host(s) in $_HI_SSH_CONFIG"
  else
    doctor_row ssh "no $_HI_SSH_CONFIG - names still reach ssh, just without completion or tags"
  fi
  doctor_backend docker docker ps -q
  doctor_backend podman podman ps -q
  doctor_backend nomad nomad job status
  doctor_backend kube kubectl get pods -o name
  t0="$(_hi_now)"
  _HI_TARGETS_TTL=0 sh "$_HI_TARGETS" >/dev/null 2>&1 || true
  t1="$(_hi_now)"
  doctor_row completion "full target list built in $(_hi_elapsed "$t0" "$t1")s cold (TAB reuses it for ${_HI_TARGETS_TTL:-5}s)"
}

# the same chain _hi dispatches on, each predicate timed, first match wins
function doctor_target() {
  local target="$1" kind="" pair name t0 t1
  _hi_h2 "Target: $target"
  for pair in "ssh host:_hi_is_ssh_host" \
    "docker container:_hi_is_docker_container" \
    "podman container:_hi_is_podman_container" \
    "nomad allocation:_hi_is_nomad_alloc" \
    "kubernetes pod:_hi_is_k8s_pod"; do
    name="${pair%%:*}"
    t0="$(_hi_now)"
    if "${pair#*:}" "$target" >/dev/null 2>&1; then
      t1="$(_hi_now)"
      kind="$name"
      doctor_row resolves "$name ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
      break
    fi
    t1="$(_hi_now)"
    doctor_row checked "not a $name ($(_hi_elapsed "$t0" "$t1")s)"
  done
  if [ -z "$kind" ]; then
    doctor_row resolves "nothing matched - hi would hand it to ssh anyway"
    kind="ssh host"
  fi
  [ "$kind" = "ssh host" ] && doctor_ssh_target "$target"
  return 0
}

# The ssh half: one BatchMode connection, multiplexed exactly like a real
# session, then the permanent-install probe and a tool inventory over the
# same socket - so the whole section costs a single authentication.
function doctor_ssh_target() {
  DOMAIN="$1"
  SSHARGS=()
  local ctl_path t0 t1 root tools err
  ctl_path="$(mktemp -u -t hi.doc.XXXXXX)"
  err="$(mktemp -t hi.doc.err.XXXXXX)"
  local -a ctl_opts=(-o ControlMaster=auto -o ControlPath="$ctl_path" -o ControlPersist=15 -o BatchMode=yes)
  t0="$(_hi_now)"
  if ! ssh "${ctl_opts[@]}" -o ConnectTimeout=5 "$DOMAIN" true 2>"$err"; then
    t1="$(_hi_now)"
    doctor_row connect "FAILED after $(_hi_elapsed "$t0" "$t1")s (BatchMode - a password/2FA prompt fails here but may work interactively)" "$RED"
    sed 's/^/      /' "$err"
    rm -f "$err"
    return 0
  fi
  t1="$(_hi_now)"
  rm -f "$err"
  doctor_row connect "ok ($(_hi_elapsed "$t0" "$t1")s to authenticate - later probes reuse the socket)" "$GREEN"
  root="$(_hi_remote_root "${ctl_opts[@]}")"
  if [ -n "$root" ]; then
    doctor_row install "permanent $root - hi loads it in place, ships nothing"
  else
    doctor_row install "none - hi ships $(_hi_wire_estimate) each session"
  fi
  # through _hi_ssh_sh, like every other command hi sends: unwrapped, a fish
  # login shell cannot parse the loop and the report claimed the target had
  # nothing - no base64, no bash, all of it false
  tools="$(_hi_ssh_sh "for c in base64 bash $_HI_SHELL_LADDER tmux vim git; do command -v \"\$c\" >/dev/null 2>&1 && printf \"%s \" \"\$c\"; done" \
    "${ctl_opts[@]}" 2>/dev/null || true)"
  doctor_row remote "has: ${tools:-nothing this probes for}"
  case " $tools" in
  *" base64 "*) ;;
  *) doctor_row remote "no base64 - the ssh bootstrap cannot decode there" "$RED" ;;
  esac
  case " $tools" in
  *" bash "*) ;;
  *) doctor_row remote "no bash - sessions fall back to ${_HI_SHELL_LADDER// / > } with aliases only" "$YELLOW" ;;
  esac
  ssh -O exit "${ctl_opts[@]}" "$DOMAIN" >/dev/null 2>&1 || true
  rm -f "$ctl_path" 2>/dev/null || true
}

# sourcing stops here (the test suite reaches the functions above); executed,
# it runs the report
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

_hi_h1 "hi doctor"
doctor_local
doctor_config
doctor_backends
[ -n "${_HI_DOC_TARGET:-}" ] && doctor_target "$_HI_DOC_TARGET"
if [ "$_HI_DOC_BAD" -eq 0 ]; then
  _hi_h1 "Nothing looks broken" "$BRGREEN"
else
  _hi_h1 "$_HI_DOC_BAD finding(s) above in red" "$RED"
fi
exit "$_HI_DOC_BAD"
