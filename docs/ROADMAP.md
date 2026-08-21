# Tooling & practices roadmap

What is left to do on say-hi. [What v1.0.0 means](#what-v100-means) is the gate
the tag waits on, and the rest is in two halves:

- **[In-repo code work](#in-repo-code-work)** — everything that can be written
  and finished in this checkout, with nothing outside it involved.
- **[Outside this repo](#outside-this-repo)** — everything gated on a machine,
  an account, a key or a click that no file here can perform. Each names where
  you go, what you do, and what ticks it.

Nothing is wired up until its checkbox is ticked. Entries that are finished,
and questions that have been decided against, are **deleted** rather than kept
here: git history is the ledger, and this file is only what is left to do.

## Contents

- [What v1.0.0 means](#what-v100-means)
- [In-repo code work](#in-repo-code-work)
  - [The session itself](#the-session-itself)
  - [Release & packaging](#release--packaging)
  - [Testing & CI](#testing--ci)
  - [Demos](#demos)
- [Outside this repo](#outside-this-repo)
  - [Repo settings and first runs](#repo-settings-and-first-runs)
  - [Release channels](#release-channels)
  - [Docs & submissions](#docs--submissions)

## What v1.0.0 means

README carries EXPERIMENTAL UNTIL v1.0.0 and entries below are ordered against
it, so this is the list that makes that orderable: what has to be true before
the tag, each line naming the entry or file that satisfies it. It is a **gate,
not a wish list** — anything that would merely be nice by v1 stays an ordinary
unticked entry below rather than padding this. The point is a list short enough
to finish.

- [ ] **The CLI surface is frozen.** `_hi_parse` in `hi.sh`, `docs/hi.1` and
      `docs/tldr.md` describe the same flags, and no rename is expected. This
      is what the [tldr page](#docs--submissions) entry is waiting on —
      examples that churn are worse than no page.
- [ ] **`macos-e2e.yml` has been green at least once.** It is written and
      called on every push; README's compatibility table still says "written
      but has never run", and that sentence is the criterion.
- [ ] **`windows-e2e.yml` has been green at least once** — the target-side
      half, same table, same sentence. Its client-side counterpart,
      `windows-client.yml`, is deliberately **not** on this list: it is an
      ordinary entry under [Testing & CI](#testing--ci), because a Windows
      _client_ is not what "stable" promises.
- [ ] **A release has gone out under branch protection**, with the manifest
      step green — the [Get a release out under branch
      protection](#repo-settings-and-first-runs) entry. The criterion below it
      cannot start until this one lands: `tap` and `aur` are `needs: publish`,
      and `publish` is the job the rule currently refuses.
- [ ] **Every publishable channel has been published once by hand**, before the
      automation is trusted with it: deb/rpm/apk and the Homebrew tap, per
      [PACKAGING.md](PACKAGING.md)'s _Publishing each channel_. The tap half is
      the [Homebrew tap](#release-channels) entry.

**The AUR is excluded on purpose.** Registration is closed to new accounts
because of spam, so there is nothing to do and no date to do it by; v1 should
not wait on somebody else's spam problem. Its entry stays tracked under
[Release channels](#release-channels) and ticks whenever it reopens.

## In-repo code work

### The session itself

- [ ] **Investigate LXC/LXD (or Incus) as a target** — the one container
      runtime with a real audience that hi does not answer to. It is also the
      _easiest_ target hi could have: an LXC container is normally a full
      system container running a real distro with systemd and bash already in
      it, so it lands in the top tier of the fallback ladder rather than the
      aliases-only one. The question is what it costs on the hot paths, and
      which project it is.

  - **Which binary, and is it one backend or two.** LXD ships `lxc exec <name>
    -- <cmd>`; Incus, the LinuxContainers fork, ships `incus exec` with the
    same shape. They are the same integration twice over, and picking "both"
    means two rows everywhere below, not one with a fallback — decide before
    writing any of it.
  - **What it touches, in roster order.** A row in `_HI_BACKENDS` (`hi.sh`),
    which is what feeds both the dispatch and `hi --doctor`; a
    `_hi_is_lxc_container` predicate beside `_hi_is_docker_container`; an arm
    in `_hi_container_cmds` setting `probe`/`cp`/`attach`; a lister and a
    `run_lister` case in `common/targets.sh` (plus its usage line), in that
    file's standalone-POSIX dialect; and an e2e suite under `tests/targets/`
    registered in `test_runner.sh`'s `_HI_TESTS` under the `backends` group.
  - **The cost is paid by machines that do not have it.** `_hi_resolve_backend`
    runs every predicate in parallel on every `hi <target>`, and `targets.sh`
    probes every backend on every TAB (GLOSSARY: HI.26). A fifth backend is a
    fifth process on both hot paths; check the `command -v` guard actually
    short-circuits before adding one, and re-run `--group bench`.
  - **The fixture is the hard part.** Every existing backend suite stands up
    its target from a container image; LXD/Incus wants a real daemon and a
    storage pool on the runner, which is a self-hosted-box change, not a
    Dockerfile. A suite that can only ever skip is worth less than no suite.
  - **Ticks when:** the answer is written down either way. If it is yes, the
    binary is named, the backend is in `_HI_BACKENDS`, and its suite is in
    `_HI_TESTS` — even if it skips everywhere but the self-hosted box.

- [ ] **Write down every target hi could connect to, and the verdict on each**
      — the wider question the LXC entry above is one row of. hi answers to ssh
      plus four container backends, and the reasoning for what is in and what is
      out lives nowhere: each new suggestion gets re-litigated from scratch, and
      nobody outside can tell whether their runtime was rejected or never
      considered.

  - **The shape already exists in this repo.** README's _Compatibility_ section
    ends with a "shells hi does not style, and why that is settled" table —
    name, status, and a why long enough to close the question. This is that
    table for targets, and it belongs next to it or in a `docs/TARGETS.md` the
    section links to.
  - **What goes on it**, at least: `lxc`/`incus`; `systemd-nspawn` and
    `machinectl`; WSL distributions (`wsl -d`); distrobox and toolbx (which
    wrap podman — do they need a row of their own, or does the podman one
    already cover them?); `nerdctl`/containerd and `crictl`/CRI-O; Apptainer
    and Singularity; Proxmox `pct enter`; FreeBSD jails (`jexec`) and illumos
    zones (`zlogin`); `chroot`; remote docker contexts; and the
    ssh-that-is-not-ssh transports — AWS SSM `start-session`, `gcloud compute
    ssh`, `fly ssh console`, Azure Bastion.
  - **Most rows should be "no", with a reason.** The cheap test is the one the
    hot-path note above states: every backend on the roster costs a probe on
    every TAB and every connect, on machines that have none of it. A row earns
    a "yes" by being something people actually sit in, not by being reachable.
  - **Some rows are already answered elsewhere** and only need collecting: the
    ssh-wrapping transports mostly work today, because anything that ends in an
    ssh connection is a `Host` entry away from being an ordinary ssh target.
  - **Ticks when:** the table exists with a verdict and a reason per row, and
    every "yes" that is not built yet has an entry here.

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

- [ ] **Source tarball under the provenance chain** — _Deliberately not a v1
      criterion (see [What v1.0.0 means](#what-v100-means)), and orderable on
      its own now that the gate is written down._ Both manifests checksum GitHub's auto-generated
      `/archive/` tarball, the one released artifact with no attestation and no
      signature over it. The release already builds the identical shape
      (`git archive` in the rehearsal): attach it as an asset, list it in
      `SHA256SUMS`, point both `url=`s at it. Touches `bump.sh`, both manifests
      and their tests.

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

- [ ] **See the Windows client-side job green** — `.github/workflows/windows-client.yml`
      has shipped and is what this entry asked for: the fast group under the
      runner's own Git Bash, proving `hi.sh` works when the machine you are
      _sitting at_ is Windows, where `windows-e2e.yml` covers the target side.
      What is left is a run, which no file here can perform.

  - **It runs `--group fast --skip shellcheck`.** The lint suite is the one
    suite in that group with nothing to say about Windows, and it cannot run
    there anyway: `.github/actions/setup-tool` resolves linux/darwin asset
    slugs into `/usr/local/bin`, and `run_shellcheck` exits 1 rather than
    standing down when shellcheck is missing — on purpose, since a lint gate
    that did not run must not read as a pass. `runner_test.sh` checks that
    every `--skip` name in a workflow is a real suite, so a rename cannot
    silently put it back.
  - **Dispatch-only until it is green**, on `windows-e2e.yml`'s precedent:
    nothing here has ever executed the harness under Git Bash, so the first
    runs are information rather than a gate on somebody's pull request. The
    `workflow_call` trigger is already there for the day ci.yml picks it up
    beside `e2e-windows`.
  - **Expect skips, not a clean sweep.** There is no zsh or fish on a Windows
    runner, so several suites will stand down yellow; that is the honest shape
    and why the job passes neither `--require-run` nor `--totals-file`.
  - **Ticks when:** the job has been green once, ci.yml calls it on push, and
    README's Windows client row reads ✅ instead of 🟡.

### Demos

- [ ] **Render the demos in CI — see it go green once.**
      `.github/workflows/demos.yml` has shipped and does what this entry asked:
      on a PR touching `docs/tapes/**` it installs the toolchain with
      [vhs-action](https://github.com/charmbracelet/vhs-action) (SHA-pinned;
      dependabot already covers it), runs
      `tapes/generate.sh --require-run color_preview` on a hosted runner, and
      attaches the GIF for seven days. It renders rather than commits, per
      `tapes/generate.sh`'s own header. The command was proved locally; the
      runner path — the action's vhs/ttyd/ffmpeg install — has never executed.

  - **It calls generate.sh, not vhs.** A tape's `Require hi` is satisfied by any
    `hi` on `$PATH`, so a runner with one installed would record the wrong tree;
    the preflight's shim is what makes the render this checkout's.
  - **vhs itself is deliberately unpinned** (`version` left at the action's
    default) where everything else this repo installs is pinned to the row: a
    pinned vhs would hide the upstream break the job exists to catch. The
    supply-chain half of the pin is the action's SHA.
  - **The six docker-backed tapes are still not wired up**, and belong on the
    self-hosted box the e2e jobs already use rather than on a hosted runner.
    That is a second entry's worth of work, not a condition of this one.
  - **Ticks when:** the job has run green on a pull request and the artifact is
    there to download — which the PR carrying `complete.tape` will do on its
    own, since it touches `docs/tapes/**`.

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
    the first line of [What v1.0.0 means](#what-v100-means). Examples that
    churn are worse than no page.
  - **Ticks when:** it is merged upstream.
