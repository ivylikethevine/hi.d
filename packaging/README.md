# Packaging hi.d

Everything needed to ship `hi` through a package manager. Nothing here publishes on its own — the release
workflow's publishing job waits on a manual approval, and the AUR and the Homebrew tap are copies you make
by hand.

## The one idea

`hi.sh` does not locate itself. It sources `${_HI_HOME:-$HOME}/hi.d/common/core.sh`, and everything else
resolves against `$_HI_ROOT="$_HI_HOME/hi.d"`. So every channel has to do two things: put the tree in a
directory literally named `hi.d`, and make sure `_HI_HOME` names that directory's **parent** before any
shell sources anything.

| channel | tree | how `_HI_HOME` gets set |
| --- | --- | --- |
| AUR, deb, rpm, apk | `/usr/share/hi.d` | `/etc/profile.d/hi.d.sh`, written by `install_tree` |
| Homebrew | `<keg>/libexec/hi.d` | the `bin/hi` wrapper, plus the rc line `install.sh` writes |

`scripts/install.sh --prefix /usr/share` (with `$DESTDIR`) does all of this and is the single decider of
what a packaged install contains — see `_HI_PACKAGE_CONTENTS` and `install_tree()` in that file. The AUR
PKGBUILDs and `package.sh` both call it. Only the Homebrew formula repeats the list, because a formula
cannot: `install_tree` hardcodes `/usr/bin` and `/etc/profile.d`, neither of which exists in a brew prefix.
`tests/scripts/packaging_test.sh` fails if that copy drifts.

## Layout

| path | what it is |
| --- | --- |
| `package.sh` | stages the tree, stamps the staged `hi.sh` with the version, then builds deb/rpm/apk with nfpm |
| `bump.sh` | writes the version + real checksums into every manifest; `--check` verifies |
| `aur/hi.d/` | the versioned AUR package (`PKGBUILD`, `.SRCINFO`) |
| `aur/hi.d-git/` | the same package built from `main` |
| `homebrew/hi.d.rb` | the tap formula |
| `nfpm/nfpm.yaml` | deb/rpm/apk, built from the staged tree |
| `windows.md` | the Windows channel assessment (nothing built) |

**The version stamp.** Every channel seds `_HI_RELEASE=` into the `hi.sh` it installs, at build time:
`package.sh` stamps the staged copy for deb/rpm/apk, the PKGBUILD's `package()` and the formula's
`inreplace` stamp theirs. It cannot live in git: `bump.sh` runs only after the tag exists (its checksums
need the tarball), so a committed stamp would always be one release stale in the very tarball Homebrew
and the AUR build from. A git checkout answers `hi --version` with `git describe` instead, so the
committed line stays empty. `tests/scripts/packaging_test.sh` guards the line and all three stampers.

## Before the first release

**Configure the approval gate.** `.github/workflows/release.yml`'s `publish` job declares
`environment: release`, but an environment with no required reviewer imposes **no gate at all** — the job
would run unattended. This is a repo setting and the workflow file cannot do it for you:

> Settings → Environments → New environment → name it `release` → tick **Required reviewers** and add
> yourself → Save.

Optionally also set *Deployment branches and tags* to `v*` so nothing but a tag can reach it.

Until that exists, a pushed `v*` tag publishes without asking.

**Protect `main`.** Also a repo setting. Required checks are the fast suites; the wrinkle is that
`release.yml`'s `publish` job pushes the regenerated manifests straight to `main` as
`github-actions[bot]`, so the protection has to let that App through — a ruleset with a bypass actor
does, classic branch protection does not. One command with the [`gh` CLI](https://cli.github.com/)
(bypass actor 15368 is the GitHub Actions App's ID):

```sh
gh api repos/{owner}/{repo}/rulesets --method POST --input - <<'JSON'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": 15368, "actor_type": "Integration", "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "fast suites (ubuntu-latest)" },
          { "context": "fast suites (macos-latest)" }
        ]
      }
    }
  ]
}
JSON
```

**Generate the apk signing key.** Without it the release apk builds unsigned and installing needs
`--allow-untrusted`. One RSA keypair, abuild-style:

```sh
openssl genrsa -out hi.d-apk.rsa 4096
openssl rsa -in hi.d-apk.rsa -pubout -out packaging/apk/hi.d.rsa.pub
```

Paste the private half into Settings → Secrets and variables → Actions → New repository secret, named
`APK_SIGNING_KEY` (a plain repo secret, not a `release` environment secret: the build job also runs on
rehearsal dispatches, and the key only signs an artifact the gated publish job still has to approve).
Commit `packaging/apk/hi.d.rsa.pub` — the filename must stay exactly what `nfpm.yaml`'s `key_name` says,
because apk matches signatures to `/etc/apk/keys/` by that name. Then delete the local private half; the
secret is its only home.

**Generate the minisign keypair.** The publish job signs `SHA256SUMS` with it — the offline half of
release verification (the attestation is the online half). Passwordless, because CI has nobody to type
one:

```sh
minisign -G -W -p minisign.pub -s minisign.key
```

Paste the contents of `minisign.key` into Settings → Environments → `release` → Environment secrets as
`MINISIGN_SECRET_KEY` (environment-sealed, unlike the apk key: only the human-gated publish job ever
reads it). Put the public key line from `minisign.pub` into the README's "Verifying a release download"
section, replacing the placeholder. Then delete both local files; the secret and the README are their
homes. Until the secret exists, releases ship unsigned sums and the publish log says so.

**Create the AUR deploy key.** Only after the AUR account exists and each package has been pushed once by
hand (the namcap gate below cannot run in this CI). `release.yml`'s `aur` job then keeps `hi.d` current: an
ed25519 key whose public half is added to your AUR account, private half added as an `AUR_SSH_KEY` repo
secret. Absent, the job prints what to copy and exits 0.

**Create the Homebrew tap token.** Only once the `homebrew-tap` repo exists. `release.yml`'s `tap` job
opens the formula PR with it: a fine-grained PAT scoped to that repo, contents + pull-requests write, added
as a `HOMEBREW_TAP_TOKEN` repo secret. Absent, the job prints what to copy by hand and exits 0.

## Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That is the whole local ceremony. The tag never moves: `bump.sh` checksums the GitHub tarball, which only
exists once the tag is pushed — so the release workflow runs the bump itself, against the tarball the tag
just created, instead of requiring a pre-tag bump and a force-retag to reconcile the two.

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

Not done yet — no account, no submission. When you do, run the pre-submit gate below for **each**
package — `aur/hi.d-git` today, and `aur/hi.d` once v1.0.0 exists. namcap is the hard step, not a
suggestion: push nothing while either its `PKGBUILD` or its built-package run has complaints.

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

Anything else is a real finding. (`coreutils` used to appear here too and was dropped from `depends` - it is
in `base`, which packaging guidelines say to assume.)

**The end-to-end check**, which is what caught the `hi.d-git` package shipping no version stamp:

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Both packages have been run through all of this against a local clone (the only substitution being
`source=`, since the repo is not published yet): built, linted, installed into a clean Arch container,
exercised, and removed with nothing left behind.

Then push `PKGBUILD` + `.SRCINFO` (only those two files) to `ssh://aur@aur.archlinux.org/hi.d-git.git`.
**This first push is the manual one** — it is where namcap actually gates. After it, `release.yml`'s `aur`
job pushes the versioned `hi.d` package on every release, given the `AUR_SSH_KEY` secret; `hi.d-git` has no
version to bump and is never touched by CI.
`hi.d-git` first — it works today with no tag — and the versioned `hi.d` once v1.0.0 exists.

Never submit with `b2sums=('SKIP')` on the versioned package. `SKIP` is correct and expected on
`hi.d-git`, whose source is a git ref.

### Homebrew tap

A tap is just a GitHub repo named `homebrew-tap` with a `Formula/` directory. Copy
`packaging/homebrew/hi.d.rb` to `Formula/hi.d.rb` there and `brew install ivy/tap/hi.d` works — no review,
no approval. Before copying, all three must pass — `brew audit --strict` is a hard gate here precisely
because nothing else reviews a tap:

**The copy is automated, the checks are not.** `release.yml`'s `tap` job (behind the same `release`
approval as `publish`) opens a PR against `<owner>/homebrew-tap` with the freshly regenerated formula and
the three commands below as its checklist. It needs a `HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT
scoped to that repo with contents + pull-requests write. Without the secret the job says so and does
nothing, which is the state until the tap repo exists. Merging the PR is still yours, and so is running
these first:

```bash
brew install --build-from-source ./packaging/homebrew/hi.d.rb
brew test hi.d
brew audit --strict --new hi.d
```

`brew audit` needs a *named* formula, so it wants the formula in a tap - `brew tap-new ivy/tap`, copy the
file into its `Formula/`, then `brew audit --strict --new ivy/tap/hi.d`. Passing a path is refused outright.

**What a clean run looks like** (this has been run, in the `homebrew/brew` container, against a local
tarball - the only substitution being `url`/`sha256`, since the repo is not published): install and test
both exit 0, and audit reports only these two, which are the unpublished repo and nothing else:

```text
* The homepage URL https://github.com/ivylikethevine/hi.d is not reachable (HTTP status code 404)
* HEAD: The URL https://github.com/ivylikethevine/hi.d.git is not a valid Git URL
```

Two real findings came out of that first run and are fixed: the description had to start with a capital,
and `uses_from_macos "openssh"` was rejected - that macro is for formulae macOS provides *to Homebrew*, and
openssh is not one. The formula now declares no dependencies at all, which is correct: `ssh` and `base64`
ship with macOS and with any Linux that would install this.

A mac is still worth using before the first publish - the container is Linux, so it exercises Linuxbrew's
paths rather than a keg under `/opt/homebrew` - but nothing about the formula itself is unverified now.

### deb / rpm / apk

Built by `package.sh` and attached to the GitHub Release. Users install the file:

```bash
sudo apt install ./hi.d_1.0.0_all.deb
```

The apk is signed (once the `APK_SIGNING_KEY` secret exists — see the checklist above) with a key apk
verifies against `/etc/apk/keys/`, so Alpine users install the public key once and never pass
`--allow-untrusted`:

```sh
wget -O /etc/apk/keys/hi.d.rsa.pub \
  https://raw.githubusercontent.com/ivylikethevine/hi.d/main/packaging/apk/hi.d.rsa.pub
apk add ./hi.d_1.0.0_noarch.apk
```

A quirk worth knowing: the apk's contents are enumerated per `_HI_PACKAGE_CONTENTS` member in
`nfpm.yaml` instead of riding the `type: tree` entry deb/rpm use — nfpm 2.47.0's tree walker writes
directory modes apk-tools rejects outright. The packaging suite keeps the copy honest, and CI's
packaging-smoke installs the signed apk on Alpine every PR so the channel can't silently regress.

No `apt upgrade` — that is the trade for not maintaining a repository. Revisit
[OBS](https://en.opensuse.org/openSUSE:Build_Service_Debian_builds) only if people start asking for a repo
to subscribe to.

## Verifying locally

```bash
tests/test_runner.sh packaging install header   # the offline drift guards
packaging/package.sh --stage-only               # inspect exactly what ships
find dist/staging \( -type f -o -type l \)
packaging/package.sh                            # needs nfpm on PATH
dpkg-deb -c dist/hi.d_*_all.deb
```

### Reproducibility

The same commit builds byte-identical deb/rpm/apk: `package.sh` exports `SOURCE_DATE_EPOCH` (HEAD's
commit time, respecting a value you set per the [reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/)
convention), clamps the staged tree's mtimes to it, and nfpm 2.47.0 stamps everything else it controls
from the same variable. CI's packaging-smoke job enforces this with a double build on every PR; to check
it locally (sequentially — nfpm.yaml hardcodes `./dist/staging`, so `--outdir` can't run two side by side):

```bash
packaging/package.sh && mv dist dist.first
packaging/package.sh && diff dist.first/SHA256SUMS dist/SHA256SUMS
```

One caveat: CI pins nfpm 2.47.0 (`.github/actions/setup-nfpm`) while `package.sh` takes whatever nfpm is
on PATH — a different local nfpm can produce different (still internally reproducible) bytes.

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

`--no-link` skips the `/usr/bin/hi` symlink, which the package already owns. Their answers go to
`~/.config/hi.d/`, never into the tree, which is what lets a root-owned checkout work at all.
`hi_update` will correctly refuse to `git pull` and tell them to update through their package manager.
