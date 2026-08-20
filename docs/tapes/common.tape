# The geometry every demo shares, sourced rather than copied into each tape:
# `Source docs/tapes/common.tape`, which resolves from the repo root the tapes
# are rendered from (docs/tapes/generate.sh, or `vhs docs/tapes/<name>.tape`).
#
# Sourced after a tape's own `Set Shell`, and before anything a tape overrides.
# Nothing else belongs here - `Output`, `Require` and the Hide/Show script stay
# per tape.
#
# Every demo renders at this one geometry, and no tape overrides it. What varies
# between the demos is hi's own configuration - the settings.sh each gets from
# docs/tapes/fixtures.sh - and nothing else, so a reader comparing two GIFs is
# looking at a config difference rather than a frame difference. The height is
# the tightest that still fits the tallest thing any demo draws, which is
# color_preview.tape's table - check that one first if you change it.

Set FontSize 16
Set Width 1100
Set Height 620
Set TypingSpeed 60ms
