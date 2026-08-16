#!/bin/sh
# stdin -> the *client's* clipboard, over OSC 52: the escape rides the session's
# pty back to the terminal emulator, so nothing is needed on the target. Run,
# not sourced - by `hi_copy` (shells/aliases.sh) and misc/vim.rc's yank autocmd,
# which is why the wrapping below lives in one file rather than in both.
set -eu

_hi_b64="$(base64 | tr -d '\r\n')"

# terminals cap the payload (~75KB in xterm, less elsewhere) and drop anything
# longer in silence, which reads as "paste gave me my previous clipboard"
if [ "${#_hi_b64}" -gt 100000 ]; then
  echo "hi_copy: too much text for OSC 52 (terminals cap the payload); clipboard unchanged" >&2
  exit 1
fi

_hi_esc="\033]52;c;$_hi_b64\a"

# tmux and screen swallow an OSC they don't know unless it is wrapped in their
# passthrough. $TMUX is tested first: tmux commonly leaves TERM as screen-*.
if [ -n "${TMUX:-}" ]; then
  _hi_esc="\033Ptmux;\033$_hi_esc\033\\" # tmux wants the inner ESC doubled
elif [ "${TERM#screen}" != "${TERM:-}" ]; then
  # unchunked: real screen truncates a long DCS, so a big yank under bare screen
  # can arrive clipped - visibly, and rarely enough not to earn a rejoin loop
  _hi_esc="\033P$_hi_esc\033\\"
fi

# The open is the test, not `[ -w /dev/tty ]`: that node is world-writable with
# or without a controlling terminal, so the check passes where the redirect then
# fails. 2>/dev/null first, so the shell's complaint doesn't reach the screen.
printf '%b' "$_hi_esc" 2>/dev/null >/dev/tty || printf '%b' "$_hi_esc"
