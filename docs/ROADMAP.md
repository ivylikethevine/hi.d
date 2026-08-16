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
      once it proves stable.
- [ ] **Windows target e2e** — the README documents the Git Bash/WSL/
      PowerShell fallback ladder and `packaging/windows.md` gates every native
      Windows channel on "the Windows CI job is green" - but no such job
      exists. windows-latest runners ship OpenSSH server: configure it, then
      drive `hi localhost` at each `DefaultShell` shape (cmd, powershell) plus
      Git Bash on PATH. First step: workflow_dispatch; the cmd `||` fallback
      the README promises is the case to pin down first.
- [ ] **kcov on a schedule** — `tests/coverage.sh` exists but only runs when
      someone remembers. A monthly `schedule:` workflow that runs it and
      uploads the HTML report as an artifact keeps "which arms of install.sh
      are untested" answerable, without wiring coverage into any PR gate (the
      original not-in-CI rule was about gating, not visibility). First step:
      the workflow, dispatch-triggerable for a dry run.

## CI & supply chain

- [ ] **Branch protection on `main`** once the release flow is live: required
      checks = the fast suites; note the release workflow's publish job pushes
      manifests to `main`, so either allow its bot or switch that step to opening
      a PR at the same time. The ready-to-run ruleset (bypass for the
      github-actions App, both fast-suite checks) is in `packaging/README.md`'s
      before-first-release checklist - a repo setting `gh api` applies in one
      command; run it alongside the `release` environment setup. Ticks when
      the ruleset is actually active on the repo.
- [ ] **Tool-version bump automation** — dependabot moves the SHA-pinned
      `uses:` but cannot see the curl-installed tools inside the setup-*
      composite actions (shellcheck, shfmt, checkbashisms, actionlint, zizmor,
      nfpm) - `.github/dependabot.yml` says so itself. A small scheduled
      workflow that asks each upstream's releases API for the latest version
      and opens a PR editing the action defaults closes that gap. First step:
      a script that just _prints_ outdated defaults; wire it to cron once its
      output is trustworthy.
- [ ] **OpenSSF Scorecard** — a public supply-chain score that directly
      credits work already done here (SHA pins, minimal token permissions,
      dependabot, zizmor, branch protection once applied). One workflow from
      ossf/scorecard-action plus a README badge. First step: run it once via
      workflow_dispatch and read the report before publishing any badge.

## Release & packaging

- [ ] **Release rehearsal** — release.yml only ever runs on a pushed tag, so
      it rots silently between releases (an actions bump, a bump.sh change, a
      runner image update). A workflow_dispatch mode that runs the whole build
      job against a fake version - `bump.sh --tarball` over a HEAD archive
      instead of the tag tarball - and stops before publish would catch that
      on demand. First step: the dispatch input and the tarball switch.
- [ ] **hi(1) man page** — every channel ships bare of docs, and `man hi` is
      the expectation a package manager sets. Hand-written troff (a
      markdown-to-man generator would add a build dep to a repo that has
      none), shipped through `install_tree` so deb/rpm/apk, AUR and brew all
      get it from the same file. First step: write `hi.1`, add it to
      `_HI_PACKAGE_CONTENTS`, nfpm.yaml and the formula.
- [ ] **Windows via WSL note (+ Scoop later)** — `packaging/windows.md`'s
      verdict: the .deb already installs into WSL unchanged, the cost is one
      README paragraph, and every native channel waits on a green Windows CI
      job. First step: the README paragraph; revisit Scoop after the Windows
      e2e item above lands.

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
- [ ] **hi doctor** — the pieces exist (hi_check_configs, hi_color_preview,
      the header's timeout-bounded backend probes) but no one command answers
      "why is hi slow or failing against this target". A `hi --doctor
    [target]` reporting backend reachability with timings, config parse
      status, overlay files found, and the ssh multiplex probe result. First
      step: inventory what each existing check already prints and what is
      missing from the picture.
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

- [ ] **CONTRIBUTING.md** — the dev loop is real but tribal: export
      `_HI_HOME`, the runner's groups and `_HI_VERBOSE`, the lint gate's
      halves (shellcheck, native zsh/fish, the bash-3.2 grep, shfmt,
      checkbashisms), and the PR-title discipline the release notes depend
      on. One page saves every future contributor the archaeology. First
      step: write down exactly the commands this repo's own CI runs.
- [ ] **Demo recording** — the README explains hi but nothing _shows_ the
      thirty seconds that sell it: connect, header, colors, prompt,
      disconnect cleanup. charmbracelet/vhs renders a GIF from a checked-in
      `.tape` script, so the demo regenerates when the header changes instead
      of rotting like a screen recording would. First step: a tape against a
      local docker target, rendered by hand before any CI wiring.
