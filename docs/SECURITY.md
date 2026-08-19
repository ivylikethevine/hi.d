# Security Policy

A tool people run against every host they touch earns the obvious
questions up front. This is the threat model: what hi does and
deliberately doesn't, what runs where, what it leaves behind, where the
trust boundaries sit, and how to report what slipped through.

## What hi does - and deliberately doesn't

- **No network calls of its own.** `hi` only execs the transports you
  already use (`ssh`, `docker exec`, `podman exec`, `nomad alloc exec`,
  `kubectl exec`) against a target you named. No telemetry, no update
  checks, no `curl`/`wget` anywhere in the shipped tree.
- **No `curl | bash`.** Installing is `git clone` plus
  `scripts/install.sh`, or a distro package (deb/rpm/apk, AUR, Homebrew)
  built from that same script. `hi --update` is `git pull` in a checkout
  you can read.
- **The payload is an allow list.** What goes over the wire is exactly
  `$_HI_PAYLOAD` at the top of `hi.sh` (`common misc shells load.sh`) -
  docs, tests, CI and editor config never leave the client. Your overlay
  (`settings.sh`, `colors`, `packages` from `~/.config/hi.d/`) is a
  second, smaller allow list.
- **base64 is armor, not crypto.** The payload is base64-encoded so it
  survives the target's login shell unmangled; it provides no
  confidentiality or integrity. Both come entirely from the transport
  (ssh, or the container runtime's exec channel).

## What runs where

`hi.sh` runs on the client: it parses arguments, picks the backend, tars
and armors the payload, and pipes it over the transport. On the target, a
single `sh` unpacks it into a temp directory and chainloads `load.sh`,
which prints the header, grafts hi's marker-delimited blocks onto the
host's rc files, and hands off to the best shell available. Everything
the target executes was generated on the client.

## Footprint and cleanup on the target

- The session tree lives in a `mktemp -d` directory (mode 0700, named
  `<user>.hi.XXXXXX`); the ssh bootstrap directory is created with
  `mkdir -m 700`.
- Removal has two independent paths: the bootstrap's
  `trap 'rm -rf $_HI_CLEANUP' exit`, and `load.sh`'s own on-exit hook.
  `tests/targets/ssh_disconnect_test.sh` verifies cleanup fires on an
  abrupt disconnect, not just a clean exit.
- The rc additions sit between `# hi-config-start` and `# hi-config-end`
  markers and are stripped back out by that same on-exit hook.
- A target with a permanent `~/hi.d` (you ran `scripts/install.sh`
  there) is used in place and nothing is deleted; the rc grafts are
  still cleaned on exit. That permanent tree never needs to be writable
  by you - root-owned, package-manager-installed copies work, because
  your config lives in `~/.config/hi.d/`.
- On the client, `install.sh` validates your existing rc files with each
  shell's own syntax checker before touching them, and `--uninstall`
  removes exactly what install wrote.

## Trust boundaries

- hi's security model is the transport's security model. It adds no
  authentication, listens on nothing, and anyone positioned to intercept
  or control your ssh/container session could do so without hi in it.
- A malicious target gets what any interactive session gives it: your
  payload and a terminal. Treat your overlay (`settings.sh`, `colors`,
  `packages`) as public to every host you visit. Nothing a target sends
  back is ever executed on the client - the one string hi reads back
  (the probe for an existing `~/hi.d`) is only interpolated into the
  script sent back to that same target. Escape sequences in session
  output remain possible, exactly as with plain `ssh`.
- Backend dispatch trusts your local `~/.ssh/config` and your
  `docker`/`podman`/`nomad`/`kubectl` CLIs - the same ones you already
  run by hand.

## Supported versions

There is no tagged release yet: the supported version is the tip of
`main`. Once v1.0 is tagged, this section becomes a version table, with
the latest release supported.

## Reporting a vulnerability

Please don't open a public issue for anything exploitable. Instead,
either:

- report privately via
  [GitHub private vulnerability reporting](https://github.com/ivylikethevine/hi.d/security/advisories/new),
  or
- email <ivylikethevine@gmail.com>.
