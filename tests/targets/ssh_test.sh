#!/bin/bash
# Boots throwaway sshd containers - one per remote login shell - and drives
# hi.sh's real ssh path (_say_hi) against each of them over actual ssh. This
# proves the base64 armor/quoting in _say_hi survives whichever shell sshd
# hands the incoming "sh -c '...'" command to server-side, not just bash/dash.
# One of those containers runs bash 3.2 (what macOS ships) rather than a
# current bash, which is what keeps hi free of bash-4-only builtins.
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

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# "<label>=<0|1>" through test_lib.sh's _hi_kv_get/_hi_kv_set rather than an
# associative array, which is bash 4 (macOS ships 3.2)
_HI_ALPINE_OK=""

function _hi_run_case() {
  local label="$1" image="$2" login_shell="$3" cmd="$4" post="${5:-}" name out exit_code=0 t0 t1 ok=1

  name="hi-sshtest-$label-$$"
  _hi_h3 "Testing login shell: $label ($login_shell)"
  t0="$(_hi_now)"

  _hi_sshd_container "$name" "$image" -e "LOGIN_SHELL=$login_shell" || return 1

  _hi_cecho " | Running: $_HI_LAUNCHER -p $_HI_SSH_PORT hitest@127.0.0.1 $cmd"
  _hi_ssh_launch "$_HI_SSH_PORT"
  # Backgrounded and waited on rather than a bare command substitution: a
  # target that never returns has to fail this case, not hang the suite. A
  # one-line mistake in the fallback rc left the `nobash` case sitting in a
  # command substitution for 36 minutes before anyone noticed, because there
  # was nothing here to stop it. 124 is _hi_wait_pid's timeout status.
  #
  # `<&3` is load-bearing and belongs with the _hi_pty_stdin call in
  # run_ssh_tests below - the two only work as a pair (see _hi_pty_stdin in
  # test_lib.sh). Backgrounding is exactly what takes stdin away: with job
  # control off, bash points a background job's fd 0 at /dev/null no matter
  # what ours was, `ssh -t` then can't allocate a pty, and a remote
  # `bash --rcfile` with no tty is not interactive - so it ignores the rcfile
  # outright and every case that hands off to bash fails with no output past
  # hi's connect prefix.
  local out_file="$_HI_WORKDIR/$label.ssh.out"
  "${_HI_SSH_LAUNCH[@]}" "$cmd" <&3 >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "${_HI_SSH_CASE_TIMEOUT:-90}"
  exit_code="$_HI_WAIT_EXIT"
  out="$(cat "$out_file" 2>/dev/null)"
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

function _hi_run_interactive_case() {
  local label="$1" image="$2" login_shell="$3" post="${4:-}" name ok=0

  name="hi-sshtest-$label-$$"
  _hi_h3 "Testing interactive session: $label ($login_shell)"

  _hi_sshd_container "$name" "$image" -e "LOGIN_SHELL=$login_shell" || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"

  if _hi_interactive_case "$label" "ssh path" "$_HI_MARKER" 90 "${_HI_SSH_LAUNCH_BARE[@]}"; then
    ok=1
    if [ -n "$post" ] && ! docker exec "$name" sh -c "$post" >/dev/null 2>&1; then
      _hi_h3 " | [$label] -- post-check FAILED: $post" "$RED"
      ok=0
    fi
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

    if _hi_build_image "$_hi_label" "hi-sshtest-$_hi_label-$$" "its fallback case" "$_hi_ctx"; then
      _hi_kv_set _HI_ALPINE_OK "$_hi_label" 1
    else
      _hi_kv_set _HI_ALPINE_OK "$_hi_label" 0
    fi
  done

  # A bash 3.2 target - the version macOS still ships, and the one every bash 4
  # builtin hi might reach for (mapfile, `declare -A`, namerefs, globstar) is
  # missing from. Built on the official bash:3.2 image with sshd on top, and
  # bash 3.2 as hitest's login shell, so both halves of a session run under it:
  # the payload sshd hands the login shell, and the interactive `bash --rcfile`
  # load.sh chainloads into.
  _HI_BASH32_OK=0
  _hi_ctx="$_HI_WORKDIR/bash32"
  mkdir -p "$_hi_ctx"
  printf 'FROM bash:3.2\nRUN apk add --no-cache openssh openssl \\\n    && ln -sf /usr/local/bin/bash /bin/bash \\\n    && adduser -D -s /usr/local/bin/bash hitest\nCOPY entrypoint.sh /entrypoint.sh\nRUN chmod +x /entrypoint.sh\nENTRYPOINT ["/entrypoint.sh"]\n' >"$_hi_ctx/Dockerfile"
  {
    printf '#!/bin/sh\nset -e\n'
    printf '%s\n' "$_HI_SSHD_ENTRYPOINT_BODY"
  } >"$_hi_ctx/entrypoint.sh"
  _hi_build_image bash32 "hi-sshtest-bash32-$$" "the bash 3.2 case" "$_hi_ctx" && _HI_BASH32_OK=1

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
    _hi_build_image debian-installed "hi-sshtest-debian-installed-$$" "the pre-installed case" \
      -f "$_HI_WORKDIR/debian-installed/Dockerfile" "$_HI_ROOT" && _HI_INSTALLED_OK=1
  fi

  _HI_MARKER="HI_SSH_TEST_OK"

  _hi_pty_stdin auto "no tty and no python3 to fake one - ssh -t may not get a real pty, results may be unreliable"
  _hi_pty_force

  _hi_suite_begin

  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    for _hi_pair in bash:/bin/bash dash:/bin/dash zsh:/usr/bin/zsh fish:/usr/bin/fish; do
      _hi_case _hi_run_case "${_hi_pair%%:*}" "$_HI_SSHD_IMAGE" "${_hi_pair#*:}" "$(_hi_probe_cmd "$_HI_MARKER" bash)"
    done
  fi

  for _hi_case_spec in nobash:alpine:ssh_fallback nobash-zsh:alpine-zsh:ssh_fallback nobash-fish:alpine-fish:ssh_fallback_fish; do
    IFS=: read -r _hi_label _hi_image _hi_shape <<<"$_hi_case_spec"
    if [ "$(_hi_kv_get _HI_ALPINE_OK "$_hi_image")" = 1 ]; then
      _hi_case _hi_run_case "$_hi_label" "hi-sshtest-$_hi_image-$$" /bin/ash "$(_hi_probe_cmd "$_HI_MARKER" "$_hi_shape")"
    fi
  done

  if [ "$_HI_BASH32_OK" -eq 1 ]; then
    _hi_case _hi_run_case bash32 "hi-sshtest-bash32-$$" /usr/local/bin/bash "$(_hi_probe_cmd "$_HI_MARKER" bash)"
    # The shape that matters for bash 3.2: $CMDARG replaces load() outright in
    # the bootloader, so a command-shaped case never reaches the header, the rc
    # graft, the shell handoff or clean_all - which is where every bash-4-only
    # builtin hi could reach for actually gets used.
    _hi_case _hi_run_interactive_case bash32-interactive "hi-sshtest-bash32-$$" /usr/local/bin/bash \
      '! ls -d /tmp/*.hi.* >/dev/null 2>&1'
    # ...and the assertion that gives those two teeth. A bash-4-ism on bash 3.2
    # mostly *doesn't* break the session - it prints "mapfile: command not
    # found" and carries on with a wrong count - so a marker-and-cleanup check
    # passes right through it. Both transcripts have to be clean instead.
    _hi_case _hi_transcript_is_clean bash32 "$_HI_WORKDIR/bash32.ssh.out"
    _hi_case _hi_transcript_is_clean bash32-interactive "$_HI_WORKDIR/bash32-interactive.interactive.out"
  fi

  if [ "$_HI_INSTALLED_OK" -eq 1 ]; then
    _hi_case _hi_run_case installed "hi-sshtest-debian-installed-$$" /bin/bash "$(_hi_probe_cmd "$_HI_MARKER" installed)" \
      'test -f /home/hitest/hi.d/.installed_sentinel'
    # the one case that catches load.sh's clean_all deleting the target's own
    # permanent install: a command-shaped case can't, since $CMDARG means
    # clean_all never runs at all. Also asserts the rc graft came back out.
    _hi_case _hi_run_interactive_case installed-interactive "hi-sshtest-debian-installed-$$" /bin/bash \
      'test -f /home/hitest/hi.d/.installed_sentinel && test -x /home/hitest/hi.d/hi.sh && ! grep -q hi-config-start /home/hitest/.bashrc'
  fi

  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    # the mirror image: a tree hi *did* ship over has to be gone afterwards,
    # so the guard above can't be satisfied by never cleaning up at all
    _hi_case _hi_run_interactive_case copied-interactive "$_HI_SSHD_IMAGE" /bin/bash \
      '! ls -d /tmp/*.hi.* >/dev/null 2>&1'
  fi

  # $$-suffixed like the container names above: these are this run's images,
  # and removing bare `hi-sshtest-alpine` would yank the tree out from under a
  # concurrent run on the same host mid-case. $_HI_SSHD_IMAGE is deliberately
  # *not* removed - it's shared with ssh_disconnect_test.sh so a full run
  # builds it once rather than twice.
  docker image rm -f "hi-sshtest-alpine-$$" "hi-sshtest-alpine-zsh-$$" "hi-sshtest-alpine-fish-$$" \
    "hi-sshtest-bash32-$$" "hi-sshtest-debian-installed-$$" >/dev/null 2>&1 || true

  _hi_suite_end "" \
    "hi's ssh path survived every login shell tested ($_HI_TOTAL cases)" \
    "hi's ssh path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_ssh_tests
