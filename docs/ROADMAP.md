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
  - [Testing & CI](#testing--ci)
  - [Demos](#demos)
  - [Project docs](#project-docs)
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

Each entry opens with its **scope** in italics, and entries are ordered by it
within each section, smallest first. The scope is what the work _is_, not how
long it takes: "one CI run" and "a backend across seven files" are the useful
distinction, and a guessed number of days is not.

Read across the sections, the shape today is: every section is down to a single
entry. [The session itself](#the-session-itself) holds the only one with code
left to write - and it is the largest thing on this page; [Testing &
CI](#testing--ci), [Demos](#demos) and [Project docs](#project-docs) are each an
observation waiting on a run or a release that no file here can trigger.

### The session itself

- [ ] **Persistent sessions on a disposable target** — _scope: the largest entry
      here. It changes cleanup semantics on both paths, needs a findable tree
      path and something to reap it, and rewrites SECURITY.md's footprint
      promise._ A dropped connection currently loses the session outright: the
      tree is deleted when the session ends, so there is nothing to reconnect
      to. This entry is that changed — keep the tree across a dropped
      connection, reconnect into the same session later, and delete only on a
      definitive exit or after a configurable timeout.

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
  - **Keeping the tree alive is only half of it.** This keeps the _tree_ alive;
    something still has to keep the _shell_ alive on the target, and hi no
    longer ships a multiplexer integration to lean on (`--tmux` was removed).
    Whether that is a multiplexer hi drives, or a reattachable shell of its
    own, is an open question this entry has to answer rather than inherit.
  - **Ticks when:** a dropped session on a disposable target can be
    reconnected to, an explicit exit still cleans up immediately, the timeout
    is a documented setting, and the disconnect suite covers both halves.

### Testing & CI

- [ ] **See the Windows client-side job green** — _scope: one CI run, then two
      lines: `ci.yml` picks the job up on push and README's Windows client row
      flips._ `.github/workflows/windows-client.yml` has shipped and is what
      this entry asked for: the fast group under the runner's own Git Bash,
      proving `hi.sh` works when the machine you are _sitting at_ is Windows,
      where `windows-e2e.yml` covers the target side. What is left is a run,
      which no file here can perform.

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

- [ ] **Shed the seven committed demo GIFs** — _scope: one commit, gated on
      seeing a render land._ The autogeneration itself has shipped:
      `demos.yml`'s `publish` job renders every tape but `demo` on the
      self-hosted box (a tape change, weekly, or dispatch) and `pages.yml` lays
      the result over the committed copies at the paths every link already
      resolves to. What is left is the size half, and it deliberately waits.

  - **Why it waits.** Until a render has actually run, those seven committed
    GIFs are what the site and README both serve. Deleting them first would
    trade a working front page for an unverified pipeline, and the pipeline
    cannot be exercised anywhere but that runner.
  - **What the commit is.** Delete `docs/demos/*.gif` except `demo.gif`
    (~1.2 MB), and repoint README's six and `docs/CONFIGURATION.md`'s
    `color_preview` at the published URLs — relative links resolve on the site
    but would 404 on github.com once the files are gone, so that half is not
    optional. `_config.yml`'s note about keeping `docs/demos` needs the same
    edit.
  - **Renders are not reproducible**, which is what makes the saving real
    rather than cosmetic: vhs records live timing through a pty, so every run
    produces different bytes. Committing them would have added ~1.2 MB of
    permanent history each time whether a demo had moved or not.
  - **Ticks when:** a `publish` run has been green, the seven are out of the
    tree, and the docs point at the site.

### Project docs

Work addressed to people rather than to the product. It moves no line of `hi`,
and it is what somebody meets first — which is why what is left here is the one
half that cannot be written in advance: what a release says it changed.

- [ ] **Say what changed in a release** — _scope: shipped; waits on a real
      release to prove it._ say-hi ships to deb, rpm, apk and Homebrew, and
      nothing told a packaged user what moved between two versions. `git log` is
      not something a `brew upgrade` reaches, which is exactly why deleting
      finished entries from this file — right for a to-do list — left that gap:
      the ledger has to be published, not merely kept.

  - **What shipped.** `release.yml`'s publish job now composes the release body
    out of both halves. GitHub's `releases/generate-notes` endpoint supplies the
    top — the PR titles merged since the last tag, derived rather than
    hand-kept, so it cannot go stale — and the _verification checklist_ this
    entry once wrongly claimed was already there is appended below it, reading
    its minisign public key straight out of
    [PACKAGING.md](PACKAGING.md#verifying-a-release-download) so the key exists
    once in the tree.
  - **Why it is composed rather than two flags.** `gh` appends generated notes
    *after* `--notes`, which would bury what changed under how to check it.
  - **A `CHANGELOG.md` is still not open**, and should only be opened if the
    generated notes turn out not to be enough — the same test as before.
  - **Ticks when:** a release has gone out whose body names what changed as well
    as how to check it, with nobody hand-writing the list. Blocked behind
    [Get a release out under branch
    protection](#repo-settings-and-first-runs), like everything else that needs
    a real tag.

## Outside this repo

These carry the same _scope_ tags as the in-repo half, and are ordered by them
within each section — except in
[Repo settings and first runs](#repo-settings-and-first-runs), where the first
entry blocks two others and dependency order wins. The scope here is only the
part **you** do — the account, the key, the click, the decision — never the
waiting.

### Repo settings and first runs

Each of these waits on something outside the checkout — a toggle in the repo's
settings, or a decision — which is why they sit here rather than in the in-repo
half: no file here can close one. The first one gates both release channels
below it.

- [ ] **Get a release out under branch protection** — _scope: one decision with
      a code fork behind it (a ruleset bypass actor, or converting `publish` to
      open a pull request), then one real release._ _The rule is on:_ `main`
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

- [ ] **A job-started hook on the self-hosted runner** — _scope: a script and an
      env var on that machine, plus one commit here deleting thirteen copies._
      Thirteen jobs across eight workflows open with the same `Reclaim the
      workspace` step: a `sudo chown -R` of `$GITHUB_WORKSPACE`, guarded on
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

- [ ] **Decide whether to keep the Scorecard badge** — _scope: a judgement call
      and one README line either way._ `scorecard.yml` runs weekly with
      `publish_results: true` and `README.md` carries the badge, so the score is
      public either way and the 404 that once blocked it is gone. The open
      question is whether showing it helps. Two checks a solo maintainer cannot
      move — Code-Review and CI-Tests — dominate the number, so it reads partly
      as a verdict on the project's headcount rather than on its engineering,
      sitting next to badges that measure something real.

  - **CII-Best-Practices used to be on that list and is not.** It reads for a
    contribution guide among other things, so it is movable by writing one —
    which is the [`CONTRIBUTING.md` entry](#project-docs) under Project docs.
    That makes the judgement here worth deferring until after it lands: a
    number with one unmovable check fewer is a different number to decide
    about.
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

- [ ] **Homebrew tap** — _scope: a repo, a scoped PAT, and one gate re-run on a
      real Mac._ Create the `homebrew-tap` repo (a plain GitHub repo with a
      `Formula/` directory), add a fine-grained PAT scoped to it (contents +
      pull-requests write) as `HOMEBREW_TAP_TOKEN`, then re-run the `brew
      install`/`test`/`audit` gate on an actual Mac (the keg lives under
      `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
    `tap` job opened a PR for.

- [ ] **AUR** — _scope: nothing actionable until registration reopens; then an
      account, a key, and one manual first push._ _Externally blocked:_
      registration is closed to new accounts because of spam, so there is no
      account to push from and nothing in this checkout changes that.
      `release.yml`'s `aur` job stays written and unexercised until it reopens,
      and this entry is tracked rather than actionable — it is deliberately not
      a v1 criterion.

  - **When it reopens:** register; `ssh-keygen -t ed25519`, add the public half
    there, add the private half as the `AUR_SSH_KEY` repo secret and delete the
    local copy. For each package's first push, re-run the namcap gate against
    the published source and push only `PKGBUILD` + `.SRCINFO` — that first
    push is manual, `release.yml`'s `aur` job handles the versioned package
    after.
  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.

### Docs & submissions

- [ ] **tldr page** — _scope: one upstream pull request, gated on the CLI
      surface being frozen._ Eight example lines reach everyone who types `tldr
      hi` before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages once the CLI surface is frozen —
    the first line of [What v1.0.0 means](#what-v100-means). Examples that
    churn are worse than no page.
  - **Ticks when:** it is merged upstream.
