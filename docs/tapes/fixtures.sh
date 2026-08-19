#!/bin/bash
# Demo-tape fixtures: the targets docs/tapes/*.tape connect to, shaped like
# the e2e fixtures (tests/test_lib.sh) but standalone - a tape render happens
# outside the test harness, on a machine that just has the backends installed.
# Everything lands under /tmp/hi-demo so `down` can remove it wholesale, and
# every resource is named hi-demo-* so a crashed render can't leak anonymous
# containers. Not sourced by anything; invoked from the tapes' Hide blocks:
#
#   docs/tapes/fixtures.sh up ssh|docker|podman|nomad|kube
#   docs/tapes/fixtures.sh down
set -euo pipefail

_HI_DEMO_DIR=/tmp/hi-demo
_HI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# a throwaway keypair and an ssh config the ssh tape's `hi -F` points at, so
# the demo never touches the renderer's ~/.ssh
function demo_keypair() {
  [ -f "$_HI_DEMO_DIR/key" ] || ssh-keygen -q -t ed25519 -N "" -f "$_HI_DEMO_DIR/key"
}

function demo_sshd_image() {
  # the image is tests/dockerfiles/demo-sshd.Dockerfile; what this function
  # assembles is its build context - the entrypoint below, and the clean
  # checkout further down
  cat >"$_HI_DEMO_DIR/entrypoint.sh" <<'EOF'
#!/bin/bash
set -eu
mkdir -p /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown -R hitest:hitest /home/hitest/.ssh
chmod 700 /home/hitest/.ssh
ssh-keygen -A
exec /usr/sbin/sshd -D -e
EOF
  # A clean copy rather than the live checkout as context: .git and dist/ would
  # bloat the build context and the image alike.
  #
  # From HEAD by default, because a demo should show a state that exists in the
  # history. $HI_DEMO_SOURCE=worktree renders what is in front of you instead -
  # which matters more than it sounds: the *client* side of every tape is the
  # working tree either way, so rendering a dirty tree without this gives you a
  # new client talking to an old target, and the GIF quietly lies.
  rm -rf "$_HI_DEMO_DIR/checkout"
  mkdir -p "$_HI_DEMO_DIR/checkout"
  if [ "${HI_DEMO_SOURCE:-head}" = worktree ]; then
    # tracked files only, uncommitted contents included - the same set
    # `git archive` would take, read from the working tree
    (cd "$_HI_ROOT" && git ls-files -z | tar --null -T - -cf -) |
      tar -x -C "$_HI_DEMO_DIR/checkout"
  else
    (cd "$_HI_ROOT" && git archive HEAD | tar -x -C "$_HI_DEMO_DIR/checkout")
  fi
  docker build -q -t hi-demo-sshd \
    -f "$_HI_ROOT/tests/dockerfiles/demo-sshd.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
}

function up_ssh() {
  demo_keypair
  demo_sshd_image
  docker rm -f hi-demo-ssh >/dev/null 2>&1 || true
  # --hostname: docker's own default is a random 12-char hex ID, which makes
  # for an ugly, meaningless color in the header's user@host line. web-1
  # gives the color-hash demo something real to hash.
  docker run -d --rm --name hi-demo-ssh --hostname web-1 -p 127.0.0.1::22 \
    -e PUBKEY="$(cat "$_HI_DEMO_DIR/key.pub")" hi-demo-sshd >/dev/null
  local port
  port="$(docker port hi-demo-ssh 22/tcp | head -1)"
  port="${port##*:}"
  cat >"$_HI_DEMO_DIR/ssh_config" <<EOF
Host hi-demo-box
  HostName 127.0.0.1
  Port $port
  User hitest
  IdentityFile $_HI_DEMO_DIR/key
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
  # wait for sshd to answer before the tape types anything
  for _ in $(seq 1 30); do
    ssh -F "$_HI_DEMO_DIR/ssh_config" hi-demo-box true 2>/dev/null && return 0
    sleep 1
  done
  echo "sshd never answered on port $port" >&2
  return 1
}

# a bare shell-only image per flavor, the docker/podman e2e shape. <hostname>
# is optional - pass one to give the header's color-hash line something
# meaningful to hash instead of the backend's random container ID; omitted
# for the tapes that are demonstrating hi against whatever a target happens
# to be named.
function up_container() { # <backend> <name> <flavor: debian|zsh|fish|ash> [hostname]
  local backend="$1" name="$2" flavor="$3" hostname="${4:-}" image
  case "$flavor" in
  debian) image=debian:bookworm-slim ;;
  ash) image=alpine:3.20 ;;
  zsh | fish)
    "$backend" build -q -t "hi-demo-$flavor-img" --build-arg "PKGS=$flavor git" \
      -f "$_HI_ROOT/tests/dockerfiles/alpine-shell.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
    image="hi-demo-$flavor-img"
    ;;
  *)
    echo "unknown flavor: $flavor" >&2
    return 1
    ;;
  esac
  "$backend" rm -f "$name" >/dev/null 2>&1 || true
  if [ -n "$hostname" ]; then
    "$backend" run -d --rm --name "$name" --hostname "$hostname" "$image" tail -f /dev/null >/dev/null
  else
    "$backend" run -d --rm --name "$name" "$image" tail -f /dev/null >/dev/null
  fi
}

function up_nomad() {
  command -v nomad >/dev/null || {
    echo "nomad is not installed" >&2
    return 1
  }
  pkill -f 'nomad agent -dev' 2>/dev/null || true
  nomad agent -dev >"$_HI_DEMO_DIR/nomad.log" 2>&1 &
  echo $! >"$_HI_DEMO_DIR/nomad.pid"
  for _ in $(seq 1 30); do
    nomad status >/dev/null 2>&1 && break
    sleep 1
  done
  cat >"$_HI_DEMO_DIR/demo.nomad.hcl" <<'EOF'
job "hi-demo" {
  type = "service"
  group "g" {
    task "box" {
      driver = "docker"
      config {
        image   = "debian:bookworm-slim"
        command = "tail"
        args    = ["-f", "/dev/null"]
      }
    }
  }
}
EOF
  nomad job run "$_HI_DEMO_DIR/demo.nomad.hcl" >/dev/null
  for _ in $(seq 1 30); do
    nomad job allocs -t '{{ range . }}{{ if eq .ClientStatus "running" }}{{ .ID }}{{ end }}{{ end }}' hi-demo \
      2>/dev/null | cut -c1-8 >"$_HI_DEMO_DIR/alloc"
    [ -s "$_HI_DEMO_DIR/alloc" ] && return 0
    sleep 1
  done
  echo "the hi-demo allocation never reached running" >&2
  return 1
}

function up_kube() {
  command -v kind >/dev/null || {
    echo "kind is not installed" >&2
    return 1
  }
  kind get clusters 2>/dev/null | grep -qx hi-demo ||
    kind create cluster --name hi-demo --wait 120s >/dev/null 2>&1
  kubectl --context kind-hi-demo delete pod hi-demo-pod --ignore-not-found >/dev/null 2>&1
  kubectl --context kind-hi-demo run hi-demo-pod --image=alpine:3.20 \
    --restart=Never --command -- sleep infinity >/dev/null
  kubectl --context kind-hi-demo wait --for=condition=Ready pod/hi-demo-pod --timeout=120s >/dev/null
}

function demo_down() {
  docker rm -f hi-demo-ssh hi-demo hi-demo-zsh >/dev/null 2>&1 || true
  podman rm -f hi-demo-fish >/dev/null 2>&1 || true
  if [ -f "$_HI_DEMO_DIR/nomad.pid" ]; then
    nomad job stop -purge hi-demo >/dev/null 2>&1 || true
    kill "$(cat "$_HI_DEMO_DIR/nomad.pid")" 2>/dev/null || true
  fi
  if kind get clusters 2>/dev/null | grep -qx hi-demo; then
    kind delete cluster --name hi-demo >/dev/null 2>&1 || true
  fi
  rm -rf "$_HI_DEMO_DIR" /tmp/hi-demo.log
}

mkdir -p "$_HI_DEMO_DIR"
case "${1:-}:${2:-}" in
up:ssh) up_ssh ;;
up:docker)
  up_container docker hi-demo debian db-prod
  up_container docker hi-demo-zsh zsh cache-1
  ;;
up:podman) up_container podman hi-demo-fish fish ;;
up:nomad) up_nomad ;;
up:kube) up_kube ;;
down:) demo_down ;;
*)
  echo "usage: fixtures.sh up <ssh|docker|podman|nomad|kube> | down" >&2
  exit 1
  ;;
esac
