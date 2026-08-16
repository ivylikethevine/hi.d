# Tooling & practices roadmap

Candidate additions for developing hi.d. Two halves, because they need two
different kinds of attention:

- **[Human actions](#human-actions)** — nothing here is code. Each entry names
  where you go, what you do, and what ticks it. Every one of them is gated on
  publishing, so all of it can wait while the package is in development.
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

## Code work

### Release & packaging

- [ ] **Channel publish automation** — cutting a release still ends with
      hand-copying manifests to the AUR and the tap. Both are pushes to git
      repos, and both can be jobs behind the same manual release gate. - **Homebrew tap PR** — _Written._ `release.yml`'s `tap` job: `needs:
      publish`, inside the same `environment: release` so it stays behind the
      one approval, opening a PR against `<owner>/homebrew-tap` with the
      freshly regenerated formula and the `brew install`/`test`/`audit`
      checklist in its body. No-ops loudly when `HOMEBREW_TAP_TOKEN` is
      absent, the same shape the apk and minisign steps use — which is what
      makes it safe to land before the tap repo exists. Ticks on its first
      real PR. - **AUR push** — _Blocked on:_ an AUR account and an SSH deploy key
      (see [External accounts](#external-accounts--submissions)). Same shape,
      higher stakes: a push to `ssh://aur@aur.archlinux.org/`, and the
      namcap gate can't run in this CI. Do the tap job first.

### Repo & CI

- [ ] **markdownlint should warn, not block** — `ci.yml`'s `markdownlint` job
      runs `DavidAnson/markdownlint-cli2-action` as a hard gate, so a prose nit
      in a doc fails the same check set that guards `hi.sh`. The two are not
      the same risk: a broken heading level has never shipped a bug. Make the
      job non-blocking while keeping its output — `continue-on-error: true` is
      the one-line version; annotations in the run summary (or a
      `::warning::`-emitting step) is the version that still gets read. Whether
      the required-checks ruleset in
      [Human actions](#github-repo-settings) needs a matching edit depends on
      which of the two is chosen, so decide that before applying the ruleset.
- [ ] **The reported payload size is the wrong number** — `_hi_size` in `hi.sh`
      is `du -shc` over `$_HI_PAYLOAD`, i.e. the *uncompressed on-disk* size of
      the directories, and that number is what the connect line and the header
      show as what hi "sent". What actually crosses the wire is the base64
      armor of a gzipped tar (plus the bootloader, itself base64 of the
      generated script) — reliably smaller, and the difference is not a rounding
      error. The honest number is already computable at the one place both
      streams are built in `_say_hi`: measure the armored strings rather than
      the source tree. Things to settle: the permanent-install branch sends no
      tree at all (today it prints "-> local hi.d install" instead of a size,
      which stays right), the container path builds its tar separately, and
      `tests/bench/bench_test.sh`'s payload budget plus the README badge both
      measure the gzipped tarball already — so the badge is the number to agree
      with, and the bench suite is where the guard belongs.

### Product

- [x] **tmux support** — _Done_, in the two halves that stand on their own.
      `misc/tmux.conf` ships alongside the vim/nano/eza configs, with the same
      overlay slot (`~/.config/hi.d/tmux.conf`, riding `$_HI_OVERLAY_FILES`),
      its own toggle (`_HI_DISABLE_TMUX`), and a `tmux -f` alias exactly as
      `vim -u` is. Carrying hi _inside_ a remote tmux turned out to be the
      config's `update-environment` lines: tmux refreshes those variables from
      the attaching client, so a window opened after attach gets a shell that
      can still find `$_HI_HOME` — verified against a server deliberately
      started without them. The cleanup conflict is settled the way this entry
      predicted: the alias exists only where `$_HI_CLEANUP` is empty, i.e. on a
      permanent install, since a detached tmux outlives the session that would
      otherwise delete the tree underneath it.
- [x] **Configurable prompt separator, per shell** — _Done._ The character
      closing the prompt was hardcoded once per shell and differed in each
      (`bash.sh` `$`, `zsh.zsh` `>`, `config.fish` `|`); those are now the
      defaults behind `_HI_PROMPT_END_BASH` / `_HI_PROMPT_END_ZSH` /
      `_HI_PROMPT_END_FISH`, resolved by `_hi_prompt_end` in `common/core.sh`
      (and its mirror in `config.fish`). The three decisions came out: root
      still overrides fish's with `#`; the value reaches `PS1` unescaped, so
      zsh's `%#` and bash's `\$` mean what they mean there; and a single
      `_HI_PROMPT_END` covers all three, with the shell-specific one winning.
      `hi_configure` asks for each (skipped when the prompt is off, and a value
      equal to the default clears the override rather than writing it).
- [ ] **Interop with the common shell frameworks** — _Unblocked_, and the
      likeliest source of "hi broke my shell" reports from anyone who doesn't
      start from a bare rc. `load.sh`'s `configure_files` appends hi's block to
      the _end_ of `~/.bashrc`, `~/.zshrc` and `config.fish`, so hi runs after
      the framework and generally wins — which is right for the prompt and
      wrong for everything the framework sets up afterwards. Known collisions,
      each worth its own test before any fix:
      - **oh-my-zsh**: `shells/zsh.zsh` sets `setopt KSH_ARRAYS`, and omz (plus
        most of its plugins and themes) assumes zsh's native 1-based arrays.
        That is the sharpest edge here and it is ours, not theirs.
      - **prompt frameworks** — powerlevel10k, starship, tide, spaceship: each
        installs its own `PROMPT`/`fish_prompt`, so whichever loads last wins
        silently. hi should notice one is present and either stand down (the
        user chose that prompt) or say so, rather than clobbering it —
        `_HI_DISABLE_PROMPT` already exists as the answer, so this is about
        detection and a one-line notice, not new machinery.
      - **completion init**: `zsh.zsh` runs its own cached `compinit`, and omz
        runs one too; two initializations mean a slower shell and, if the
        `fpath` differs between them, a confusing one.
      - **bash-it / ble.sh** and **fisher / oh-my-fish**: same shape, less
        common; `PROMPT_COMMAND` chaining in bash is already handled
        (`ps1${PROMPT_COMMAND:+; $PROMPT_COMMAND}`), which is the pattern the
        rest should follow.
      First step is a matrix rather than code: a container per framework in the
      e2e suite (they all install from a script into a bare image), asserting
      the session comes up with no shell errors — the same bar
      `tests/targets/ssh_test.sh` already holds bash 3.2 to. What that matrix
      says is failing decides which of the above gets fixed and which gets
      documented as "turn this toggle off".
- [x] **tmux auto-attach** — _Done._ `hi --tmux <target>` (or
      `_HI_TMUX_ATTACH=1` in settings.sh, with `--no-tmux` to override it back)
      runs the session inside a named tmux on the target, so a dropped
      connection detaches instead of losing the work. The open question is
      answered by `new-session -A`: attach to `$_HI_TMUX_SESSION` (default
      `hi`) if it exists, create it if not — the one answer that never loses
      anything. The client only decides whether it was asked for; load.sh's
      `_hi_tmux_wanted` asks the target's own questions and refuses *loudly,
      without dropping the connection*, when there is no tmux there or when the
      tree is disposable (a detached session would outlive the tree it reads).
      `tests/targets/ssh_test.sh` proves the promise the only way that means
      anything: it starts a session, kills the client, and asserts the tmux
      session is still there.
