# The nomad demo: a dev agent, one docker-driver job, and hi straight into
# the allocation by ID prefix. Render with `vhs docs/tapes/nomad.tape` from
# the repo root, docker running, nomad and hi on PATH; fixtures.sh starts
# the agent and leaves the alloc ID in /tmp/hi-demo/alloc. Manual artifact,
# reviewed by eye.
#
# The Hide blocks pace themselves with Wait+Screen on sentinel text instead
# of fixed sleeps; the quoted split in fixture-o''k keeps the typed command
# from matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/nomad.gif

Set FontSize 15
Set Width 1100
Set Height 620
Set TypingSpeed 60ms

Require hi
Require nomad
Require docker

Hide
Type "docs/tapes/fixtures.sh up nomad >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "clear"
Enter
Show

Sleep 1s
Type "# a nomad allocation, addressed by ID prefix like any other target"
Enter
Type "nomad job status hi-demo | tail -2"
Enter
Sleep 2s
Type "hi $(cat /tmp/hi-demo/alloc)"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s
Type "hostname"
Enter
Sleep 2s
Type "exit"
Enter
Wait+Screen@30s /hi closing!/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under
# vhs, and the cleanup never earns a frame anyway.)
