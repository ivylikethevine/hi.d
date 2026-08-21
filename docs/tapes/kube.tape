# The kubernetes demo, from a zsh client into a bare alpine pod (busybox
# ash is all it has - hi's aliases-only fallback). Render with
# `vhs docs/tapes/kube.tape` from the repo root, docker running, kind and
# kubectl and hi on PATH; the kind cluster takes a minute the first time.
# Manual artifact, reviewed by eye.
#
# Its configuration: _HI_DISABLE_GIT_STATUS=1, from the settings.sh
# docs/tapes/fixtures.sh writes. A pod reached through the aliases-only fallback
# draws no header, so the client prompt is the only surface a knob shows on
# here - see fixtures.sh for why that rules out the more obvious pick.
#
# The Hide blocks pace themselves with Wait+Screen on sentinel text instead
# of fixed sleeps; the quoted split in fixture-o''k keeps the typed command
# from matching its own sentinel. Visible sleeps are reading time only.

Output docs/demos/kube.gif

Set Shell zsh
Source docs/tapes/common.tape

# zsh's theme - see the table in common.tape
Set Theme "Dracula"

Require hi
Require kind
Require kubectl

Hide
Type "setopt interactive_comments"
Enter
Type "docs/tapes/fixtures.sh up kube >/tmp/hi-demo.log 2>&1 && echo fixture-o''k"
Enter
Wait+Screen@300s /fixture-ok/
Type "kubectl config use-context kind-hi-demo >/dev/null 2>&1"
Enter
Type "source /tmp/hi-demo/clientrc.zsh"
Enter
Type "clear"
Enter
Show

Sleep 1s
Type "# a k8s pod - resolved after the rest"
Enter
Type "hi api-7"
Enter
Wait+Screen@60s /aliases/
Sleep 3s
Type "uname -a"
Enter
Sleep 2s
Type "exit"
Enter
Sleep 2s

# No in-tape cleanup: run `docs/tapes/fixtures.sh down` after rendering.
# (Typing into the pty right after a session teardown proved flaky under
# vhs, and the cleanup never earns a frame anyway.)
