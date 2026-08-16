# Tooling & practices roadmap

Candidate additions for developing hi.d, roughly ordered by payoff-per-effort
within each section. Each entry says what it is, why it fits this repo
specifically, and the concrete first step. Nothing here is wired up until its
checkbox is ticked.

## Testing & performance

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

## CI & supply chain

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

## Release & packaging

- [ ] **Signed release sums** — the attestation proves which workflow run
      built the artifacts, but verifying it needs `gh` and GitHub; a
      detached minisign (or signify) signature over SHA256SUMS is the
      offline half - one keypair, one `minisign -Sm` in the publish job, the
      public key printed in the README. First step: generate the keypair and
      decide where the secret half lives (a repo secret, sealed to the
      release environment).
- [ ] **Reproducible packages** — SHA256SUMS is only as meaningful as the
      build is repeatable: two runs over the same tag should produce
      byte-identical deb/rpm/apk. The staging copy and gzip are already
      deterministic (`gzip -9n`); what remains is nfpm timestamps and file
      ordering. First step: build twice locally, diff the artifacts, and fix
      whatever differs (nfpm's `mtime` and `SOURCE_DATE_EPOCH` are the
      levers).
- [ ] **Alpine apk channel, done properly** — nfpm already emits an .apk,
      but unsigned: installing it needs `--allow-untrusted`, which is a
      non-starter advice-wise. Either sign it (abuild keygen + nfpm's apk
      signature support) and host a tiny repo index alongside the release,
      or write an APKBUILD and submit to aports/testing the way the AUR
      package works for Arch. First step: sign the existing artifact and
      verify `apk add` accepts it from a local file without the flag.
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
- [ ] **`hi --version`** — nothing installed can say what it is: a checkout
      can `git describe`, but a deb/rpm/apk or brew install has no version
      anywhere hi can read. Have `bump.sh` stamp the version into hi.sh (a
      `_HI_VERSION=` line it rewrites, like the manifests), print it for
      `--version`, fall back to `git describe` in a checkout, and show it in
      the doctor and the connect header. First step: the stamp in bump.sh,
      so the next release carries it.
- [ ] **Glyph fallback for C-locale targets** — the banner and packages
      check lean on ↑ ✓ ✗ ~; on a target without UTF-8 (LANG=C busybox,
      serial consoles) they render as mojibake. Probe the target locale the
      way everything else is probed and fall back to ASCII (^ ok x) when
      multibyte would break. First step: reproduce in the alpine e2e image
      with LANG=C and see how bad it actually looks.
- [ ] **Ghostty intercompatibility** — ghostty sets TERM=xterm-ghostty,
      which most targets have no terminfo for: backspace and clear break the
      session before hi even matters, and hi is exactly the tool positioned
      to fix it, since it already ships an environment. Options, smallest
      first: export a safe TERM fallback in the session rc when the target
      lacks the entry (`infocmp` probe); or carry the compiled terminfo over
      in the payload and set TERMINFO. First step: the probe + TERM
      fallback, tested from a real ghostty against the alpine e2e image.

## Documentation

- [ ] **tldr page** — a `hi` page in the tldr-pages repo
      (github.com/tldr-pages/tldr): five example lines reach everyone who
      types `tldr hi` before anyone reads a man page. Upstream has its own
      style guide and review, so this is a submission, not a file here.
      First step: draft the page against their template once v1 is tagged
      and the CLI surface is frozen - examples that churn are worse than no
      page. The draft is checked in (`docs/tldr.md`, seven examples in their
      format); ticks when it is actually submitted and merged upstream,
      after v1.
- [ ] **Per-target demo GIFs** — the README demo shows one docker session;
      the pitch is that every target type behaves identically, and only more
      GIFs can show that. One tape per backend (ssh with a permanent
      install, docker, podman, nomad, kube) across a variety of target
      shells and base images (debian/bash, alpine/ash, a zsh-only and a
      fish-only box), reusing the e2e fixtures that already build exactly
      those. Rendered by hand like the first one; a gallery section or
      docs/demos.md keeps the README from ballooning. First step: the ssh
      permanent-install tape, which is the flow the current GIF cannot
      show.
