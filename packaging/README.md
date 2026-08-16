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
| `package.sh` | stages the tree, then builds deb/rpm/apk with nfpm |
| `bump.sh` | writes the version + real checksums into every manifest; `--check` verifies |
| `aur/hi.d/` | the versioned AUR package (`PKGBUILD`, `.SRCINFO`) |
| `aur/hi.d-git/` | the same package built from `main` |
| `homebrew/hi.d.rb` | the tap formula |
| `nfpm/nfpm.yaml` | deb/rpm/apk, built from the staged tree |
| `windows.md` | the Windows channel assessment (nothing built) |

## Before the first release

**Configure the approval gate.** `.github/workflows/release.yml`'s `publish` job declares
`environment: release`, but an environment with no required reviewer imposes **no gate at all** — the job
would run unattended. This is a repo setting and the workflow file cannot do it for you:

> Settings → Environments → New environment → name it `release` → tick **Required reviewers** and add
> yourself → Save.

Optionally also set *Deployment branches and tags* to `v*` so nothing but a tag can reach it.

Until that exists, a pushed `v*` tag publishes without asking.

## Cutting a release

```bash
packaging/bump.sh 1.0.0        # needs the tag to exist first - see below
git add -A packaging && git commit -m "packaging: 1.0.0"
git push && git push --tags
```

Order matters and is slightly awkward: `bump.sh` checksums the GitHub tarball, which only exists once the
tag is pushed. So in practice:

1. `git tag v1.0.0 && git push --tags` — the tarball now exists.
2. `packaging/bump.sh 1.0.0` — fetches it, writes `pkgver`, `b2sums`, the formula `url`/`sha256`, and
   regenerates `.SRCINFO`.
3. Commit the manifests and push.
4. Re-push the tag onto that commit (`git tag -f v1.0.0 && git push -f --tags`) so the workflow's
   `bump.sh --check` sees manifests that match. The workflow refuses to build otherwise, which is the
   point — a release whose manifests disagree with its tag is worse than no release.
5. Approve the `publish` job in the Actions UI. Packages and manifests land on the release.

## Publishing each channel (all manual)

### AUR

Not done yet — no account, no submission. When you do:

```bash
cd packaging/aur/hi.d-git
makepkg -f                       # builds it
namcap PKGBUILD ./*.pkg.tar.zst  # catches hardcoded paths and bad permissions
pacman -Qlp ./*.pkg.tar.zst      # /usr/share/hi.d/..., /usr/bin/hi, /etc/profile.d/hi.d.sh
```

Then push `PKGBUILD` + `.SRCINFO` (only those two files) to `ssh://aur@aur.archlinux.org/hi.d-git.git`.
`hi.d-git` first — it works today with no tag — and the versioned `hi.d` once v1.0.0 exists.

Never submit with `b2sums=('SKIP')` on the versioned package. `SKIP` is correct and expected on
`hi.d-git`, whose source is a git ref.

### Homebrew tap

A tap is just a GitHub repo named `homebrew-tap` with a `Formula/` directory. Copy
`packaging/homebrew/hi.d.rb` to `Formula/hi.d.rb` there and `brew install ivy/tap/hi.d` works — no review,
no approval. Before copying:

```bash
brew install --build-from-source ./packaging/homebrew/hi.d.rb
brew test hi.d
brew audit --strict --new hi.d
```

Only reachable from a mac (or Homebrew on Linux); none of it can be verified from this repo's CI.

### deb / rpm / apk

Built by `package.sh` and attached to the GitHub Release. Users install the file:

```bash
sudo apt install ./hi.d_1.0.0_all.deb
```

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
