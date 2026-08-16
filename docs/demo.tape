# The README demo, as a script instead of a stale recording: render with
# `vhs docs/demo.tape` (https://github.com/charmbracelet/vhs) from the repo
# root, with docker running and hi installed on PATH. Regenerate whenever the
# header or prompt changes. Not rendered in CI - docs/demo.gif is a manual
# artifact, reviewed by eye before committing.

Output docs/demo.gif

Set FontSize 15
Set Width 1100
Set Height 620
Set TypingSpeed 60ms

Hide
Type "docker run -d --rm --name hi-demo debian:bookworm-slim tail -f /dev/null >/dev/null"
Enter
Sleep 4s
Type "clear"
Enter
Show

Sleep 1s
Type "hi hi-demo"
Enter
Sleep 8s

Type "cd /tmp && ls"
Enter
Sleep 2s

Type "exit"
Enter
Sleep 3s

Hide
Type "docker rm -f hi-demo >/dev/null 2>&1"
Enter
Show
Sleep 2s
