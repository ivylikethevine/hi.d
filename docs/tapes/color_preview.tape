# `hi --color-preview`: what every ssh host and your user resolve to, in the
# colors they actually render in. Render with `vhs docs/tapes/color_preview.tape`
# from the repo root, with hi on PATH. Manual artifact, reviewed by eye.
#
# Its configuration: a `colors` overlay rather than a settings.sh - the one demo
# whose whole subject is a config file rather than a session. It lives in the
# same overlay dir every other demo uses, and the clientrc fixtures.sh writes
# already points $_HI_CONFIG_DIR there, so nothing below has to.
#
# The only tape that needs no backend at all - the preview reads files, not
# targets, so there is nothing to start and nothing to tear down.
#
# $HOME is exported below, and only $HOME: common/paths.sh derives the ssh
# config from it every time it is sourced, so a throwaway one is the only way to
# put demo hostnames in front of the preview. That is not neatness - reading the
# renderer's own ~/.ssh/config would put their hostnames into a committed GIF.

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
