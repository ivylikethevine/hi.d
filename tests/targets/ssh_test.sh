#!/bin/bash
# Throwaway sshd containers - one per remote login shell - driven through
# hi.sh's real ssh path over actual ssh, which is what proves _say_hi's
# armor and quoting survive whatever shell sshd hands the command to. The
# images cover: bash/dash/zsh/fish logins; bash 3.2 (what macOS ships, and what
# keeps hi free of bash-4 builtins); a pre-installed hi.d, to prove _say_hi
# loads it in place rather than shipping a tree; bash-less alpine with only zsh
# with only fish, and with only mksh, for the fallback tiers the plain alpine
# image never reaches; and that same install plus tmux, for --tmux. The debian base comes
# from test_lib.sh's _hi_sshd_image, shared with ssh_disconnect_test.sh.
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

# <label> <image> <login_shell> <cmd> [post] [extra-marker...] - anything past
# $5 is handed to _hi_case_result as a further must-appear transcript marker
# (the same variadic contract _hi_run_ksh_git_case uses for the branch name)
function _hi_run_case() {
  local label="$1" image="$2" login_shell="$3" cmd="$4" post="${5:-}" name exit_code=0 t0 t1 ok=0

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
  t1="$(_hi_now)"

  # the shared verdict, then the same post-check shape _hi_run_interactive_case uses
  if _hi_case_result "$label" "ssh path" "$exit_code" "$t0" "$t1" "$out_file" "$_HI_TEST_MARKER" "${@:6}"; then
    ok=1
    if [ -n "$post" ] && ! docker exec "$name" sh -c "$post" >/dev/null 2>&1; then
      _hi_h3 " | [$label] -- post-check FAILED: $post" "$RED"
      ok=0
    fi
  fi

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

function _hi_run_interactive_case() {
  local label="$1" image="$2" login_shell="$3" post="${4:-}" name ok=0

  name="hi-sshtest-$label-$$"
  _hi_h3 "Testing interactive session: $label ($login_shell)"

  _hi_sshd_container "$name" "$image" -e "LOGIN_SHELL=$login_shell" || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"

  if _hi_interactive_case "$label" "ssh path" "$_HI_TEST_MARKER" 90 "${_HI_SSH_LAUNCH_BARE[@]}"; then
    ok=1
    if [ -n "$post" ] && ! docker exec "$name" sh -c "$post" >/dev/null 2>&1; then
      _hi_h3 " | [$label] -- post-check FAILED: $post" "$RED"
      ok=0
    fi
  fi

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

# `hi --tmux <target>`: the session runs inside a named tmux on the target, and
# the whole point of it is that a dropped connection detaches rather than losing
# the work. So this case does not drive an interactive session at all - it
# starts one, waits for the tmux session to exist, *kills the client*, and
# asserts the session is still there afterwards. Nothing short of that actually
# tests the promise.
#
# The target is the pre-installed image plus tmux, since load.sh refuses --tmux
# on a disposable tree - a detached tmux would outlive the tree it reads.
function _hi_tmux_session_listed() {
  docker exec -u hitest "$1" tmux ls 2>/dev/null | grep -q "^hi:"
}

function _hi_run_tmux_case() {
  local name="hi-sshtest-tmux-$$" ok=0 session_pid out
  local -a launch

  _hi_h3 "Testing interactive session: tmux (--tmux, permanent install)"
  _hi_sshd_container "$name" "hi-sshtest-debian-tmux-$$" -e "LOGIN_SHELL=/bin/bash" || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"
  # --tmux goes after the launcher and before the target: _hi_parse takes hi's
  # own flags anywhere ahead of the first bare word
  launch=("${_HI_SSH_LAUNCH_BARE[0]}" --tmux "${_HI_SSH_LAUNCH_BARE[@]:1}")
  out="$_HI_WORKDIR/tmux.interactive.out"
  : >"$out"

  # held open by a sleep rather than fed an `exit`: this session is meant to be
  # interrupted, not ended politely
  # shellcheck disable=SC2094 # separate processes; the reader only polls
  { sleep 120; } | "${_HI_PTY_FORCED[@]}" "${launch[@]}" >"$out" 2>&1 &
  session_pid=$!

  if _hi_poll_bool 60 0.5 _hi_tmux_session_listed "$name"; then
    kill -9 "$session_pid" 2>/dev/null || true
    wait "$session_pid" 2>/dev/null || true
    # the session outlived the client that started it, which is the feature
    if _hi_poll_bool 20 0.5 _hi_tmux_session_listed "$name"; then
      ok=1
      _hi_cecho " | [tmux] -- the session survived the dropped connection: OK" "$GREEN"
    else
      _hi_h3 " | [tmux] -- the tmux session died with the client" "$RED"
    fi
  else
    kill -9 "$session_pid" 2>/dev/null || true
    wait "$session_pid" 2>/dev/null || true
    _hi_h3 " | [tmux] -- no tmux session was ever created" "$RED"
    sed 's/^/      /' "$out" | tail -5
  fi

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

# The bash-less ksh/mksh tier's git segment (shells/ksh.sh), which is the one
# thing in hi's prompt that has to be recomputed per line without bash around.
# It has to be an *interactive* case: the command-shaped nobash-ksh case above
# goes through $CMDARG and never draws a prompt at all.
#
# The login directory is made the repo rather than cd-ing into one, so the very
# first prompt already carries the segment and the driver stays the shared one.
# The branch name is the assertion: a pty echoes back everything typed, and
# nothing types this, so finding it in the transcript means mksh expanded
# $(_hi_ksh_git) while drawing the prompt.
function _hi_run_ksh_git_case() {
  local image="$1" name="hi-sshtest-kshgit-$$" branch="hi-ksh-probe" ok=0

  _hi_h3 "Testing the mksh tier's git segment"
  _hi_sshd_container "$name" "$image" -e "LOGIN_SHELL=/bin/ash" || return 1

  # identity and safe.directory passed with -c rather than written by
  # `git config`: the exec runs as root inside a directory owned by hitest,
  # which is exactly the dubious-ownership case git refuses to write config in
  if ! docker exec "$name" sh -c "
    G=\"git -c safe.directory=/home/hitest -c user.email=test@example.com -c user.name=Test -C /home/hitest\"
    \$G init -q -b $branch . &&
    echo tracked > /home/hitest/tracked.txt &&
    \$G add tracked.txt &&
    \$G commit -qm initial &&
    chown -R hitest:hitest /home/hitest" >/dev/null 2>&1; then
    _hi_h3 " | [kshgit] -- could not build the probe repo" "$RED"
    _hi_rm_container "$name"
    return 1
  fi

  _hi_ssh_launch "$_HI_SSH_PORT"

  # The shared driver, with its knobs turned for this tier: no bash means the
  # session never reaches load.sh, so there is no "hi closing" to wait for -
  # the echoed marker is the closing line instead - and the branch name is the
  # extra assertion: nothing types it, so it is in the transcript only because
  # mksh expanded $(_hi_ksh_git) to draw the prompt.
  _hi_interactive_case -c "$_HI_TEST_MARKER-INTERACTIVE" -m "$branch" \
    kshgit "mksh git segment" "$_HI_TEST_MARKER" 90 "${_HI_SSH_LAUNCH_BARE[@]}" && ok=1

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

# A second, plain shell opened *while* a hi session is live reads the same
# grafted ~/.bashrc with none of the session's env - the exact shape of a VS
# Code remote terminal or a second plain ssh landing mid-session. The crash
# guard has to stand the graft down: the bystander asked for the host's own
# shell, and gets it with zero errors. The session must be *interactive* (a
# command-shaped one never grafts - $CMDARG replaces load() outright), so the
# pty feeder holds it open, runs the probe mid-session, and only then types
# exit. The probe rides docker exec rather than a second ssh: what is under
# test is the rc read, not the transport.
function _hi_run_bystander_case() {
  local name="hi-sshtest-bystander-$$" ok=0
  local out_file="$_HI_WORKDIR/bystander.interactive.out"
  local by_file="$_HI_WORKDIR/bystander.by.out"
  local graft_flag="$_HI_WORKDIR/bystander.grafted"
  _hi_h3 "Testing a bystander shell during a live session"
  if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
    _hi_skip "[bystander]" "no python3 to drive an interactive pty"
    return 0
  fi
  _hi_sshd_container "$name" "$_HI_SSHD_IMAGE" -e "LOGIN_SHELL=/bin/bash" || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"
  : >"$out_file"
  rm -f "$by_file" "$graft_flag"
  # same watch-the-transcript shape as _hi_interactive_case; SC2094 does not
  # apply for the same reason it states. The grep is the literal marker,
  # spelled out - this suite doesn't source load.sh, where $_HI_CONFIG_START
  # has its one definition.
  # shellcheck disable=SC2094
  {
    _hi_poll_bool "$((${_HI_INTERACTIVE_SETTLE:-4} * 4))" 0.25 _hi_session_ready "$out_file" || true
    if _hi_poll_bool 40 0.25 docker exec "$name" grep -q '^# hi-config-start' /home/hitest/.bashrc; then
      : >"$graft_flag"
      docker exec -u hitest -e HOME=/home/hitest "$name" bash -ic 'echo BYSTANDER-OK' >"$by_file" 2>&1 || true
    fi
    printf 'exit\n'
    _hi_poll_bool 20 0.25 grep -q "hi closing" "$out_file" || true
  } | "${_HI_PTY_FORCED[@]}" "${_HI_SSH_LAUNCH_BARE[@]}" >"$out_file" 2>&1 &
  _hi_wait_pid "$!" "${_HI_SSH_CASE_TIMEOUT:-90}"
  # the error sweep is the shared vocabulary plus this case's own tells: a
  # graft that ran anyway sources a missing tree ("No such file") or leaves
  # its prompt variable behind (HI_PS1)
  if [ ! -f "$graft_flag" ]; then
    _hi_h3 " | [bystander] -- graft never appeared in ~/.bashrc" "$RED"
  elif grep -q BYSTANDER-OK "$by_file" &&
    ! grep -q -e "No such file" -e HI_PS1 "$by_file" &&
    _hi_transcript_is_clean bystander "$by_file"; then
    ok=1
  else
    _hi_h3 " | [bystander] -- transcript not clean:" "$RED"
    sed 's/^/      /' "$by_file"
  fi
  _hi_rm_container "$name"
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

  # "+" separates extra packages, not a space: the specs are split on
  # whitespace by the loop itself. The mksh image carries git because it is the
  # only one whose prompt has a live git segment to render (shells/ksh.sh).
  for _hi_img in alpine: alpine-zsh:zsh alpine-fish:fish alpine-ksh:mksh+git; do
    _hi_label="${_hi_img%%:*}"
    _hi_ctx="$_HI_WORKDIR/$_hi_label"
    mkdir -p "$_hi_ctx"
    printf 'FROM alpine:3.20\nRUN apk add --no-cache openssh %s \\\n    && adduser -D -s /bin/ash hitest\nCOPY entrypoint.sh /entrypoint.sh\nRUN chmod +x /entrypoint.sh\nENTRYPOINT ["/entrypoint.sh"]\n' \
      "$(printf '%s' "${_hi_img#*:}" | tr '+' ' ')" >"$_hi_ctx/Dockerfile"
    _hi_sshd_entrypoint "$_hi_ctx" /bin/sh

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
  printf 'FROM bash:3.2\nRUN apk add --no-cache openssh \\\n    && ln -sf /usr/local/bin/bash /bin/bash \\\n    && adduser -D -s /usr/local/bin/bash hitest\nCOPY entrypoint.sh /entrypoint.sh\nRUN chmod +x /entrypoint.sh\nENTRYPOINT ["/entrypoint.sh"]\n' >"$_hi_ctx/Dockerfile"
  _hi_sshd_entrypoint "$_hi_ctx" /bin/sh
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

  # the same permanent install, plus tmux, for the --tmux case below
  _HI_TMUX_OK=0
  if [ "$_HI_INSTALLED_OK" -eq 1 ]; then
    mkdir -p "$_HI_WORKDIR/debian-tmux"
    cat >"$_HI_WORKDIR/debian-tmux/Dockerfile" <<EOF
  FROM hi-sshtest-debian-installed-$$
  RUN apt-get update -qq && apt-get install -y -qq tmux >/dev/null
EOF
    _hi_build_image debian-tmux "hi-sshtest-debian-tmux-$$" "the --tmux case" \
      -f "$_HI_WORKDIR/debian-tmux/Dockerfile" "$_HI_WORKDIR/debian-tmux" && _HI_TMUX_OK=1
  fi

  _HI_TEST_MARKER="HI_SSH_TEST_OK"

  # see the registration in the bash32 block below for why this exists; the
  # find runs inside the container so the file list and the parser agree on
  # what a path is
  function test_bash32_parses_every_file() {
    docker run --rm -v "$_HI_HOME/hi.d":/w:ro bash:3.2 bash -c '
      rc=0
      for f in $(find /w -name "*.sh" -not -path "*/.git/*"); do
        out=$(bash -n "$f" 2>&1) || {
          printf "%s\n%s\n" "$f" "$out"
          rc=1
        }
      done
      exit $rc'
  }

  _hi_pty_stdin auto "no tty and no python3 to fake one - ssh -t may not get a real pty, results may be unreliable"
  _hi_pty_force

  _hi_suite_begin

  if [ "$_HI_DEBIAN_OK" -eq 1 ]; then
    for _hi_pair in bash:/bin/bash dash:/bin/dash zsh:/usr/bin/zsh fish:/usr/bin/fish; do
      _hi_case _hi_run_case "${_hi_pair%%:*}" "$_HI_SSHD_IMAGE" "${_hi_pair#*:}" "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
    done

    # The preamble's TERM fallback, all three arms: an unknown name (kitty's
    # xterm-kitty is the common offender; ghostty's xterm-ghostty was the
    # motivating one) swapped for xterm-256color, a ubiquitous name skipped,
    # and a name the skip list ignores but the target's terminfo has
    # (xterm-mono ships in debian's ncurses-base) left alone on the probe's
    # say-so. The env prefix is the client TERM ssh's pty request carries
    # over; the trailing marker is the assertion, matched unanchored since
    # the pty transcript ends lines in \r\n.
    for _hi_term_spec in swap:xterm-kitty:xterm-256color known:xterm-256color:xterm-256color \
      terminfo:xterm-mono:xterm-mono; do
      IFS=: read -r _hi_label _hi_client _hi_want <<<"$_hi_term_spec"
      TERM="$_hi_client" _hi_case _hi_run_case "term-$_hi_label" "$_HI_SSHD_IMAGE" /bin/bash \
        "echo TERMPROBE=\$TERM; echo $_HI_TEST_MARKER" "" "TERMPROBE=$_hi_want"
    done

    _hi_case _hi_run_bystander_case
  fi

  for _hi_case_spec in nobash:alpine:ssh_fallback nobash-zsh:alpine-zsh:ssh_fallback \
    nobash-fish:alpine-fish:ssh_fallback_fish nobash-ksh:alpine-ksh:ssh_fallback; do
    IFS=: read -r _hi_label _hi_image _hi_shape <<<"$_hi_case_spec"
    if [ "$(_hi_kv_get _HI_ALPINE_OK "$_hi_image")" = 1 ]; then
      _hi_case _hi_run_case "$_hi_label" "hi-sshtest-$_hi_image-$$" /bin/ash "$(_hi_probe_cmd "$_HI_TEST_MARKER" "$_hi_shape")"
    fi
  done

  [ "$(_hi_kv_get _HI_ALPINE_OK alpine-ksh)" = 1 ] &&
    _hi_case _hi_run_ksh_git_case "hi-sshtest-alpine-ksh-$$"

  if [ "$_HI_BASH32_OK" -eq 1 ]; then
    _hi_case _hi_run_case bash32 "hi-sshtest-bash32-$$" /usr/local/bin/bash "$(_hi_probe_cmd "$_HI_TEST_MARKER" bash)"
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
    # every *.sh through a real 3.2 parser (`bash -n`): the lint suite's grep
    # table only knows the constructs it lists, while the parser catches the
    # unlisted ones - an apostrophe in a comment inside $( ), say, which 3.2
    # reads as an unterminated string (GLOSSARY: apostrophes in substitution
    # comments). The macOS CI job found that one at runtime; this catches the
    # whole class before a release does.
    _hi_check "every *.sh parses under bash 3.2" test_bash32_parses_every_file
  fi

  if [ "$_HI_INSTALLED_OK" -eq 1 ]; then
    _hi_case _hi_run_case installed "hi-sshtest-debian-installed-$$" /bin/bash "$(_hi_probe_cmd "$_HI_TEST_MARKER" installed)" \
      'test -f /home/hitest/hi.d/.installed_sentinel'
    # the one case that catches load.sh's clean_all deleting the target's own
    # permanent install: a command-shaped case can't, since $CMDARG means
    # clean_all never runs at all. Also asserts the rc graft came back out.
    _hi_case _hi_run_interactive_case installed-interactive "hi-sshtest-debian-installed-$$" /bin/bash \
      'test -f /home/hitest/hi.d/.installed_sentinel && test -x /home/hitest/hi.d/hi.sh && ! grep -q hi-config-start /home/hitest/.bashrc'
    # The same permanent install behind a *fish* login shell. _hi_remote_root's
    # probe reaches that shell before any sh does, and `_r="$HOME/hi.d"` is not
    # an assignment in fish - unwrapped, this answered "nothing installed" and
    # hi shipped a tree the target already had. The marker asserts $_HI_ROOT is
    # the permanent one, so a regression here fails rather than merely wasting
    # a copy.
    _hi_case _hi_run_case installed-fish "hi-sshtest-debian-installed-$$" /usr/bin/fish \
      "$(_hi_probe_cmd "$_HI_TEST_MARKER" installed)"
  fi

  if [ "$_HI_TMUX_OK" -eq 1 ]; then
    if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
      _hi_skip "[tmux]" "no python3 to drive an interactive pty"
    else
      _hi_case _hi_run_tmux_case
    fi
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
    "hi-sshtest-alpine-ksh-$$" \
    "hi-sshtest-bash32-$$" "hi-sshtest-debian-installed-$$" "hi-sshtest-debian-tmux-$$" >/dev/null 2>&1 || true

  _hi_suite_end "" \
    "hi's ssh path survived every login shell tested ($_HI_TOTAL cases)" \
    "hi's ssh path FAILED: $_HI_FAILED/$_HI_TOTAL cases"
}

run_ssh_tests
