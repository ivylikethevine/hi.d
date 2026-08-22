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
unticked entry below rather than padding this, and the one piece of product work
left (_[persistent sessions](#the-session-itself)_) is explicitly deferred past
the tag rather than held in front of it. The point is a list short enough to
finish.

- [ ] **The CLI surface is frozen.** `_hi_parse` in `hi.sh`, `docs/hi.1` and
      `docs/tldr.md` describe the same flags, and no rename is expected. This
      is what the [tldr page](#docs--submissions) entry is waiting on —
      examples that churn are worse than no page.
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
entry, and **none of them is work for before v1.0.0**. [The session
itself](#the-session-itself) holds the only one with code left to write, and it
is deferred past the tag on purpose; [Testing & CI](#testing--ci),
[Demos](#demos) and [Project docs](#project-docs) are each an observation
waiting on a run or a release that no file here can trigger. Everything that
gates the tag is either a criterion above or an entry under [Outside this
repo](#outside-this-repo).

### The session itself

- [ ] **Persistent sessions on a disposable target** — _**deferred until after
      v1.0.0.** Scope: the largest entry here. It changes cleanup semantics on
      both paths, needs a findable tree path and something to reap it, and
      rewrites SECURITY.md's footprint promise._ Deferred because the thing it
      changes is the promise v1 is being tagged on: SECURITY.md says a machine
      you visited looks untouched, and every other entry left is a run or a
      click rather than a rewrite of that sentence. The notes below stay
      because they are the research, not because the work is queued.

  A dropped connection currently loses the session outright: the
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

- [ ] **Decide what the Windows client job is allowed to assert** — _scope: a
      decision about the test fixtures, then whatever it implies; no product
      code is implicated._ `.github/workflows/windows-client.yml` has run.
      It is red, and what it found is worth writing down rather than
      re-deriving: **37 failures across 8 suites, none of them a portability
      bug in `hi`.** Every one traces to two facts about Git Bash.

  - **It cannot create symbolic links.** `ln -s` needs Developer Mode or
    administrator on Windows, so it fails outright. That is the whole of:
    `install`'s seven `config_hi`/`install_tree` cases and `packaging`'s
    _Symlink matches install_tree's_ (they exercise the symlink `install.sh`
    makes); `install_location`'s _runs through a symlink onto it_; and - less
    obviously - `targets`' three sweep cases, `packages_preview`'s two and most
    of `doctor`'s five, because `_hi_real_path` (`tests/lib/fixtures.sh:95`)
    builds its toolboxes out of `ln -sf` and silently prints an **empty**
    directory when they fail. A suite that then replaces `$PATH` with it has no
    `sh`, `awk` or `sed` at all, which is why those cases fail in ways that
    look unrelated to symlinks.
  - **It has no POSIX execute bit.** MSYS answers `access(X_OK)` from the
    file's magic or extension unless the mount carries `acl`, so `chmod +x` on
    a file with no `#!` does not stick. `_hi_probe_home` (`tests/hi/remote_test.sh:40`)
    makes its launcher with `: >hi.sh` - an empty file - and
    `_hi_remote_root_probe` requires `[ -x "$_h/say-hi/hi.sh" ]`, so the probe
    correctly answers "nothing installed" for all fourteen of `hi_remote`'s
    cases. The probe is right; the fixture cannot say what it means to say
    there.
  - **Two odds and ends.** `test_lib`'s _wrapper really allocates a pty_ wants
    Python's `pty`, which is Unix-only. `packaging`'s two checksum cases see
    `<hash> *name` because `sha256sum` opens binary by default on Windows -
    the assertion is brittle, not the code: `SHA256SUMS` is written by Linux
    CI and `sha256sum -c` reads both spellings either way.
  - **So the decision is about the fixtures, not about hi.** Either the cases
    that need a real symlink or a real exec bit learn to stand down yellow on
    MSYS - the doctrine the backend suites already use, and the only route to a
    green job - or this job stays dispatch-only and red-but-explained. Nothing
    is blocked on it either way: a Windows _client_ is deliberately not a
    v1.0.0 criterion, because a Windows client is not what "stable" promises.
    `windows-e2e.yml` covers the target side, and that is the half the tag
    rests on.
  - **Unchanged from before the run:** it runs `--group fast --skip
    shellcheck`, because `.github/actions/setup-tool` resolves linux/darwin
    asset slugs and `run_shellcheck` exits 1 rather than standing down when
    shellcheck is missing. There is no zsh or fish on the runner either, so 45
    cases skip yellow before any of the above.
  - **Ticks when:** the fixtures either stand down or are made to work, the job
    is green once, ci.yml calls it on push, and
    [SUPPORTED.md](SUPPORTED.md#the-targets-os)'s Windows row reads ✅ for the
    client half as well as the target half.

### Demos

- [ ] **See a full demo render land on the site** — _scope: one green
      `publish` run; the commit half has already shipped._ Both halves of the
      autogeneration are in: `demos.yml`'s `publish` job renders every tape but
      `demo` on the self-hosted box, `pages.yml` lays the result over the site,
      the six GIFs are out of the tree, and README and
      [CONFIGURATION.md](CONFIGURATION.md) already link them at their published
      URLs. `docs/demos/demo.gif` stays committed on purpose - it is the
      hand-rendered one, and `.githooks/demo_staleness.sh` is what says when it
      has gone stale.

  - **Nothing 404s yet, and the merge order decides whether anything ever
    does.** The deletion and the URL repoint live on `dev` only: `main` still
    carries the six GIFs and the relative links that resolve to them, so the
    front page is intact today. It breaks the moment `dev` merges — and since
    `publish` never runs on a pull request (below), dispatching one against
    `main` *before* the merge keeps that window at zero, where merging first
    leaves the front page broken for the length of a render. Nothing here can
    prove the pipeline either way, which is why this entry stays open after the
    commit: the pipeline is now the only source of the images the front page
    shows.
  - **The pull-request job is not the one that matters.** `demos.yml` has two:
    `render` gates a PR that touches a tape, on a hosted runner, and renders
    exactly `color_preview` - a green there says the vhs/ttyd/font toolchain
    works and nothing about the other seven. `publish` is the one that produces
    the site's GIFs, and it never runs on a pull request: push to `main`,
    the weekly cron, or a manual dispatch.
  - **The renderer's own dependencies were the last thing to bite.** A tape
    that opens `Set Shell zsh` wants that shell on the machine doing the
    recording, not on the target, so `publish` installs zsh, fish and nomad the
    way `ci.yml`'s backends job does - docker, podman, kind and kubectl are
    what the box already carries. Without them five of the seven tapes failed
    under `--require-run`.
  - **Ticks when:** a `publish` run has been green end to end and the seven
    published URLs actually serve an image — README's six, plus the
    `color_preview` one that [CONFIGURATION.md](CONFIGURATION.md) is the only
    link to. Seven tapes render; six GIFs left the tree, because `complete` was
    never committed in the first place.

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

- [ ] **Get a release out under branch protection** — _scope: one real release,
      plus one repository setting to confirm first._ _The rule is on:_ `main`
      requires a pull request and refuses a direct push, which closes
      Scorecard's highest-severity finding. What has not happened is a release
      under it, and until one does **both release-channel entries below are
      blocked behind this one**: `tap` and `aur` are `needs: publish`.

  - **The code half has shipped.** `publish` no longer pushes to `main`: its
    credential-keeping checkout writes the regenerated `PKGBUILD`, `.SRCINFO`
    and `say-hi.rb` onto a `manifests-<tag>` branch and opens a pull request,
    on the `tap` job's precedent, with `pull-requests: write` on the job to do
    it. No workflow in the tree pushes to `main` any more. The release does not
    wait on that merge either - `tap` and `aur` read the manifests out of the
    `packages` artifact, not out of `main`.
  - **Confirm one setting before the first tag.** A workflow can only open that
    pull request if _Settings → Actions → General → Allow GitHub Actions to
    create and approve pull requests_ is on. With it off, `gh pr create` fails
    with "GitHub Actions is not permitted to create or approve pull requests" -
    at the last step of the release, with the packages already published, which
    is exactly the failure the PR conversion was meant to remove.
  - **The required checks are still unset.** Only the pull-request requirement
    is configured. When they go on, per the note on the markdownlint job, do
    not make the advisory ones required — `markdownlint`, `hadolint`, lychee
    and trivy are all designed to be ignorable. `e2e (macOS)` and
    `e2e (Windows)` are now green on push and are reasonable candidates.
  - **Ticks when:** a release has gone out under the rule, with the manifest
    pull request opened rather than a push refused.

- [ ] **A job-started hook on the self-hosted runner** — _scope: a script and an
      env var on that machine, plus one commit here deleting fifteen copies._
      Fifteen jobs across ten workflows open with the same `Reclaim the
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
  - **Recount before deleting rather than trusting the number here.** It was
    thirteen across eight when this entry was written and is fifteen across ten
    now, because workflows keep arriving;
    `grep -rc 'Reclaim the workspace' .github/workflows/` is the whole check.
  - **Ticks when:** the hook is in place and every copy is deleted in one
    commit. Do both at once: the copies are harmless, but leaving them after
    the hook exists means two mechanisms for one problem.

- [ ] **Decide whether to keep the Scorecard badge** — _scope: a judgement call
      and one README line either way, with nothing to judge before
      2026-08-25._ `scorecard.yml` runs weekly with `publish_results: true` and
      `README.md` carries the badge, but **no score has been published yet**:
      `api.scorecard.dev` and `api.securityscorecards.dev` both 404 for this
      repo, and the badge renders `openssf scorecard: invalid repo path` — on
      `main` as much as here. The cause is benign. `publish_results` only takes
      effect on a *scheduled* run against the default branch, the cron is
      `41 7 * * 2`, and the schedule-only trigger landed on `main` on Wed
      2026-08-19 — so the first run is Tue 2026-08-25 and there has not been
      one. If the badge is still an error after that date, a run fired and
      failed rather than never having fired, and the Actions tab is the only
      place that tells those two apart.

  - **Until then the README shows an error rather than a number.** Leave it:
    re-adding the line afterwards is a second commit spent on a few days of
    cosmetic blemish, on a repo whose first heading already says EXPERIMENTAL.
    Pull it only if that reads worse in practice than it does written down.
  - **The question the number has to answer** is whether showing it helps. Two
    checks a solo maintainer cannot move — Code-Review and CI-Tests — dominate
    it, so it reads partly as a verdict on the project's headcount rather than
    on its engineering, sitting next to badges that measure something real.
  - **CII-Best-Practices used to be on that list and is not.** It reads for a
    contribution guide among other things, so it was movable by writing one —
    and `docs/CONTRIBUTING.md` has since shipped. That is one unmovable check
    fewer than when this entry was written, which is the other reason to judge
    the first real report rather than guess at it.
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
