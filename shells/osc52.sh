#!/bin/sh
# stdin -> the *client's* clipboard, over OSC 52.
#
# The one piece of "your environment follows you" that otherwise stops at the
# ssh boundary: a yank on a target lands in the clipboard of the machine you are
# sitting at, because the escape travels back up the same pty the session runs
# on and the terminal emulator - not the host - acts on it. No X11 forwarding,
# no clipboard daemon, nothing installed on the target.
#
# Sourced by nothing; it is run: `hi_copy` (shells/aliases.sh) and misc/vim.rc's
# yank autocmd both pipe text in. Kept as its own file rather than inlined in
# both, so the wrapping rules below have one implementation.
#
# Two things make this fiddlier than "print an escape":
#   - /dev/tty, not stdout. In `cmd | hi_copy` stdout is a pipe, and an escape
#     written there reaches a file, not the terminal. Falls back to stdout only
#     when there is no controlling terminal to write to at all.
#   - tmux and screen swallow unknown OSC sequences instead of forwarding them
#     to the outer terminal, so inside either one the payload has to be wrapped
#     in that multiplexer's passthrough (DCS ... ST).
#
# Terminals cap the payload (xterm's default is ~74994 bytes, others lower) and
# drop anything longer without saying so - hence the size guard, which is a
# clamp on nothing but our own noise, not a promise about any given terminal.
set -eu

_hi_b64="$(base64 | tr -d '\r\n')"

# 100000 base64 chars is ~75000 bytes of payload, at the generous end of what
# terminals accept. Past it the escape is dropped anyway; say so rather than
# leaving the user wondering why paste gives them the previous clipboard.
if [ "${#_hi_b64}" -gt 100000 ]; then
  echo "hi_copy: too much text for OSC 52 (terminals cap the payload); clipboard unchanged" >&2
  exit 1
fi

_hi_esc="\033]52;c;$_hi_b64\a"

# TERM is how a screen session announces itself (screen sets screen*); tmux
# sets $TMUX and may leave TERM as screen-256color, so it is tested first.
if [ -n "${TMUX:-}" ]; then
  # tmux's passthrough needs every ESC in the payload doubled; ours is the one
  # in $_hi_esc, and base64 contributes none.
  _hi_esc="\033Ptmux;\033$_hi_esc\033\\"
elif [ "${TERM#screen}" != "${TERM:-}" ]; then
  # screen's DCS passthrough, unchunked. Real screen truncates a DCS string
  # past a few hundred bytes, so a large yank under bare screen (not tmux) can
  # arrive clipped - the case is rare enough not to be worth the chunk-and-
  # rejoin loop, and a clipped paste is visible rather than silent.
  _hi_esc="\033P$_hi_esc\033\\"
fi

# The open is the test, not `[ -w /dev/tty ]`: the device node is world-writable
# whether or not this process has a controlling terminal, so the permission
# check passes in a cron job or a `sh -c` with no tty and the redirect then
# fails anyway. 2>/dev/null comes first so the shell's own "no such device"
# lands there rather than on the user's screen.
printf '%b' "$_hi_esc" 2>/dev/null >/dev/tty || printf '%b' "$_hi_esc"
