# Tooling & practices roadmap

Candidate additions for developing hi.d, in two halves:

- **[Code work](#code-work)** — written in this repo, each marked
  **Unblocked** or **Blocked on:**.
- **[Human actions](#human-actions)** — no code; each names where you go, what
  you do, and what ticks it. Almost all is gated on publishing, so it sits at
  the bottom and blocks nothing day to day — the exceptions say so.

Nothing is wired up until its checkbox is ticked, and finished entries are
**deleted** rather than left ticked: git history is the ledger, this file is
only what's left.

## Code work

### Release & packaging

- [ ] **Channel publish automation** — updating the AUR and the tap used to be
      hand-copying manifests. Both are now jobs behind the one release gate.
      Ticks when both have run for real.

  - **Homebrew tap PR** — _Written._ `release.yml`'s `tap` job (`needs: publish`, same `environment: release`) opens a PR against `<owner>/homebrew-tap` with the regenerated formula and the `brew install`/`test`/`audit` checklist in its body. No-ops loudly without `HOMEBREW_TAP_TOKEN`, which is what makes it safe to land before the tap repo exists.
  - **AUR push** — _Written; the account is the remaining half._ The `aur` job pushes the regenerated `PKGBUILD` and `.SRCINFO` to `ssh://aur@aur.archlinux.org/hi.d.git` behind the same gate, key in `$RUNNER_TEMP` and the host key keyscanned rather than trusted on first use. Refuses a checkout with untracked files; no-ops loudly without `AUR_SSH_KEY`. It deliberately does not run namcap — that needs an Arch box — so each package's _first_ push stays manual and this job is for the releases after. `hi.d-git` is never touched: it builds from `main` and has no version to bump.

- [ ] **Source tarball under the provenance chain** — _Blocked on: v1._ Both
      manifests checksum GitHub's auto-generated `/archive/` tarball, the one
      released artifact with no attestation and no signature over it. The
      release already builds the identical shape (`git archive` in the
      rehearsal): attach it as an asset, list it in `SHA256SUMS`, point both
      `url=`s at it. Touches `bump.sh`, both manifests and their tests.

### Product

- [ ] **Shells hi doesn't style yet** — the README's
      [compatibility tables](../README.md#compatibility) say where each shell
      stands. The ksh/mksh tier (live git segment included) and the nushell
      session tier are shipped and suite-proven; only the open halves are here:

  - **the bash-less tier's header** — recommendation: leave it unwritten.
    `common/header.sh` is bash, the tier exists because bash is absent, and a
    second POSIX implementation would need keeping in sync forever — the git
    segment earned that cost, a header would not.
  - **elvish and xonsh** — each needs its own language for any of it; **tcsh**
    has no `$ENV` to hook. Worth deciding per shell — as a _login_ shell they
    all work today.

### Cleanup & structure

What is left here are three **recommendations against** doing the work, kept
because each is a question that will be asked again. The rosters, the version
stamp and the CI tooling shipped; git history is the ledger.

- [ ] **Unify the two fallback-launch recipes** — recommendation: leave both.
      The launch idiom is already shared (`_hi_fallback_rc`,
      `_hi_ladder_probe`, `_hi_fallback_prompt`, `_hi_armored_line`); what
      remains diverges by mechanism, not by accident. ssh writes the rc and
      has the _target_ append per arm, because the payload has to be armored;
      the container composes client-side and writes once, because `exec -i`
      takes raw bytes. A shared renderer would have to emit into both, which
      is more machinery than the three duplicated arms it would remove.
- [ ] **One git-segment implementation** — recommendation: keep both, for the
      same reason the bash-less tier has no header. Retiring
      `common/git_prompt.sh` in favor of `shells/ksh.sh`'s POSIX segment costs
      bash and zsh a `$( )` fork per prompt (their out-var call exists to
      avoid exactly that, and POSIX has no `printf -v`), adds ksh.sh's
      heredoc subshell and temp file per prompt, leaks `_hi_kg_*` into the
      user's shell for want of `local`, and loses `REBASE-i 3/7` and the
      rebase `head-name` branch recovery. The payload win is ~119 lines
      against 39KB used of a 48KB budget — the one thing not in short supply.
- [ ] **Runner parallelism** — `test_runner.sh --jobs N`, still waiting until
      the serial wall clock actually hurts. Two things to know before
      starting: `_HI_SSHD_IMAGE` is a _fixed_ tag four e2e suites share on
      purpose so a full run builds it once, so parallelising that group means
      either serialising it anyway or losing the sharing; and bash 3.2 has no
      `wait -n`, so the pool has to poll `kill -0` the way `_hi_wait_pid`
      does. `fast`'s 19 suites are the subset that would parallelise cleanly.

### Docs

- [ ] **The packaging runbook itself** — seven places point at
      `packaging/README.md` (release.yml five times, this file's AUR entry,
      packaging_test.sh's header) and CLAUDE.md points at `docs/packaging.md`.
      Neither file exists. The content is real and mostly written down already,
      scattered: the pre-submit namcap gate, the tap's `brew audit --strict
      --new` gate, and what the release workflow does and does not automate.
      One file, and the eight references pointed at it.

- [ ] **Jekyll GitHub Pages site** — _Written; the one click is the remaining
      half._ `pages.yml` builds the repo's markdown with the stock
      `jekyll-build-pages` → `upload-pages-artifact` → `deploy-pages` chain,
      SHA-pinned and minimal-permission like every workflow here (write scopes
      on the `deploy` job alone; Pages deploys never cancel in flight).
      `_config.yml` picks the primer theme, excludes everything that is code
      rather than prose, and turns on the four plugins the markdown needs:
      `readme-index` (so `README.md` is the index, as on github.com),
      `relative-links` (so `docs/GLOSSARY.md`-style cross-links resolve on the
      site too), `optional-front-matter` and `titles-from-headings`.

  - **Where:** Settings → Pages
  - **Do:** set _Source_ to **GitHub Actions**. Only exists once the repo is public.
  - **Ticks when:** that is set and a dispatch of `pages.yml` has deployed once, with the README rendering as the index and the docs cross-links resolving.

## Human actions

### GitHub repo settings

Both are one-time, pre-first-release, and neither can be done from a workflow
file. The exact commands live in the entries below — this file is the single
copy, and the README's "Packaging & releases" points at it.

- [ ] **The `release` approval gate** — `release.yml`'s `publish` job declares
      `environment: release`, but an environment with no required reviewer is
      **no gate at all**: a pushed `v*` tag would publish unattended.

  - **Where:** Settings → Environments
  - **Do:** New environment → name it `release` → tick **Required reviewers** and add yourself → Save. Optionally set _Deployment branches and tags_ to `v*` so nothing but a tag can reach it.
  - **Ticks when:** the environment exists with a reviewer on it.

- [ ] **Branch protection on `main`** — required checks = the fast suites. The
      wrinkle: `publish` pushes the regenerated manifests straight to `main` as
      `github-actions[bot]`, so the protection must let that App through — a
      ruleset with a bypass actor does, classic branch protection does not.

  - **Where:** the `gh` CLI (a repo setting under the hood)
  - **Do:** run the command below — one shot, bypass actor 15368 (the GitHub Actions App) already filled in. Do it alongside the `release` environment above.
  - **Ticks when:** the ruleset is active on the repo.

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

### Secrets & keys

Two keypairs. **The in-repo half of both is written and tested** — CI consumes each secret the moment it exists and says so loudly when it doesn't. What's left is generating the key and pasting it in.

- [ ] **apk signing key** — wired end to end: `nfpm.yaml` declares the
      signature (key from `$HI_APK_KEY`, name `hi.d.rsa.pub`), `release.yml`
      injects the `APK_SIGNING_KEY` secret, and CI's packaging-smoke installs a
      signed apk on Alpine every PR. Without the key the release apk builds
      unsigned and installing it needs `--allow-untrusted`.

  - **Where:** a terminal, then Settings → Secrets and variables → Actions
  - **Do:** generate the RSA keypair (abuild-style), add the private half as the `APK_SIGNING_KEY` **repo** secret (not an environment secret — the ungated build job needs it), commit `packaging/apk/hi.d.rsa.pub` under exactly that filename (apk matches signatures to `/etc/apk/keys/` by name, and it must stay what `nfpm.yaml`'s `key_name` says), delete the local private half.
  - **Ticks when:** the secret exists and the public key is committed.

    ```sh
    openssl genrsa -out hi.d-apk.rsa 4096
    openssl rsa -in hi.d-apk.rsa -pubout -out packaging/apk/hi.d.rsa.pub
    ```

- [ ] **minisign keypair** — the publish job installs a pinned minisign
      (drift-checked weekly) and signs `SHA256SUMS` with `MINISIGN_SECRET_KEY`;
      the `.minisig` rides the upload only when it exists, and the README's
      "Verifying a release download" already shows the check.

  - **Where:** a terminal, then Settings → Environments → `release` → Environment secrets
  - **Do:** generate it passwordless (CI has nobody to type one), paste `minisign.key`'s contents as the `MINISIGN_SECRET_KEY` **environment** secret (sealed to the gated publish job), put `minisign.pub`'s public key line into the README's "Verifying a release download" over the `RWT-PLACEHOLDER-…` value, delete both local files.
  - **Ticks when:** the secret exists and the README carries the real key.

    ```sh
    minisign -G -W -p minisign.pub -s minisign.key
    ```

- [ ] **Homebrew tap token** — only once the tap-PR job (see [Code
      work](#code-work)) has something to push to. The job no-ops cleanly
      without it.

  - **Where:** a fine-grained PAT, then Settings → Secrets and variables → Actions
  - **Do:** create a token scoped to the `homebrew-tap` repo with contents + pull-requests write, add it as `HOMEBREW_TAP_TOKEN`.
  - **Ticks when:** the secret exists and a release has opened a tap PR.

- [ ] **AUR deploy key** — only once the account exists and each package has
      been pushed by hand once (that first push is where namcap gates, and no
      runner here can run it). The `aur` job keeps the versioned package
      current after that, and no-ops loudly without the secret.

  - **Where:** a terminal, then Settings → Secrets and variables → Actions
  - **Do:** `ssh-keygen -t ed25519`, add the public half to your AUR account, add the private half as `AUR_SSH_KEY`, delete the local private half.
  - **Ticks when:** the secret exists and a release has pushed to the AUR.

### CI runs to dispatch

All three are written, committed, and dispatch-only. They need nothing but the repo pushed and Actions enabled — click Run workflow and read the result.

- [ ] **macOS loopback e2e** (`macos-e2e.yml`) — CI's macos job runs only the
      fast suites, so the BSD userland (`sed -i ''`, `mktemp -t`, `base64 -D`,
      bash 3.2) is never crossed by a real connection. GitHub's macOS runners
      ship sshd, so the job enables Remote Login, authorizes a throwaway key,
      and runs `hi localhost 'echo marker'` — the whole client-and-target BSD
      path in one go. Pty-wrapped, with a cleanup-trap assertion.

  - **Ticks when:** its first green dispatch. Promote to every-PR only once it proves stable.

- [ ] **Windows target e2e** (`windows-e2e.yml`) — the README documents the
      Git Bash/WSL/PowerShell fallback ladder but no Windows job has ever run.
      This is the _target_-side job; the client-side one the README's "Windows
      channels" gates on (the fast suites under Git Bash) is not written yet.
      It configures the stock sshd, sets the admin `authorized_keys` ACL,
      drives `hi localhost` from Git Bash, and asserts the PowerShell greeting
      — the cmd `||` fallback is the case to watch. Explicitly experimental;
      `.gitattributes` pins LF repo-wide, so the classic CRLF-checkout
      first-dispatch failure is off the risk list.

  - **Ticks when:** its first green dispatch.

- [ ] **OpenSSF Scorecard** (`scorecard.yml`) — a public supply-chain score
      crediting work already done here (SHA pins, minimal token permissions,
      dependabot, zizmor, branch protection once applied). Dispatch-only,
      SARIF artifact, `publish_results` off.

  - **Ticks when:** it has been run once and the report read. Only then decide about a README badge.

### External accounts & submissions

Each needs an account or a repo that doesn't exist yet; all of it waits for v1.

- [ ] **AUR** — no account, no submission yet. Two packages: `hi.d-git` (works
      today, no tag needed) and `hi.d` (once v1.0.0 exists).

  - **Do:** register an AUR account and add an SSH key, then run the pre-submit gate in `packaging/README.md` for **each** package — `makepkg -f`, `namcap PKGBUILD`, `namcap ./*.pkg.tar.zst`, `pacman -Qlp`. namcap is a hard gate, not a suggestion. Push only `PKGBUILD` + `.SRCINFO`. Never submit the versioned package with `b2sums=('SKIP')` — `SKIP` is correct only on `hi.d-git`.
  - **Ticks when:** both packages are live on the AUR.

- [ ] **Homebrew tap** — a tap is just a GitHub repo named `homebrew-tap` with
      a `Formula/` directory. No review, no approval, which is exactly why the
      local gate matters.

  - **Do:** create the repo, then `brew install --build-from-source`, `brew test hi.d`, and `brew audit --strict --new hi.d` must all pass before the formula is copied in.
  - **Ticks when:** `brew install ivy/tap/hi.d` works.

- [ ] **tldr page** — five example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages **after v1**, once the CLI surface is frozen — examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.

### Needs a machine this repo's CI doesn't have

Not GitHub-button work: human actions purely because no runner covers them, listed apart so they aren't mistaken for something a workflow could take over.

- [ ] **Homebrew formula verification** — _the formula is verified; the mac is
      not._ `brew install --build-from-source`, `brew test` and
      `brew audit --strict --new` have all run in the `homebrew/brew` container
      against a local tarball, and the keg was exercised (`hi --version`
      reports the formula's version, the man page lands, the wrapper exports
      `_HI_HOME`, `hi --doctor` reads the keg). Two findings came out and are
      fixed: the description needed a capital, and audit rejects
      `uses_from_macos "openssh"` — the formula now declares no dependencies,
      which is right, since `ssh` and `base64` ship with every system that
      could install it. Audit's only remaining complaints are the unreachable
      homepage and HEAD URL, i.e. the repo not being public yet.

  - **Ticks when:** the same three commands pass on an actual mac, where the keg lives under `/opt/homebrew` rather than Linuxbrew's prefix.

- [ ] **AUR package verification** — _the local half is done_: both PKGBUILDs
      built with `makepkg`, linted with `namcap` (recipe silent, package down
      to three documented false positives), installed into a clean
      `archlinux:base` container, exercised and removed. Two fixes came out —
      `coreutils` dropped from `depends` (it is in `base`), and `hi.d-git` now
      stamps `$pkgver`, since the installed tree has no `.git` for
      `hi --version` to fall back on. What's left needs the real thing: the
      same run against the published source, once the repo is public.

  - **Ticks when:** run clean for both packages against the published source.

Nice to have -

- built in configuration UI for host/tags/colors configuration as well as users
- built in package color/priority modification
- package groups/conditional loading
- evaluate moving hi.sh and load.sh to common or bin (revise directory structure)
