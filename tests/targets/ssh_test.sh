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
#
# Nearly every function below is invoked indirectly - by name, through
# _hi_case's/_hi_poll_bool's "$@", or as a trap hook - which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/bootstrap.sh
source "${_HI_HOME:-$HOME}/hi.d/common/bootstrap.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

declare -A _HI_ALPINE_OK=()

function _hi_run_case() {
  local label="$1" image="$2" login_shell="$3" cmd="$4" post="${5:-}" name out exit_code=0 t0 t1 ok=1

  name="hi-sshtest-$label-$$"
  _hi_h3 "Testing login shell: $label ($login_shell)"
  t0="$(_hi_now)"

  _hi_sshd_container "$name" "$image" -e "LOGIN_SHELL=$login_shell" || return 1

  _hi_cecho " | Running: $_HI_LAUNCHER -p $_HI_SSH_PORT hitest@127.0.0.1 $cmd"
  _hi_ssh_launch "$_HI_SSH_PORT"
  out="$("${_HI_SSH_LAUNCH[@]}" "$cmd" 2>&1)" || exit_code=$?
  t1="$(_hi_now)"

  if printf '%s' "$out" | grep -q "$_HI_MARKER"; then
    if [ -n "$post" ] && ! docker exec "$name" sh -c "$post" >/dev/null 2>&1; then
      _hi_h3 " | [$label] -- post-check FAILED: $post ($(_hi_elapsed "$t0" "$t1")s)" "$RED"
      ok=0
    else
      _hi_cecho " | [$label] -- ssh path OK ($(_hi_elapsed "$t0" "$t1")s)" "$GREEN"
    fi
  else
    _hi_h3 " | [$label] -- FAILED (exit $exit_code, $(_hi_elapsed "$t0" "$t1")s)" "$RED"
    printf '%s\n' "$out" | sed 's/^/      /'
    ok=0
  fi

  docker rm -f "$name" >/dev/null 2>&1
  [ "$ok" -eq 1 ]
}

function run_ssh_tests() {
  _hi_require_backend docker

  _hi_workdir sshtest
  _hi_h1 "Testing hi's ssh path across remote login shells"
  _hi_ssh_keypair

  _hi_h2 "Building test images"
  _HI_DEBIAN_OK=1
  _hi_sshd_image "its shells" || _HI_DEBIAN_OK=0

  for _hi_img in alpine: alpine-zsh:zsh alpine-fish:fish; do
    _hi_label="${_hi_img%%:*}"
    _hi_ctx="$_HI_WORKDIR/$_hi_label"
    mkdir -p "$_hi_ctx"
    printf 'FROM alpine:3.20\nRUN apk add --no-cache openssh openssl %s \\\n    && adduser -D -s /bin/ash hitest\nCOPY entrypoint.sh /entrypoint.sh\nRUN chmod +x /entrypoint.sh\nENTRYPOINT ["/entrypoint.sh"]\n' "${_hi_img#*:}" >"$_hi_ctx/Dockerfile"
    {
      printf '#!/bin/sh\nset -e\n'
      printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
    } >"$_hi_ctx/entrypoint.sh"

    _HI_ALPINE_OK[$_hi_label]=1
    _hi_build_image "$_hi_label" "hi-sshtest-$_hi_label" "its fallback case" "$_hi_ctx" ||
      _HI_ALPINE_OK[$_hi_label]=0
  done

  _HI_INSTALLED_OK=0
  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    mkdir -p "$_HI_WORKDIR/debian-installed"
    cat >"$_HI_WORKDIR/debian-installed/Dockerfile" <<EOF
  FROM $_HI_SSHD_IMAGE
  COPY --chown=hitest:hitest . /home/hitest/hi.d
  RUN chmod +x /home/hitest/hi.d/hi.sh \\
      && touch /home/hitest/hi.d/.installed_sentinel \\
      && chown hitest:hitest /home/hitest/hi.d/.installed_sentinel
EOF
    _hi_build_image debian-installed hi-sshtest-debian-installed "the pre-installed case" \
      -f "$_HI_WORKDIR/debian-installed/Dockerfile" "$_HI_ROOT" && _HI_INSTALLED_OK=1
  fi

  _HI_MARKER="HI_SSH_TEST_OK"

  _hi_pty_wrap 0 auto "no tty and no python3 to fake one - ssh -t may not get a real pty, results may be unreliable"

  _hi_suite_begin

  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    for _hi_pair in bash:/bin/bash dash:/bin/dash zsh:/usr/bin/zsh fish:/usr/bin/fish; do
      _hi_case _hi_run_case "${_hi_pair%%:*}" "$_HI_SSHD_IMAGE" "${_hi_pair#*:}" "$(_hi_probe_cmd "$_HI_MARKER" bash)"
    done
  fi

  for _hi_case_spec in nobash:alpine:ssh_fallback nobash-zsh:alpine-zsh:ssh_fallback nobash-fish:alpine-fish:ssh_fallback_fish; do
    IFS=: read -r _hi_label _hi_image _hi_shape <<<"$_hi_case_spec"
    if [ "${_HI_ALPINE_OK[$_hi_image]}" -eq 1 ]; then
      _hi_case _hi_run_case "$_hi_label" "hi-sshtest-$_hi_image" /bin/ash "$(_hi_probe_cmd "$_HI_MARKER" "$_hi_shape")"
    fi
  done

  if [ "$_HI_INSTALLED_OK" -eq 1 ]; then
    _hi_case _hi_run_case installed hi-sshtest-debian-installed /bin/bash "$(_hi_probe_cmd "$_HI_MARKER" installed)" \
      'test -f /home/hitest/hi.d/.installed_sentinel'
  fi

  docker image rm -f hi-sshtest-alpine hi-sshtest-alpine-zsh hi-sshtest-alpine-fish hi-sshtest-debian-installed >/dev/null 2>&1 || true

  _hi_suite_end "" \
    "hi's ssh path survived every login shell tested ($_HI_TOTAL cases)" \
    "hi's ssh path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_ssh_tests
