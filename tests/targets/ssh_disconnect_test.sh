#!/bin/bash
# End-to-end test of hi.sh's ephemeral-target cleanup (the `trap 'rm -rf
# $_HI_CLEANUP' exit` set up in _say_hi's non-installed branch, see hi.sh)
# surviving an abrupt disconnect, not just a clean `exit`.
#
# A real network partition can't be produced from here without extra
# privileges (iptables/NET_ADMIN inside the container), so this simulates one
# the way that's actually reachable from an unprivileged test: freeze every
# local ssh process for the session with SIGSTOP rather than killing it. The
# underlying TCP socket stays open and nothing sent to it gets answered -
# indistinguishable, from the target's point of view, from the cable getting
# pulled. The target-side sshd (started below with a 2s ClientAliveInterval
# and ClientAliveCountMax=1) is what actually notices and tears the session
# down, exactly as it would for a real dead link - so this proves the trap
# fires from a real server-side session teardown, not from a clean
# client-initiated close. hi.sh's own ControlMaster (see _hi_remote_root)
# means there can be two local ssh processes for one session - the persistent
# multiplexing master plus the interactive `-t` client - so every matching
# pid gets frozen, not just the obvious one.
#
# Skips cleanly if docker or pgrep aren't available.
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

command -v docker >/dev/null 2>&1 || { _hi_cecho "docker not installed, skipping" "$YELLOW"; exit 0; }
docker info >/dev/null 2>&1 || { _hi_cecho "docker daemon not reachable, skipping" "$YELLOW"; exit 0; }
command -v pgrep >/dev/null 2>&1 || { _hi_cecho "pgrep not installed, skipping" "$YELLOW"; exit 0; }

_HI_WORKDIR="$(mktemp -d -t hi.sshdisconnecttest.XXXXXX)"
declare -a _HI_STARTED=()

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function _hi_assert() {
  local label="$1"
  shift
  if "$@"; then
    _hi_cecho " | $label: OK" "$GREEN"
  else
    _hi_cecho " | $label: FAILED" "$RED"
    return 1
  fi
}

# shellcheck disable=SC2329 # trap function is never invoked directly
function _hi_cleanup() {
  local c
  for c in "${_HI_STARTED[@]:-}"; do
    [ -n "$c" ] && docker stop -t 0 "$c" >/dev/null 2>&1 || true
  done
  rm -rf "$_HI_WORKDIR"
}
_hi_on_exit _hi_cleanup
_hi_h1 "Testing hi's ssh cleanup trap survives an abrupt disconnect"
_hi_h2 "generating throwaway ed25519 keypair at $_HI_WORKDIR/id"
ssh-keygen -t ed25519 -N '' -q -f "$_HI_WORKDIR/id"
_HI_PUBKEY="$(cat "$_HI_WORKDIR/id.pub")"

# --- build the throwaway sshd image ---------------------------------------
# a short ClientAlive setting so the server gives up on a gone-silent client
# in a few seconds instead of the OS-default TCP timeout (minutes to hours) -
# see the file header for why that's what's actually under test here
mkdir -p "$_HI_WORKDIR/image"
cat >"$_HI_WORKDIR/image/Dockerfile" <<'EOF'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server openssl bash \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF
cat >"$_HI_WORKDIR/image/entrypoint.sh" <<'EOF'
#!/bin/bash
set -e
echo "hitest:*" | chpasswd -e
chown hitest:hitest /home/hitest
install -d -m 700 -o hitest -g hitest /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown hitest:hitest /home/hitest/.ssh/authorized_keys
chmod 600 /home/hitest/.ssh/authorized_keys
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e -o PasswordAuthentication=no -o PermitRootLogin=no -o UsePAM=no \
  -o ClientAliveInterval=2 -o ClientAliveCountMax=1
EOF

_hi_h2 "Building test image"
_hi_h3 "building hi-sshdisconnecttest from $_HI_WORKDIR/image (log: $_HI_WORKDIR/image.log)"
if ! docker build -q -t hi-sshdisconnecttest "$_HI_WORKDIR/image" >/dev/null 2>"$_HI_WORKDIR/image.log"; then
  _hi_cecho " | image failed to build, skipping (see $_HI_WORKDIR/image.log)" "$YELLOW"
  exit 0
fi

# --- start the one container both cases share -----------------------------
_HI_CONTAINER="hi-sshdisconnecttest-$$"
if ! docker run -d --rm --name "$_HI_CONTAINER" -p 127.0.0.1::22 \
  -e "PUBKEY=$_HI_PUBKEY" "hi-sshdisconnecttest" >/dev/null 2>"$_HI_WORKDIR/container.log"; then
  _hi_cecho " | failed to start container" "$RED"
  exit 1
fi
_HI_STARTED+=("$_HI_CONTAINER")

_HI_PORT="$(docker port "$_HI_CONTAINER" 22/tcp | head -1 | sed 's/.*://')"
_hi_cecho " | container: $_HI_CONTAINER (port: $_HI_PORT)"

# shellcheck disable=SC2329 # invoked indirectly, via _hi_poll_bool's "$@"
function _hi_ssh_disconnect_reachable() {
  ssh -i "$_HI_WORKDIR/id" -p "$_HI_PORT" -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=2 \
    hitest@127.0.0.1 true
}

_hi_cecho " | waiting for sshd on 127.0.0.1:$_HI_PORT"
if ! _hi_poll_bool 40 0.25 _hi_ssh_disconnect_reachable; then
  _hi_cecho " | sshd never came up" "$RED"
  exit 1
fi

# every local ssh process belonging to this session - the interactive client
# plus hi.sh's own ControlMaster, if the multiplexed connection spun one up
# shellcheck disable=SC2329 # invoked from the test_* functions below
function _hi_ssh_disconnect_pids() {
  pgrep -f -- "ssh .*-p $_HI_PORT .*hitest@127.0.0.1" 2>/dev/null || true
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_poll_bool's "$@"
function _hi_cleanup_dir_gone() {
  ! docker exec "$_HI_CONTAINER" test -d "$1" 2>/dev/null
}

# ---- the actual cases -------------------------------------------------

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_clean_exit_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/clean.out" cleanup_dir

  _hi_pty_wrap 0 auto "no tty and no python3 to fake one - results may be unreliable"
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" -p "$_HI_PORT" -i "$_HI_WORKDIR/id" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -o IdentitiesOnly=yes -o ConnectTimeout=5 hitest@127.0.0.1 \
    'echo READY:$_HI_CLEANUP' >"$out_file" 2>&1 || true

  # hi.sh's own connect-progress output has no trailing newline before the
# command's own output starts, so READY: often lands mid-line behind raw
# terminal escape/erase codes from the pty transcript - extract it by
# pattern, not by anchoring on the start of a line
cleanup_dir="$(grep -oE 'READY:[^[:space:]]*' "$out_file" | sed 's/^READY://' | head -1)"
  [ -n "$cleanup_dir" ] || return 1
  # the session already ran to completion (ssh above was synchronous), so the
  # target-side trap has already had its chance to fire by now
  ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null
}

# shellcheck disable=SC2329 # invoked indirectly, via _hi_case's "$@"
function test_sudden_disconnect_removes_cleanup_dir() {
  local out_file="$_HI_WORKDIR/disconnect.out" cleanup_dir launcher_pid pid ok=0
  local -a pids=()
  : >"$out_file"

  exec 3<&0
  _hi_pty_wrap 3 auto "no tty and no python3 to fake one - results may be unreliable"
  # shellcheck disable=SC2016 # $_HI_CLEANUP expands on the target, not here
  "${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" -p "$_HI_PORT" -i "$_HI_WORKDIR/id" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -o IdentitiesOnly=yes -o ConnectTimeout=5 hitest@127.0.0.1 \
    'echo READY:$_HI_CLEANUP; sleep 30' <&3 >"$out_file" 2>&1 &
  launcher_pid=$!

  # confirm the session is actually up before freezing anything - racing the
  # freeze against a connection that hasn't started yet would be a false pass
  if ! _hi_poll_bool 40 0.25 grep -q 'READY:' "$out_file"; then
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi
  # hi.sh's own connect-progress output has no trailing newline before the
  # command's own output starts, so READY: often lands mid-line behind raw
  # terminal escape/erase codes from the pty transcript - extract it by
  # pattern, not by anchoring on the start of a line
  cleanup_dir="$(grep -oE 'READY:[^[:space:]]*' "$out_file" | sed 's/^READY://' | head -1)"
  if [ -z "$cleanup_dir" ] || ! docker exec "$_HI_CONTAINER" test -d "$cleanup_dir" 2>/dev/null; then
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi

  mapfile -t pids < <(_hi_ssh_disconnect_pids)
  if [ "${#pids[@]}" -eq 0 ]; then
    _hi_cecho " | no local ssh process found to freeze" "$RED"
    kill -9 "$launcher_pid" 2>/dev/null || true
    return 1
  fi
  for pid in "${pids[@]}"; do kill -STOP "$pid" 2>/dev/null || true; done

  _hi_poll_bool 60 0.5 _hi_cleanup_dir_gone "$cleanup_dir" && ok=1

  for pid in "${pids[@]}"; do kill -9 "$pid" 2>/dev/null || true; done
  _hi_wait_pid "$launcher_pid" 5

  [ "$ok" -eq 1 ]
}

_HI_FAILED=0
_HI_TOTAL=0

_hi_h2 "Cleanup on disconnect"
_hi_case _hi_assert "clean exit removes the cleanup dir" test_clean_exit_removes_cleanup_dir
_hi_case _hi_assert "sudden (frozen-connection) disconnect still removes it" test_sudden_disconnect_removes_cleanup_dir

if [ "$_HI_FAILED" -eq 0 ]; then
  _hi_h1 "hi's ssh cleanup trap survived every case ($_HI_TOTAL cases)"
else
  _hi_h1 "hi's ssh cleanup trap FAILED: $_HI_FAILED/$_HI_TOTAL cases" "$RED"
fi

docker image rm -f hi-sshdisconnecttest >/dev/null 2>&1 || true
exit "$_HI_FAILED"
