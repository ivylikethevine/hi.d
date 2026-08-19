# Packaging & releases

Everything needed to ship `hi` through a package manager. Nothing here publishes
on its own — the publishing job waits on a manual approval, and the AUR and the
Homebrew tap are copies you make by hand. The **one-time setup** each channel
needs first (the `release` approval gate, branch protection, the apk and
minisign keypairs, the AUR deploy key, the tap token) is a checklist with exact
commands in [ROADMAP.md](ROADMAP.md)'s _GitHub repo settings_, _Secrets & keys_
and _Release channels_ sections. Until those exist, a pushed `v*` tag publishes
unattended and the release ships unsigned sums.

Every workflow's `runs-on:` reads a repo/org Actions variable first —
`vars.RUNNER_LABEL`, or `vars.MACOS_RUNNER_LABEL` / `vars.WINDOWS_RUNNER_LABEL`
for the two OS-locked e2e jobs — falling back to the GitHub-hosted label when
unset, so nothing changes until you set one. Jobs that install apt packages or
touch the Docker socket (`ci.yml`'s `test`, `bench`, `packaging-smoke`, `e2e`,
`e2e-backends`, and `coverage.yml`) need a self-hosted runner providing those;
`macos-e2e.yml` and `windows-e2e.yml` need a same-OS one if substituted.

## The one idea

`hi.sh` does not locate itself. It sources `${_HI_HOME:-$HOME}/hi.d/common/core.sh`, and everything else
resolves against `$_HI_ROOT="$_HI_HOME/hi.d"`. So every channel has to do two things: put the tree in a
directory literally named `hi.d`, and make sure `_HI_HOME` names that directory's **parent** before any
shell sources anything.

| channel            | tree                 | how `_HI_HOME` gets set                                    |
| ------------------ | -------------------- | ---------------------------------------------------------- |
| AUR, deb, rpm, apk | `/usr/share/hi.d`    | `/etc/profile.d/hi.d.sh`, written by `install_tree`        |
| Homebrew           | `<keg>/libexec/hi.d` | the `bin/hi` wrapper, plus the rc line `install.sh` writes |

`scripts/install.sh --prefix /usr/share` (with `$DESTDIR`) does all of this and is the single decider of
what a packaged install contains — `_HI_PACKAGE_CONTENTS` and `install_tree()` in that file. Both AUR
PKGBUILDs and `mkpkg.sh` call it. Only the Homebrew formula repeats the list, because a formula cannot
call it: `install_tree` hardcodes `/usr/bin` and `/etc/profile.d`, neither of which exists in a brew
prefix. `tests/scripts/packaging_test.sh` fails if that copy drifts.

## Layout

| path               | what it is                                                                          |
| ------------------ | ----------------------------------------------------------------------------------- |
| `mkpkg.sh`         | stages the tree, stamps it, then builds deb/rpm/apk with nfpm                       |
| `stamp.sh`         | writes the version into a built tree's `hi.sh` and man page; every channel calls it |
| `bump.sh`          | writes the version + real checksums into every manifest; `--check` verifies         |
| `aur/hi.d/`        | the versioned AUR package (`PKGBUILD`, `.SRCINFO`)                                  |
| `aur/hi.d-git/`    | the same package built from `main`                                                  |
| `homebrew/hi.d.rb` | the tap formula                                                                     |
| `nfpm/nfpm.yaml`   | deb/rpm/apk, built from the staged tree                                             |

**The version stamp.** `packaging/stamp.sh` writes `_HI_RELEASE=` into the `hi.sh` a channel installs and
the version into the man page's `.TH` line. All four call it — `mkpkg.sh` for deb/rpm/apk, both
`PKGBUILD`s' `package()`, the formula's `install` — so there is one implementation rather than four seds.
It cannot live in git: `bump.sh` runs only after the tag exists (its checksums need the tarball), so a
committed stamp would always be one release stale in the very tarball Homebrew and the AUR build from. A
checkout answers `hi --version` with `git describe` instead, so the committed line stays empty. The
formula passes `--date <version>`, having no `SOURCE_DATE_EPOCH`, and `stamp.sh` refuses to guess one.
`tests/scripts/packaging_test.sh` guards all of it.

## Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That is the whole local ceremony. The tag never moves: `bump.sh` checksums the GitHub tarball, which only
exists once the tag is pushed, so the workflow runs the bump itself against that tarball rather than
requiring a pre-tag bump and a force-retag to reconcile the two.

1. `git tag v1.0.0 && git push origin v1.0.0` — the tarball now exists and the workflow starts.
2. The `build` job runs the fast suites, then `bump.sh 1.0.0` (fetches the tarball, writes `pkgver`,
   `b2sums`, the formula `url`/`sha256`, and the derivable `.SRCINFO` lines), verifies with
   `bump.sh --check`, runs the packaging drift guards against the fresh manifests, and builds the
   deb/rpm/apk plus a `SHA256SUMS` over them. Nothing has published yet.
3. Approve the `publish` job in the Actions UI — this is your review point, over the exact artifacts the
   build produced. Packages, `SHA256SUMS`, and manifests land on the release, and the regenerated
   manifests are committed back to `main` (they are consumed from the AUR/tap repos, not from inside the
   tarball, so they don't need to be in the tagged tree).
4. Both channels update themselves once their secrets exist: the tap gets a PR (`HOMEBREW_TAP_TOKEN`), the
   AUR gets a push (`AUR_SSH_KEY`). Until then, copy the manifests from the release (or from `main`) by hand,
   per the sections below.

`bump.sh 1.0.0` still works by hand if CI is ever unavailable (`--tarball <file>` skips the
download), and `bump.sh --check 1.0.0` stays useful locally to confirm the manifests match a cut release.

**Release notes are the PR titles.** The publish job's `gh release create --generate-notes` drafts the
notes from the PR titles merged since the last tag — there is no separate notes file to write. The
discipline that makes this good enough: title PRs the way you'd want them read in release notes, and skim
`gh pr list --state merged` before tagging to retitle anything that wouldn't. Revisit git-cliff only if
the generated notes start needing curation.

## Publishing each channel

Every channel below is gated on the manual approval in `release.yml`, and two of them (the AUR and the tap)
are pushed by CI once their secrets exist — the checks each section describes are still yours to run first.

### AUR

Not done yet — no account, no submission. When you do, run the gate below for **each** package:
`aur/hi.d-git` today, `aur/hi.d` once v1.0.0 exists. namcap is the hard step, not a suggestion — push
nothing while either its `PKGBUILD` or its built-package run has complaints.

```bash
cd packaging/aur/hi.d-git        # then again in packaging/aur/hi.d
makepkg -f                       # builds it
namcap PKGBUILD                  # lints the recipe itself
namcap ./*.pkg.tar.zst           # catches hardcoded paths and bad permissions
pacman -Qlp ./*.pkg.tar.zst      # /usr/share/hi.d/..., /usr/bin/hi, /etc/profile.d/hi.d.sh
```

**What a clean run looks like.** `namcap PKGBUILD` is silent. `namcap` on the built package prints exactly
three warnings, all of them namcap being unable to read shell scripts, all correct to keep:

```text
W: Dependency fish detected but optional (programs ['fish'] ...)   # optdepend on purpose - hi works without it
W: Dependency zsh detected but optional (programs ['zsh'] ...)     # same
W: Dependency included, but may not be needed ('openssh')          # hi runs ssh; no shebang says so
```

Anything else is a real finding. (`coreutils` appeared here too and was dropped from `depends` — it is in
`base`, which packaging guidelines say to assume.)

**The end-to-end check**, which is what caught the `hi.d-git` package shipping no version stamp:

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Both packages have been through all of this against a local clone (the only substitution being `source=`,
the repo not being published yet): built, linted, installed into a clean Arch container, exercised, and
removed with nothing left behind.

Then push `PKGBUILD` + `.SRCINFO` — only those two — to `ssh://aur@aur.archlinux.org/hi.d-git.git`,
`hi.d-git` first since it needs no tag. **That first push is the manual one**, because it is where namcap
gates. After it, `release.yml`'s `aur` job pushes the versioned `hi.d` on every release, given the
`AUR_SSH_KEY` secret; `hi.d-git` has no version to bump and CI never touches it.

Never submit the versioned package with `b2sums=('SKIP')` — `SKIP` is correct only on `hi.d-git`, whose
source is a git ref.

### Homebrew tap

A tap is just a GitHub repo named `homebrew-tap` with a `Formula/` directory. Copy
`packaging/homebrew/hi.d.rb` to `Formula/hi.d.rb` there and `brew install ivy/tap/hi.d` works — no review,
no approval, which is exactly why `brew audit --strict` is a hard gate here.

**The copy is automated, the checks are not.** `release.yml`'s `tap` job (behind the same approval as
`publish`) opens a PR against `<owner>/homebrew-tap` with the regenerated formula and the three commands
below as its checklist. It needs a `HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT scoped to that
repo with contents + pull-requests write — and without it the job says so and does nothing, which is the
state until the tap repo exists. Merging the PR is yours, as is running these first:

```bash
brew install --build-from-source ./packaging/homebrew/hi.d.rb
brew test hi.d
brew audit --strict --new hi.d
```

`brew audit` needs a _named_ formula, so it wants one in a tap: `brew tap-new ivy/tap`, copy the file into
its `Formula/`, then `brew audit --strict --new ivy/tap/hi.d`. Passing a path is refused outright.

**What a clean run looks like** — this has been run in the `homebrew/brew` container against a local
tarball, the only substitution being `url`/`sha256`: install and test exit 0, and audit reports only these
two, which are the unpublished repo and nothing else:

```text
* The homepage URL https://github.com/ivylikethevine/hi.d is not reachable (HTTP status code 404)
* HEAD: The URL https://github.com/ivylikethevine/hi.d.git is not a valid Git URL
```

Two real findings came out of that run and are fixed: the description had to start with a capital, and
`uses_from_macos "openssh"` was rejected — that macro is for formulae macOS provides _to Homebrew_, and
openssh is not one. The formula now declares no dependencies at all, which is correct: `ssh` and `base64`
ship with macOS and with any Linux that would install this.

A mac is still worth using before the first publish, since the container exercises Linuxbrew's paths
rather than a keg under `/opt/homebrew` — but nothing about the formula itself is unverified now.

### deb / rpm / apk

Built by `mkpkg.sh` and attached to the GitHub Release. Users install the file:

```bash
sudo apt install ./hi.d_1.0.0_all.deb
```

The apk is signed (once the `APK_SIGNING_KEY` secret exists — see the ROADMAP checklist) with a key apk
verifies against `/etc/apk/keys/`, so Alpine users install the public key once and never pass
`--allow-untrusted`:

```sh
wget -O /etc/apk/keys/hi.d.rsa.pub \
  https://raw.githubusercontent.com/ivylikethevine/hi.d/main/packaging/apk/hi.d.rsa.pub
apk add ./hi.d_1.0.0_noarch.apk
```

A quirk worth knowing: the apk enumerates its contents per `_HI_PACKAGE_CONTENTS` member in `nfpm.yaml`
rather than riding the `type: tree` entry deb/rpm use, because nfpm 2.47.0's tree walker writes directory
modes apk-tools rejects outright. The packaging suite keeps that copy honest, and CI's packaging-smoke
installs the signed apk on Alpine every PR so the channel can't silently regress.

No `apt upgrade` — the trade for not maintaining a repository. Revisit
[OBS](https://en.opensuse.org/openSUSE:Build_Service_Debian_builds) only if people ask for a repo to
subscribe to.

## Windows channels

An assessment, not a plan — nothing here is built. It is the Windows counterpart to the "Shipping hi.d"
distribution review, which covered Arch, macOS and Debian/Ubuntu and never looked at Windows.

### The question is which POSIX layer, not whether to port

`hi.sh` is `#!/bin/bash` with `set -euo pipefail`, and it shells out to `tar`, `openssl`, `mktemp`, `awk`,
`sed`, `find`, `du`, `hostname` and `ssh`. Native Windows has none of that, so no Windows package installs
"hi.d" on its own — every channel below installs _hi.d plus a dependency on somebody's POSIX userland_,
and they differ mainly in which one they lean on and how honestly they admit it.

Easy to conflate, so stated once: **Windows as a target** is already done (see
the README's [Windows hosts](../README.md#windows-hosts) section). **Windows
as a client** — someone sitting at a Windows box typing `hi prod` — is the gap
this section is about.

### The prerequisite: the CI that exists tests the other half

The one Windows job, `windows-e2e.yml`, is not the one the channels below wait on: it exercises Windows
**as a target** — a stock OpenSSH server with no bash on `PATH`, driven from the runner's Git Bash,
asserting the cmd `||` ladder lands in the PowerShell fallback. Dispatch-only, never run.

Missing is the client-side job: **a `windows-latest` job running the fast suites under Git Bash**, which
would tell us whether hi.d works when Windows is the machine you type `hi` on. It should land before any
Windows channel. GitHub's `windows-latest` runners ship Git for Windows, so `shell: bash` is Git Bash and
the fast group is pure shell with no daemons — a cheap job answering four currently open questions:

- whether `_hi_read_lines`, `_hi_repeat` and the rest behave under MSYS2's bash (they should — it is bash
  4.4+, well past the 3.2 floor)
- whether the path handling survives `C:`-style paths leaking into `$_HI_HOME` through `cygpath`
  translation
- whether `install.sh`'s rc-file rewriting finds the right `~/.bashrc` (Git Bash's `$HOME` is not always
  `%USERPROFILE%`)
- whether `hi.sh`'s `tar`/`openssl` payload path works with MSYS2's binaries and CRLF-safe pipes

Until that job exists and is green, a Windows package would ship untested by construction.

### One thing already fixed

`config_hi`'s `sudo ln -sfn "$_HI_LAUNCHER" /usr/bin/hi` means nothing under Git Bash: there is no `sudo`,
and `/usr/bin` is a virtual path inside the Git for Windows installation no package should write to.
`scripts/install.sh --no-link` skips it. Windows was the third consumer to need that flag, after Homebrew
and any distro package.

### The channels

#### WSL — the recommendation

Not a channel at all, which is the point — see the README's [Installing hi on
Windows](../README.md#windows-hosts) section: the `.deb` installs into WSL
unchanged and the user gets the real thing rather than an approximation.

Cost: one paragraph in the README. Reaches: most of the plausible audience.

#### Scoop — the only native channel worth building

A bucket is a GitHub repo of JSON manifests with no review queue — structurally the same deal as a
Homebrew tap, and so the cheapest native option. Scoop installs to `~/scoop/apps/hi.d/current`, making
the writability problem as soft as Homebrew's.

What it needs beyond a manifest:

- `"depends": "git"` — Git for Windows is what supplies bash, `openssl`, `tar` and `ssh`.
- A `hi.cmd` shim, because Scoop's own shims cannot execute a bash script directly. It has to translate the
  install path with `cygpath -u`, export `_HI_HOME` to the parent of the `hi.d` directory, and `exec`
  `hi.sh` — the same job the Homebrew formula's `bin/hi` wrapper does, in a language that makes it harder.
- The shim is the part that will actually break, and it is exactly the part no current CI job exercises.

Verdict: **start here if anything gets built, but only after the client-side Windows CI job is green.**

#### winget — reaches the most people, costs the most per release

Microsoft-blessed and preinstalled on Windows 11, so by far the widest reach. The costs are real: it wants
an installer artifact (a `zip` with a portable nested installer is the workable shape for a script
project), each version is a YAML manifest PR into `microsoft/winget-pkgs`, and there is a moderation queue
plus automated validation. Reasonable once hi.d has Windows users; premature before that.

#### MSYS2 — the best technical fit, the narrowest audience

MSYS2 is a real POSIX userland with a real package manager, so hi.d would work there with no shim and no
dependency hand-waving. Two things make it interesting beyond that: its packages build from PKGBUILDs in
Arch's format, so `packaging/aur/hi.d/PKGBUILD` is most of the work already, and its `/etc/profile.d` is
real, so the `_HI_HOME` export lands as on Linux.

Against it: submission goes through `MSYS2/MSYS2-packages` with review, and the audience is small and
technical enough to be comfortable cloning the repo.

### Side by side

| channel    | reaches            | needs                               | auto-updates          | setup                    | per release         |
| ---------- | ------------------ | ----------------------------------- | --------------------- | ------------------------ | ------------------- |
| WSL        | anyone running WSL | nothing new — the `.deb`            | no (same as any deb)  | a README paragraph       | nothing             |
| Scoop      | Scoop users        | Git for Windows + a `.cmd` shim     | yes, `scoop update`   | a bucket repo + the shim | bump version + hash |
| winget     | all of Windows 11  | a zip/portable artifact             | yes, `winget upgrade` | manifest PR + moderation | a PR per release    |
| MSYS2      | MSYS2 users        | nothing — real POSIX                | yes, `pacman -Syu`    | PKGBUILD + review        | bump in their repo  |

### What I would do

1. **Document WSL as the supported Windows path.** Done — it costs a paragraph, and it is honest about
   what hi.d is.
2. **Add the `windows-latest` Git Bash CI job** — the client-side one, running the fast suites. This is
   the actual prerequisite, and it has value even if no Windows package is ever published. (The
   target-side `windows-e2e.yml` is written but is a different job, and has not been dispatched yet.)
3. **Revisit Scoop once that job is green and someone asks.** The manifest is an afternoon; the shim is
   the risk, and the CI job is what makes that risk observable.
4. **Leave winget and MSYS2 until there is demand**, and prefer MSYS2 of the two if the demand comes from
   people who already have a POSIX userland.

## Verifying a packaged build locally

```bash
tests/test_runner.sh packaging install header   # the offline drift guards
packaging/mkpkg.sh --stage-only               # inspect exactly what ships
find dist/staging \( -type f -o -type l \)
packaging/mkpkg.sh                            # needs nfpm on PATH
dpkg-deb -c dist/hi.d_*_all.deb
```

### Reproducibility

The same commit builds byte-identical deb/rpm/apk: `mkpkg.sh` exports `SOURCE_DATE_EPOCH` (HEAD's commit
time, respecting a value you set per the
[reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/) convention), clamps the
staged tree's mtimes to it, and nfpm stamps everything else it controls from the same variable. CI's
packaging-smoke job enforces it with a double build on every PR. Locally, run them sequentially — nfpm.yaml
hardcodes `./dist/staging`, so `--outdir` cannot run two side by side:

```bash
packaging/mkpkg.sh && mv dist dist.first
packaging/mkpkg.sh && diff dist.first/SHA256SUMS dist/SHA256SUMS
```

One caveat: CI pins nfpm 2.47.0 (`.github/actions/setup-tool/tools.txt`) while `mkpkg.sh` takes whatever
nfpm is on PATH — a different local nfpm can produce different (still internally reproducible) bytes.

The honest end-to-end check for the `/etc/profile.d` snippet, which is the part no unit test can prove:

```bash
docker run --rm -it -v "$PWD/dist:/dist" debian:stable \
  bash -lc 'apt-get update -qq && apt-get install -y /dist/hi.d_*_all.deb && echo "$_HI_HOME" && hi'
```

## After installing from a package

The tree is root-owned and holds nobody's settings. Each user runs, once:

```bash
/usr/share/hi.d/scripts/install.sh --no-link
```

`--no-link` skips the `/usr/bin/hi` symlink the package already owns. Answers go to `~/.config/hi.d/`,
never into the tree, which is what lets a root-owned checkout work at all. `hi_update` correctly refuses to
`git pull` and points at the package manager instead.
