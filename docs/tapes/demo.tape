# The README demo, as a script instead of a stale recording: render with
# `vhs docs/tapes/demo.tape` (https://github.com/charmbracelet/vhs) from the
# repo root, with docker running and hi installed on PATH. Regenerate whenever
# the header or prompt changes. Not rendered in CI - docs/demos/demo.gif is a
# manual artifact, reviewed by eye before committing.
#
# Its configuration: none. Every other demo turns a knob (docs/tapes/fixtures.sh
# writes each one a settings.sh); this is the shot that shows the shipped
# defaults with everything on, so it must stay stock to mean anything.
#
# The target is the same debian box docker.tape's first case uses, through
# docs/tapes/fixtures.sh rather than a docker run of its own, so the demo at the
# top of the README cannot drift from the one further down.

Output docs/demos/demo.gif

Source docs/tapes/common.tape

Require hi
Require docker

Hide
Type "docs/tapes/fixtures.sh up demo >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "hi db-prod"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s

Type "cd /tmp && ls"
Enter
Sleep 2s

Type "exit"
Enter
Wait+Screen@30s /hi closing!/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
