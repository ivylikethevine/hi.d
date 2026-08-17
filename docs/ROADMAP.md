# Tooling & practices roadmap

Candidate additions for developing hi.d. Two halves, because they need two
different kinds of attention:

- **[Code work](#code-work)** — entries that are written in this repo. Each is
  marked **Unblocked** or **Blocked on:** so it's clear at a glance which need
  a human step first.
- **[Human actions](#human-actions)** — nothing there is code. Each entry
  names where you go, what you do, and what ticks it. Almost all of it is
  gated on publishing, so it sits at the bottom: none of it blocks daily
  development, and it can wait while the package is in development — the
  exceptions say so.

Nothing here is wired up until its checkbox is ticked. Finished entries are
**removed** rather than left ticked — git history is the ledger of what was
done; this file is only ever what's left.

## Code work

### Release & packaging

- [ ] **Channel publish automation** — cutting a release used to end with
      hand-copying manifests to the AUR and the tap. Both are pushes to git
      repos, and both are now jobs behind the same manual release gate. This
      entry ticks when both have run for real.

  - **Homebrew tap PR** — _Written._ `release.yml`'s `tap` job: `needs: publish`, inside the same `environment: release` so it stays behind the one approval, opening a PR against `<owner>/homebrew-tap` with the freshly regenerated formula and the `brew install`/`test`/`audit` checklist in its body. No-ops loudly without `HOMEBREW_TAP_TOKEN`, the same shape the apk and minisign steps use — which is what makes it safe to land before the tap repo exists.
  - **AUR push** — _Written; the account is the remaining half._ The `aur` job pushes the regenerated `PKGBUILD` and `.SRCINFO` to `ssh://aur@aur.archlinux.org/hi.d.git` behind the same gate, with the key kept in `$RUNNER_TEMP` and the host key keyscanned rather than trusted on first use. It refuses to push a checkout with untracked files, and no-ops loudly without `AUR_SSH_KEY`. What it deliberately does not do is run namcap — that needs an Arch box — so the *first* push of each package stays manual and this job is for the releases after it. `hi.d-git` is never touched: it builds from `main` and has no version to bump.

- [ ] **Source tarball under the provenance chain** — *Blocked on: v1.* The
      PKGBUILD and formula checksum GitHub's auto-generated `/archive/`
      tarball — the one released artifact with no attestation and no minisign
      signature over it. The release already builds the identical shape
      (`git archive` in the rehearsal); attach it as an asset, list it in
      `SHA256SUMS`, and point both manifests' `url=` at it. Medium: touches
      `bump.sh`, both manifests and their tests.

### Product

- [ ] **Shells hi doesn't style yet** — the README's
      [compatibility tables](../README.md#compatibility) say where each shell
      stands today; the ksh/mksh tier (live git segment included) and the
      nushell session tier are shipped and suite-proven, so only the open
      halves are listed here:

  - **the bash-less tier's header** — recommendation: leave it unwritten.
    `common/header.sh` is bash, the tier exists because bash is absent, and a
    second POSIX implementation would have to be kept in sync forever — the
    git segment earned that cost, a header would not.
  - **elvish and xonsh** — each needs its own language for any of it; **tcsh**
    has no `$ENV` equivalent to hook. Decide per shell whether that is worth
    it — as a *login* shell they all work today.

### Cleanup & structure

Deferred on purpose from the Aug 2026 simplification passes — each is real,
none urgent, and the drift-prone spots have test pins holding them in the
meantime.

- [ ] **Unify the two fallback-launch recipes** — _the gap is closed; the
      duplication is what's left._ `_say_hi_container` now gives ksh/mksh the
      live git segment the ssh path always granted them (it ships
      `shells/ksh.sh` beside `aliases.sh` and sources it by absolute path,
      since that transport lands no tree), pinned by
      `test_container_fallback_gives_ksh_the_git_segment`. What that work
      showed is that the *launch* idiom was already common — the container
      `*)` arm's `ENV=… exec $fallback -i` is the ssh ksh arm verbatim — so
      only the rc **contents** diverge, and a shared recipe function would
      have to render into two different mechanisms (armored heredoc vs.
      `sh -c` round trips) to be worth writing. The zsh/fish/ksh arms still
      exist twice; whether that duplication is worth a shared renderer is now
      an open question rather than an assumed yes.
- [ ] **Parallelize the independent probes** — header.sh's `identity()` runs
      its docker/nomad/kubectl probes serially (worst case the *sum* of three
      2s timeouts while the user waits at connect), and `_hi`'s dispatch
      walks the backend predicates the same way before a kube target
      connects. Background jobs + `wait` turns both into max(probes). Same
      family: bash/zsh completion could keep the target list in a shell
      variable for `$_HI_TARGETS_TTL` seconds so repeat TABs fork nothing.
- [ ] **Single-home the remaining hand-synced rosters** — the prompt-end
      defaults (install.sh's rows vs each shell rc's literal), the
      shell↔rc-file pairing (install.sh's `_HI_RC_TABLE`, load.sh's
      `_HI_CONFIGS`, paths.sh's path vars, doctor's shell loop), and the
      glyph/palette tables (core.sh / config.fish / ksh.sh, agreement-pinned
      by tests today). Each is a lockstep edit; the dialect boundaries mean
      data-file or generation approaches rather than shared functions.
- [ ] **One git-segment implementation** — `shells/ksh.sh`'s POSIX segment
      could serve the bash tier too and retire `common/git_prompt.sh` (~150
      payload lines, the largest size win available). Weigh the per-prompt
      cost of losing bash-only builtins before starting.
- [ ] **`--version` stamping through one entry point** — the four
      per-channel sed pairs (mkpkg.sh, both PKGBUILDs, the Homebrew formula)
      re-implement the same stamp.
- [ ] **CI tooling consolidation** — one parameterized `setup-tool` action
      plus a tools manifest could replace the eight composite actions, their
      eight install scripts, and `check_tool_versions.sh`'s roster;
      release.yml's artifact/manifest lists could read a mkpkg-emitted file.
- [ ] **Runner parallelism** — `test_runner.sh --jobs N`. New machinery, so
      it waits until the serial wall clock actually hurts.

### Docs

- [ ] **Jekyll GitHub Pages action** — _Unblocked to write; publishing waits
      on the repo being public._ A `pages.yml` workflow that renders the
      repo's markdown (`README.md` as the index — it now carries the demos,
      comparison, architecture, packaging and Windows material inline — plus
      what is left in `docs/`: GLOSSARY, CONTRIBUTING, SECURITY, this file and
      tldr, which interlink with relative links `link-check.yml` keeps
      honest) into a GitHub Pages site via the
      stock `actions/jekyll-build-pages` → `actions/deploy-pages` pair,
      SHA-pinned and minimal-permission like every other workflow here,
      plus a small `_config.yml` choosing a theme and excluding the
      non-docs tree. The human half is one click — Settings → Pages →
      Source: GitHub Actions — which only exists once the repo is public.

### Tests

- [ ] **a host report from the harness** — when a suite fails on someone's
      machine and passes in CI (or the reverse), the first three questions are
      always the same and none of them are in the output: what bash is this,
      what userland, and is `_HI_HOME` even pointing at this checkout. A single
      debug block, printed once at the top of a run, would answer them: bash
      version and path, OS/kernel, whether the userland is GNU or BSD/busybox,
      `$_HI_HOME`/`$_HI_ROOT` and whether they resolve to the tree the runner
      was invoked from, which backends (`docker`/`podman`/`nomad`/`kubectl`/
      `ssh`) probe available, and the lint tools' versions (`shellcheck`,
      `shfmt`, `checkbashisms`). Natural home is `tests/test_lib.sh` — it
      already owns the skip preamble and the probe commands — behind a flag or
      env on `tests/test_runner.sh` so CI logs can always carry it without
      noising up a local run. The `_HI_HOME` line alone pays for it: pointing
      at the wrong tree is this repo's most common false result, and it
      currently shows only as a suite quietly running fewer cases.

  - **Ticks when:** a run with the flag prints the block, and CI's fast job passes it by default.

- [ ] **the relay e2e** — prove `hi` can be chained: from machine A (has
      hi.d) to machine B (doesn't), then *from inside that session* on to
      machine C — the config landing intact on the final hop, and the
      cleanup traps firing on **both** B and C, on clean exit and on an
      error/kill mid-relay alike. Harness-wise this is two sshd containers on
      one docker network, a key authorized from B to C, and the existing pty
      feeder typing the second `hi` into the first session; the
      disconnect-trap assertion already exists in `ssh_disconnect_test.sh`
      to crib from. The test will immediately surface the real design
      question, which should be answered on purpose rather than by accident:
      **`hi.sh` itself is deliberately not in `$_HI_PAYLOAD`**, so a
      disposable session on B has no launcher to relay with — the `hi` alias
      points at `$_HI_LAUNCHER`, which only exists where hi.d is permanently
      installed. So either the relay is documented as
      permanent-install-only (and the test proves that path), or an opt-in
      (`_HI_RELAY=1`?) ships `hi.sh` in the payload for hop-capable
      sessions and the test proves the disposable path too — weigh the
      payload cost against the badge before choosing the second.

## Human actions

### GitHub repo settings

Both are one-time, both are pre-first-release, and neither can be done from a
workflow file. The exact commands live here, in the entries below — this file
is the single copy, and the README's "Packaging & releases" points at it.

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

Two keypairs. **The in-repo half of both is already written and tested** — CI consumes each secret the moment it exists and says so loudly in the log when it doesn't. What's left is generating the key and pasting it in; the exact commands are in each entry below.

- [ ] **apk signing key** — signing is wired end to end: `nfpm.yaml` declares
      the signature (key from `$HI_APK_KEY`, name `hi.d.rsa.pub`), `release.yml`
      injects the `APK_SIGNING_KEY` repo secret, and CI's packaging-smoke
      installs a signed apk on Alpine every PR. Without the key the release apk
      builds unsigned and installing it needs `--allow-untrusted`.

  - **Where:** a terminal, then Settings → Secrets and variables → Actions
  - **Do:** generate the RSA keypair (abuild-style), add the private half as the `APK_SIGNING_KEY` **repo** secret (not an environment secret — the ungated build job needs it), commit `packaging/apk/hi.d.rsa.pub` under exactly that filename (apk matches signatures to `/etc/apk/keys/` by name, and it must stay what `nfpm.yaml`'s `key_name` says), delete the local private half.
  - **Ticks when:** the secret exists and the public key is committed.

    ```sh
    openssl genrsa -out hi.d-apk.rsa 4096
    openssl rsa -in hi.d-apk.rsa -pubout -out packaging/apk/hi.d.rsa.pub
    ```

- [ ] **minisign keypair** — the publish job installs a pinned minisign
      (drift-checked weekly) and signs `SHA256SUMS` with
      `MINISIGN_SECRET_KEY`; the `.minisig` rides the upload only when it
      exists, and the README's "Verifying a release download" section already
      shows the check.

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
      documents the Git Bash/WSL/PowerShell fallback ladder but no Windows job
      has ever run. (This is the *target*-side job; the README's "Windows
      channels" gates the native channels on a separate client-side job — the
      fast suites under Git Bash — which is not written yet.) The job configures the
      stock sshd, sets the admin `authorized_keys` ACL, drives `hi localhost`
      from Git Bash, and asserts the PowerShell greeting — the cmd `||` fallback
      the README promises is the case to watch. Explicitly experimental.
      (`.gitattributes` now pins LF endings repo-wide, which removes the
      classic CRLF-checkout first-dispatch failure from the risk list.)

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

- [ ] **Homebrew formula verification** — _the formula is verified; the mac is
      not._ `brew install --build-from-source`, `brew test` and
      `brew audit --strict --new` have all been run in the `homebrew/brew`
      container against a local tarball, and the installed keg exercised
      (`hi --version` reports the formula's version, the man page lands, the
      wrapper exports `_HI_HOME`, `hi --doctor` reads the keg). Two real
      findings came out of it and are fixed: the description needed a capital,
      and `uses_from_macos "openssh"` is rejected by audit - the formula now
      declares no dependencies, which is right, since `ssh` and `base64` ship
      with every system that could install it. Audit's only remaining
      complaints are the unreachable homepage and HEAD URL, i.e. the repo not
      being public yet.

  - **Ticks when:** the same three commands pass on an actual mac, where the keg lives under `/opt/homebrew` rather than Linuxbrew's prefix.
- [ ] **AUR package verification** — _the local half is done_: both PKGBUILDs
      have been built with `makepkg`, linted with `namcap` (recipe silent,
      package down to three documented false positives), installed into a clean
      `archlinux:base` container, exercised and removed. Two fixes came out of
      it — `coreutils` dropped from `depends` (it is in `base`) and `hi.d-git`
      now stamps `$pkgver`, since the installed tree has no `.git` for
      `hi --version` to fall back on. What is left is the part that needs the
      real thing: the same run against the published source rather than a local
      clone, which is only possible once the repo is public.

  - **Ticks when:** run clean for both packages against the published source.
