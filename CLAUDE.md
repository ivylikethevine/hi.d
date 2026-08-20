# CLAUDE.md — working on say-hi

Conventions for agent sessions in this repo. The README and docs/ describe the
product; this file is only what a session needs to work here safely.

## The one hard rule: `_HI_HOME`

Always set `_HI_HOME` explicitly — to this checkout's parent, e.g.
`_HI_HOME=/home/ivy/projects/claude` — on every hi.sh, script, or test
invocation. Symptom of forgetting: suites report fewer/MISSING cases, or a
script runs "clean" because it ran against the wrong tree.

There are two say-hi trees on this machine, and neither is wired into the
user's shell any more:

- `~/projects/claude/say-hi` — **this dev checkout**, deliberately not
  installed, so work here never runs in the user's live shell.
- `~/projects/say-hi` — the user's real install, moved there from the old
  `~/hi.d`. Never inspect or touch it, even if it looks dirty. The rename has
  landed on `main`, so it is a `git pull` away from being current — whether it
  has pulled is not this checkout's business either way.

The hazard is no longer a login profile: the rc wiring was removed on purpose,
and nothing on disk exports `_HI_*` any more — not `.bashrc`, `.zshrc`,
`config.fish`, `/etc/profile.d/`, nor `/etc/environment`. What remains is
**inherited process state**. A long-lived shell started back when `~/hi.d`
existed still carries a full `_HI_*` set (`_HI_HOME=/home/ivy`,
`_HI_ROOT=/home/ivy/hi.d`, `_HI_TEST_LIB=/home/ivy/hi.d/tests/test_lib.sh`,
~50 more) and hands it to every child, agent sessions included. Those paths
point at a tree that no longer exists, so the runner dies at its `source` line
with a bare `No such file or directory` naming a path nobody typed — before
`_hi_host_tree_check` (`tests/lib/report.sh`) ever gets to warn. Check with
`env | grep '^_HI_'`, and clear it with:

```sh
unset $(env | sed -n 's/^\(_HI_[A-Za-z0-9_]*\)=.*/\1/p')
```

In a shell with no `_HI_*` set, no override is needed at all — every entry
point derives the tree from its own path (GLOSSARY: HI.33), and
`tests/test_runner.sh <suite>` just works.

**`_HI_HOME` alone is not enough to run one suite directly.** An inherited
environment also carries `_HI_ROOT` and `_HI_TEST_LIB`, and a suite's source
line is `${_HI_TEST_LIB:-…}` — the inherited value wins, so the *harness* is
loaded out of the old tree while `core.sh` quietly corrects `$_HI_ROOT` to the
tree you asked for. The run half-succeeds against two trees at once. Either go
through the runner, which sources the harness by absolute path:

```sh
_HI_HOME=/home/ivy/projects/claude tests/test_runner.sh <suite>
```

or, when a suite really has to run on its own, set both:

```sh
export _HI_HOME=/home/ivy/projects/claude
export _HI_TEST_LIB=$_HI_HOME/say-hi/tests/test_lib.sh
```

## Testing

- `tests/test_runner.sh` runs everything; `--group fast` is the CI gate. Lint
  (shellcheck, shfmt, checkbashisms, the bash-4 construct grep) is enforced by
  the fast group itself — there is no separate lint step.
- Run the suite at the **end** of a multi-step change, not between its steps.
  A structural refactor breaks loudly at source time, and each run costs ~2
  minutes — twice through a six-step change buys nothing the last run doesn't.
- A suite lives in `tests/<the directory it tests>/`: `tests/hi/` and
  `tests/load/` for the two scripts at the tree root, `tests/lint/` for the
  lint gate, `tests/harness/` for the suites that test the harness, and
  `tests/common|shells|misc|scripts|packaging/` mirroring the tree. The harness
  is `tests/test_lib.sh`, a façade over `tests/lib/` — that path is pinned by
  `common/paths.sh`'s `$_HI_TEST_LIB`, which ships, so it does not move. A
  suite sources the façade and nothing else (`docs/GLOSSARY.md`'s HI.34).
- Skip the suite when the diff is prose only — it costs ~2 minutes, most of it
  shellcheck, and no case reads ordinary `.md`. "Only `.yml`/`.md`" is _not_
  the same test, though: the fast group reads several of both. Run it when the
  diff touches `.github/workflows/*.yml` (`runner_test.sh` checks that every
  `--group` name `ci.yml` invokes exists; `packaging_test.sh` asserts against
  `release.yml` and scans every workflow for its `tool:` pins),
  `docs/GLOSSARY.md` (drift-checked against the tree's `# GLOSSARY:` tags by
  `tests/lint/shellcheck_test.sh`), or `packaging/nfpm/nfpm.yaml`. `README.md`'s
  payload badge is read by `bench_test.sh` — `--group bench`, not fast.
- The container suites run their cases in parallel (`_hi_par_case` /
  `_hi_par_wait` in `tests/lib/parallel.sh`), capped at four at a time. Set
  `_HI_PAR_WIDTH=1` to put a suite back on one case at a time — it is the same
  code path, and it is what to reach for when a case is flaky or a transcript
  needs reading live rather than replayed. The lint suite fans out the same
  way, one shellcheck invocation per CPU over a share of the file list;
  `_HI_SC_WIDTH=1` is its serial form.
- `shfmt -w .` is **not** the fix for a red shfmt gate: the gate reads the same
  `*.sh` list shellcheck does, and `.` also reformats `shells/zsh.zsh`, which
  is zsh and ships. Reformat the paths the failure names.
- The e2e suites (ssh, docker, podman, nomad, kube) need real backends, and
  they do run in this environment (the sandbox allows the docker socket as of
  Aug 2026). A suite that stands down reports yellow **SKIPPED**, never green;
  `--require-run` turns skips into failures. Try e2e first and read the
  STATUS/SKIP columns rather than assuming.
- `tests/coverage.sh` is deliberately not in CI and its numbers are currently
  untrustworthy — its own header explains why (kcov loses the DEBUG trap once
  the harness is sourced). Don't write tests to move those figures.

## Hard constraints

- bash 3.2 floor: no mapfile/readarray, associative arrays, namerefs, or case
  conversion. The lint suite greps for violations.
- `common/`, `misc/`, `shells/`, `load.sh` and `hi.sh` itself ship in the ssh
  payload (`$_HI_PAYLOAD`). It is CI-enforced twice, and the two are different
  numbers: `bench_payload_size` budgets the gzipped tar (65536 B), while the
  README badge tracks `_hi_wire_bytes` — the assembled script a session
  actually sends, which is what `hi` prints on connect — to within 5%. They
  move independently: putting a file _into_ the tar raises the first and
  lowers the second. Both measure a **default** configuration - `_hi_payload_tar`
  trims `misc/vim.rc`, `misc/nano.rc` and `shells/osc52.sh` when the overlay has
  turned them off, so a configured client sends less than either number. Tooling-only helpers must not go into `common/core.sh`;
  check both numbers when touching shipped files.
- Several files are dialect-constrained and say so at the top: paths.sh's
  four-shell plain-export subset, aliases.sh's POSIX+fish subset, and
  targets.sh's standalone POSIX. Respect the stated subset over "cleaner" bash.

## Workflow

- `docs/ROADMAP.md` is a to-do list, not a changelog: finished entries are
  deleted (git history is the ledger); entries whose code half shipped but
  which wait on a human step stay unticked, rewritten to say what shipped and
  what the tick now means.
