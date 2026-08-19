# The geometry every demo shares, sourced rather than copied into each tape:
# `Source docs/tapes/common.tape`, which resolves from the repo root the tapes
# are rendered from (docs/tapes/generate.sh, or `vhs docs/tapes/<name>.tape`).
#
# Sourced after a tape's own `Set Shell`, and before anything a tape overrides:
# later `Set` lines win, which is how color_preview.tape gets a taller frame
# for its table. Nothing else belongs here - `Output`, `Require` and the
# Hide/Show script stay per tape.

Set FontSize 15
Set Width 1100
Set Height 620
Set TypingSpeed 60ms
