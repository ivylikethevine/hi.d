# Contributing to hi.d

The dev loop is small but has a few load-bearing habits. This page is the
archaeology so you don't have to do it.

## Running the tests

Every script resolves against `$_HI_HOME/hi.d`. The runner defaults
`_HI_HOME` to this checkout's parent, so a fresh clone works with no setup -
but never point anything at your real `~/hi.d`:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh header shellcheck  # just the named suites
tests/test_runner.sh --group fast       # what CI runs on every push
tests/test_runner.sh --group bench      # hot-path timings vs ceilings
tests/test_runner.sh --group e2e        # real containers; needs docker
```

A passing suite's transcript is collapsed to one status line; failures
replay in full and are recapped under the summary table. `_HI_VERBOSE=1`
streams everything live. A suite whose backend is missing reports
**SKIPPED**, never a green pass, and `--require-run` (what CI's e2e jobs
pass) turns those skips into failures.

`tests/coverage.sh` runs the fast suites under kcov when you want to know
which arms of `install.sh`/`bump.sh` the cases never touch.

## The lint gate

`tests/test_runner.sh shellcheck` is one suite with five halves, and CI runs
all of them:

1. **shellcheck** over every `*.sh` (CI pins the version - see
   `.github/actions/setup-shellcheck`).
2. **Native syntax checks**: `zsh -n` / `fish --no-execute` over the files
   those shells parse for themselves.
3. **The bash-3.2 grep**: no `mapfile`, no associative arrays, no namerefs,
   no `${x,,}` - macOS ships bash 3.2 and hi runs there. Every
   deliberately-odd construct this forces is explained once in
   [docs/GLOSSARY.md](docs/GLOSSARY.md); code references entries with
   `# GLOSSARY: <entry>` tags rather than re-explaining.
4. **shfmt** as a formatting gate. The style comes from `.editorconfig`;
   fix a red run with `shfmt -w .`.
5. **checkbashisms** over the `#!/bin/sh` files, which dash and busybox sh
   really do parse on minimal targets.

Halves 4 and 5 skip yellow when the tool isn't installed locally; CI always
enforces them.

## PR titles are the release notes

The release workflow drafts notes with `gh release create --generate-notes`,
which reads merged PR titles. Title your PR the way you'd want it read in a
changelog.

## What ships where

Two allow lists decide everything: `$_HI_PAYLOAD` in `hi.sh` (what rides to
a target - `tests/`, `docs/`, CI and editor config never do) and
`_HI_PACKAGE_CONTENTS` in `scripts/install.sh` (what a packaged install
contains). Anything new stays off both until it earns a place, and
`tests/scripts/packaging_test.sh` fails if the copies of that decision
drift.
