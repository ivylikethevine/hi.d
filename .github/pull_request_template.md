<!--
docs/CONTRIBUTING.md has the long version of all of this. Delete any line below that
does not apply — an unticked box you explain is fine, an unticked box left
silent is what slows a review down.
-->

## What this changes, and why

<!-- The behaviour that moved. Link the issue if there is one. -->

## The gate

<!--
Paste the summary line from `tests/test_runner.sh --group fast` — the one that
reads like:

  ===== 25/25 test suites passed (66.534s) =====
-->

```text

```

- [ ] `--group fast` is green (lint is inside it — there is no separate step)
- [ ] `--group e2e` / `--group backends` ran, if this touches a backend path —
      say which, and whether they **ran** or **skipped**
- [ ] `--group bench` re-checked, if this touches a file that ships in the
      payload (`common/`, `misc/`, `shells/`, `load.sh`, `hi.sh`)

## The constraints

- [ ] bash 3.2 floor: no `mapfile`, associative arrays, namerefs or `${x,,}`
- [ ] the dialect-constrained files still hold their stated subset
      (`common/paths.sh`, `misc/aliases.sh`, `common/targets.sh`)
- [ ] nothing new derives the say-hi tree from `$HOME`
- [ ] a new suite lives in `tests/<what it tests>/` and is registered in
      `test_runner.sh`'s `_HI_TESTS` table

## Docs

- [ ] the docs that describe what moved are updated (docs/CONTRIBUTING.md has the
      table: flags → `docs/hi.1` + `docs/tldr.md`, settings →
      `docs/CONFIGURATION.md`, targets → `docs/SUPPORTED.md` /
      `docs/UNSUPPORTED.md`, and so on)
- [ ] any new idiom has a `GLOSSARY: HI.NN` tag and an entry to point at
- [ ] a finished `docs/ROADMAP.md` entry is **deleted**, not ticked

## AI

- [ ] some of this was written with generative AI, and I have understood,
      reviewed and stood behind it — see [README's AI Usage](https://github.com/ivylikethevine/say-hi/blob/main/README.md#ai-usage)
