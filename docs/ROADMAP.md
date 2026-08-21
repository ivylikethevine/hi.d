# Tooling & practices roadmap

What is left to do on say-hi, in two halves:

- **[In-repo code work](#in-repo-code-work)** — everything that can be written
  and finished in this checkout, with nothing outside it involved.
- **[Outside this repo](#outside-this-repo)** — everything gated on a machine,
  an account, a key or a click that no file here can perform. Each names where
  you go, what you do, and what ticks it.

Nothing is wired up until its checkbox is ticked. Entries that are finished,
and questions that have been decided against, are **deleted** rather than kept
here: git history is the ledger, and this file is only what is left to do.

## Contents

- [In-repo code work](#in-repo-code-work)
  - [The session itself](#the-session-itself)
  - [Release & packaging](#release--packaging)
  - [Tooling](#tooling)
  - [Testing & CI](#testing--ci)
  - [Demos](#demos)
- [Outside this repo](#outside-this-repo)
  - [Repo settings and first runs](#repo-settings-and-first-runs)
  - [Release channels](#release-channels)
  - [Docs & submissions](#docs--submissions)

## In-repo code work

### The session itself

- [ ] **Persistent sessions on a disposable target** — `--tmux` already gives
      you detach-and-reattach, but only where say-hi is permanently installed:
      on a disposable target `_hi_tmux_wanted` (`load.sh`) refuses outright,
      because the tree is deleted when the session ends and a detached tmux
      would outlive it. This entry is that restriction removed — keep the tree
      across a dropped connection, reconnect into the same session later, and
      delete only on a definitive exit or after a configurable timeout.

  - **What has to stop happening, carefully.** Cleanup has two independent
    paths — the bootstrap's `trap 'rm -rf $_HI_CLEANUP' exit` and `load.sh`'s
    own on-exit hook — and `tests/targets/ssh_disconnect_test.sh` exists
    specifically to prove they fire on an _abrupt_ disconnect rather than only
    a clean exit. That is the current contract and it is deliberate, so this
    makes it conditional rather than weaker: the suite gains a second case
    (dropped **with** persistence keeps the tree) beside the one it has
    (dropped **without** still reaps it).
  - **The tree has to be findable again.** It is
    `mktemp -d -t $(_hi_whoami).hi.XXXXXX` (`hi.sh`), a fresh random name every
    session, which is exactly what nothing can reconnect to. A resumable
    session needs a deterministic path, or a pointer the next `hi` reads on the
    way in — still per-user and still mode 0700, or SECURITY.md's footprint
    section stops being true.
  - **Something has to reap it, and there is no daemon.** Two shapes, and they
    trade the same way: a watchdog detached at disconnect
    (`sh -c 'sleep N; rm -rf ...'`) keeps the promise even if you never come
    back, at the cost of leaving a process on the target; reap-on-next-connect
    costs nothing and runs nothing, but leaves the tree indefinitely if you
    don't return. Only the first keeps "a machine you visited looks untouched"
    literally true. Either way SECURITY.md's _Footprint and cleanup_ section
    needs rewriting, and the timeout wants a name and a row in
    [CONFIGURATION.md](CONFIGURATION.md).
  - **It composes with `--tmux` rather than replacing it.** tmux keeps the
    _shell_ alive; this keeps the _tree_ alive underneath it. Landing it is
    also what lets `_hi_tmux_wanted` drop its permanent-install refusal, which
    is the visible half of the feature.
  - **Ticks when:** a dropped session on a disposable target can be
    reconnected to, an explicit exit still cleans up immediately, the timeout
    is a documented setting, and the disconnect suite covers both halves.

### Release & packaging

- [ ] **Say what v1.0.0 means** — README says EXPERIMENTAL UNTIL v1.0.0 and two
      entries here are blocked on it, with nothing anywhere stating what v1 is.
      That makes "blocked on v1" a mood rather than a date: no entry can be
      scheduled against it, and nobody can tell whether shipping it is a week
      away or a quarter. The fix is a list, not a release — write down what has
      to be true, and the blocked entries become orderable behind it.

  - **The obvious candidates**, each already tracked somewhere in this file: the
    CLI surface frozen (the tldr entry is blocked on exactly that),
    `macos-e2e.yml` and `windows-e2e.yml` green at least once rather than merely
    written, and every channel that _can_ be published published once by hand
    before the automation is trusted with it. Scope that last one to the
    publishable ones: the AUR is closed to new accounts, and v1 should not wait
    on somebody else's spam problem.
  - **It is a gate, not a wish list.** Anything that would be nice by v1 but
    does not block calling the thing stable belongs in its own entry, unticked,
    rather than padding this one — the point is a list short enough to finish.
  - **Ticks when:** the criteria are written down, and every one of them names
    the entry or file that satisfies it.

- [ ] **Re-render the seven demo GIFs** — the last of the `hi.d` → `say-hi`
      rename, and the one step no file here can perform. Everything else landed;
      the GIFs in `docs/demos/` were rendered before it did, so they still show
      `~/hi.d` on screen while every word around them says `say-hi`.

  - `docs/tapes/generate.sh` already refuses to run unless the checkout is named
    `say-hi`, so the guard is in place. It needs docker and a clean tree.
  - **A second change rides along.** The tapes now set a theme per client shell
    (`common.tape` has the table: Catppuccin Mocha for bash, Dracula for zsh,
    nord for fish), which nothing has rendered yet - so the committed GIFs are
    stale twice over, and one re-render settles both. Look at the colored
    output with fresh eyes when you do: hi's own palette is drawn over these
    backgrounds, and the check's tiers now use cyan and magenta as well.
  - Its own commit, since it is seven binary files.
  - **Ticks when:** the GIFs show the current name, on the current themes.

- [ ] **Source tarball under the provenance chain** — _Blocked on **Say what
      v1.0.0 means**, above._ Both manifests checksum GitHub's auto-generated
      `/archive/` tarball, the one released artifact with no attestation and no
      signature over it. The release already builds the identical shape
      (`git archive` in the rehearsal): attach it as an asset, list it in
      `SHA256SUMS`, point both `url=`s at it. Touches `bump.sh`, both manifests
      and their tests.

- [ ] **Investigate publishing to nix** — the one channel with a real audience
      this project has not looked at, and the question is which of two routes
      rather than whether it can be built: the build shape is already solved.

  - **The derivation is the Homebrew formula.** `packaging/homebrew/say-hi.rb`
    installs the tree into a prefix subdirectory literally named `say-hi`, runs
    `packaging/stamp.sh` for the version, and writes a `bin/hi` wrapper whose
    only job is `export _HI_HOME=<prefix>`. A nix derivation is that same
    shape - `$out/share/say-hi` plus a wrapped `$out/bin/hi` - and for the same
    reason it cannot call `scripts/install.sh --prefix`: `install_tree`
    hardcodes `/usr/bin` and `/etc/profile.d`, neither of which exists in a
    store path.
  - **Which is the cost to weigh.** That makes nix a _third_ copy of
    `_HI_PACKAGE_CONTENTS`, where `tests/packaging/packaging_test.sh` currently
    guards exactly one (the formula). The drift guard has to grow a case before
    the channel ships, not after.
  - **Flake or nixpkgs**, and they are not the same commitment. A `flake.nix`
    in this repo is publishable today with no external review - `nix run
    github:ivylikethevine/say-hi` works the moment it lands, and a flake on the
    repo itself needs no source hash, so `bump.sh` learns nothing new. A
    nixpkgs submission is discoverable from `environment.systemPackages`, which
    is where nix users actually look, but it is upstream review plus a standing
    maintainer entry, and `bump.sh` grows a fourth manifest to checksum.
  - **The `/etc/profile.d` half has no plain-package equivalent.** Packaged
    installs rely on that snippet so a _new_ process - a login shell, tmux's
    `update-environment`, another machine's `hi` probing this one - can read
    `$_HI_HOME` with no tree to derive it from. On NixOS that wants a module
    (`environment.etc`, or a `programs.say-hi` option); under home-manager the
    rc line `install.sh` writes already covers it. Decide whether a module
    ships at all, or whether the answer is "run `install.sh --no-link`", which
    is what the formula's `caveats` already says.
  - **Two things come free** and are worth noting in the answer: nix builds are
    hermetic, so the reproducibility `mkpkg.sh` works for is a property rather
    than a CI check, and a `checkPhase` running `--group fast` would make the
    build itself a test.
  - **Ticks when:** the answer is written down either way. If it is yes, name
    the route, and `packaging_test.sh` covers the new copy of the contents list
    before anything is published.

### Tooling

- [ ] **Decide whether Renovate replaces dependabot plus `tool-versions.yml`** —
      a consolidation to weigh, not an obvious win. Three classes of pin live
      here, and each is watched differently: dependabot handles the `uses:`
      SHAs and the `tests/dockerfiles` digests;
      `.github/actions/setup-tool/tools.txt` (ten curl-installed tools) has no
      ecosystem, which is exactly why
      `tool-versions.yml` exists as a bespoke weekly drift script; and the same
      images named as plain tags in `tests/lib/backend.sh`,
      `docs/tapes/fixtures.sh` and `ci.yml` have no watcher at all, only
      `lint_image_tags` failing the build when one disagrees with the
      digest-pinned version.

  - **What Renovate would buy:** `customManagers` match arbitrary files by
    regex, so `tools.txt`'s version column and the tag strings in shell both
    become ordinary managed dependencies - the tag strings would be _bumped_
    rather than merely guarded. That is one tool watching all three classes,
    and `.github/scripts/check_tool_versions.sh` plus its workflow delete.
  - **What it costs:** a second bot app on the repo, a `renovate.json` that is
    its own dialect to learn, and the loss of something the current setup has —
    `tool-versions.yml` fails loudly with `::warning` annotations in a run,
    where Renovate opens PRs. For ten pins that is arguably a downgrade in
    signal.
  - **Ticks when:** the answer is written down either way. If it stays
    dependabot, say so here and in `.github/dependabot.yml`'s header so the
    question stops being reopened.

- [ ] **Say what a refused push means in `SECURITY.md`** — _secret scanning and
      push protection are both on._ Push protection is the half that acts: it
      refuses the push rather than reporting the leak afterwards, so a
      contributor who trips it gets GitHub's own error and nothing from this
      project saying what to do next. Four credentials make that reachable — the
      two signing keys, plus `AUR_SSH_KEY` and `HOMEBREW_TAP_TOKEN` — and every
      one is generated on a laptop, pasted into a settings page and deleted
      locally, a sequence whose failure mode is a paste into the wrong buffer
      and a commit.

  - **What the note has to say:** that the refusal is the guard working, that
    the fix is editing the file rather than forcing the push, and where to go
    if the blocked string is a false positive. `docs/SECURITY.md` is the file —
    there is no `CONTRIBUTING.md` in this tree.
  - **Still not gitleaks or trufflehog.** GitHub's own scanner runs on the push
    path where a third-party action cannot; revisit only if a key format it
    does not recognise shows up.
  - **Ticks when:** `docs/SECURITY.md` carries the note.

### Testing & CI

- [ ] **See the two advisory scanners green** — both are written, wired and
      advisory, and neither has been observed green in a real run. That
      observation is all either one has left.

  - **trivy** over the digest-pinned base images, weekly and on dispatch
    (`.github/workflows/image-scan.yml`). `--ignore-unfixed` is the whole
    design rather than a detail: without it `debian:bookworm-slim` alone
    reports 22 HIGH/CRITICAL that Debian will never fix, and a gate that is red
    forever teaches everyone to skip it. With it, the job going red means
    exactly one thing — bump the pin. The scan list is `sed`'d out of the
    `FROM …@sha256:` lines rather than repeated, so a base image added or
    repinned is covered without editing the workflow.
  - **hadolint** over the eighteen fixture Dockerfiles, on every PR
    (`ci.yml`'s `hadolint` job). `.hadolint.yaml` carries a reason per silenced
    rule and says which findings are deliberately left visible (`DL3009`,
    `DL3015`).
  - **Ticks when:** each has been seen green in CI. Measured locally at the
    current pins, all three images report zero fixable HIGH/CRITICAL.

- [ ] **The Windows client-side job** — `windows-e2e.yml` is the _target_-side
      job: it stands up sshd and drives `hi localhost` into it. The client-side
      half — the fast suites run under Git Bash, proving `hi.sh` itself works
      when the machine you are sitting at is Windows — has never been written,
      and README's compatibility table rests on it.

  - **Scope it to the suites that can run there.** The fast group is
    dependency-free by design, which is what makes it the candidate; anything
    needing a container backend is out of scope on a Windows runner.
  - **Ticks when:** a workflow runs the fast group under Git Bash and has been
    green once, and README's Windows row says which half is proven.

### Demos

- [ ] **A completion demo** — `hi <TAB>` is the feature nothing shows.
      `../common/targets.sh` answers with ssh hosts _and_ every running
      container across docker, podman, nomad and kube, tagged by backend, and
      fish renders that list with its description column — the one shell where
      a still frame carries the whole idea. The fixture is the gap: every
      backend has to be up at once, where `tapes/fixtures.sh` brings them up one
      at a time.

  - **Cheapest path to "one of everything":** compose the existing `up_*`
    fixtures rather than writing a new one, and let the tape stand down the way
    the others do when a backend is missing — a half-populated completion list
    is a worse artifact than a skipped render.
  - **Flag completion has already shipped**, so the tape can show both halves:
    `hi --<TAB>` answers out of the same `targets.sh` roster without probing a
    backend. Two panes in one render, or the target half alone if that reads
    cleaner.
  - **Ticks when:** `demos/complete.gif` renders from a tape listed in
    `_HI_GEN_TAPES` (`tapes/generate.sh`), with ssh hosts and all four container
    backends in the same completion pane, and the README shows it.

- [ ] **Render the demos in CI** —
      [vhs-action](https://github.com/charmbracelet/vhs-action) installs vhs,
      ttyd and ffmpeg on a runner, which is the whole toolchain
      `tapes/generate.sh` shells out to. Today a tape that stopped rendering is
      found by hand, months later, by whoever next runs the script; the GIFs are
      committed artifacts and nothing re-renders them on a pull request.

  - **Start where nothing is needed:** `tapes/color_preview.tape` wants no
    backend at all and renders in seconds, so it can gate every PR touching
    `docs/tapes/**` on a hosted runner. The docker-backed tapes belong on the
    self-hosted box the e2e jobs already use.
  - **Render, do not commit.** A GIF is reviewed by eye before it lands
    (`tapes/generate.sh`'s header says so); CI's job is to prove the tape still
    runs and to upload the result as an artifact, not to push a binary nobody
    looked at.
  - **Ticks when:** a workflow renders at least one tape on every PR that
    touches `docs/tapes/**`, fails when vhs does, and attaches what it made.

## Outside this repo

### Repo settings and first runs

Each of these waits on something outside the checkout — a toggle in the repo's
settings, or a decision — which is why they sit here rather than in the in-repo
half: no file here can close one. The first one gates both release channels
below it.

- [ ] **Get a release out under branch protection** — _the rule is on:_ `main`
      requires a pull request and refuses a direct push, which closes
      Scorecard's highest-severity finding. What has not happened is a release
      under it, and until one does **both release-channel entries below are
      blocked behind this one**: `tap` and `aur` are `needs: publish`, and
      `publish` is the job that cannot currently finish.

  - **`publish` still pushes straight to `main`, and that push is now
    refused.** `release.yml`'s second checkout is the one that keeps its
    credentials (`ref: main`), and the `Commit the manifests to main` step ends
    in `git push origin main`, under `set -euo pipefail`, to land the
    regenerated `PKGBUILD`, `.SRCINFO` and `say-hi.rb`. Under a PR-required
    rule that fails, so the next tag dies at the last step of the release with
    the packages already published and neither channel job reached.
  - **Two ways to close it**, and they are a real choice rather than a
    formality: give the GitHub Actions app a bypass actor on the ruleset and
    leave the job alone, or convert `publish` to open a pull request the way
    the `aur`/`tap` half already does — the `tap` job is the in-repo precedent
    for exactly that shape. The bypass keeps releases one-step; the PR keeps
    the rule honest with no exceptions.
  - **The required checks are still unset.** Only the pull-request requirement
    is configured. When they go on, per the note on the markdownlint job, do
    not make the advisory ones required — `markdownlint`, `hadolint`, lychee
    and trivy are all designed to be ignorable.
  - **Ticks when:** a release has gone out under the rule with the manifest
    step green.

- [ ] **A job-started hook on the self-hosted runner** — thirteen jobs across
      eight workflows open with the same `Reclaim the workspace` step: a
      `sudo chown -R` of `$GITHUB_WORKSPACE`, guarded on
      `runner.environment != 'github-hosted'`, because that box's `_work`
      persists between jobs and one root-owned file from a container test makes
      the next checkout's cleanup throw (docs/PACKAGING.md has the full
      account). It cannot be factored into a composite action, since it has to
      run _before_ `actions/checkout` and `uses: ./.github/actions/...` needs
      the checkout that has not happened yet.

  - **Where it actually belongs:** `ACTIONS_RUNNER_HOOK_JOB_STARTED` on the
    runner itself — a script the runner executes before every job, which is
    exactly this step's scope. Setting it is a file and an env var on that
    machine, which is why this is here and not in the in-repo half.
  - **Ticks when:** the hook is in place and the thirteen copies are deleted in
    one commit. Do both at once: the copies are harmless, but leaving them
    after the hook exists means two mechanisms for one problem.

- [ ] **Decide whether to keep the Scorecard badge** — `scorecard.yml` runs
      weekly with `publish_results: true` and `README.md` carries the badge, so
      the score is public either way and the 404 that once blocked it is gone.
      The open question is whether showing it helps. Three checks a solo
      maintainer cannot move — Code-Review, CI-Tests and CII-Best-Practices —
      dominate the number, so it reads as a verdict on the project's headcount
      rather than on its engineering, sitting next to badges that measure
      something real.

  - **The rest of the report is settled and needs nothing.** SAST counts
    `codeql.yml`'s `actions` pack over the workflows (worth having on its own
    merits, and a poor reason to believe the resulting number, since the
    product is still bash and still unread by it); Fuzzing has no obvious
    target in a shell tree; everything else already passes.
  - **Ticks when:** the badge either stays, with a sentence here saying why the
    number is worth showing, or comes back out of the README.

### Release channels

Both jobs are written and behind the release gate, and both wait on the
branch-protection entry above before they can run at all. What is left in each
beyond that is human — an account, a key, and (once) a real Mac. The full
walkthrough (commands, what a clean run prints, what's already been verified)
is [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_ section; these two
entries are just the remaining human steps and their tick conditions.

- [ ] **AUR** — _externally blocked:_ registration is closed to new accounts
      because of spam, so there is no account to push from and nothing in this
      checkout changes that. `release.yml`'s `aur` job stays written and
      unexercised until it reopens, and this entry is tracked rather than
      actionable — it is deliberately not a v1 criterion.

  - **When it reopens:** register; `ssh-keygen -t ed25519`, add the public half
    there, add the private half as the `AUR_SSH_KEY` repo secret and delete the
    local copy. For each package's first push, re-run the namcap gate against
    the published source and push only `PKGBUILD` + `.SRCINFO` — that first
    push is manual, `release.yml`'s `aur` job handles the versioned package
    after.
  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.

- [ ] **Homebrew tap** — create the `homebrew-tap` repo (a plain GitHub repo
      with a `Formula/` directory), add a fine-grained PAT scoped to it
      (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`, then re-run
      the `brew install`/`test`/`audit` gate on an actual Mac (the keg lives
      under `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
    `tap` job opened a PR for.

### Docs & submissions

- [ ] **tldr page** — eight example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages once the CLI surface is frozen —
    which is one of the criteria **Say what v1.0.0 means** exists to write down.
    Examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.
