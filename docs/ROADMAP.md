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

Read across the sections, the shape today is: [Demos](#demos) and all but one
entry under [Testing & CI](#testing--ci) are observations waiting on a run that
no file here can trigger; [The session itself](#the-session-itself) is the work
that moves the product, in increasing order of how much of the tree it touches;
and [Project docs](#project-docs) is work that moves no code at all, which is
why it sits last rather than first.

### The session itself

- [ ] **Work through the second wave of target candidates** — _scope: research
      and prose, about a dozen verdict rows; no code unless one comes back yes._
      [TARGETS.md](TARGETS.md) settled the runtimes that had been suggested
      before it existed, and `lxc`/`incus` is the one row it left open. This is
      the list of everything _not_ on it: candidates nobody has ruled on yet,
      with a first read on each. It is an evaluation to finish, not a plan to
      build — most of these should end up as "decided against" rows, and the
      entry ticks either way.

  The bar is the one TARGETS.md states: a row earns a yes by being something
  people **sit in**, not by being reachable, because every backend on the
  roster costs a fork on every `hi <target>` and every TAB (GLOSSARY: HI.26) on
  machines that have none of it.

  - **Not backends at all — naming layers over what already ships.** The
    cheapest wins here, if they are wins: they cost no probe, because the
    runtime underneath is already on the roster.
    - **`docker compose` service names.** People think in `web`/`db`, not in
      `myproject-web-1`. `docker compose ps -q <service>` resolves one to a
      container hi already answers to. The open question is where it belongs:
      a lister in `common/targets.sh` so TAB offers both names, or nothing at
      all if the container name is close enough.
    - **devcontainers / VS Code dev containers.** Already reachable today, on
      exactly the distrobox precedent — they are docker containers, so the
      docker row finds them by name. Worth a TARGETS.md row saying so rather
      than a backend.
  - **Genuinely new backends, roughly in order of how real the audience is.**
    - **`adb shell` (Android).** The best fit on this list: `adb shell`,
      `adb push`, `adb devices` map onto `_hi_container_cmds`' probe/cp/attach
      triple almost exactly, the CLI is one binary on every platform hi runs
      on, and a debuggable device is a full Linux userland people genuinely sit
      in. The catch is what lands there — a Toybox/Android shell, so the
      no-bash tier, and `$HOME` semantics that are not a normal Unix home.
    - **AWS ECS Exec** (`aws ecs execute-command --interactive`). Real audience
      and a real exec shape, but the name is a cluster/task/container triple
      rather than one word, and it needs the Session Manager plugin installed
      beside the CLI. Closer to nomad's `alloc/task` split than to docker's.
    - **Slurm** (`srun --pty bash`). The HPC row. Whether it is a target at all
      is the question: `srun` _allocates_ rather than attaches, so `hi` would
      be queueing a job, not connecting to a machine — and the thing people
      want a styled shell on is usually the login node, which is already an
      ordinary ssh host.
    - **`multipass`, Vagrant, Codespaces** (`multipass shell`,
      `vagrant ssh`, `gh codespace ssh`). All three end in ssh, so they are
      arguably already answered the way TARGETS.md answers AWS SSM and
      `gcloud compute ssh` — a `Host` entry away. Confirm that, and if it
      holds, they are one collected row rather than three candidates.
    - **Docker Swarm services**, **Azure Container Instances**
      (`az container exec`), **`systemd-run`/portable services**. Listed for
      completeness; none has shown an audience that sits in them.
  - **Rows that are interesting because they are "no".** A verdict with a
    reason is the deliverable, and these are the ones people will ask about:
    **Talos Linux** and other shell-less immutable distributions (there is no
    shell to style, by design); **serial consoles** (`picocom`, `virsh
    console`) and **telnet**, where there is no file transfer channel at all,
    so the payload cannot land; **WinRM / PowerShell Remoting**, which is the
    same bash-only answer README's compatibility table already gives.
  - **Ticks when:** every candidate above has a row in
    [TARGETS.md](TARGETS.md) with a verdict and a reason, and each "yes" that
    is not built has its own entry here.

- [ ] **Investigate LXC/LXD (or Incus) as a target** — _scope: a decision; then,
      if it is yes, a backend across the seven places TARGETS.md lists, plus a
      fixture the self-hosted runner does not have yet._ The one container
      runtime with a real audience that hi does not answer to, and the only open
      row on [TARGETS.md](TARGETS.md), which carries both the case for it and
      that checklist.

  - **Which binary, and is it one backend or two.** LXD ships `lxc exec <name>
    -- <cmd>`; Incus, the LinuxContainers fork, ships `incus exec` with the
    same shape. They are the same integration twice over, and picking "both"
    means two rows everywhere, not one with a fallback — decide before writing
    any of it.
  - **The cost is paid by machines that do not have it.** `_hi_resolve_backend`
    runs every predicate in parallel on every `hi <target>`, and `targets.sh`
    probes every backend on every TAB (GLOSSARY: HI.26). A fifth backend is a
    fifth process on both hot paths; check the `command -v` guard actually
    short-circuits before adding one, and re-run `--group bench`.
  - **The fixture is the hard part.** Every existing backend suite stands up
    its target from a container image; LXD/Incus wants a real daemon and a
    storage pool on the runner, which is a self-hosted-box change, not a
    Dockerfile. A suite that can only ever skip is worth less than no suite.
  - **Ticks when:** the answer is written down either way — TARGETS.md's row
    stops saying "open". If it is yes, the binary is named, the backend is in
    `_HI_BACKENDS`, and its suite is in `_HI_TESTS` — even if it skips
    everywhere but the self-hosted box.

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

- [ ] **Collapse the coverage tooling to the half that is honest** — _scope:
      mostly deletion — one script, one workflow, one badge and a paragraph out;
      one `.simplecov` filter in._ Two scripts, two workflows, two README badges
      and a section of [TESTING.md](TESTING.md) exist to publish two numbers
      that this repo separately tells you not to believe, in three places. Both
      badges are deliberately grey and read `load-time` and `heredoc-inflated`
      rather than `coverage`. That is honest, and it is also the argument for
      not carrying them.

  - **The two failure modes are not equally fixable**, which is what makes this
    a deletion rather than a repair. kcov loses its `DEBUG` trap the moment the
    harness is sourced, so its figure describes what ran while things were
    _loading_ — `common/git_prompt.sh` at 2.56% with seventeen cases passing
    against it. Nothing in this checkout can reach that; it is where kcov reads
    a bash script from.
  - **bashcov is wrong in a bounded way.** It reads bash's own `xtrace`, gets
    that same file right at 92.68%, and correctly reads 0 for an uncalled
    function. It counts every line of a **heredoc body** as covered, so the
    files that generate scripts read high — `hi.sh` at 97.38%, with `_say_hi`
    and `_say_hi_container` both reporting 100% for 182 lines nothing in
    `--group fast` calls. TESTING.md already names the believable set
    (`common/`, `shells/`, `misc/`), which is the filter this entry writes down.
  - **What the commit is.** A `.simplecov` filter scoping `coverage_v2.sh` to
    the files without heredocs, so the aggregate means something; then
    `tests/coverage.sh`, `.github/workflows/coverage.yml`, the kcov badge and
    its half of README's disclaimer paragraph come out, and TESTING.md's
    _Coverage and profiling_ loses the "read both or neither" framing it only
    needs while there are two.
  - **Neither gates anything, and neither should start.** The point is one
    number a reader can act on instead of two that each need a disclaimer — not
    a threshold. `docs/TESTING.md`'s "don't write tests to move those figures"
    survives this entry unchanged.
  - **Ticks when:** one coverage script and one workflow remain, the surviving
    badge's number is one the docs do not have to apologise for, and README
    carries a single coverage badge.

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

Work addressed to people rather than to the product: what a release says it
changed, what a contributor is told before they open a pull request, and how
much of the front page is reference material. None of it moves a line of `hi`,
and all of it is what somebody meets first.

- [ ] **Say what changed in a release** — _scope: one line in `release.yml`; a
      `CHANGELOG.md` only if the one line proves too thin._ say-hi ships to
      deb, rpm, apk and Homebrew, and nothing tells a packaged user what moved
      between two versions. `release.yml`'s `gh release create` puts a
      _verification checklist_ in the body — useful, and not an answer to that
      question — and `--generate-notes` is not passed.

  - **The rule this does not break.** This file deletes finished entries
    because git history is the ledger. That stays right for a to-do list, and
    it is exactly why the gap exists: `git log` is not something a
    `brew upgrade` reaches. The ledger has to be published, not kept.
  - **Start with `--generate-notes`**, above the existing checklist body rather
    than in place of it: it costs one line, it is derived from the commits and
    the merged pull requests, and it cannot go stale the way a hand-kept file
    does. A `CHANGELOG.md` is worth writing only once releases start carrying
    notes somebody actually composed — which is a different entry, and should
    only be opened if this one turns out not to be enough.
  - **Ticks when:** a release's body names what changed as well as how to check
    it, without anybody hand-writing the list.

- [ ] **A `CONTRIBUTING.md`, and issue/PR templates** — _scope: three short
      files, mostly links to docs that already exist._ `.github/` holds
      workflows, a composite action and dependabot config, and nothing
      addressed to a person. The conventions are real and written down — the
      `_HI_HOME` rule, where a suite lives, the bash 3.2 floor, the `GLOSSARY:`
      tag discipline — but they live in `CLAUDE.md`, which is addressed to
      agent sessions. Somebody opening their first pull request has no
      equivalent.

  - **Short, and mostly a signpost.** [TESTING.md](TESTING.md) already carries
    the runbook and [GLOSSARY.md](GLOSSARY.md) the idioms; what is missing is
    the page that says _read those two, run `--group fast`, and here is the
    bash 3.2 floor_. Anything longer will drift out of step with the files it
    is summarising.
  - **It also moves a Scorecard check.** The
    [Scorecard badge](#repo-settings-and-first-runs) entry lists three checks a
    solo maintainer cannot move; CII-Best-Practices is not one of them, because
    a contribution guide is part of what it reads for. That entry has been
    corrected to say so, and the judgement it is waiting on should be made
    after this one lands rather than before.
  - **Ticks when:** a `CONTRIBUTING.md` exists, the templates are in
    `.github/`, and neither restates what TESTING.md or GLOSSARY.md already
    say.

- [ ] **Finish the README split** — _scope: two sections moved, plus the
      anchors and the contents block that point at them._ The front page is
      down to two sections that are reference material rather than a pitch:
      **How it works**, and **Built from/with/in mind** with its four backend
      subsections. _Regenerating the demo GIFs_ and _Verifying a release
      download_ have already gone to [PACKAGING.md](PACKAGING.md); these are
      what is left of the same argument.

  - **Where each goes.** _How it works_ is the mechanism behind the config
    overlay it currently sits under, so [CONFIGURATION.md](CONFIGURATION.md).
    _Built from/with/in mind_ is a per-backend account of what hi does on the
    other end, which is [TARGETS.md](TARGETS.md)'s subject — and TARGETS.md
    already carries the verdict rows those four sections describe the
    implementation of.
  - **The links are the work**, not the prose. Both are linked from inside
    README and from the compatibility table, and relative anchors that resolve
    on the Pages site 404 on github.com — the same trap the
    [demo GIF entry](#demos) names. Every inbound link moves with the section.
  - **Not a rule about length.** The test is whether a section answers "should
    I use this" or "how does this work"; the second kind is what `docs/` is
    for. Nothing here is deleted, and nothing shipped changes — every comment
    in the tree is stripped out of the payload on the way to a target
    (GLOSSARY: HI.35), so prose density in the code is not the same question
    and is not part of this entry.
  - **Ticks when:** both sections are in `docs/`, README's contents block and
    every inbound link point at their new homes, and no link 404s on
    github.com.

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
