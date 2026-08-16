# Tooling & practices roadmap

Candidate additions for developing hi.d, roughly ordered by payoff-per-effort
within each section. Each entry says what it is, why it fits this repo
specifically, and the concrete first step. Nothing here is wired up until its
checkbox is ticked.

## In progress — awaiting outside action

In-repo work for these is done; each ticks on an event outside this
repository (a CI dispatch, a repo setting, an upstream merge).

- [ ] **macOS loopback e2e** — CI's macos job runs only the fast suites, so
      the BSD userland (`sed -i ''`, `mktemp -t`, `base64 -D`, bash 3.2) is
      never crossed by a real connection. GitHub's macOS runners ship sshd: a
      job that enables Remote Login, authorizes a throwaway key, and runs
      `hi localhost 'echo marker'` covers the whole client-and-target BSD path
      in one go. First step: a workflow_dispatch job; promote to every-PR only
      once it proves stable. The job is written
      (`.github/workflows/macos-e2e.yml`, pty-wrapped like the e2e suites,
      with a cleanup-trap assertion); ticks on its first green dispatch.
- [ ] **Windows target e2e** — the README documents the Git Bash/WSL/
      PowerShell fallback ladder and `packaging/windows.md` gates every native
      Windows channel on "the Windows CI job is green" - but no such job
      exists. windows-latest runners ship OpenSSH server: configure it, then
      drive `hi localhost` at each `DefaultShell` shape (cmd, powershell) plus
      Git Bash on PATH. First step: workflow_dispatch; the cmd `||` fallback
      the README promises is the case to pin down first. The job is written
      (`.github/workflows/windows-e2e.yml`: stock sshd, admin authorized_keys
      ACL, Git Bash client, asserts the PowerShell greeting); explicitly
      experimental - ticks on its first green dispatch.
- [ ] **Branch protection on `main`** once the release flow is live: required
      checks = the fast suites; note the release workflow's publish job pushes
      manifests to `main`, so either allow its bot or switch that step to opening
      a PR at the same time. The ready-to-run ruleset (bypass for the
      github-actions App, both fast-suite checks) is in `packaging/README.md`'s
      before-first-release checklist - a repo setting `gh api` applies in one
      command; run it alongside the `release` environment setup. Ticks when
      the ruleset is actually active on the repo.
- [ ] **OpenSSF Scorecard** — a public supply-chain score that directly
      credits work already done here (SHA pins, minimal token permissions,
      dependabot, zizmor, branch protection once applied). One workflow from
      ossf/scorecard-action plus a README badge. First step: run it once via
      workflow_dispatch and read the report before publishing any badge.
      The workflow is written (`.github/workflows/scorecard.yml`,
      dispatch-only, SARIF artifact, publish_results off); ticks once it has
      been run and the report read.
- [ ] **tldr page** — a `hi` page in the tldr-pages repo
      (github.com/tldr-pages/tldr): five example lines reach everyone who
      types `tldr hi` before anyone reads a man page. Upstream has its own
      style guide and review, so this is a submission, not a file here.
      First step: draft the page against their template once v1 is tagged
      and the CLI surface is frozen - examples that churn are worse than no
      page. The draft is checked in (`docs/tldr.md`, seven examples in their
      format); ticks when it is actually submitted and merged upstream,
      after v1.

## Release & packaging

- [ ] **Signed release sums** — wired: the publish job installs a pinned
      minisign (setup-minisign, drift-checked weekly) and signs SHA256SUMS
      with the `MINISIGN_SECRET_KEY` environment secret, sealed to the
      release gate; the .minisig rides the upload only when it exists, and
      the README's "Verifying a release download" section shows the check.
      Ticks on the human half: `minisign -G -W` per packaging/README.md's
      checklist, add the environment secret, and replace the README's
      placeholder public key.
- [ ] **Alpine apk channel, done properly** — signing is wired: nfpm.yaml
      declares the signature (key from `$HI_APK_KEY`, name `hi.d.rsa.pub`),
      release.yml injects the `APK_SIGNING_KEY` repo secret, and CI's
      packaging-smoke installs a signed apk on Alpine every PR. Along the way
      the channel turned out to be broken outright - nfpm 2.47.0's `type:
    tree` writes directory modes apk-tools rejects ("package file format
      error"); the apk now enumerates its contents per member, guarded by the
      packaging suite, until that is fixed upstream. Ticks on the human half:
      generate the keypair per packaging/README.md's checklist, add the
      secret, commit `packaging/apk/hi.d.rsa.pub`.
- [ ] **Channel publish automation** — cutting a release still ends with
      hand-copying manifests to the AUR and the tap. Both are pushes to git
      repos, and both could be jobs behind the same manual release gate: an
      AUR push with an SSH deploy key secret, a tap PR with a fine-grained
      token. Keeps the human approval, removes the copy step it approves.
      First step: the tap PR job - lower stakes, same shape.

## Product

- [ ] **tmux support** — scope to decide, likely some combination of: a
      shipped `misc/tmux.conf` alongside the vim/nano/eza configs (with an
      overlay slot in `~/.config/hi.d/` like colors/packages); carrying the hi
      session cleanly _inside_ a remote tmux (prompt/colors/aliases surviving
      `tmux new` on the target, which today starts a fresh login shell that
      hasn't sourced hi's rc); and possibly a `hi <target>` flag or setting to
      auto-attach/create a named tmux session remotely so a dropped connection
      resumes instead of losing the session. The cleanup trap needs thought:
      detached tmux outlives the ssh session, which conflicts with "remove
      everything on exit" - probably only offered when the target has a
      permanent ~/hi.d.
- [ ] **Per-host settings overlay** — one global settings.sh means the same
      toggles everywhere, but hosts differ: a slow link wants
      `_HI_HEADER_CHECK=0`, a shared root box wants the prompt only. A
      `~/.config/hi.d/settings.d/<host>.sh` sourced after settings.sh when
      `$_HI_TARGET` matches keeps the overlay model intact (outside the tree,
      rides the existing overlay stream). First step: decide the matching rule
      (exact host vs `# Tags:` hosttag) before writing any code.
- [ ] **Fleet update for permanent installs** — targets with a permanent
      `~/hi.d` go stale until someone remembers to run `hi_update` _on_ each
      host. A `hi --update <target>` that runs the remote tree's own update
      over the existing connection path (and refuses for package-manager
      installs, exactly as `hi_update` does locally). First step: scope what
      "update" means for each install flavor before touching hi.sh.
- [ ] **OSC 52 clipboard** — yanking on a remote host into the _local_
      clipboard is the one piece of "your environment follows you" that stops
      at the ssh boundary. vim.rc can emit OSC 52 on yank and modern terminals
      accept it; a small `hi_copy` alias covers the non-vim case. Terminal
      support varies, so it wants a toggle like every other feature. First
      step: the vim.rc autocmd behind `_HI_DISABLE_OSC52`, tested in the
      terminals actually in use.

## Documentation

- [x] **Per-target demo GIFs** — done: one tape per backend in docs/tapes/
      (ssh permanent-install, docker debian/bash + a one-off into a zsh-only
      alpine, podman fish-client-into-fish-only-box, nomad alloc by ID
      prefix, kube ash pod), self-pacing via vhs Wait+Screen sentinels
      rather than fixed sleeps, with docs/tapes/fixtures.sh standing up
      every target (e2e-fixture shapes, standalone; `fixtures.sh down`
      removes the lot). Rendered GIFs live in docs/demos/, the gallery is
      docs/demos.md, and the README links it under the original demo.
