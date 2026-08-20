# Tooling & practices roadmap

What is left to do on say-hi, in two halves:

- **[In-repo code work](#in-repo-code-work)** — everything that can be written
  and finished in this checkout, with nothing outside it involved.
- **[Outside this repo](#outside-this-repo)** — everything gated on a machine,
  an account, a key or a click that no file here can perform. Each names where
  you go, what you do, and what ticks it. Almost all of it is gated on
  publishing, so it sits at the bottom and blocks nothing day to day.

Nothing is wired up until its checkbox is ticked. Entries that are finished,
and questions that have been decided against, are **deleted** rather than kept
here: git history is the ledger, and this file is only what is left to do.

## Contents

- [In-repo code work](#in-repo-code-work)
  - [Release & packaging](#release--packaging)
  - [Tooling](#tooling)
  - [Testing & CI](#testing--ci)
  - [Demos](#demos)
- [Outside this repo](#outside-this-repo)
  - [Secrets & keys](#secrets--keys)
  - [Release channels](#release-channels)
  - [Repo settings and first runs](#repo-settings-and-first-runs)
  - [Docs & submissions](#docs--submissions)

## In-repo code work

### Release & packaging

- [ ] **Say what v1.0.0 means** — README says EXPERIMENTAL UNTIL v1.0.0 and two
      entries here are already _Blocked on: v1_, with nothing anywhere stating
      what v1 is. That makes "blocked on v1" a mood rather than a date: no entry
      can be scheduled against it, and nobody can tell whether shipping it is a
      week away or a quarter. The fix is a list, not a release — write down what
      has to be true, and the blocked entries become orderable behind it.

  - **The obvious candidates**, each already tracked somewhere in this file: the
    CLI surface frozen (the tldr entry is blocked on exactly that), both keypairs
    generated, `macos-e2e.yml` and `windows-e2e.yml` green at least once rather
    than merely written, and every release channel published once by hand before
    the automation is trusted with it.
  - **It is a gate, not a wish list.** Anything that would be nice by v1 but does
    not block calling the thing stable belongs in its own entry, unticked, rather
    than padding this one — the point is a list short enough to finish.
  - **Ticks when:** the criteria are written down, every one of them names the
    entry or file that satisfies it, and the two _Blocked on: v1_ entries point
    at this one instead of at a version number.

- [ ] **Finish the `hi.d` → `say-hi` rename** — _everything but the GIFs has
      shipped._ The tree resolves as `$_HI_HOME/say-hi`, the config overlay is
      `~/.config/say-hi`, all four packages are named `say-hi`, the profile hook
      is `/etc/profile.d/say-hi.sh` and the apk key is
      `packaging/apk/say-hi.rsa.pub`. The old name is accepted nowhere — the
      probe fallback, the overlay fallback and `overlay_migrate` are all out.
      The GitHub repo is renamed, and the AUR had nothing to rename. One step is
      left, and it is the one no file here can perform; **ticks when it is
      done.**

  - **Re-render the seven demo GIFs** in `docs/demos/` — they show `~/hi.d` on
    screen, and `docs/tapes/generate.sh` refuses to run unless the checkout is
    named `say-hi`. Needs docker and a clean tree; its own commit, since it is
    seven binary files.

- [ ] **Source tarball under the provenance chain** — _Blocked on **Say what
      v1.0.0 means**, above._ Both
      manifests checksum GitHub's auto-generated `/archive/` tarball, the one
      released artifact with no attestation and no signature over it. The
      release already builds the identical shape (`git archive` in the
      rehearsal): attach it as an asset, list it in `SHA256SUMS`, point both
      `url=`s at it. Touches `bump.sh`, both manifests and their tests.

### Tooling

- [ ] **Decide whether Renovate replaces dependabot plus `tool-versions.yml`** —
      a consolidation to weigh, not an obvious win. Three classes of pin move
      here and only two have a watcher: dependabot handles the `uses:` SHAs and
      now the `tests/dockerfiles` digests, while
      `.github/actions/setup-tool/tools.txt` (ten curl-installed tools) has no
      ecosystem, which is exactly why `tool-versions.yml` exists — a bespoke
      weekly script that reads the same rows and warns on drift. A third class
      has no watcher but does have a gate: the same images named as plain tags
      in `tests/lib/backend.sh`, `docs/tapes/fixtures.sh` and `ci.yml`, which
      dependabot cannot see because it reads Dockerfiles - `lint_image_tags`
      fails the build when one of them disagrees with the digest-pinned
      version, so dependabot bumps one place and the gate makes the rest
      follow.

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

### Testing & CI

- [ ] **Trivy over the pinned base images, `--ignore-unfixed`** — the missing
      half of digest-pinning. `tests/dockerfiles` now pins `alpine:3.24`,
      `debian:bookworm-slim` and `bash:3.2` by digest, which is what makes a
      fixture build reproducible and also what freezes whatever CVEs those
      layers carried that day. Dependabot opens a bump PR weekly, but it bumps
      on release, not on severity — nothing currently says "the digest you are
      pinned to now has a fixable hole".

  - **`--ignore-unfixed` is the whole design, not a detail.** Measured on the
    current pins: `debian:bookworm-slim` reports **17 HIGH and 5 CRITICAL**,
    and **every one of the 22 has no fix available** — Debian won't-fix
    entries, eight of them `perl-base`. A gate on the raw number is red
    forever and teaches everyone to skip it. With `--ignore-unfixed` all three
    images report **0** today, so the job is green until something actionable
    lands and it's going red means exactly one thing: bump the pin.
  - **The code half is in place.** `.github/workflows/image-scan.yml` runs it weekly and on
    dispatch, advisory like markdownlint and link-check. trivy is pinned in
    `setup-tool`'s `tools.txt`, so it caches and the weekly drift check
    watches it like every other tool — no new action dependency. The scan
    list is `sed`'d out of the `FROM …@sha256:` lines rather than repeated,
    so a base image added or repinned is covered without editing that file.
  - **Ticks when:** it has been seen green in CI. Measured locally at the
    current pins: all three images report zero fixable HIGH/CRITICAL.

- [ ] **hadolint over the eighteen fixture Dockerfiles** — nothing lints them
      today, and a sweep finds real things rather than style noise. Counted
      across the set: `DL3009` (apt lists left in the layer) ×10, `DL3015`
      (no `--no-install-recommends`) ×10, `DL4006` (a piped `RUN` with no
      `pipefail`, so a failing left-hand side passes) ×3, plus `DL3002`,
      `DL3008` and `DL3018`.

  - **Expect to silence some of it.** `DL3008`/`DL3018` want every apt and apk
    package version-pinned, which for throwaway fixtures is the same argument
    the pinning entry above settles the other way — pin the base image,
    not every package inside it. `DL3002` (last USER is root) is what an
    sshd fixture is. A `.hadolint.yaml` naming those, with the reason, is
    part of the work.
  - **`DL4006` is the one that is a bug**, and it is fixed rather than
    ignored: piping curl into sh with no `pipefail` lets a 404 build a green
    image with the framework missing, and the suite then tests an absence.
    `framework-atuin`, `framework-mise` and `framework-starship` all carry
    `SHELL ["/bin/bash", "-o", "pipefail", "-c"]`.
  - **The code half is in place.** `ci.yml`'s `hadolint` job, advisory, on every PR rather
    than only ones touching `tests/dockerfiles/**` — a job-level paths filter
    does not exist and the job costs seconds, so the superset is the simpler
    honest answer. `.hadolint.yaml` carries a reason per silenced rule and
    says which findings are deliberately left visible (`DL3009`, `DL3015`).
  - **Ticks when:** it has been seen green in CI.

- [ ] **The Windows client-side job** — `windows-e2e.yml` is the _target_-side
      job: it stands up sshd and drives `hi localhost` into it. The client-side
      half — the fast suites run under Git Bash, proving `hi.sh` itself works
      when the machine you are sitting at is Windows — has never been written,
      and README's compatibility table rests on it. It ticks on its own schedule
      and blocks nothing else, which is why it is its own entry rather than a
      clause inside the target-side one.

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
  - **If flag completion lands first**, this demo is where it shows: **`hi
--<TAB>` completes hi's own flags** (Tooling) is the other half of the same
    feature, and a tape rendered before it would need re-rendering after.
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

### Secrets & keys

Two keypairs. **The in-repo half of both is written and tested** — CI consumes each secret the moment it exists and says so loudly when it doesn't. What's left is generating the key and pasting it in.

- [ ] **apk signing key** — wired end to end: `nfpm.yaml` declares the
      signature (key from `$HI_APK_KEY`, name `say-hi.rsa.pub`), `release.yml`
      injects the `APK_SIGNING_KEY` secret, and CI's packaging-smoke installs a
      signed apk on Alpine every PR. Without the key the release apk builds
      unsigned and installing it needs `--allow-untrusted`.

  - **Where:** a terminal, then Settings → Secrets and variables → Actions
  - **Do:** generate the RSA keypair (abuild-style), add the private half as the `APK_SIGNING_KEY` **repo** secret (not an environment secret — the ungated build job needs it), commit `packaging/apk/say-hi.rsa.pub` under exactly that filename (apk matches signatures to `/etc/apk/keys/` by name, and it must stay what `nfpm.yaml`'s `key_name` says), delete the local private half.
  - **Ticks when:** the secret exists and the public key is committed.

    ```sh
    openssl genrsa -out say-hi-apk.rsa 4096
    openssl rsa -in say-hi-apk.rsa -pubout -out packaging/apk/say-hi.rsa.pub
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

NOTE: AUR registration is closed due to spam so... :shrug:

- [ ] **AUR** — register an account; `ssh-keygen -t ed25519`, add the public
      half there, add the private half as the `AUR_SSH_KEY` repo secret and
      delete the local copy. For each package's first push, re-run the
      namcap gate against the published source and push only `PKGBUILD` +
      `.SRCINFO` — that first push is manual, `release.yml`'s `aur` job
      handles the versioned package after.

  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `say-hi` current for one real release.

- [ ] **Homebrew tap** — create the `homebrew-tap` repo (a plain GitHub repo
      with a `Formula/` directory), add a fine-grained PAT scoped to it
      (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`, then re-run
      the `brew install`/`test`/`audit` gate on an actual Mac (the keg lives
      under `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/say-hi` works, from a release the
    `tap` job opened a PR for.

### Repo settings and first runs

Each of these waits on something outside the checkout — a toggle in the repo's
settings, or a decision — which is why they sit here rather than in the in-repo
half: no file here can close one.

- [ ] **Turn branch protection on for `main`** — Scorecard's highest-severity
      finding, and nothing in the repo blocks it: the tests count is published
      to the Pages site rather than pushed to `main` by a `contents: write`
      job, so `release.yml`'s gated `publish` job is the only writer, and it
      writes against tags.

  - **Watch for:** `publish` still commits the packaging manifests to `main`
    (`release.yml`, the second credentialed checkout), so whatever rule goes on
    has to let that job through or the release path breaks at the last step.
    Decide the required checks too — and per the note on the markdownlint job,
    do not make the advisory ones required.
  - **Ticks when:** the rule exists and a release has gone out under it.

- [ ] **Secret scanning and push protection** — free on a public repo, off by
      default, and this repo now has four things worth protecting:
      `APK_SIGNING_KEY` and `MINISIGN_SECRET_KEY` (the two signing keys, both
      under **Secrets & keys** above), `AUR_SSH_KEY` and `HOMEBREW_TAP_TOKEN`
      (the two publishing credentials, under **Release channels**). Every one
      of them is generated on a laptop, pasted into a settings page, and
      deleted locally — a sequence whose failure mode is a paste into the wrong
      buffer and a commit.

  - **Push protection is the half that matters.** Scanning tells you a
    credential leaked, which by then means rotating an AUR key and a tap token.
    Push protection refuses the push that would leak it, so the recovery is
    editing a file rather than re-registering with two package channels.
  - **Where:** Settings → Code security. Turn on secret scanning, then push
    protection.
  - **Not a workflow, and not gitleaks or trufflehog.** GitHub's own scanner
    runs on the push path where a third-party action cannot, and it costs
    nothing here. Revisit only if a key format it does not recognise shows up.
  - **Ticks when:** both are on, and the CONTRIBUTING/SECURITY note says what a
    contributor should do when a push is refused.

- [ ] **A job-started hook on the self-hosted runner** — thirteen jobs across
      eight workflows open with the same `Reclaim the workspace` step: a
      `sudo chown -R` of `$GITHUB_WORKSPACE`, guarded on
      `runner.environment != 'github-hosted'`, because that box's `_work`
      persists between jobs and one root-owned file from a container test makes
      the next checkout's cleanup throw (docs/PACKAGING.md has the full
      account). It cannot be factored into a composite action: it has to run
      _before_ `actions/checkout`, and `uses: ./.github/actions/...` needs the
      checkout that has not happened yet.

  - **Where it actually belongs:** `ACTIONS_RUNNER_HOOK_JOB_STARTED` on the
    runner itself — a script the runner executes before every job, which is
    exactly this step's scope. Setting it is a file and an env var on that
    machine, which is why this is here and not in the in-repo half.
  - **Ticks when:** the hook is in place and the thirteen copies are deleted in
    one commit. Do both at once: the copies are harmless, but leaving them
    after the hook exists means two mechanisms for one problem.

- [ ] **Decide what to do about the checks this repo cannot score** — the rest
      of the first Scorecard report, none of it a defect. **License 0** is dealt
      with: the MIT text is `LICENSE.md` at the root, which is the one place
      github.com and Scorecard both look. What is left is judgement. **Code-Review 0/26** and **CI-Tests 0/1** are what a
      single maintainer merging their own work scores no matter how good the CI
      is. **SAST** is the one that moved: Scorecard counts none of shellcheck,
      actionlint or zizmor, and CodeQL has no shell analyser to offer instead -
      but `codeql.yml` now runs CodeQL's `actions` pack over the workflows,
      which Scorecard does count. Worth having on its own merits; a poor reason
      to believe the resulting number, since the product is still bash and
      still unread by it. **Fuzzing 0** has no
      obvious target in a shell tree, though `common/targets.sh` and the colors
      parser are the two that take untrusted-ish input. **CII-Best-Practices 0**
      is a self-certification questionnaire nobody has filled in. Everything
      else passed silently: Token-Permissions, Dangerous-Workflow,
      Binary-Artifacts, Packaging, Dependency-Update-Tool, Security-Policy,
      Vulnerabilities, Maintained, Signed-Releases and Contributors.

  - **The real question** is not how to raise the number but whether to show
    it. `scorecard.yml` sets `publish_results: true`, so the score is on the
    OpenSSF API; what is undecided is the README badge. A score dominated by
    "solo maintainer" is not obviously worth displaying — which is the call to
    make here.
  - **The code half is in place.** The workflow runs weekly rather than on dispatch, so the
    answer arrives as a trend instead of whenever someone remembers. Its
    `manual-dispatch` environment went with the change — a schedule cannot
    satisfy a required reviewer, and the job is `read-all` with an artifact for
    output so it needs none. `publish_results` is on and the SARIF uploads to
    code scanning, so findings land in the Security tab rather than inside an
    artifact.
  - **The badge shipped, which settles half of it.** `README.md` now carries
    `api.scorecard.dev/projects/github.com/ivylikethevine/say-hi/badge`, so the
    scheduled run has published and the 404 that blocked it is gone. What that
    proves is only that the number _renders_ — not that a score dominated by
    "solo maintainer" is worth showing. Removing it again is still a live
    option, and is the decision this entry is now about.
  - **Ticks when:** `publish_results` is settled either way in writing, and the
    badge either stays with a sentence here saying why, or comes back out.

### Docs & submissions

- [ ] **tldr page** — five example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages once the CLI surface is frozen —
    which is one of the criteria **Say what v1.0.0 means** exists to write down.
    Examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.
