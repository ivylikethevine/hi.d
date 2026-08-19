# `hi --color-preview`: what every ssh host and your user resolve to, in the
# colors they actually render in. Render with `vhs docs/tapes/color_preview.tape`
# from the repo root, with hi on PATH. Manual artifact, reviewed by eye.
#
# The only tape that needs no backend at all - the preview reads files, not
# targets, so there is nothing to start and nothing to tear down.
#
# docs/tapes/fixtures.sh writes a throwaway $HOME holding the ssh config and the
# colors overlay, and the Hide block points $HOME and $_HI_CONFIG_DIR at it.
# Both, because they travel differently: common/paths.sh derives the ssh config
# from $HOME every time it is sourced, but only *reads* $_HI_CONFIG_DIR. This is
# not neatness: reading the renderer's own ~/.ssh/config would put their
# hostnames into a committed GIF.

Output docs/demos/color_preview.gif

Set FontSize 15
Set Width 1100
Set Height 700
Set TypingSpeed 60ms

Require hi

Hide
Type "docs/tapes/fixtures.sh up colors >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@60s /fixture-ok/
Type "export HOME=/tmp/hi-demo/home"
Enter
Type "export _HI_CONFIG_DIR=/tmp/hi-demo/home/.config/hi.d"
Enter
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# every ssh host, and the color each resolves to"
Enter
Sleep 1s
Type "hi --color-preview"
Enter
Wait+Screen@30s /PREVIEW/
Sleep 6s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
