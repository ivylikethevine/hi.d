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
- `common/` and `shells/` ship in the ssh payload, which is CI-enforced twice
  and they are different numbers: `bench_payload_size` budgets the gzipped tar
  (49152 B), while the README badge tracks `_hi_wire_bytes` — the assembled
  script a session actually sends, which is what `hi` prints on connect — to
  within 5%. Tooling-only helpers must not go into `common/core.sh`; check both
  numbers when touching shipped files.
- Several files are dialect-constrained and say so at the top: paths.sh's
  four-shell plain-export subset, aliases.sh's POSIX+fish subset, and
  targets.sh's standalone POSIX. Respect the stated subset over "cleaner" bash.

## Workflow

- `docs/ROADMAP.md` is a to-do list, not a changelog: finished entries are
  deleted (git history is the ledger); entries whose code half shipped but
  which wait on a human step stay unticked, rewritten to say what shipped and
  what the tick now means.
