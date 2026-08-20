# Testing

Every script resolves against `$_HI_HOME/hi.d`. The runner defaults `_HI_HOME` to this checkout's parent, so
a fresh clone works with no setup - but never point anything at your real `~/hi.d`:

```sh
export _HI_HOME=/path/to/parent-of-hi.d
tests/test_runner.sh
```

## Contents

- [Running the tests](#running-the-tests)
  - [Where a suite lives](#where-a-suite-lives)
  - [The container suites run their cases in parallel](#the-container-suites-run-their-cases-in-parallel)
  - [The images are files; the build contexts are not](#the-images-are-files-the-build-contexts-are-not)
- [The lint gate](#the-lint-gate)
- [Relaying](#relaying)
- [Local-only](#local-only)

## Running the tests

Run everything with `tests/test_runner.sh` (reachable as `hi --test` once installed) - it times each suite and
prints a colored pass/fail summary at the end:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
tests/test_runner.sh --group fast       # what CI runs on every push/PR
tests/test_runner.sh --host-report      # ...prefixed with what this machine is
tests/test_runner.sh --verbose          # every transcript, nothing collapsed
```

A passing suite's transcript collapses to one status line; failures replay in full and are recapped under
the summary table. `--verbose` (`_HI_VERBOSE=1`) streams every transcript live instead, which is what you
want when a case fails only under the runner. A suite whose backend is missing reports **SKIPPED**, never a
green pass, and `--require-run` (what CI's e2e/backends jobs pass) turns those skips into failures.

`--host-report` (`_HI_HOST_REPORT=1`) prints one block before the first suite: bash, the OS, whether the
userland is GNU/BSD/busybox, the locale's glyph verdict, which tree `$_HI_HOME` actually resolves to, which
backends answer, and the lint tools' versions - the questions asked every time a suite passes on one machine
and fails on another. CI passes it on every job. The `_HI_HOME` half of it prints on **every** run, flag or
not - but only when the tree the suites are testing isn't the one you invoked the runner from, which is the
quietest way to get a wrong result here.

Four groups (`--group <name>`), matching CI's four jobs. `--list` prints the membership, which is the copy
to trust — `tests/test_runner.sh --group fast --list`:

- **`fast`** — dependency-free, the first thing CI runs on every push/PR. Every suite except the four below,
  including `test_lib`, `test_lib_report`, `test_lib_par` and `test_runner`, which are the harness testing
  itself.
- **`bench`** — hot-path timings checked against ceilings, plus the payload's two size budgets.
- **`e2e`** — `ssh`, `ssh_disconnect`, `ssh_relay`, `docker`, `framework`: real throwaway containers driving
  `hi.sh`'s actual connection paths, covering both halves of it (`_say_hi` and `_say_hi_container`).
- **`backends`** — `podman`, `nomad`, `kube`: split from `e2e` because they need extra runner setup (podman,
  nomad, kind) beyond docker; a separate, slower CI job.

Every e2e/backends suite skips cleanly with a warning rather than failing when its backend isn't installed.
Every test script also runs directly, e.g. `tests/lint/shellcheck_test.sh`.

### Where a suite lives

`tests/<the directory it tests>/`. `tests/common/`, `tests/shells/`, `tests/misc/`, `tests/scripts/` and
`tests/packaging/` mirror the tree; `tests/hi/` and `tests/load/` cover the two scripts at the root;
`tests/lint/` is the lint gate, `tests/bench/` the timings, `tests/targets/` the container/ssh e2e suites,
and `tests/harness/` the suites that test the harness. The harness itself is `tests/test_lib.sh` — a façade
over `tests/lib/`, which is where its parts live. A suite sources the façade and nothing else
(`docs/GLOSSARY.md`'s HI.34).

### The container suites run their cases in parallel

`ssh`, `ssh_relay`, `docker`, `podman`, `framework` and `kube` spend nearly all their wall clock waiting on
one container at a time, so their cases run in a batch: `_hi_par_case` in `tests/lib/parallel.sh` submits a case
to a background subshell, `_hi_par_wait` collects the batch. Each case writes its verdict to a file that the
parent tallies (a subshell's counter increments would die with it), registers what it started on a teardown
ledger the exit trap sweeps, and buffers its output to be replayed **in submission order** - so a parallel
run's transcript reads exactly like a serial one, only the timings overlap. Cases that read another case's
files stay serial: `ssh_test.sh`'s two `_hi_transcript_is_clean` checks run after the batch, not in it.

The batch is capped, and every run says how wide it went (`| login-shell cases: 4 at a time, …`). The
default is four, or the CPU count if that is smaller; unbounded fan-out thrashes the docker daemon on a
laptop and is both slower and flakier. `_HI_PAR_WIDTH` overrides it:

```sh
_HI_PAR_WIDTH=1 tests/test_runner.sh ssh   # serial, down the same code path - what to use when bisecting a flake
_HI_PAR_WIDTH=8 tests/test_runner.sh ssh   # a big machine, if the daemon can take it
```

`nomad` pins itself to `_HI_PAR_WIDTH=1`: its jobs are tracked in a shell array its cleanup hook purges,
which is the one fixture in the tree that is not case-scoped.

`tests/coverage.sh` runs the fast suites under kcov when you want to know which arms of
`install.sh`/`bump.sh` the cases never touch. It's deliberately not in CI and its numbers are currently
untrustworthy (kcov loses the DEBUG trap once `test_lib.sh` is sourced) - don't write tests to move those
figures.

### The images are files; the build contexts are not

Every container image an e2e suite builds is a real Dockerfile under
[`tests/dockerfiles/`](../tests/dockerfiles) - `sshd-debian` and `sshd-alpine` for the ssh targets, `alpine-shell` for
the bare shell ones, `framework-*` for the nine shell frameworks, and so on. What stays generated per case
is the _build context_: the throwaway keypair's `entrypoint.sh`, and for the pre-installed case the repo
itself. Suites reach a file through `_hi_dockerfile <stem>` and pass it with `-f`; the variants that differ
only by a package list or a base image are one file plus a `--build-arg` (`PKGS`, `BASE`) rather than a
file each.

`docs/tapes/fixtures.sh` builds from the same folder, spelling the path out rather than using the helper -
a tape render happens outside the test harness, so it does not source `test_lib.sh`.

The lint gate checks both directions: no Dockerfile without a caller, no caller naming a Dockerfile that
isn't there. Inline heredocs could not get that wrong; files can, and the failure would otherwise surface
as "the image just didn't build" in an e2e run on a machine with a container backend.

## The lint gate

`tests/test_runner.sh shellcheck` is one suite with seven halves, and CI runs all of them:

1. **shellcheck** over every `*.sh` (CI pins the version - see
   `.github/actions/setup-tool/tools.txt`). It is the whole cost of the fast
   group, so the file list is dealt into one invocation per CPU and replayed
   in order; `_HI_SC_WIDTH=1` puts it back on a single process.
2. **Native syntax checks**: `zsh -n` / `fish --no-execute` over the files
   those shells parse for themselves.
3. **The bash-3.2 grep**: no `mapfile`, no associative arrays, no namerefs,
   no `${x,,}` - macOS ships bash 3.2 and hi runs there. Every
   deliberately-odd construct this forces is explained once in
   [GLOSSARY.md](GLOSSARY.md); code references entries by their stable
   `HI.NN` code with `# GLOSSARY: HI.NN` tags rather than re-explaining.
4. **shfmt** as a formatting gate over the same `*.sh` list. The style comes
   from `.editorconfig`; fix a red run with `shfmt -w` on the paths it
   names, not `shfmt -w .` - that would also reformat `shells/zsh.zsh`,
   which is not in the gate and is zsh, not bash.
5. **checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
   really do parse on minimal targets.
6. **GLOSSARY tags**: every `# GLOSSARY: HI.NN` in the tree has to name a code
   [GLOSSARY.md](GLOSSARY.md) defines, so a deleted entry can't strand the tags
   pointing at it. Codes are matched, not titles - retitling an entry touches
   no shipped file.
7. **tests/dockerfiles/**: every image definition has a caller and every
   caller has an image definition - see above.

Halves 4 and 5 skip yellow when the tool isn't installed locally; CI always enforces them.

## Relaying

`hi` chains: from a session on B you can `hi C`, and the second hop is a full hi session. That works from a
_disposable_ session too, because `hi.sh` rides every bash-capable one — it is not in the payload tar, but
both transports write it to the target alongside the tree. `ssh_relay` is the proof: A → B → C, config
intact on the final hop, cleanup traps firing on **both** B and C, on a clean exit and on the link being
killed mid-relay. The one tier that cannot relay is the container transport's bash-less fallback, which
ships `aliases.sh` alone and never loads `paths.sh` — there `hi` is simply not defined.

## Local-only

The tests are local-only: `tests/` is stripped from the payload, so `hi --test` on a target says so rather
than running (likewise `hi --install`, `hi --configure`, `hi --check-configs`, `hi --color-preview`). `hi --update` is
the odd one out — it needs a `.git`, absent both in a hi session and in a package-manager install, so it
says where to update instead of running `git pull` in a non-repo. `hi --packages-preview` is the other: its
legend lives in `scripts/`, but the check it previews lives in the shipped `common/header.sh`, so on a
target it runs that half rather than saying no.
