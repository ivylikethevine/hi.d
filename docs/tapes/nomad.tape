# The nomad demo: a dev agent, one docker-driver job, and hi straight into
# the allocation by ID prefix. Render with `vhs docs/tapes/nomad.tape` from
# the repo root, docker running, nomad and hi on PATH; fixtures.sh starts
# the agent and leaves the alloc ID in /tmp/hi-demo/alloc. Manual artifact,
# reviewed by eye.
#
# Its configuration: _HI_HEADER_IDENTITY=0 and the GHz CPU line. The banner
# stays on, and has to: the Wait+Screen below is /Disconnected/, which banner()
# prints - so this is the one demo that cannot switch the header off.
#
# The Hide blocks pace themselves with Wait+Screen on sentinel text instead
# of fixed sleeps; the quoted split in fixture-o''k keeps the typed command
# from matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/nomad.gif

Source docs/tapes/common.tape

Require hi
Require nomad
Require docker

Hide
Type "docs/tapes/fixtures.sh up nomad >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# a nomad allocation, by ID prefix"
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
# on /Disconnected/ rather than the /hi closing!/ the other tapes wait for:
# both render, but under vhs the nomad teardown reliably beats the scrape to
# that last line and the wait times out. The banner above it is just as good a
# "the session is over" marker, and the sleep keeps the closing line in frame.
Wait+Screen@60s /Disconnected/
Sleep 4s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under
# vhs, and the cleanup never earns a frame anyway.)
