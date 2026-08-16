# Tooling & practices roadmap

Candidate additions for developing hi.d, roughly ordered by payoff-per-effort
within each section. Each entry says what it is, why it fits this repo
specifically, and the concrete first step. Nothing here is wired up until its
checkbox is ticked.

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
      session cleanly _inside_ a remote tmux (prompt/colors/aliases surviving
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
