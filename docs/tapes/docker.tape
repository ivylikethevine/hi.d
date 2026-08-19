# The docker demo, from a zsh client: one debian/bash target, then an
# alpine box whose only real shell is zsh - same session either way, which
# is the whole pitch. Render with `vhs docs/tapes/docker.tape` from the
# repo root, docker running, hi on PATH. Manual artifact, reviewed by eye.
#
# The Hide blocks pace themselves with Wait+Screen on sentinel text instead
# of fixed sleeps; the quoted split in fixture-o''k keeps the typed command
# from matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/docker.gif

Set Shell zsh
Set FontSize 15
Set Width 1100
Set Height 620
Set TypingSpeed 60ms

Require hi
Require docker

Hide
Type "setopt interactive_comments"
Enter
Type "docs/tapes/fixtures.sh up docker >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@240s /fixture-ok/
Type "source /tmp/hi-demo/clientrc.zsh"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# a debian container, bash inside"
Enter
Type "hi hi-demo"
Enter
Wait+Screen@60s /hi loaded with/
Sleep 3s
Type "cat /etc/os-release | head -2"
Enter
Sleep 2s
Type "exit"
Enter
Wait+Screen@30s /hi closing!/
Sleep 2s

Type "# an alpine box with no bash - one-off command"
Enter
Type "hi hi-demo-zsh 'zsh --version'"
Enter
Wait+Screen@60s /zsh 5/
Sleep 3s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under
# vhs, and the cleanup never earns a frame anyway.)
