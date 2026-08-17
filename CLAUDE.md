# CLAUDE.md — working on hi.d

Conventions for agent sessions in this repo. The README and docs/ describe the
product; this file is only what a session needs to work here safely.

## The one hard rule: `_HI_HOME`

Always set `_HI_HOME` explicitly — to this checkout's parent, e.g.
`_HI_HOME=/home/ivy/projects/claude` — on every hi.sh, script, or test
invocation. This machine's login profile exports `_HI_HOME=/home/ivy`, so the
inherited value silently points every run at `~/hi.d`: the user's real,
unrelated install. Never inspect or touch `~/hi.d`, even if it looks dirty.
Symptom of forgetting: suites report fewer/MISSING cases, or a script runs
"clean" because it ran against the wrong tree.

## Testing

- `tests/test_runner.sh` runs everything; `--group fast` is the CI gate. Lint
  (shellcheck, shfmt, checkbashisms, the bash-4 construct grep) is enforced by
  the fast group itself — there is no separate lint step.
- The e2e suites (ssh, docker, podman, nomad, kube) need real backends, and
  they do run in this environment (the sandbox allows the docker socket as of
  Aug 2026). A suite that stands down reports yellow **SKIPPED**, never green;
  `--require-run` turns skips into failures. Try e2e first and read the
  STATUS/SKIP columns rather than assuming.
- `tests/coverage.sh` is deliberately not in CI and its numbers are currently
  untrustworthy — its own header explains why (kcov loses the DEBUG trap once
  test_lib.sh is sourced). Don't write tests to move those figures.

## Hard constraints

- bash 3.2 floor: no mapfile/readarray, associative arrays, namerefs, or case
  conversion. The lint suite greps for violations.
- `common/` and `shells/` ship in the ssh payload, which has a CI-enforced
  size budget (bench suite + README badge). Tooling-only helpers must not go
  into `common/core.sh`; check the payload delta when touching shipped files.
- Several files are dialect-constrained and say so at the top: paths.sh's
  four-shell plain-export subset, aliases.sh's POSIX+fish subset, targets.sh
  and bin/hi standalone POSIX. Respect the stated subset over "cleaner" bash.

## Workflow with Ivy

- Commit per logical chunk during long sessions, but the prose is disposable:
  Ivy squashes unpushed agent commits (`git reset --soft origin/<branch>`) and
  writes the final message themselves. Offer the squash when a session wraps.
- `docs/ROADMAP.md` is a to-do list, not a changelog: finished entries are
  deleted (git history is the ledger); entries whose code half shipped but
  which wait on a human step stay unticked, rewritten to say what shipped and
  what the tick now means.

## Reference

Packaging decisions are argued in two published artifacts (the second is
mirrored at `docs/windows.md`; the first has no in-repo copy):

- **Shipping hi.d** — <https://claude.ai/code/artifact/a7d6ace8-9a90-4a99-8c5f-ce02b85d59d9>
  — AUR, Homebrew tap, nfpm→Releases, OBS, install script, Nix/mise/Snap.
- **hi.d on Windows** — <https://claude.ai/code/artifact/187b96ee-b16c-4171-8522-687498267fe4>
  — Scoop, winget, Chocolatey, MSYS2, Cygwin, WSL; assessment only.

`docs/packaging.md` is the publishing runbook that came out of both.
