#!/bin/sh
# stdin -> the *client's* clipboard over OSC 52 - the escape rides the pty
# back, nothing needed on the target. Run, not sourced, by `hi_copy` AND
# vim.rc's yank autocmd - one file so the wrapping isn't written twice.
set -eu

_hi_b64="$(base64 | tr -d '\r\n')"

# terminals cap the payload (~75KB in xterm, less elsewhere) and drop anything
# longer in silence, which reads as "paste gave me my previous clipboard"
if [ "${#_hi_b64}" -gt 100000 ]; then
  echo "hi_copy: too much text for OSC 52 (terminals cap the payload); clipboard unchanged" >&2
  exit 1
fi

_hi_esc="\033]52;c;$_hi_b64\a"

# tmux/screen swallow unknown OSCs unless passthrough-wrapped ($TMUX first:
# tmux leaves TERM as screen-*); zellij is the explicit opposite - it handles
# OSC 52 itself, has no DCS passthrough, and must get the escape raw.
if [ -n "${TMUX:-}" ]; then
  _hi_esc="\033Ptmux;\033$_hi_esc\033\\" # tmux wants the inner ESC doubled
elif [ -n "${ZELLIJ:-}" ]; then
  : # raw
elif [ "${TERM#screen}" != "${TERM:-}" ]; then
  # unchunked: real screen truncates a long DCS, so a big yank under bare screen
  # can arrive clipped - visibly, and rarely enough not to earn a rejoin loop
  _hi_esc="\033P$_hi_esc\033\\"
fi

# the open is the test - `[ -w /dev/tty ]` passes with no controlling
# terminal; 2>/dev/null first so the shell's complaint stays off the screen
printf '%b' "$_hi_esc" 2>/dev/null >/dev/tty || printf '%b' "$_hi_esc"
