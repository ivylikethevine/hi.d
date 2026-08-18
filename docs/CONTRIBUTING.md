# Contributing to hi.d

The dev loop is small but has a few load-bearing habits. This page is the
archaeology so you don't have to do it.

## Running the tests

[TESTING.md](TESTING.md) is the full runbook - `test_runner.sh` usage, the
four suite groups, `--host-report`/`--verbose`, and the lint gate's five
halves. The one habit worth repeating here: never point any script at your
real `~/hi.d` - the runner defaults `_HI_HOME` to this checkout's parent, so
a fresh clone works with no setup.

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
