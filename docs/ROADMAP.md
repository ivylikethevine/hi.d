# Tooling & practices roadmap

What is left to do on hi.d, in two halves:

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

- [ ] **Rename the tree from `hi.d` to `say-hi`** — the directory name is
      load-bearing in more places than it looks. Every path in the product
      resolves as `$_HI_HOME/hi.d` (`common/core.sh`, `common/paths.sh`, `hi.sh`,
      `load.sh`, `scripts/install.sh`, `packaging/lib.sh`), all four packages are
      named `hi.d`, the packaged profile hook is `/etc/profile.d/hi.d.sh`, and
      `packaging/apk/hi.d.rsa.pub` is matched by filename out of `/etc/apk/keys/`.
      Nothing is published to any channel yet, which is exactly why this is a
      _now_ item: the cost is at its floor today and rises the moment the first
      channel goes live, so it belongs **before** v1 rather than after it.

  - **The transition is the hard half, not the rename.** An existing install has
    `~/hi.d` and rc lines pointing at it. `scripts/install.sh` repairs its own
    lines, but `hi.sh`'s permanent-install probe reads the `_HI_HOME` line a
    _target_ wrote and falls back to `~/hi.d` when there is none — so a target
    nobody has updated still answers with the old name. That fallback has to
    accept both names for a release or two, and `hi --doctor` should say which
    one it found.
  - **Four names, four decisions.** The tree (`hi.d`), the command (`hi`), the
    env prefix (`_HI_*`) and the config directory (`~/.config/hi.d/`) are
    independent. This entry is the **tree only**; renaming the other three is a
    much larger change and each would need its own entry and its own migration.
  - **Everything with the name baked in has to move together:** the four package
    manifests and their tests, the apk key filename (`nfpm.yaml`'s `key_name`
    must keep matching it), the repo URL in every manifest and doc, and the demo
    GIFs, which show real paths on screen and would have to be re-rendered.
  - **Ticks when:** a fresh install lands in `$_HI_HOME/say-hi`, an existing
    `~/hi.d` is still found and still connects, `tests/scripts/install_location_test.sh`
    covers both names, and no file in the tree names `hi.d` except where it is
    deliberately describing the old name.

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
      `.github/actions/setup-tool/tools.txt` (eight curl-installed tools) has no
      ecosystem, which is exactly why `tool-versions.yml` exists — a bespoke
      weekly script that reads the same rows and warns on drift. A third class
      has no watcher at all: the same three images named as plain tags in
      `tests/test_lib.sh` and `docs/tapes/fixtures.sh`, which dependabot cannot
      see because it reads Dockerfiles.

  - **What Renovate would buy:** `customManagers` match arbitrary files by
    regex, so `tools.txt`'s version column and the tag strings in shell both
    become ordinary managed dependencies. That is one tool watching all three
    classes, and `.github/scripts/check_tool_versions.sh` plus its workflow
    delete.
  - **What it costs:** a second bot app on the repo, a `renovate.json` that is
    its own dialect to learn, and the loss of something the current setup has —
    `tool-versions.yml` fails loudly with `::warning` annotations in a run,
    where Renovate opens PRs. For eight pins that is arguably a downgrade in
    signal.
  - **Ticks when:** the answer is written down either way. If it stays
    dependabot, say so here and in `.github/dependabot.yml`'s header so the
    question stops being reopened.

- [ ] **Trim misc/aliases.sh from the payload too** — the leftover half of
      "do not ship what the toggles turned off", and the half that is not
      obviously worth doing. `_hi_payload_tar` now drops `misc/vim.rc`,
      `misc/nano.rc` and `shells/osc52.sh` when the overlay has switched them
      off, measured at −2071 bytes gzipped with both toggles set. `aliases.sh`
      is the biggest file in `misc/` at 8.7KB and would be the headline
      saving, but it is deliberately excluded.

  - **Why it is excluded.** `_HI_DISABLE_ALIASES` turns off the _personal_
    aliases, and the file installs the `vim`/`nano`, `hi_copy` and `tmux`
    aliases, plus fish's toggle backstop `eval`, **above** its own early
    return — its comments say so explicitly ("above the early return, so
    disabling personal aliases still leaves the theme"). Trimming it is a
    behaviour change wearing a size saving's clothes, and
    `tests/hi/payload_test.sh` now pins that it keeps shipping.
  - **What it would take:** split the file, so the always-on half and the
    personal-aliases half are separate payload members and only the second is
    trimmed. That is a real refactor of a file three shells parse under a
    shared dialect constraint, for 8.7KB uncompressed on the sessions of people
    who turned aliases off.
  - **Ticks when:** the split exists and a case pins the personal half leaving
    the payload while the editor aliases stay — or when this is closed as not
    worth doing, which is a legitimate answer and should be written here.

### Testing & CI

- [ ] **Settle the fixture images' pinning** — Scorecard's Pinned-Dependencies
      scores 3 on nineteen findings, and every one of them is in
      `tests/dockerfiles/`: sixteen tag-pinned `FROM` lines (`alpine:3.20`,
      `debian:bookworm-slim`, `bash:3.2`, `${BASE}`) and three `curl | sh`
      installers in the atuin, mise and starship framework fixtures. Nothing
      here ships — these are test fixtures, and the workflows and actions the
      release path actually uses are already SHA-pinned, which is why the score
      is 3 rather than 0.

  - **The case for leaving it:** a digest-pinned fixture base has to be bumped
    by hand forever, and buys no user-facing safety, since no byte of these
    images reaches a release. The three `curl | sh` lines are worse to pin than
    to keep: each fixture exists to test hi against whatever that framework
    currently installs, so pinning them tests a frozen framework instead.
  - **The case for pinning anyway:** a fixture base that moves under the suite
    turns a green run red for reasons nobody changed, and the digest is the
    only thing that makes a failed e2e run reproducible.
  - **Ticks when:** the decision is written down — in `docs/TESTING.md` if the
    answer is "deliberately not pinned", or in the Dockerfiles if it is not.
    Either way Scorecard keeps reporting it, so the point is to stop
    re-deciding it every time the report is read.

- [ ] **Trivy over the pinned base images, `--ignore-unfixed`** — the missing
      half of digest-pinning. `tests/dockerfiles` now pins `alpine:3.20`,
      `debian:bookworm-slim` and `bash:3.2` by digest, which is what makes a
      fixture build reproducible and also what freezes whatever CVEs those
      layers carried that day. Dependabot opens a bump PR weekly, but it bumps
      on _release_, not on severity — nothing currently says "the digest you are
      pinned to now has a fixable hole".

  - **`--ignore-unfixed` is the whole design, not a detail.** Measured on the
      current pins: `debian:bookworm-slim` reports **17 HIGH and 5 CRITICAL**,
      and **every one of the 22 has no fix available** — Debian won't-fix
      entries, eight of them `perl-base`. A gate on the raw number is red
      forever and teaches everyone to skip it. With `--ignore-unfixed` all three
      images report **0** today, so the job is green until something actionable
      lands and its going red means exactly one thing: bump the pin.
  - **The code half is in place.** `.github/workflows/image-scan.yml` runs it weekly and on
      dispatch, advisory like markdownlint and link-check. trivy is pinned in
      `setup-tool`'s `tools.txt`, so it caches and the weekly drift check
      watches it like every other tool — no new action dependency. The scan
      list is `sed`'d out of the `FROM …@sha256:` lines rather than repeated,
      so a base image added or repinned is covered without editing that file.
  - **Ticks when:** it has been seen green in CI. Measured locally at the
      current pins: all three images report zero fixable HIGH/CRITICAL.

- [ ] **hadolint over the seventeen fixture Dockerfiles** — nothing lints them
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

- [ ] **timep profiling for the paths the bench suite guards** — `_hi_bench`
      (`../tests/bench/bench_test.sh`) gives one average per hot path against a
      generous ceiling, which answers _whether_ something got slower and never
      _which command inside it did_ — so every regression starts by
      hand-bisecting an rc file. [timep](https://github.com/jkool702/timep) is
      the missing half: a trap-based bash profiler that maps the call-stack tree
      and emits per-command SELF and TOTAL wall time, TOTAL CPU time, and an
      optional flamegraph. Shape it like `tests/coverage.sh` — a
      `tests/profile.sh` run by hand, deliberately **not** in CI. The bench
      ceilings stay the gate; this is what you run once one of them trips.
      `tests/` ships in neither `$_HI_PAYLOAD` nor `$_HI_PACKAGE_CONTENTS`,
      which is why `coverage.sh` lives there and why this belongs beside it.

  - **Point it at the product, never at a suite.** timep drives the DEBUG trap —
    the same mechanism `coverage.sh`'s header documents kcov losing the moment
    `test_lib.sh` is sourced. Profile the argv `_hi_bench_env` already builds
    (`bash -c 'source shells/bash.sh'`; `header.sh` then `hi_header Online`; the
    50-call `_hi_git_prompt` loop; `hi.sh`'s payload assembly) rather than
    wrapping `test_runner.sh`, or this lands in kcov's hole for the same reason.
  - **bash arms only.** It profiles bash, so `shells/config.fish`,
    `shells/zsh.zsh` and `common/targets.sh`-under-`sh` stay bench-only. Scope is
    `shells/bash.sh`, `common/header.sh`, `common/git_prompt.sh` and `hi.sh`.
  - **Dev-only dependencies, so state them and skip cleanly:** bash loadable
    builtins, `/dev/shm` (or `$TMPDIR`), and perl for the flamegraph. Print a
    yellow skip naming where to get it rather than failing, as `coverage.sh`
    does for a missing kcov, and say which backend actually ran, as `_hi_bench`
    does for hyperfine.
  - **Ticks when:** `tests/profile.sh` produces a per-command profile for at
    least the header and git-prompt paths, and its header says what the numbers
    do and do not mean as bluntly as `coverage.sh`'s does.

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

- [ ] **Pin what two concurrent sessions to one host do** — `configure_files`
      (`load.sh`) skips the graft when the marker is already there, and
      `clean_all` strips it on exit. So of two overlapping sessions to the same
      target, the first to leave removes the block the second is still relying
      on. Nothing is lost — session trees are per-`mktemp`, running shells read
      their rc once, and the graft is guarded on `$_HI_HOME` so it can never
      source a stranger's tree — but a shell started _afterwards_ inside the
      surviving session (`tmux new-window`, `su`, a nested login) comes up bare.

  - **The entry's job is to decide, not to fix.** Refcount the graft, or state
    it as a known limit beside the tmux limits already in `CONFIGURATION.md`.
    Both are defensible; what is not defensible is that neither the docs nor a
    test currently says which one is true.
  - **Ticks when:** the behaviour is whichever of the two is chosen, and a case
    pins it — two overlapping sessions, the first one exiting, then a fresh shell
    in the second.

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
      signature (key from `$HI_APK_KEY`, name `hi.d.rsa.pub`), `release.yml`
      injects the `APK_SIGNING_KEY` secret, and CI's packaging-smoke installs a
      signed apk on Alpine every PR. Without the key the release apk builds
      unsigned and installing it needs `--allow-untrusted`.

  - **Where:** a terminal, then Settings → Secrets and variables → Actions
  - **Do:** generate the RSA keypair (abuild-style), add the private half as the `APK_SIGNING_KEY` **repo** secret (not an environment secret — the ungated build job needs it), commit `packaging/apk/hi.d.rsa.pub` under exactly that filename (apk matches signatures to `/etc/apk/keys/` by name, and it must stay what `nfpm.yaml`'s `key_name` says), delete the local private half.
  - **Ticks when:** the secret exists and the public key is committed.

    ```sh
    openssl genrsa -out hi.d-apk.rsa 4096
    openssl rsa -in hi.d-apk.rsa -pubout -out packaging/apk/hi.d.rsa.pub
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

- [ ] **AUR** — register an account; `ssh-keygen -t ed25519`, add the public
      half there, add the private half as the `AUR_SSH_KEY` repo secret and
      delete the local copy. For each package's first push, re-run the
      namcap gate against the published source and push only `PKGBUILD` +
      `.SRCINFO` — that first push is manual, `release.yml`'s `aur` job
      handles the versioned package after.

  - **Ticks when:** both packages are live on the AUR and the `aur` job has
    kept `hi.d` current for one real release.

- [ ] **Homebrew tap** — create the `homebrew-tap` repo (a plain GitHub repo
      with a `Formula/` directory), add a fine-grained PAT scoped to it
      (contents + pull-requests write) as `HOMEBREW_TAP_TOKEN`, then re-run
      the `brew install`/`test`/`audit` gate on an actual Mac (the keg lives
      under `/opt/homebrew` there, not Linuxbrew's prefix used so far).

  - **Ticks when:** `brew install ivy/tap/hi.d` works, from a release the
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

- [ ] **A job-started hook on the self-hosted runner** — eleven jobs across
      six workflows open with the same `Reclaim the workspace` step: a
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
  - **Ticks when:** the hook is in place and the eleven copies are deleted in
    one commit. Do both at once: the copies are harmless, but leaving them
    after the hook exists means two mechanisms for one problem.

- [ ] **Decide what to do about the checks this repo cannot score** — the rest
      of the first Scorecard report, none of it a defect. **License 0** is dealt
      with: the MIT text is `LICENSE.md` at the root, which is the one place
      github.com and Scorecard both look. What is left is judgement. **Code-Review 0/26** and **CI-Tests 0/1** are what a
      single maintainer merging their own work scores no matter how good the CI
      is. **SAST 0** is Scorecard not counting shellcheck, actionlint or zizmor,
      and CodeQL has no shell support to offer instead. **Fuzzing 0** has no
      obvious target in a shell tree, though `common/targets.sh` and the colors
      parser are the two that take untrusted-ish input. **CII-Best-Practices 0**
      is a self-certification questionnaire nobody has filled in. Everything
      else passed silently: Token-Permissions, Dangerous-Workflow,
      Binary-Artifacts, Packaging, Dependency-Update-Tool, Security-Policy,
      Vulnerabilities, Maintained, Signed-Releases and Contributors.

  - **The real question** is not how to raise the number but whether to publish
    it: `scorecard.yml` still sets `publish_results: false`, and a README badge
    needs it on. A score dominated by "solo maintainer" is not obviously worth
    displaying — which is the call to make here.
  - **The code half is in place.** The workflow runs weekly rather than on dispatch, so the
    answer arrives as a trend instead of whenever someone remembers. Its
    `manual-dispatch` environment went with the change — a schedule cannot
    satisfy a required reviewer, and the job is `read-all` with an artifact for
    output so it needs none. `publish_results` is on and the SARIF uploads to
    code scanning, so findings land in the Security tab rather than inside an
    artifact.
  - **The README badge is deliberately not there yet.**
    `api.securityscorecards.dev` 404s for this repo until a
    _scheduled_ run has published, and shields renders that as
    `openssf scorecard: invalid repo path` while scorecard.dev's viewer errors
    outright. A `workflow_dispatch` will not fix it — the action only publishes
    on a schedule. Add the badge after the first Tuesday run, once
    `curl -s https://api.securityscorecards.dev/projects/github.com/ivylikethevine/hi.d`
    answers 200.
  - **Ticks when:** `publish_results` is settled either way, and the README
    badge decision follows from it.

### Docs & submissions

- [ ] **tldr page** — five example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages once the CLI surface is frozen —
    which is one of the criteria **Say what v1.0.0 means** exists to write down.
    Examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.
