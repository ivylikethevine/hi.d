# Tooling & practices roadmap

What is left to do on hi.d, in two halves:

- **[In-repo code work](#in-repo-code-work)** — everything that can be written
  and finished in this checkout, with nothing outside it involved.
- **[Outside this repo](#outside-this-repo)** — everything gated on a machine,
  an account, a key or a click that no file here can perform. Each names where
  you go, what you do, and what ticks it. Almost all of it is gated on
  publishing, so it sits at the bottom and blocks nothing day to day.

Nothing is wired up until its checkbox is ticked. Entries that are finished,
and questions that have been decided against, are **deleted** rather than kept
here: git history is the ledger, and this file is only what is left to do.

## In-repo code work

### Release & packaging

- [ ] **Source tarball under the provenance chain** — _Blocked on: v1._ Both
      manifests checksum GitHub's auto-generated `/archive/` tarball, the one
      released artifact with no attestation and no signature over it. The
      release already builds the identical shape (`git archive` in the
      rehearsal): attach it as an asset, list it in `SHA256SUMS`, point both
      `url=`s at it. Touches `bump.sh`, both manifests and their tests.

### Tooling

- [ ] **timep profiling for the paths the bench suite guards** — `_hi_bench`
      (`../tests/bench/bench_test.sh`) gives one average per hot path against a
      generous ceiling, which answers _whether_ something got slower and never
      _which command inside it did_ — so every regression starts by
      hand-bisecting an rc file. [timep](https://github.com/jkool702/timep) is
      the missing half: a trap-based bash profiler that maps the call-stack tree
      and emits per-command SELF and TOTAL wall time, TOTAL CPU time, and an
      optional flamegraph. Shape it like `tests/coverage.sh` — a
      `tests/profile.sh` run by hand, deliberately **not** in CI. The bench
      ceilings stay the gate; this is what you run once one of them trips.
      `tests/` ships in neither `$_HI_PAYLOAD` nor `$_HI_PACKAGE_CONTENTS`,
      which is why `coverage.sh` lives there and why this belongs beside it.

  - **Point it at the product, never at a suite.** timep drives the DEBUG trap —
    the same mechanism `coverage.sh`'s header documents kcov losing the moment
    `test_lib.sh` is sourced. Profile the argv `_hi_bench_env` already builds
    (`bash -c 'source shells/bash.sh'`; `header.sh` then `hi_header Online`; the
    50-call `_hi_git_prompt` loop; `hi.sh`'s payload assembly) rather than
    wrapping `test_runner.sh`, or this lands in kcov's hole for the same reason.
  - **bash arms only.** It profiles bash, so `shells/config.fish`,
    `shells/zsh.zsh` and `common/targets.sh`-under-`sh` stay bench-only. Scope is
    `shells/bash.sh`, `common/header.sh`, `common/git_prompt.sh` and `hi.sh`.
  - **Dev-only dependencies, so state them and skip cleanly:** bash loadable
    builtins, `/dev/shm` (or `$TMPDIR`), and perl for the flamegraph. Print a
    yellow skip naming where to get it rather than failing, as `coverage.sh`
    does for a missing kcov, and say which backend actually ran, as `_hi_bench`
    does for hyperfine.
  - **Ticks when:** `tests/profile.sh` produces a per-command profile for at
    least the header and git-prompt paths, and its header says what the numbers
    do and do not mean as bluntly as `coverage.sh`'s does.

## Outside this repo

### GitHub repo settings

All four are one-time, pre-first-release, and none can be done from a workflow
file. The exact commands live in the entries below — this file is the single
copy, and the README's "Packaging & releases" points at it. The last two are
what `vars.RUNNER_LABEL` waits on: until both are set, pointing that variable
at a self-hosted runner is the thing that exposes it.

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

- [ ] **Fork PRs need approval to run at all** — a public repo plus a
      self-hosted runner is the combination GitHub warns about: a fork PR is a
      stranger's branch, and `ci.yml` runs `tests/test_runner.sh` from it.
      `ci.yml`'s `runner` job already denies fork PRs the self-hosted label
      whatever `RUNNER_LABEL` says; this is the other half, and it stops the
      run before it starts rather than redirecting it.

  - **Where:** Settings → Actions → General → *Fork pull request workflows from outside collaborators*
  - **Do:** select **Require approval for all outside collaborators** — the default is only first-time contributors, which is not the same promise.
  - **Ticks when:** the strictest of the three options is the one selected.

- [ ] **The `manual-dispatch` approval gate** — `macos-e2e.yml`,
      `windows-e2e.yml`, `scorecard.yml` and `release.yml`'s rehearsal `gate`
      job all declare `environment: manual-dispatch`. As with `release` above,
      an environment with no required reviewer is **no gate at all** — the
      declarations are inert until this exists. `workflow_dispatch` already
      demands write access, so this is the second lock, not the first.

  - **Where:** Settings → Environments
  - **Do:** New environment → name it `manual-dispatch` → tick **Required reviewers** and add yourself → Save.
  - **Ticks when:** the environment exists with a reviewer on it, and a dispatch of `scorecard.yml` lands in *Waiting* instead of running.

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

### Release channels

Both jobs are written and behind the release gate; what's left in each is
human — an account, a key, and (once) a real machine or a real box to run the
gate namcap needs. The full walkthrough (commands, what a clean run prints,
what's already been verified) is [PACKAGING.md](PACKAGING.md)'s
_Publishing each channel_ section — these two entries are just the remaining
human steps and their tick conditions.

- [ ] **AUR** — register an account; `ssh-keygen -t ed25519`, add the public
      half there, add the private half as the `AUR_SSH_KEY` repo secret and
      delete the local copy. For each package's first push, re-run the
      namcap gate against the published source and push only `PKGBUILD` +
      `.SRCINFO` — that first push is manual, `release.yml`'s `aur` job
      handles the versioned package after.

  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `hi.d` current for one real release.

- [ ] **Homebrew tap** — create the `homebrew-tap` repo (a plain GitHub repo
      with a `Formula/` directory), add a fine-grained PAT scoped to it
      (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`, then re-run
      the `brew install`/`test`/`audit` gate on an actual Mac (the keg lives
      under `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/hi.d` works, from a release the
    `tap` job opened a PR for.

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

### Docs & submissions

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

- [ ] **tldr page** — five example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages **after v1**, once the CLI surface is frozen — examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.
