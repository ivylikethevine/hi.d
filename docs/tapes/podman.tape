# The podman demo, from a fish client into a fish-only alpine box: neither
# side has bash in the loop and the session still looks the same. Render
# with `vhs docs/tapes/podman.tape` from the repo root, podman working, hi
# on PATH. Manual artifact, reviewed by eye.
#
# Its configuration: _HI_PROMPT_END_FISH, from the settings.sh
# docs/tapes/fixtures.sh writes - fish's own prompt separator, on the one tape
# with fish at both ends. (The fish-only abbr knob was tried here and taken back
# out; fixtures.sh says why.)
#
# The Hide blocks pace themselves with Wait+Screen on sentinel text instead
# of fixed sleeps; the quoted split in fixture-o''k keeps the typed command
# from matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/podman.gif

Set Shell fish
Source docs/tapes/common.tape

# fish's theme - see the table in common.tape
Set Theme "nord"

Require hi
Require podman

Hide
Type "docs/tapes/fixtures.sh up podman >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.fish"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# a fish-only alpine container, via podman"
Enter
Type "hi edge-1"
Enter
Wait+Screen@60s /plain fish/
Sleep 3s
Type "echo $FISH_VERSION"
Enter
Sleep 2s
Type "ll / | head -4"
Enter
Sleep 2s
Type "exit"
Enter
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under
# vhs, and the cleanup never earns a frame anyway.)
