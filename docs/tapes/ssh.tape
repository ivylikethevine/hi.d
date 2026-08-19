# The ssh permanent-install demo: the target carries its own ~/hi.d, so
# nothing ships over the wire - hi loads the tree in place and leaves it
# alone on exit. Render with `vhs docs/tapes/ssh.tape` from the repo root,
# with docker running and hi on PATH; docs/tapes/fixtures.sh builds the
# sshd container (this checkout preinstalled) and a throwaway ssh config,
# so the render never touches ~/.ssh. Manual artifact, reviewed by eye.
#
# The Hide blocks pace themselves with Wait+Screen on sentinel text instead
# of fixed sleeps; the quoted split in fixture-o''k keeps the typed command
# from matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/ssh.gif

Source docs/tapes/common.tape

Require hi
Require docker

Hide
Type "docs/tapes/fixtures.sh up ssh >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.bash"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# an ssh host with a permanent ~/hi.d - nothing ships"
Enter
Type "hi -F /tmp/hi-demo/ssh_config hi-demo-box"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s

Type "echo $_HI_ROOT  # the target's own copy, not a /tmp unpack"
Enter
Sleep 2s

Type "exit"
Enter
Wait+Screen@30s /hi closing!/
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under
# vhs, and the cleanup never earns a frame anyway.)
