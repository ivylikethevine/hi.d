# Testing

Every script resolves against `$_HI_HOME/hi.d`. The runner defaults `_HI_HOME` to this checkout's parent, so
a fresh clone works with no setup - but never point anything at your real `~/hi.d`:

```sh
export _HI_HOME=/path/to/parent-of-hi.d
tests/test_runner.sh
```

## Running the tests

Run everything with `tests/test_runner.sh` (aliased to `hi_test` once installed) - it times each suite and
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

Four groups (`--group <name>`), matching CI's four jobs. `fast`: `aliases`, `alias_fallthrough`, `osc52`,
`tmux`, `shellcheck`, `install`, `packaging`, `hi`, `header`, `core`, `git_prompt`, `targets`, `paths`,
`color_preview`, `packages_preview`, `doctor`, `load`, `rc`, `test_lib`, `test_runner` — dependency-free, the first thing CI runs
on every push/PR (the last two are the harness testing itself). `bench`: hot-path timings checked against
ceilings. `e2e`: `ssh`, `ssh_disconnect`, `ssh_relay`, `docker`, `framework` — real throwaway containers
driving `hi.sh`'s actual connection paths, covering both halves of it (`_say_hi` and `_say_hi_container`).
`backends`: `podman`, `nomad`, `kube` — split from `e2e` because they need extra runner setup (podman, nomad,
kind) beyond docker; a separate, slower CI job. Every e2e/backends suite skips cleanly with a warning rather
than failing when its backend isn't installed. Every test script also runs directly, e.g.
`tests/shells/shellcheck_test.sh`.

`tests/coverage.sh` runs the fast suites under kcov when you want to know which arms of
`install.sh`/`bump.sh` the cases never touch. It's deliberately not in CI and its numbers are currently
untrustworthy (kcov loses the DEBUG trap once `test_lib.sh` is sourced) - don't write tests to move those
figures.

## The lint gate

`tests/test_runner.sh shellcheck` is one suite with five halves, and CI runs all of them:

1. **shellcheck** over every `*.sh` (CI pins the version - see
   `.github/actions/setup-tool/tools.txt`).
2. **Native syntax checks**: `zsh -n` / `fish --no-execute` over the files
   those shells parse for themselves.
3. **The bash-3.2 grep**: no `mapfile`, no associative arrays, no namerefs,
   no `${x,,}` - macOS ships bash 3.2 and hi runs there. Every
   deliberately-odd construct this forces is explained once in
   [GLOSSARY.md](GLOSSARY.md); code references entries with
   `# GLOSSARY: <entry>` tags rather than re-explaining.
4. **shfmt** as a formatting gate. The style comes from `.editorconfig`;
   fix a red run with `shfmt -w .`.
5. **checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
   really do parse on minimal targets.

Halves 4 and 5 skip yellow when the tool isn't installed locally; CI always enforces them.

## Relaying

`hi` chains: from a session on B you can `hi C`, and the second hop is a full hi session. That works from a
_disposable_ session too, because `hi.sh` rides every bash-capable one — it is not in the payload tar, but
both transports write it to the target alongside the tree. `ssh_relay` is the proof: A → B → C, config
intact on the final hop, cleanup traps firing on **both** B and C, on a clean exit and on the link being
killed mid-relay. The one tier that cannot relay is the container transport's bash-less fallback, which
ships `aliases.sh` alone and never loads `paths.sh` — there `hi` is simply not defined.

## Local-only

The tests are local-only: `tests/` is stripped from the payload, so `hi_test` on a target says so rather
than running (likewise `hi_install`, `hi_configure`, `hi_check_configs`, `hi_color_preview`). `hi_update` is
the odd one out — it needs a `.git`, absent both in a hi session and in a package-manager install, so it
says where to update instead of running `git pull` in a non-repo. `hi_packages_preview` is the other: its
legend lives in `scripts/`, but the check it previews lives in the shipped `common/header.sh`, so on a
target it runs that half rather than saying no.
