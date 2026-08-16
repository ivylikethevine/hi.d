# Tooling & practices roadmap

Candidate additions for developing hi.d. Two halves, because they need two
different kinds of attention:

- **[Human actions](#human-actions)** — nothing here is code. Each entry names
  where you go, what you do, and what ticks it. Almost all of it is gated on
  publishing, so it can wait while the package is in development; the
  exceptions say so.
- **[Code work](#code-work)** — entries that are written in this repo. Each is
  marked **Unblocked** or **Blocked on:** so it's clear at a glance which need a
  human step first.

Nothing here is wired up until its checkbox is ticked.

## Human actions

### GitHub repo settings

Both are one-time, both are pre-first-release, and neither can be done from a
workflow file — see `packaging/README.md`'s "Before the first release".

- [ ] **The `release` approval gate** — `.github/workflows/release.yml`'s
      `publish` job declares `environment: release`, but an environment with no
      required reviewer imposes **no gate at all**: a pushed `v*` tag would
      publish unattended.

  - **Where:** Settings → Environments
  - **Do:** New environment → name it `release` → tick **Required reviewers** and add yourself → Save. Optionally set _Deployment branches and tags_ to `v*` so nothing but a tag can reach it.
  - **Ticks when:** the environment exists with a reviewer on it.

- [ ] **Branch protection on `main`** — required checks = the fast suites. The
      wrinkle is that the release workflow's `publish` job pushes the
      regenerated manifests straight to `main` as `github-actions[bot]`, so the
      protection has to let that App through: a ruleset with a bypass actor
      does, classic branch protection does not.

  - **Where:** the `gh` CLI (a repo setting under the hood)
  - **Do:** run the ready-made `gh api repos/{owner}/{repo}/rulesets` command in `packaging/README.md` — one command, bypass actor already filled in. Do it alongside the `release` environment above.
  - **Ticks when:** the ruleset is active on the repo.

### Secrets & keys

Two keypairs. **The in-repo half of both is already written and tested** — CI consumes each secret the moment it exists and says so loudly in the log when it doesn't. What's left is generating the key and pasting it in. Exact commands live in `packaging/README.md`'s checklist rather than here, so there's one copy.

- [ ] **apk signing key** — signing is wired end to end: `nfpm.yaml` declares
      the signature (key from `$HI_APK_KEY`, name `hi.d.rsa.pub`), `release.yml`
      injects the `APK_SIGNING_KEY` repo secret, and CI's packaging-smoke
      installs a signed apk on Alpine every PR. Without the key the release apk
      builds unsigned and installing it needs `--allow-untrusted`.

  - **Where:** a terminal, then Settings → Secrets and variables → Actions
  - **Do:** generate the RSA keypair, add the private half as the `APK_SIGNING_KEY` **repo** secret (not an environment secret — the ungated build job needs it), commit `packaging/apk/hi.d.rsa.pub` under exactly that filename, delete the local private half.
  - **Ticks when:** the secret exists and the public key is committed.

- [ ] **minisign keypair** — the publish job installs a pinned minisign
      (drift-checked weekly) and signs `SHA256SUMS` with
      `MINISIGN_SECRET_KEY`; the `.minisig` rides the upload only when it
      exists, and the README's "Verifying a release download" section already
      shows the check.

  - **Where:** a terminal, then Settings → Environments → `release` → Environment secrets
  - **Do:** `minisign -G -W`, paste the secret key as the `MINISIGN_SECRET_KEY` **environment** secret (sealed to the gated publish job), replace the placeholder public key in the README, delete both local files.
  - **Ticks when:** the secret exists and the README carries the real key.

- [ ] **Homebrew tap token** — only once the tap-PR job (see [Code
      work](#code-work)) has something to push to. The job no-ops cleanly
      without it.

  - **Where:** a fine-grained PAT, then Settings → Secrets and variables → Actions
  - **Do:** create a token scoped to the `homebrew-tap` repo with contents + pull-requests write, add it as `HOMEBREW_TAP_TOKEN`.
  - **Ticks when:** the secret exists and a release has opened a tap PR.

- [ ] **AUR deploy key** — only once the AUR account exists and each package has
      been pushed by hand once (that first push is where namcap gates, and no
      runner here can run it). `release.yml`'s `aur` job keeps the versioned
      package current after that, and no-ops loudly without the secret.

  - **Where:** a terminal, then Settings → Secrets and variables → Actions
  - **Do:** `ssh-keygen -t ed25519`, add the public half to your AUR account, add the private half as `AUR_SSH_KEY`, delete the local private half.
  - **Ticks when:** the secret exists and a release has pushed to the AUR.

### CI runs to dispatch

All three workflows are written, committed, and dispatch-only. They need nothing but the repo pushed and Actions enabled — click Run workflow and read the result.

- [ ] **macOS loopback e2e** (`.github/workflows/macos-e2e.yml`) — CI's macos
      job runs only the fast suites, so the BSD userland (`sed -i ''`,
      `mktemp -t`, `base64 -D`, bash 3.2) is never crossed by a real connection.
      GitHub's macOS runners ship sshd, so the job enables Remote Login,
      authorizes a throwaway key, and runs `hi localhost 'echo marker'` — the
      whole client-and-target BSD path in one go. Pty-wrapped like the e2e
      suites, with a cleanup-trap assertion.

  - **Ticks when:** its first green dispatch. Promote to every-PR only once it proves stable.

- [ ] **Windows target e2e** (`.github/workflows/windows-e2e.yml`) — the README
      documents the Git Bash/WSL/PowerShell fallback ladder and
      `packaging/windows.md` gates every native Windows channel on "the Windows
      CI job is green", but no such job has ever run. The job configures the
      stock sshd, sets the admin `authorized_keys` ACL, drives `hi localhost`
      from Git Bash, and asserts the PowerShell greeting — the cmd `||` fallback
      the README promises is the case to watch. Explicitly experimental.

  - **Ticks when:** its first green dispatch.

- [ ] **OpenSSF Scorecard** (`.github/workflows/scorecard.yml`) — a public
      supply-chain score that credits work already done here (SHA pins, minimal
      token permissions, dependabot, zizmor, branch protection once applied).
      Dispatch-only, SARIF artifact, `publish_results` off.

  - **Ticks when:** it has been run once and the report read. Only then decide about a README badge.

### External accounts & submissions

Each needs an account or a repo that doesn't exist yet, and each is a
publishing step — all of it waits for v1.

- [ ] **AUR** — no account, no submission yet. Two packages: `hi.d-git` (works
      today, no tag needed) and `hi.d` (once v1.0.0 exists).

  - **Do:** register an AUR account and add an SSH key, then run the pre-submit gate in `packaging/README.md` for **each** package — `makepkg -f`, `namcap PKGBUILD`, `namcap ./*.pkg.tar.zst`, `pacman -Qlp`. namcap is a hard gate, not a suggestion. Push only `PKGBUILD` + `.SRCINFO`. Never submit the versioned package with `b2sums=('SKIP')` — `SKIP` is correct only on `hi.d-git`.
  - **Ticks when:** both packages are live on the AUR.

- [ ] **Homebrew tap** — a tap is just a GitHub repo named `homebrew-tap` with a
      `Formula/` directory; no review, no approval, which is exactly why the
      local gate matters.

  - **Do:** create the repo, then `brew install --build-from-source`, `brew test hi.d`, and `brew audit --strict --new hi.d` must all pass before the formula is copied in.
  - **Ticks when:** `brew install ivy/tap/hi.d` works.

- [ ] **tldr page** — five example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream (github.com/tldr-pages/tldr) has
      its own style guide and review, so this is a submission, not a file here.
      The draft is checked in at `docs/tldr.md` (seven examples, their format).

  - **Do:** open the PR against tldr-pages **after v1**, once the CLI surface is frozen — examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.

### Needs a machine this repo's CI doesn't have

Not GitHub-button work: these are human actions purely because no runner covers them. Listed separately so they don't get mistaken for something a workflow could take over.

- [ ] **Homebrew formula verification** — reachable only from a mac (or
      Homebrew on Linux). `brew install --build-from-source`, `brew test`,
      `brew audit --strict --new`. Nothing in this repo's CI can check any of
      it, which is why the checklist _is_ the enforcement.

  - **Ticks when:** run against the v1 formula.

- [ ] **AUR package verification** — needs an Arch box (or container) for
      `makepkg` and `namcap`. Same story: the packaging suite guards the
      manifest's shape offline, but only namcap catches hardcoded paths and bad
      permissions in a built package.

  - **Ticks when:** run clean for both AUR packages.

- [ ] **Regenerate the demo GIFs** — the one entry here that is _not_ waiting on
      publishing. `docs/demos.md` says it plainly: the GIFs are manual
      artifacts, reviewed by eye, and regenerated whenever the header or the
      prompt changes. Both have changed since they were recorded — the packages
      check now carries hi's own dependencies, and the prompt separator is a
      setting — so all five are stale, plus `docs/demo.gif` in the README.

  - **Where:** a machine with `vhs`, docker, podman, nomad and a kind cluster — the same set `docs/tapes/fixtures.sh` stands up, which is why no runner does this.
  - **Do:** `docs/tapes/fixtures.sh`, then `vhs docs/tapes/<name>.tape` from the repo root for each, then `fixtures.sh down`.
  - **Ticks when:** all five plus `docs/demo.gif` match what a session prints today.

## Code work

### Release & packaging

- [ ] **Channel publish automation** — cutting a release used to end with
      hand-copying manifests to the AUR and the tap. Both are pushes to git
      repos, and both are now jobs behind the same manual release gate. This
      entry ticks when both have run for real.

  - **Homebrew tap PR** — _Written._ `release.yml`'s `tap` job: `needs: publish`, inside the same `environment: release` so it stays behind the one approval, opening a PR against `<owner>/homebrew-tap` with the freshly regenerated formula and the `brew install`/`test`/`audit` checklist in its body. No-ops loudly without `HOMEBREW_TAP_TOKEN`, the same shape the apk and minisign steps use — which is what makes it safe to land before the tap repo exists.
  - **AUR push** — _Written; the account is the remaining half._ The `aur` job pushes the regenerated `PKGBUILD` and `.SRCINFO` to `ssh://aur@aur.archlinux.org/hi.d.git` behind the same gate, with the key kept in `$RUNNER_TEMP` and the host key keyscanned rather than trusted on first use. It refuses to push a checkout with untracked files, and no-ops loudly without `AUR_SSH_KEY`. What it deliberately does not do is run namcap — that needs an Arch box — so the *first* push of each package stays manual and this job is for the releases after it. `hi.d-git` is never touched: it builds from `main` and has no version to bump.

### Product

- [ ] **Shells hi doesn't style yet** — the README's
      [compatibility tables](../README.md#compatibility) now say plainly which
      shells get the full session (bash ≥ 3.2, zsh, fish), which get aliases
      only (sh/dash/ash), and which get nothing (nushell, elvish, xonsh, ksh,
      tcsh, PowerShell). Any of them landing hi a session as a *login* shell is
      already fine — that path only has to run one `sh -c`. What is missing is a
      session shell: an rc in `shells/`, a tier in `hi.sh`'s
      `_hi_remote_suffix` ladder and in `load.sh`'s `load()`. `ksh`/`mksh` is
      the one worth doing first by a distance: it reads `$ENV` exactly as the
      `sh` fallback already does, and `shells/aliases.sh` is POSIX, so it is a
      prompt and a ladder tier rather than a third implementation of
      everything. nushell and elvish each need their own language; xonsh is
      Python. Decide per shell whether the aliases are worth porting before
      writing any of them.

- [ ] **Session shell should follow the login shell** — _Unblocked_, and the
      design question the matrix above turned up. `load.sh`'s `load()` picks
      the session shell by what the target *has* (`fish` > `zsh` > `bash`) and
      never looks at what the user's login shell is. So someone whose login
      shell is zsh-with-oh-my-zsh, on a box that also has fish, is handed fish —
      and their entire setup never loads. It is deliberate ("prefer the nicest
      shell available") and it is defensible for hi's own configs, which are
      grafted onto all three rc files anyway; it is much less defensible for the
      user's. First step is a decision, not code: prefer `$SHELL` when hi
      supports it and fall back to the ranking otherwise, or make the ranking a
      setting (`_HI_SHELL_PREFERENCE`), or both. Then it is a few lines in
      `load()` and a case in the e2e matrix per shape.
