# Tooling & practices roadmap

Candidate additions for developing hi.d, roughly ordered by payoff-per-effort
within each section. Each entry says what it is, why it fits this repo
specifically, and the concrete first step. Nothing here is wired up until its
checkbox is ticked.

## Lint & format

- [ ] **shfmt** — the 2-space / `function`-keyword / `case` style is currently
  enforced only by habit. Add a case to `tests/shells/shellcheck_test.sh` that
  runs `shfmt -d` over every `*.sh` and skips (yellow, via `_hi_skip`) when
  shfmt is absent; pin the version in CI the same way shellcheck is pinned.
  First step: `shfmt -d .` locally and fix the (probably tiny) diff.
- [ ] **checkbashisms** — shellcheck does not catch every bashism in the
  `#!/bin/sh` files, and `common/paths.sh` is sourced by dash/sh/fish. Add it
  to the lint suite for the sh-shebang file list only, skip-if-absent.
- [ ] **actionlint** — lints workflow YAML: bad `needs`, invalid contexts,
  shellcheck over `run:` blocks. Single Go binary; install in CI with the same
  composite-action pattern as shellcheck/nfpm. First step: run it once
  locally against `.github/workflows/`.
- [ ] **zizmor** — GitHub Actions security audit (script injection, excessive
  permissions, unpinned actions). One-shot `zizmor .github/` locally first;
  promote to CI only if it stays quiet.

## Testing & performance

- [x] **bench suite** — `tests/bench/bench_test.sh`, its own `bench` runner
  group and CI job: shell startup per shell, header, git prompt per call,
  targets.sh cold/warm, all against generous ceilings.
- [x] **hyperfine** — statistical timing (warmup, outlier detection) as the
  bench suite's preferred backend when installed, plain timing loop otherwise.
- [x] **payload size budget** — `bench_payload_size` builds the payload
  exactly the way `hi.sh` does (`tar` + `$_HI_PAYLOAD`) and fails over 48KB
  gzipped (~26KB today).
- [x] **kcov** — line coverage for the bash suites, run occasionally (not CI)
  to find which arms of `install.sh`/`bump.sh` the ~500 cases never touch -
  `tests/coverage.sh`.

## CI & supply chain

- [ ] **Pin actions by commit SHA** — mutable tags (`actions/checkout@v4`) are
  the standard supply-chain gap for public repos. Pin each `uses:` to a full
  SHA with the tag in a trailing comment.
- [ ] **Dependabot** — `.github/dependabot.yml` with
  `package-ecosystem: github-actions`; keeps the SHA pins above (and the
  composite actions' tool versions) moving via PRs instead of memory.
- [ ] **Branch protection on `main`** once the release flow is live: required
  checks = the fast suites; note the release workflow's publish job pushes
  manifests to `main`, so either allow its bot or switch that step to opening
  a PR at the same time.

## Release & packaging

- [ ] **namcap in the AUR checklist** — already named in
  `packaging/README.md`'s verification steps; make it a hard pre-submit step
  for both PKGBUILDs.
- [ ] **brew audit --strict** in the tap-publish checklist (only runnable from
  a mac / Homebrew-on-Linux; cannot be CI here).
- [ ] **Release-notes discipline** — `gh release create --generate-notes`
  drafts from PR titles; keeping PR titles release-worthy is the cheap
  alternative to conventional-commits tooling. Revisit git-cliff only if
  notes start needing curation.
- [ ] **Artifact attestation** — `actions/attest-build-provenance` on the
  deb/rpm/apk once there are real users; cheap to add, pairs with the
  existing SHA256SUMS.

## Product

- [ ] **Armor the payload with `base64` instead of `openssl`** — the openssl
  dependency is pure ASCII armor (`_HI_ARMOR`/`_HI_UNARMOR`), no crypto.
  `base64` ships on strictly more targets (coreutils, busybox, macOS/BSD,
  Git Bash) than openssl does, so switching drops hi's biggest target-side
  requirement. Decode portably with `{ base64 -d 2>/dev/null || base64 -D; }`
  (old BSD/macOS spell it -D; the failed flag parse consumes no stdin), keep
  the encode side wrapped, remove `_hi_remote_preamble`'s openssl abort, and
  update the README requirements. Verify with the full e2e group - the ssh
  bootstrap one-liner is the riskiest line in the repo.
- [ ] **tmux support** — scope to decide, likely some combination of: a
  shipped `misc/tmux.conf` alongside the vim/nano/eza configs (with an
  overlay slot in `~/.config/hi.d/` like colors/packages); carrying the hi
  session cleanly *inside* a remote tmux (prompt/colors/aliases surviving
  `tmux new` on the target, which today starts a fresh login shell that
  hasn't sourced hi's rc); and possibly a `hi <target>` flag or setting to
  auto-attach/create a named tmux session remotely so a dropped connection
  resumes instead of losing the session. The cleanup trap needs thought:
  detached tmux outlives the ssh session, which conflicts with "remove
  everything on exit" - probably only offered when the target has a
  permanent ~/hi.d.
- [ ] **Branch indicator in the Online header** — when the installed `~/hi.d`
  is neither a release checkout nor on `main`, append the branch name in
  parentheses after the banner's up-arrow/changes indicator (the
  `_HI_BANNER_CHANGES` block in `common/header.sh`). Online header only —
  the disconnect banner stays as-is. Derivable via
  `git -C "$_HI_ROOT" symbolic-ref --short -q HEAD` (empty on a detached
  release tag), cached alongside the existing `_HI_BANNER_CHANGES` memo so
  it stays one git call per session.

## Documentation

- [x] **docs/GLOSSARY.md** — one entry per deliberately-odd construct
  (bash-3.2 stand-ins, POSIX+fish constraints, BSD/GNU traps); shipped files
  carry a one-line `# GLOSSARY: <entry>` tag instead of a paragraph, and
  `docs/` never ships (`$_HI_PAYLOAD` is an allow list).
- [x] **SECURITY.md / threat-model note** — a tool people run against every
  host they touch earns the questions; the answers already exist (no network
  calls, no curl|bash, cleanup traps, root-owned-tree support) and writing
  them down is trust-building. Ships with a pre-v1 supported-versions line
  (tip of `main`); swap in a version table when v1 is tagged.
- [x] **.editorconfig** — 2-space shell, tabs-in-Makefiles-style exceptions if
  any; keeps non-Zed editors honest alongside `.zed/settings.json`. No
  exceptions turned out to be needed: no Makefiles, and the tree is
  uniformly 2-space.
