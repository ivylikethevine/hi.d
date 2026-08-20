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

- [ ] **`hi --<TAB>` completes hi's own flags** — completion answers targets and
      nothing else: `complete -F _hi_complete hi` (`shells/bash.sh`),
      `compdef _hi hi` (`shells/zsh.zsh`) and `complete -c hi -f -a '(sh
      $_HI_TARGETS)'` (`shells/config.fish`) all resolve `common/targets.sh` and
      stop there. So none of the flags `hi --help` lists complete, in any shell —
      the one part of the CLI a user cannot discover by pressing TAB, in a tool
      whose pitch is that the session is the same everywhere.

  - **Single-home the roster or it will drift.** The flags are spelled out in
    `hi.sh`'s `--help` heredoc and again in `docs/hi.1`; three completions would
    make five copies. Put the list where `$_HI_SHELL_TABLE` lives and have the
    lint suite check the four consumers agree, the way it already drift-checks
    the `GLOSSARY:` tags.
  - **Not every flag exists on a target.** `--install`, `--test`,
    `--configure`, `--check-configs` and `--color-preview` need `scripts/`, which
    the payload does not carry, so a session offering them completes straight
    into `$_HI_NO_CHECKOUT`. Filter on `$_HI_REMOTE_SESSION` rather than shipping
    a list that is wrong on half the machines it runs on.
  - **It costs wire.** The completions ship, and the payload is CI-budgeted
    twice; check both numbers, not just the badge.
  - **Ticks when:** `hi --<TAB>` completes flags in bash, zsh and fish, a remote
    session offers only the flags that work there, and a lint case fails when the
    roster and `--help` disagree.

- [ ] **Pick the container or task on multi-container targets** — README
      documents the same limitation twice and it is the only place `hi <target>`
      is knowingly less capable than the CLI underneath it. A multi-task Nomad
      allocation needs `nomad alloc exec -task <name>` and a multi-container pod
      needs `kubectl exec -c <name>`; `hi` passes through neither, so an
      allocation needs a single unambiguous task and a pod silently gets its
      first container — `kubectl`'s own default, with `kubectl`'s warning, which
      is not the same thing as a choice.

  - **Where it plugs in:** `_say_hi_container` (`hi.sh`) already builds a
    `probe`/`cp`/`attach` triple per backend, and every one of the three needs
    the same flag — that triple is the whole surface this touches.
  - **Decide the spelling first.** A `--task`/`--container` flag, a setting, or
    `pod/container` on the target itself are three different answers with
    different completion stories; `common/targets.sh` would have to emit the
    inner names for the last one.
  - **Ticks when:** a multi-container pod and a multi-task allocation each get a
    named session, `tests/targets/kube_test.sh` and `tests/targets/nomad_test.sh`
    cover both, and README's two caveats are replaced by the syntax.

- [ ] **`hi --doctor <container>` reaches as deep as the ssh arm** —
      `doctor_target` (`scripts/doctor.sh`) walks the resolution chain for any
      target, then hands off to `doctor_ssh_target` **only** for an ssh host. A
      docker, podman, nomad or kube target therefore gets one `resolves` row and
      stops: no bash/`base64` inventory, no shell-ladder verdict, no size. That
      is precisely the report wanted when a container session comes up in the
      aliases-only tier, and it is the half the doctor does not answer.

  - **The ssh arm is the template**, and the probe commands already exist —
      `_say_hi_container`'s `probe` triple is the same call this needs, so this
      is a second consumer of an existing roster rather than new plumbing.
  - **Say what a disposable target costs.** The ssh arm prints whether a
    permanent tree is there and what a session ships otherwise; the container
    arm has the same two answers to give.
  - **Ticks when:** `hi --doctor <container>` reports the target's shells,
    `base64` and the tier a session would land in, for all four backends, and
    `tests/scripts/doctor_test.sh` covers one of them.

- [ ] **Do not ship what the toggles turned off** — `$_HI_PAYLOAD` is whole
      directories, so every session sends `misc/vim.rc` and `misc/nano.rc` under
      `_HI_DISABLE_EDITORS=1`, `shells/osc52.sh` under `_HI_DISABLE_OSC52=1`, and
      `misc/aliases.sh` — the single biggest file in `misc/` — under
      `_HI_DISABLE_ALIASES=1`. The client already knows all three answers before
      it builds the tar, so this costs no probe, no round trip and no protocol.

  - **Read the overlay, not the environment.** The toggle that applies on the
    target is the one in the overlay's `settings.sh`, which rides along and is
    sourced there; the client shell's own exported value is a different thing
    entirely. Trim on the wrong one and a locally-disabled feature silently stops
    shipping to hosts that never disabled it.
  - **Both budgets start measuring a _default_ configuration** once the payload
    varies — `bench_payload_size`'s gzipped ceiling and README's wire badge alike.
    Say so where each is documented, or the next person to read them will think
    the number is the number.
  - **Ticks when:** a client with a toggle off sends a measurably smaller
    payload, the session on the far side is unchanged for everyone else, and a
    case pins one toggle to the file it stops shipping.

- [ ] **A floor for the packages check** — `../misc/packages` ranks every entry
      1–5 and `full_check` (`../common/header.sh`) gives each rank its own pair
      of colors, hiding the "not installed" half from 4 down. What no setting
      can do is show _less_: every rank that resolves gets printed, and the
      header is the first thing a session puts on screen. A minimum-priority
      setting — `_HI_PACKAGES_MIN_PRIORITY` in `settings.sh`, alongside the
      other knobs — would let a host say "4 and up" and get a two-line header
      instead of a paragraph.

  - **One number, two consumers.** The check and `hi --packages-preview`
    (`../scripts/packages_preview.sh`) read the same file and have to agree; the
    preview's legend should name the ranks the floor is hiding rather than
    quietly dropping their rows, the way it already explains a "hidden" cell.
  - **Ticks when:** the setting exists, both consumers honor it,
    `CONFIGURATION.md` documents it next to the other toggles, and a case pins
    the boundary — a package exactly at the floor shows, one below it does not.

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
  - **Ticks when:** the behaviour is whichever of the two was chosen, and a case
    pins it — two overlapping sessions, the first one exiting, then a fresh shell
    in the second.

- [ ] **Break up the three test files over 1000 lines** — `tests/test_lib.sh`
      (~1680), `tests/shells/hi_test.sh` (~1250) and
      `tests/harness/lib_test.sh` (~1130) are the only source files in the tree
      past that mark, and they are the three a session is most likely to have to
      read end to end. `test_lib.sh` is the worst of them because every suite
      sources it: it is the harness, the assertions, the parallel-case runner,
      the container ledger, the fixture builders and the host report in one file.

  - **Split on the seams that already exist.** The file is written in labelled
    blocks — counters and assertions, the parallel batch, workdir and cleanup,
    container and key fixtures, reporting — and each has its own header comment
    already. Sourcing one file that sources the parts keeps every suite's
    `source "${_HI_TEST_LIB:-...}"` line working unchanged.
  - **The two suites split by subject**, not by size: `hi_test.sh` covers
    argument parsing, payload assembly and the remote suffix, and `lib_test.sh`
    covers the harness's own contracts.
  - **Nothing here ships**, so neither payload budget moves — but the lint suite
    walks every `*.sh` in the tree, so a split adds files to shellcheck's count
    rather than work to a session.
  - **Ticks when:** no file under `tests/` is over 1000 lines, the suite list in
    `tests/test_runner.sh` is unchanged, and `--group fast` passes the same
    number of cases it did before.

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
half: no file here can close one. The macOS and Windows e2e workflows used to
sit here too; both are green now, and `ci.yml` calls each on every push to
`main` behind the two fast-suite jobs.

- [ ] **Turn branch protection on for `main`** — Scorecard's highest-severity
      finding, and the one thing on that report that was genuinely blocked
      until now: `ci.yml`'s `badge` job held `contents: write` and pushed a
      commit to `main` on every run, so a protected branch would have failed
      it. That job is gone — the tests count is published to the Pages site
      instead — and `release.yml`'s gated `publish` job is the only writer
      left, against tags rather than `main`.

  - **Watch for:** `publish` still commits the packaging manifests to `main`
    (`release.yml`, the second credentialed checkout), so whatever rule goes on
    has to let that job through or the release path breaks at the last step.
    Decide the required checks too — and per the note on the markdownlint job,
    do not make the advisory ones required.
  - **Ticks when:** the rule exists and a release has gone out under it.

- [ ] **Decide what to do about the checks this repo cannot score** — the rest
      of the first Scorecard report, none of it a defect. **License 0** was the
      one real finding and is already dealt with: the MIT text was always there,
      just at `docs/LICENSE.md`, where neither github.com nor Scorecard looks —
      it is `LICENSE.md` at the root now and the next run should score it. What
      is left is judgement. **Code-Review 0/26** and **CI-Tests 0/1** are what a
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
  - **Ticks when:** `publish_results` is settled either way, and the README
    badge decision follows from it.

- [ ] **Publish the Pages site** (`pages.yml`) — the site builds today and
      deploys nowhere: `Settings -> Pages -> Source: GitHub Actions` is a click
      that only exists on a public repo, and it has not been made. It now costs
      more than a missing site. README's tests badge is a shields `endpoint`
      reading `badges/tests.json` off that site, so until the click lands it
      renders `tests | inaccessible` rather than a count.

  - **Ticks when:** the source is set to GitHub Actions, a deploy goes green,
    and README's tests badge shows a number. Shipped since: `pages.yml` builds
    and deploys on every CI success on `main` (plus docs pushes and dispatch),
    and writes `_site/badges/tests.json` from the fast group's own totals —
    which replaced `ci.yml`'s `badge` job, the one that used to commit the
    number back onto `main` on top of whatever the author had just pushed.

### Docs & submissions

- [ ] **tldr page** — five example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages once the CLI surface is frozen —
    which is one of the criteria **Say what v1.0.0 means** exists to write down.
    Examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.
