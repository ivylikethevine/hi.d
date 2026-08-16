# Every target, the same session

The pitch is that `hi` behaves identically whatever is on the other end — an
ssh host, a container, an allocation, a pod — and whatever shell each side
happens to run. One GIF per backend, deliberately varying both sides. Each is
rendered from the tape next to it (`vhs docs/tapes/<name>.tape`, from the repo
root, with the backend running and `hi` on PATH; `docs/tapes/fixtures.sh`
builds every target the tapes connect to and `fixtures.sh down` removes them
all). Manual artifacts, reviewed by eye — regenerate whenever the header or
prompt changes.

Two things to get right when you do: `hi` on `$PATH` must be *this* checkout
(`/usr/bin/hi` may point at another install), and the target image is built
from `HEAD`, so uncommitted work shows on the client side of the GIF but not
the target's. Render from a commit, or set `HI_DEMO_SOURCE=worktree` to build
the target from the working tree instead.

## ssh, with a permanent install

The target carries its own `~/hi.d`, so nothing ships over the wire — hi
loads the tree in place and leaves it alone on exit. Client: bash.

![hi over ssh into a host with a permanent ~/hi.d](demos/ssh.gif)

## docker

A debian/bash container, then an alpine box whose only real shell is zsh —
hi probes and falls back without being told. Client: zsh.

![hi into a debian container, then an alpine zsh-only container](demos/docker.gif)

## podman

A fish-only alpine container from a fish client: no bash anywhere in the
loop. Same session, same code path as docker.

![hi from fish into a fish-only alpine container via podman](demos/podman.gif)

## nomad

A dev agent, one docker-driver job, and `hi <alloc-id-prefix>` straight into
the allocation. Client: bash.

![hi into a nomad allocation by ID prefix](demos/nomad.gif)

## kubernetes

A kind cluster and a bare alpine pod — busybox ash is all it has, which is
hi's aliases-only fallback. Client: zsh.

![hi into a kubernetes pod on a kind cluster](demos/kube.gif)
