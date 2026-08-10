#!/bin/bash
# Boots throwaway sshd containers - one per remote login shell - and drives
# hi.sh's real ssh path (_say_hi) against each of them over actual ssh. This
# proves the base64 armor/quoting in _say_hi survives whichever shell sshd
# hands the incoming "sh -c '...'" command to server-side, not just bash/dash.
# Also boots one extra debian container with hi.d pre-installed (as
# scripts/install.sh would leave it) to prove _say_hi detects it and loads it
# in place instead of copying a fresh one over.
# Everything is ephemeral and bound to 127.0.0.1 only; nothing touches the
# user's real ~/.ssh/config or ~/.ssh/known_hosts. Skips cleanly if docker
# isn't installed/running. Needs network access the first time it runs, to
# build the test images (cached by docker afterwards).
set -euo pipefail

# shellcheck source=../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"

command -v docker >/dev/null 2>&1 || { _hi_cecho "docker not installed, skipping" "$YELLOW"; exit 0; }
docker info >/dev/null 2>&1 || { _hi_cecho "docker daemon not reachable, skipping" "$YELLOW"; exit 0; }

_HI_WORKDIR="$(mktemp -d -t hi.sshtest.XXXXXX)"
declare -a _HI_STARTED=()

# shellcheck disable=SC2329 # trap function is never invoked directly
function _hi_cleanup() {
  local c
  for c in "${_HI_STARTED[@]:-}"; do
    [ -n "$c" ] && docker stop -t 0 "$c" >/dev/null 2>&1
  done
  rm -rf "$_HI_WORKDIR"
}
_hi_on_exit _hi_cleanup
_hi_h1 "Testing hi's ssh path across remote login shells"
_hi_h2 "generating throwaway ed25519 keypair at $_HI_WORKDIR/id"
ssh-keygen -t ed25519 -N '' -q -f "$_HI_WORKDIR/id"
_HI_PUBKEY="$(cat "$_HI_WORKDIR/id.pub")"

# --- build the two throwaway sshd images ------------------------------
# one debian image covers every shell that also has bash installed (bash's
# presence, not the login shell, is what _say_hi branches on); a separate
# bash-less alpine image exercises its no-bash fallback path.
mkdir -p "$_HI_WORKDIR/debian" "$_HI_WORKDIR/alpine"

cat >"$_HI_WORKDIR/debian/Dockerfile" <<'EOF'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server openssl bash dash zsh fish \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

cat >"$_HI_WORKDIR/alpine/Dockerfile" <<'EOF'
FROM alpine:3.20
RUN apk add --no-cache openssh openssl \
    && adduser -D -s /bin/ash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

# both entrypoints do the same setup past the shebang/login-shell line -
# useradd/adduser -D both lock the account, and sshd refuses locked accounts
# outright even for pubkey auth, so both need the chpasswd unlock below
_HI_ENTRYPOINT_BODY="$(cat <<'EOF'
echo "hitest:*" | chpasswd -e
chown hitest:hitest /home/hitest
install -d -m 700 -o hitest -g hitest /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown hitest:hitest /home/hitest/.ssh/authorized_keys
chmod 600 /home/hitest/.ssh/authorized_keys
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e -o PasswordAuthentication=no -o PermitRootLogin=no -o UsePAM=no
EOF
)"

{
  # shellcheck disable=SC2016 # this is entrypoint.sh content, resolved on the container
  printf '#!/bin/bash\nset -e\nusermod -s "${LOGIN_SHELL:-/bin/bash}" hitest\n'
  printf '%s\n' "$_HI_ENTRYPOINT_BODY"
} >"$_HI_WORKDIR/debian/entrypoint.sh"

{
  printf '#!/bin/sh\nset -e\n'
  printf '%s\n' "$_HI_ENTRYPOINT_BODY"
} >"$_HI_WORKDIR/alpine/entrypoint.sh"

_hi_h2 "Building test images"
_HI_DEBIAN_OK=1
_HI_ALPINE_OK=1
_hi_h3 "building hi-sshtest-debian from $_HI_WORKDIR/debian (log: $_HI_WORKDIR/debian.log)"
docker build -q -t hi-sshtest-debian "$_HI_WORKDIR/debian" >/dev/null 2>"$_HI_WORKDIR/debian.log" || _HI_DEBIAN_OK=0
_hi_h3 "building hi-sshtest-alpine from $_HI_WORKDIR/alpine (log: $_HI_WORKDIR/alpine.log)"
docker build -q -t hi-sshtest-alpine "$_HI_WORKDIR/alpine" >/dev/null 2>"$_HI_WORKDIR/alpine.log" || _HI_ALPINE_OK=0

[ "$_HI_DEBIAN_OK" -eq 1 ] || _hi_cecho " | debian image failed to build, skipping its shells (see $_HI_WORKDIR/debian.log)" "$YELLOW"
[ "$_HI_ALPINE_OK" -eq 1 ] || _hi_cecho " | alpine image failed to build, skipping the no-bash case (see $_HI_WORKDIR/alpine.log)" "$YELLOW"

# a third image, layered on the debian one, with a real checkout of this repo
# already sitting at ~/hi.d - i.e. what a host looks like after
# scripts/install.sh has run there. The build context is $_HI_ROOT itself
# (this checkout), so it's an exact copy, uncommitted changes included.
_HI_INSTALLED_OK=$_HI_DEBIAN_OK
if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
  mkdir -p "$_HI_WORKDIR/debian-installed"
  cat >"$_HI_WORKDIR/debian-installed/Dockerfile" <<'EOF'
FROM hi-sshtest-debian
COPY --chown=hitest:hitest . /home/hitest/hi.d
RUN chmod +x /home/hitest/hi.d/hi.sh \
    && touch /home/hitest/hi.d/.installed_sentinel \
    && chown hitest:hitest /home/hitest/hi.d/.installed_sentinel
EOF
  _hi_cecho " | building hi-sshtest-debian-installed from $_HI_ROOT (log: $_HI_WORKDIR/debian-installed.log)"
  docker build -q -t hi-sshtest-debian-installed \
    -f "$_HI_WORKDIR/debian-installed/Dockerfile" "$_HI_ROOT" \
    >/dev/null 2>"$_HI_WORKDIR/debian-installed.log" || _HI_INSTALLED_OK=0
fi
[ "$_HI_INSTALLED_OK" -eq 1 ] || _hi_cecho " | debian-installed image failed to build, skipping the pre-installed case (see $_HI_WORKDIR/debian-installed.log)" "$YELLOW"

# --- the actual per-shell test -----------------------------------------
_HI_MARKER="HI_SSH_TEST_OK"
# with bash on the target, _say_hi's bootloader hands off straight to
# `bash --rcfile hi.bashrc` without sourcing aliases.sh itself (that only
# happens once an interactive `load` grafts hi's config onto the target's
# own rc files) - so this asserts the copy landed *and* sources it directly
# shellcheck disable=2016 # this expands later
_HI_CMD_BASH='test -f "$_HI_ROOT/hi.sh" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo '"$_HI_MARKER"
# the no-bash fallback rc already sources aliases.sh before running our
# command, so this only needs to assert the copy landed and the alias took
# shellcheck disable=2016 # this expands later
_HI_CMD_FALLBACK='test -f "$_HI_ROOT/hi.sh" && alias hi_info >/dev/null 2>&1 && echo '"$_HI_MARKER"
# the target already has a permanent hi.d - this asserts _say_hi pointed
# straight at it ($_HI_ROOT = ~/hi.d, never a mktemp'd copy) instead of
# shipping a fresh tree over
# shellcheck disable=2016 # this expands later
_HI_CMD_INSTALLED='test "$_HI_ROOT" = "$HOME/hi.d" && source "$_HI_ALIASES" && alias hi_info >/dev/null 2>&1 && echo '"$_HI_MARKER"

# _say_hi's bash branch only sources hi.bashrc if bash *is* interactive,
# which it only is if ssh actually allocated a remote pty. A lone `ssh -t`
# silently skips that when *our own* stdin isn't a terminal - true whenever
# this runs headless/CI, or even here since $() always redirects stdout but
# leaves stdin as-is. Route through a locally-faked pty in that case so the
# test is reliable everywhere, not just when someone happens to run it from
# an interactive terminal.
declare -a _HI_PTY_WRAP=()
if [ ! -t 0 ]; then
  if command -v python3 >/dev/null 2>&1; then
    _HI_PTY_WRAP=(python3 -c 'import pty, sys; sys.exit(pty.spawn(sys.argv[1:]))')
  else
    _hi_cecho " | no tty and no python3 to fake one - ssh -t may not get a real pty, results may be unreliable" "$YELLOW"
  fi
fi

_HI_FAILED=0

# polls until the container's sshd actually completes a handshake, so the
# real test isn't racing the container's boot
function _hi_wait_for_ssh() {
  local port="$1" key="$2" i
  for ((i = 0; i < 40; i++)); do
    ssh -i "$key" -p "$port" -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=2 \
      hitest@127.0.0.1 true 2>/dev/null && return 0
    sleep 0.25
  done
  return 1
}

function _hi_run_case() {
  local label="$1" image="$2" login_shell="$3" cmd="$4" post="${5:-}" name port out exit_code=0

  name="hi-sshtest-$label-$$"
  _hi_h3 "Testing login shell: $label"

  if ! docker run -d --rm --name "$name" -p 127.0.0.1::22 \
    -e "PUBKEY=$_HI_PUBKEY" -e "LOGIN_SHELL=$login_shell" "$image" >/dev/null 2>"$_HI_WORKDIR/$label.log"; then
    _hi_cecho " | failed to start container" "$RED"
    return 1
  fi
  _HI_STARTED+=("$name")
  _hi_cecho " | container: $name (login shell: $login_shell)"

  port="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
  _hi_cecho " | waiting for sshd on 127.0.0.1:$port"
  if ! _hi_wait_for_ssh "$port" "$_HI_WORKDIR/id"; then
    _hi_cecho " |  sshd never came up" "$RED"
    return 1
  fi

  _hi_cecho " | running: $_HI_LAUNCHER -p $port hitest@127.0.0.1 $cmd"
  out="$("${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" -p "$port" -i "$_HI_WORKDIR/id" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o IdentitiesOnly=yes \
    -o ConnectTimeout=5 hitest@127.0.0.1 "$cmd" 2>&1)" || exit_code=$?

  if printf '%s' "$out" | grep -q "$_HI_MARKER"; then
    _hi_cecho " | $label -- ssh path OK" "$GREEN"
    if [ -n "$post" ] && ! docker exec "$name" sh -c "$post" >/dev/null 2>&1; then
      _hi_h3 " |  $label -- post-check FAILED: $post"
      _HI_FAILED=1
    fi
  else
    _hi_h3 " | $label -- FAILED (exit $exit_code)"
    printf '%s\n' "$out" | sed 's/^/      /'
    _HI_FAILED=1
  fi

  docker stop -t 0 "$name" >/dev/null 2>&1
}


if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
  for _hi_pair in bash:/bin/bash dash:/bin/dash zsh:/usr/bin/zsh fish:/usr/bin/fish; do
    _hi_run_case "${_hi_pair%%:*}" hi-sshtest-debian "${_hi_pair#*:}" "$_HI_CMD_BASH" || _HI_FAILED=1
  done
fi

if [ "$_HI_ALPINE_OK" -eq 1 ]; then
  _hi_run_case nobash hi-sshtest-alpine /bin/ash "$_HI_CMD_FALLBACK" || _HI_FAILED=1
fi

if [ "$_HI_INSTALLED_OK" -eq 1 ]; then
  _hi_run_case installed hi-sshtest-debian-installed /bin/bash "$_HI_CMD_INSTALLED" \
    'test -f /home/hitest/hi.d/.installed_sentinel' || _HI_FAILED=1
fi

if [ "$_HI_FAILED" -eq 0 ]; then
  _hi_h1 "hi's ssh path survived every login shell tested"
else
  _hi_h1 "hi's ssh path FAILED for one or more login shells"
fi

docker image rm -f hi-sshtest-debian hi-sshtest-alpine hi-sshtest-debian-installed
exit "$_HI_FAILED"
