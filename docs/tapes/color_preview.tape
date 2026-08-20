# `hi --color-preview`: what every ssh host and your user resolve to, in the
# colors they actually render in. Render with `vhs docs/tapes/color_preview.tape`
# from the repo root, with hi on PATH. Manual artifact, reviewed by eye.
#
# Its configuration: the colors overlay itself, in a throwaway $HOME - the one
# demo whose whole subject is a config file rather than a session.
#
# The only tape that needs no backend at all - the preview reads files, not
# targets, so there is nothing to start and nothing to tear down.
#
# docs/tapes/fixtures.sh writes a throwaway $HOME holding the ssh config and the
# colors overlay. $HOME is exported below because common/paths.sh derives the ssh
# config from it every time it is sourced; $_HI_CONFIG_DIR is not, because the
# clientrc fixtures.sh writes already points there. This is not neatness:
# reading the renderer's own ~/.ssh/config would put their hostnames into a
# committed GIF.

Output docs/demos/color_preview.gif

Source docs/tapes/common.tape

Require hi

Hide
Type "docs/tapes/fixtures.sh up colors >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@60s /fixture-ok/
Type "export HOME=/tmp/hi-demo/home"
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
