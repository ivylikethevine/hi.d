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
  - [Demos](#demos)
- [Outside this repo](#outside-this-repo)
  - [Secrets & keys](#secrets--keys)
  - [Release channels](#release-channels)
  - [CI runs to dispatch](#ci-runs-to-dispatch)
  - [Docs & submissions](#docs--submissions)

## In-repo code work

### Release & packaging

- [ ] **Source tarball under the provenance chain** — _Blocked on: v1._ Both
      manifests checksum GitHub's auto-generated `/archive/` tarball, the one
      released artifact with no attestation and no signature over it. The
      release already builds the identical shape (`git archive` in the
      rehearsal): attach it as an asset, list it in `SHA256SUMS`, point both
      `url=`s at it. Touches `bump.sh`, both manifests and their tests.

### Tooling

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

- [ ] **Test hi.d from a non-standard install location** — every path in the
      product already resolves through `$_HI_HOME/hi.d`
      (`../common/paths.sh`, `../common/core.sh`, `../shells/config.fish`), and
      `install.sh` emits an `_HI_HOME` export precisely when the tree is *not*
      at `$HOME/hi.d`. So the mechanism exists; what is missing is a suite that
      pins it, rather than exercising it by accident because a developer's
      checkout happens to sit elsewhere.

  - **The gap is the `installed` shape.** `_hi_probe_cmd`
    (`../tests/test_lib.sh`) asserts `[ "$_HI_ROOT" = "$HOME/hi.d" ]` for the
    `installed` case, so the one e2e shape modelling a permanent install only
    ever models it at the default path. A second shape, installed to something
    like `$HOME/opt/nested/hi.d`, is what would catch a hardcoded `~/hi.d`
    creeping back into a shipped file.
  - **Cover the rc wiring, not just the launcher.** The export install.sh
    writes into `.bashrc` / `.zshrc` / `config.fish` is what makes a
    non-default location survive into a new shell, and nothing reads it back.
  - **Ticks when:** a case installs hi.d somewhere other than `$HOME/hi.d`,
    opens a fresh shell in each of the four dialects, and gets a working
    header, prompt and `hi --doctor` out of it.

- [ ] **Find a non-standard permanent hi.d on a target** — `_hi_remote_root`
      (`../hi.sh`) probes exactly one path, `_r="$HOME/hi.d"`. A target whose
      hi.d lives anywhere else is invisible to it, so hi copies the payload
      over instead of reusing what is already installed there: the slow path,
      silently, on precisely the machines most likely to have a curated tree.

  - **A product gap before it is a test gap.** The probe has to ask the target
    where its hi.d is — the `_HI_HOME` export `install.sh` already writes into
    the login rc files is the obvious source — and fall back to `$HOME/hi.d`
    when it gets no answer.
  - **`--tmux` rides on the same answer.** It needs a permanent hi.d on the
    target, so today it is equally blind to one in a non-standard place.
  - **Ticks when:** an e2e case installs hi.d to a non-default path on a target
    and `hi` there reuses it — asserted on the connect path, not on the session
    merely working, since copying the payload would produce a working session
    too.

- [ ] **Retire the `~/hi.d` default** — every entry point resolves its tree
      through `${_HI_HOME:-$HOME}/hi.d`: `../hi.sh`, `../common/core.sh`'s
      `: "${_HI_HOME:=$HOME}"`, `../common/header.sh`, `../shells/bash.sh` and
      `../shells/zsh.zsh`, the three previews under `../scripts/`, and every
      suite through `../tests/test_lib.sh`. The default is a guess that is right
      for a standard install and wrong everywhere else — and when it is wrong it
      does not fail, it silently reads *another tree*. Both platform e2e jobs
      spent their first real run sourcing `/Users/runner/hi.d/common/core.sh`
      out of a runner home that has no hi.d in it, and this machine's login
      profile exports an `_HI_HOME` aimed at an unrelated install.

  - **Derive it, do not default it.** Two files already do: `../scripts/install.sh`
    and `../tests/test_runner.sh` both resolve their own location and set
    `_HI_HOME` from it. A file that can find itself has no business guessing
    `$HOME`.
  - **The one place a default is honest** is a shipped copy on a target, which
    has no checkout to derive from — and even there the ssh preamble exports
    `_HI_HOME` ahead of it (`../hi.sh`), so the fallback can be "say so and
    stop" rather than `$HOME`.
  - **Half of it is in already:** `../hi.sh` now tests the path before sourcing
    it and answers `set _HI_HOME to the directory that holds it` instead of
    letting bash report a file nobody named. That message is what the rest of
    the tree owes too.
  - **Ticks when:** no shipped file spells `:-$HOME` or `:=$HOME` next to
    `/hi.d`, a checkout outside `$HOME` runs with `_HI_HOME` unset, and the lint
    suite greps for the pattern the way it already greps for bash-4 constructs.

- [ ] **A floor for the packages check** — `../misc/packages` ranks every entry
      1–5 and `full_check` (`../common/header.sh`) gives each rank its own pair
      of colors, hiding the "not installed" half from 4 down. What no setting
      can do is show *less*: every rank that resolves gets printed, and the
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

### Demos

- [ ] **A different hi configuration per demo** — all seven tapes render the
      shipped defaults at the same 1100×620 with every feature on, so the set
      sells one look rather than a configurable tool. Give each demo a
      configuration of its own — a trimmed or disabled header, a narrower or
      taller frame, individual `_HI_DISABLE_*` toggles, a different prompt end,
      a colors overlay — and seven GIFs turn into seven answers to "what can I
      change?".

  - **Where it plugs in:** `client_rc` (`tapes/fixtures.sh`) writes the rc every
    tape sources, which is where a per-demo toggle or overlay belongs; the
    geometry now comes from `tapes/common.tape`, which a tape overrides with its
    own `Set` lines after the `Source` — `tapes/color_preview.tape` already does
    that for height.
  - **Keep the pairs honest.** `demo.tape` and `docker.tape` share a target on
    purpose (the README's top GIF must not drift from the one further down), so
    vary the client configuration there, not the fixture.
  - **Ticks when:** no two demos ship the same configuration, and the README
    line under each GIF names the knob that demo is showing.

- [ ] **A completion demo** — `hi <TAB>` is the feature nothing shows.
      `../common/targets.sh` answers with ssh hosts *and* every running
      container across docker, podman, nomad and kube, tagged by backend, and
      fish renders that list with its description column — the one shell where
      a still frame carries the whole idea. The fixture is the gap: every
      backend has to be up at once, where `tapes/fixtures.sh` brings them up one
      at a time.

  - **Cheapest path to "one of everything":** compose the existing `up_*`
    fixtures rather than writing a new one, and let the tape stand down the way
    the others do when a backend is missing — a half-populated completion list
    is a worse artifact than a skipped render.
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

### CI runs to dispatch

Written, committed, and waiting on a real run. The two e2e workflows are no longer dispatch-only: `ci.yml` calls both on every push to `main`, once the ubuntu and macOS fast-suite jobs are green, so the next push to `main` runs them. Dispatch still works for running one on its own.

- [ ] **macOS loopback e2e** (`macos-e2e.yml`) — CI's macos job runs only the
      fast suites, so the BSD userland (`sed -i ''`, `mktemp -t`, `base64 -D`,
      bash 3.2) is never crossed by a real connection. GitHub's macOS runners
      ship sshd, so the job enables Remote Login, authorizes a throwaway key,
      and runs `hi localhost 'echo marker'` — the whole client-and-target BSD
      path in one go. Pty-wrapped, with a cleanup-trap assertion.

  - **Ticks when:** its first green run. Shipped since: `ci.yml`'s `e2e-macos`
    job calls it on every push to `main` behind both fast-suite jobs, and
    README carries a macOS badge that reads "no status" until then.

- [ ] **Windows target e2e** (`windows-e2e.yml`) — the README documents the
      Git Bash/WSL/PowerShell fallback ladder but no Windows job has ever run.
      This is the _target_-side job; the client-side one the README's "Windows
      channels" gates on (the fast suites under Git Bash) is not written yet.
      It configures the stock sshd, sets the admin `authorized_keys` ACL,
      drives `hi localhost` from Git Bash, and asserts the PowerShell greeting
      — the cmd `||` fallback is the case to watch. Explicitly experimental;
      `.gitattributes` pins LF repo-wide, so the classic CRLF-checkout
      first-dispatch failure is off the risk list.

  - **Ticks when:** its first green run. Shipped since: `ci.yml`'s `e2e-windows`
    job calls it on every push to `main` behind both fast-suite jobs, and
    README carries a Windows badge that reads "no status" until then.

- [ ] **OpenSSF Scorecard** (`scorecard.yml`) — a public supply-chain score
      crediting work already done here (SHA pins, minimal token permissions,
      dependabot, zizmor, branch protection once applied). Dispatch-only,
      SARIF artifact, `publish_results` off.

  - **Ticks when:** it has been run once and the report read. Only then decide about a README badge.

### Docs & submissions

- [ ] **tldr page** — five example lines reach everyone who types `tldr hi`
      before anyone reads a man page. Upstream has its own style guide and
      review, so this is a submission, not a file here; the draft is at
      `docs/tldr.md`.

  - **Do:** open the PR against tldr-pages **after v1**, once the CLI surface is frozen — examples that churn are worse than no page.
  - **Ticks when:** it is merged upstream.
