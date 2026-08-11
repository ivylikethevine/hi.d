#!/bin/bash
# Boots throwaway sshd containers - one per remote login shell - and drives
# hi.sh's real ssh path (_say_hi) against each of them over actual ssh. This
# proves the base64 armor/quoting in _say_hi survives whichever shell sshd
# hands the incoming "sh -c '...'" command to server-side, not just bash/dash.
# Also boots one extra debian container with hi.d pre-installed (as
# scripts/install.sh would leave it) to prove _say_hi detects it and loads it
# in place instead of copying a fresh one over, plus two bash-less alpine
# images - one with only zsh, one with only fish - to prove those two tiers of
# _hi_remote_suffix's `for _hi_s in zsh fish sh` fallback probe actually get
# picked when they're what's available, not just the sh tier (the plain
# bash-less alpine image below only ever exercises sh, since it has neither
# zsh nor fish installed).
# The debian image itself comes from test_lib.sh's _hi_sshd_image, shared with
# ssh_disconnect_test.sh so a full run builds it once rather than twice.
# Everything is ephemeral and bound to 127.0.0.1 only; nothing touches the
# user's real ~/.ssh/config or ~/.ssh/known_hosts. Skips cleanly if docker
# isn't installed/running. Needs network access the first time it runs, to
# build the test images (cached by docker afterwards).
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

_hi_require_backend docker "not installed"

_hi_workdir sshtest
_hi_h1 "Testing hi's ssh path across remote login shells"
_hi_ssh_keypair

# --- build the throwaway sshd images -----------------------------------
# the shared debian image covers every shell that also has bash installed
# (bash's presence, not the login shell, is what _say_hi branches on); the
# alpine images exercise its no-bash fallback path - plain alpine has neither
# zsh nor fish, so it only ever reaches the fallback's sh tier; alpine-zsh/
# alpine-fish each add exactly one of those, to reach the tiers ahead of it in
# the probe.
_hi_h2 "Building test images"
_HI_DEBIAN_OK=1
_hi_sshd_image || _HI_DEBIAN_OK=0
[ "$_HI_DEBIAN_OK" -eq 1 ] || _hi_cecho " | Debian image failed to build, skipping its shells (see $_HI_WORKDIR/sshd.log)" "$YELLOW"

# label:extra apk package - one image per no-bash tier of the fallback probe,
# all three sharing one Dockerfile/entrypoint shape rather than four
# hand-unrolled near-copies
declare -A _HI_ALPINE_OK=()
for _hi_img in alpine: alpine-zsh:zsh alpine-fish:fish; do
  _hi_label="${_hi_img%%:*}"
  _hi_ctx="$_HI_WORKDIR/$_hi_label"
  mkdir -p "$_hi_ctx"
  printf 'FROM alpine:3.20\nRUN apk add --no-cache openssh openssl %s \\\n    && adduser -D -s /bin/ash hitest\nCOPY entrypoint.sh /entrypoint.sh\nRUN chmod +x /entrypoint.sh\nENTRYPOINT ["/entrypoint.sh"]\n' "${_hi_img#*:}" >"$_hi_ctx/Dockerfile"
  # alpine has no usermod (that's shadow, not busybox), so unlike the debian
  # entrypoint this one can't honour $LOGIN_SHELL - these images only ever run
  # with the ash login shell adduser gave them, which is all the no-bash
  # fallback cases need
  {
    printf '#!/bin/sh\nset -e\n'
    printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
  } >"$_hi_ctx/entrypoint.sh"

  _hi_h3 "Building hi-sshtest-$_hi_label from $_hi_ctx"
  if docker build -q -t "hi-sshtest-$_hi_label" "$_hi_ctx" >/dev/null 2>"$_HI_WORKDIR/$_hi_label.log"; then
    _HI_ALPINE_OK[$_hi_label]=1
  else
    _HI_ALPINE_OK[$_hi_label]=0
    _hi_cecho " | ${_hi_label} image failed to build, skipping its fallback case (see $_HI_WORKDIR/$_hi_label.log)" "$YELLOW"
  fi
done

# one more image, layered on the shared debian one, with a real checkout of
# this repo already sitting at ~/hi.d - i.e. what a host looks like after
# scripts/install.sh has run there. The build context is $_HI_ROOT itself
# (this checkout), so it's an exact copy, uncommitted changes included.
_HI_INSTALLED_OK=$_HI_DEBIAN_OK
if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
  mkdir -p "$_HI_WORKDIR/debian-installed"
  cat >"$_HI_WORKDIR/debian-installed/Dockerfile" <<EOF
FROM $_HI_SSHD_IMAGE
COPY --chown=hitest:hitest . /home/hitest/hi.d
RUN chmod +x /home/hitest/hi.d/hi.sh \\
    && touch /home/hitest/hi.d/.installed_sentinel \\
    && chown hitest:hitest /home/hitest/hi.d/.installed_sentinel
EOF
  _hi_cecho " | Building hi-sshtest-debian-installed from $_HI_ROOT"
  docker build -q -t hi-sshtest-debian-installed \
    -f "$_HI_WORKDIR/debian-installed/Dockerfile" "$_HI_ROOT" \
    >/dev/null 2>"$_HI_WORKDIR/debian-installed.log" || _HI_INSTALLED_OK=0
fi
[ "$_HI_INSTALLED_OK" -eq 1 ] || _hi_cecho " | Debian-installed image failed to build, skipping the pre-installed case (see $_HI_WORKDIR/debian-installed.log)" "$YELLOW"

# --- the actual per-shell test -----------------------------------------
_HI_MARKER="HI_SSH_TEST_OK"

# _say_hi's bash branch only sources hi.bashrc if bash *is* interactive,
# which it only is if ssh actually allocated a remote pty. A lone `ssh -t`
# silently skips that when *our own* stdin isn't a terminal - true whenever
# this runs headless/CI, or even here since $() always redirects stdout but
# leaves stdin as-is. Route through a locally-faked pty in that case so the
# test is reliable everywhere, not just when someone happens to run it from
# an interactive terminal.
_hi_pty_wrap 0 auto "no tty and no python3 to fake one - ssh -t may not get a real pty, results may be unreliable"

_hi_suite_begin

function _hi_run_case() {
  local label="$1" image="$2" login_shell="$3" cmd="$4" post="${5:-}" name port out exit_code=0 t0 t1 ok=1

  name="hi-sshtest-$label-$$"
  _hi_h3 "Testing login shell: $label"
  t0="$(_hi_now)"

  if ! docker run -d --rm --name "$name" -p 127.0.0.1::22 \
    -e "PUBKEY=$_HI_PUBKEY" -e "LOGIN_SHELL=$login_shell" "$image" >/dev/null 2>"$_HI_WORKDIR/$label.log"; then
    _hi_cecho " | Failed to start container" "$RED"
    return 1
  fi
  _hi_track_container "$name"
  _hi_cecho " | Container: $name (login shell: $login_shell)"

  port="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"
  _hi_cecho " | Waiting for sshd on 127.0.0.1:$port"
  if ! _hi_poll_bool 40 0.25 _hi_ssh_reachable "$port"; then
    _hi_cecho " | Sshd never came up" "$RED"
    return 1
  fi

  _hi_cecho " | Running: $_HI_LAUNCHER -p $port hitest@127.0.0.1 $cmd"
  out="$("${_HI_PTY_WRAP[@]}" "$_HI_LAUNCHER" -p "$port" -i "$_HI_WORKDIR/id" "${_HI_SSH_OPTS[@]}" \
    -o ConnectTimeout=5 hitest@127.0.0.1 "$cmd" 2>&1)" || exit_code=$?
  t1="$(_hi_now)"

  if printf '%s' "$out" | grep -q "$_HI_MARKER"; then
    if [ -n "$post" ] && ! docker exec "$name" sh -c "$post" >/dev/null 2>&1; then
      _hi_h3 " | [$label] -- post-check FAILED: $post ($(_hi_elapsed "$t0" "$t1")s)"
      ok=0
    else
      _hi_cecho " | [$label] -- ssh path OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    fi
  else
    _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)"
    printf '%s\n' "$out" | sed 's/^/      /'
    ok=0
  fi

  docker rm -f "$name" >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
  for _hi_pair in bash:/bin/bash dash:/bin/dash zsh:/usr/bin/zsh fish:/usr/bin/fish; do
    _hi_case _hi_run_case "${_hi_pair%%:*}" "$_HI_SSHD_IMAGE" "${_hi_pair#*:}" "$(_hi_probe_cmd "$_HI_MARKER" bash)"
  done
fi

# label:image-suffix:probe shape - the plain and zsh tiers assert through the
# same posix dialect, fish needs its own
for _hi_case_spec in nobash:alpine:ssh_fallback nobash-zsh:alpine-zsh:ssh_fallback nobash-fish:alpine-fish:ssh_fallback_fish; do
  _hi_label="${_hi_case_spec%%:*}"
  _hi_rest="${_hi_case_spec#*:}"
  _hi_image="${_hi_rest%%:*}"
  if [ "${_HI_ALPINE_OK[$_hi_image]}" -eq 1 ]; then
    _hi_case _hi_run_case "$_hi_label" "hi-sshtest-$_hi_image" /bin/ash "$(_hi_probe_cmd "$_HI_MARKER" "${_hi_rest#*:}")"
  fi
done

if [ "$_HI_INSTALLED_OK" -eq 1 ]; then
  _hi_case _hi_run_case installed hi-sshtest-debian-installed /bin/bash "$(_hi_probe_cmd "$_HI_MARKER" installed)" \
    'test -f /home/hitest/hi.d/.installed_sentinel'
fi

# $_HI_SSHD_IMAGE is deliberately left behind - see test_lib.sh's comment on
# it; only this suite's own images go
docker image rm -f hi-sshtest-alpine hi-sshtest-alpine-zsh hi-sshtest-alpine-fish hi-sshtest-debian-installed >/dev/null 2>&1 || true

_hi_suite_end "" \
  "hi's ssh path survived every login shell tested ($_HI_TOTAL cases)" \
  "hi's ssh path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
