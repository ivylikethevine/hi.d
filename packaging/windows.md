# Shipping hi.d to Windows

An assessment, not a plan. Nothing in this document is built. It is the Windows counterpart to the
"Shipping hi.d" distribution review, which covered Arch, macOS and Debian/Ubuntu and never looked at
Windows at all.

## The question is which POSIX layer, not whether to port

`hi.sh` is `#!/bin/bash` with `set -euo pipefail`, and it shells out to `tar`, `openssl`, `mktemp`, `awk`,
`sed`, `find`, `du`, `hostname` and `ssh`. Native Windows has none of that. So there is no version of this
where a Windows package installs "hi.d" on its own — every channel below really installs *hi.d plus a
dependency on somebody's POSIX userland*, and the channels differ mainly in which one they lean on and how
honestly they admit it.

Worth being clear about what already works, because it is easy to conflate:

- **Windows as a target** is done. `README.md` covers it: WSL, Git Bash, Cygwin or MSYS2 on the target's
  `PATH` gets the full session, and stock Windows OpenSSH with no bash falls back to a plain PowerShell
  session over the same connection.
- **Windows as a client** — someone sitting at a Windows box typing `hi prod` — is the gap this document
  is about.

## The prerequisite: there is no Windows CI

The Linux and macOS channels ship on the back of a test suite that actually runs on those platforms.
`.github/workflows/ci.yml` has `ubuntu-latest` and an advisory `macos-latest` job; it has nothing for
Windows. Every claim about hi.d under Git Bash today is a guess.

That is the same shape of finding the first review opened with — the blocker was in hi.d, not in the
packaging — and it points the same way: **a `windows-latest` job running the fast suites under Git Bash
should land before any Windows channel does.** GitHub's `windows-latest` runners ship Git for Windows, so
`shell: bash` in a workflow step is Git Bash, and the fast group is pure shell with no daemons. It is a
cheap job. What it would tell us is currently unknown:

- whether `_hi_read_lines`, `_hi_repeat` and the rest behave under MSYS2's bash (they should — it is bash
  4.4+, well past the 3.2 floor)
- whether the path handling survives `C:`-style paths leaking into `$_HI_HOME` through `cygpath`
  translation
- whether `install.sh`'s rc-file rewriting finds the right `~/.bashrc` (Git Bash's `$HOME` is not always
  `%USERPROFILE%`)
- whether `hi.sh`'s `tar`/`openssl` payload path works with MSYS2's binaries and CRLF-safe pipes

Until that job is green, a Windows package would ship untested by construction.

## One thing already fixed

`config_hi`'s `sudo ln -sfn "$_HI_LAUNCHER" /usr/bin/hi` has no meaning under Git Bash: there is no `sudo`,
and `/usr/bin` is a virtual path inside the Git for Windows installation that a package has no business
writing to. `scripts/install.sh --no-link` now skips that step. Windows was the third consumer to need it,
after Homebrew and any distro package — see `packaging/README.md`.

## The channels

### WSL — the recommendation

Not a channel at all, which is the point. The `.deb` built by `packaging/package.sh` installs into WSL
unchanged, `/etc/profile.d/hi.d.sh` works exactly as it does on any Debian, and the user gets the real
thing rather than an approximation. It is also where a Windows developer who already uses `ssh`, `docker`
and `kubectl` is most likely to be working.

Cost: one paragraph in the README. Reaches: most of the plausible audience.

### Scoop — the only native channel worth building

A bucket is a GitHub repo of JSON manifests with no review queue — structurally the same deal as a
Homebrew tap, which is why it is the cheapest native option. Scoop installs to
`~/scoop/apps/hi.d/current`, so the writability problem is as soft as Homebrew's.

What it needs beyond a manifest:

- `"depends": "git"` — Git for Windows is what supplies bash, `openssl`, `tar` and `ssh`.
- A `hi.cmd` shim, because Scoop's own shims cannot execute a bash script directly. It has to translate the
  install path with `cygpath -u`, export `_HI_HOME` to the parent of the `hi.d` directory, and `exec`
  `hi.sh` — the same job the Homebrew formula's `bin/hi` wrapper does, in a language that makes it harder.
- The shim is the part that will actually break, and it is exactly the part no current CI job exercises.

Verdict: **start here if anything gets built, but only after the Windows CI job is green.**

### winget — reaches the most people, costs the most per release

Microsoft-blessed and preinstalled on Windows 11, so it has by far the widest reach. The costs are real: it
wants an installer artifact (a `zip` with a portable nested installer is the workable shape for a script
project), each version is a YAML manifest PR into `microsoft/winget-pkgs`, and there is a moderation queue
plus automated validation. Reasonable once hi.d has actual Windows users; premature before that.

### Chocolatey — no advantage over the two above

A `.nuspec` plus a `chocolateyInstall.ps1`, behind a moderation queue, with a hard dependency on Git for
Windows to supply the userland. It reaches an audience that overlaps heavily with Scoop's and asks for more
per release. `misc/packages` already probes for `choco`, which is the only argument in its favour and not a
strong one.

### MSYS2 — the best technical fit, the narrowest audience

MSYS2 is a real POSIX userland with a real package manager, so hi.d would work there with no shim and no
dependency hand-waving at all. Two things make it interesting beyond that: its packages are built from
PKGBUILDs in Arch's format, so `packaging/aur/hi.d/PKGBUILD` is most of the work already done, and its
`/etc/profile.d` is real, so the `_HI_HOME` export lands the same way it does on Linux.

Against it: submission goes through `MSYS2/MSYS2-packages` with review, and the audience is small and
technical enough to be comfortable cloning the repo.

### Cygwin — skip

`cygport` and a maintainer slot, for an audience that has largely moved to WSL or MSYS2.

### A native PowerShell port — skip, emphatically

Worth naming only to rule out. hi.d is ~2,000 lines of shell whose entire value is that the *same* config
lands on every host; a second implementation in PowerShell would be a second thing to keep in sync forever,
and it still could not run `load.sh` on the target.

## Side by side

| channel | reaches | needs | auto-updates | setup | per release |
| --- | --- | --- | --- | --- | --- |
| WSL | anyone running WSL | nothing new — the `.deb` | no (same as any deb) | a README paragraph | nothing |
| Scoop | Scoop users | Git for Windows + a `.cmd` shim | yes, `scoop update` | a bucket repo + the shim | bump version + hash |
| winget | all of Windows 11 | a zip/portable artifact | yes, `winget upgrade` | manifest PR + moderation | a PR per release |
| Chocolatey | choco users | Git for Windows + PowerShell script | yes, `choco upgrade` | nuspec + moderation | a push per release |
| MSYS2 | MSYS2 users | nothing — real POSIX | yes, `pacman -Syu` | PKGBUILD + review | bump in their repo |
| Cygwin | few | cygport | yes | maintainer slot | per release |

## What I would do

1. **Document WSL as the supported Windows path.** It already works, it costs a paragraph, and it is
   honest about what hi.d is.
2. **Add the `windows-latest` Git Bash CI job.** This is the actual prerequisite, and it has value even if
   no Windows package is ever published — Windows is already a supported *target*, and nothing tests that
   either.
3. **Revisit Scoop once that job is green and someone asks.** The manifest is an afternoon; the shim is the
   risk, and the CI job is what turns that risk into something observable.
4. **Leave winget, Chocolatey, MSYS2 and Cygwin until there is demand**, and prefer MSYS2 over the other
   three if the demand comes from people who already have a POSIX userland.
