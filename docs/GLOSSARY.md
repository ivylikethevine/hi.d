# Glossary of deliberate oddities

hi.d's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `shells/aliases.sh` and
`settings.sh` natively). On top of that, targets split between **GNU and BSD
userlands**. Each entry below is a construct that looks odd until you know
which master it serves.

Shipped files reference these entries with a short `# GLOSSARY: <entry>` tag
instead of re-explaining - every byte in `common/`, `shells/`, `misc/` and
`load.sh` rides over the wire on each `hi`. This file never ships (the
payload is `$_HI_PAYLOAD` in `hi.sh`; `docs/` isn't in it).

## empty-array guard

`${a[@]+"${a[@]}"}` wherever an array may be empty under `set -u`: bash 3.2
treats expanding an _empty_ array as a fatal "unbound variable". Plain
`"${a[@]}"` is only safe when at least one element is guaranteed.

**Exception - the index form.** `"${!a[@]}"` is already empty-safe and must
NOT get the guard: bash 3.2 reads `${!a[@]+...}` as expanding to nothing
whatever the array holds, and bash 5 reads it as an indirect reference and
errors outright. The lint table in `tests/shells/shellcheck_test.sh` rejects
the guarded index form.

## _hi_read_lines

`mapfile`/`readarray` are bash 4; on 3.2 the builtin simply doesn't exist.
`_hi_read_lines <array-name>` (`common/core.sh`) is the stand-in: a `while
read` loop assigning through `eval`, keeping a last line without a trailing
newline the way `mapfile -t` does. Use it exactly like
`_hi_read_lines lines < <(cmd)`.

## parallel arrays

Associative arrays (`declare -A`/`local -A`) are bash 4 - on 3.2 the
_declaration alone_ is a fatal "invalid option". Where a map is needed,
either parallel indexed arrays sharing one index with a keys array as the
lookup table (`_hi_group_index` in `scripts/color_preview.sh`), or
`"<key>=<value>"` strings via `_hi_kv_get`/`_hi_kv_set` (`tests/test_lib.sh`).

## dynamic-name assignment

bash 3.2 has no namerefs (`declare -n`, bash 4.3), so writing into a
caller-named variable goes through `eval` (see `_hi_read_lines`,
`_hi_widen`) or `printf -v` where the value is a single formatted string.
Reading a caller's `local` works through bash's dynamic scoping, which is why
some helpers deliberately live beside their one caller instead of taking the
array as an argument.

## printf -v out-var

`out="$(fn)"` forks a subshell per call; `fn outvar` with `printf -v "$outvar"`
doesn't. Used on hot paths (`_hi_git_prompt`'s optional out-var, `_hi_repeat`)

- but only in bash: zsh's `printf` has no `-v`, so zsh callers keep the
  stdout form.

## source guard

`[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` above a script's imperative
tail: sourcing the file defines its functions and stops there, which is how
the test suites reach the functions without running an install/bump/render.
`scripts/install.sh`, `packaging/bump.sh`, `packaging/package.sh`,
`scripts/color_preview.sh` all carry it.

## toggle defaulting

fish has no `${X:-0}`, and it sources `aliases.sh`/`paths.sh`/`settings.sh`
natively - so every `_HI_DISABLE_*` toggle is read _bare_, and a bare read of
an unset variable is fatal under bash's `set -u`. Therefore the toggles must
always exist: `common/core.sh` defaults the `_HI_TOGGLES` list (defaulted,
never assigned, so settings.sh and paths.sh's gate still win),
`shells/config.fish` mirrors it with `set -q X; or set -gx X 0` (fish can't
read a bash array), and `hi.sh`'s `_hi_fallback_rc` emits `export X=0` lines
from the same list for bash-less targets.

## sed tempfile rewrite

Never `sed -i`: its in-place flag takes an argument on BSD and not on GNU.
Rewrites go `sed > tmpfile` then write back. See also cat-over-mv below for
why the write-back is `cat`, not `mv`.

## cat-over-mv

Writing a tempfile back over an existing file goes through the existing
inode: `cat "$tmp" > "$target"; rm -f "$tmp"` (`_hi_write_back` in
`scripts/install.sh`, `rewrite` in `packaging/bump.sh`). `mv` would transplant
mktemp's 0600 mode onto the target and sever any hardlink/ACL on it - a
dotfile manager's hardlinked `~/.bashrc` must see the new content.
Non-atomicity is acceptable for single-user rc files; `common/targets.sh`'s
cache swap keeps `mv` deliberately, for atomicity over a file it owns.

## strftime %e over %-e

`date +%-e` (no-padding) is a GNU extension; BSD strftime prints the literal
characters. `%e` is the portable day-of-month.

## LC_ALL=C sort

Under a UTF-8 locale, BSD `sort` exits "Illegal byte sequence" on non-UTF-8
input - and does so having printed nothing while the pipeline carries on.
Any sort whose input isn't guaranteed clean UTF-8 is pinned to `LC_ALL=C`.

## bytes vs columns

`${#var}` counts bytes, not display columns, and in the C locale multibyte
characters inflate it - a banner padded by `${#...}` comes out narrow. Width
math around user-visible strings computes column counts explicitly (see
`changes_w` in `common/header.sh`, `_hi_visible_len` in `scripts/install.sh`).

## command -v fallthrough

`alias x="$(command -v tool-a || command -v tool-b || command -v fallback)"`
in `shells/aliases.sh`: resolved at source time, valid in sh, bash, zsh _and_
fish (modern fish parses `$(...)`), and never leaves the alias pointing at a
missing binary. The `|| command -v echo` tail keeps `set -u`/`set -e` shells
alive when nothing matches.

## _hi_on_exit

zsh doesn't run bash-style `trap ... EXIT` the same way; it has `TRAPEXIT`.
`_hi_on_exit` (`common/core.sh`) picks per shell, and is the only way cleanup
traps are registered in shared code.

## strict-mode bracketing

Files that run inside an interactive shell (`common/core.sh`, `hi.sh`,
`shells/bash.sh`, `common/git_prompt.sh`, ...) set `set -euo pipefail` at the
top _and disable it at the end of their own code_: left on, any later
non-zero status or unset variable kills the user's session. The bootloader
and fallback rc do the same on targets - forgetting it there is what once
broke `hi <target> <command>` outright.

## no-fork reads

On per-prompt/per-startup paths, builtins over binaries: `read -r x < file`
instead of `$(cat file)` (a miss costs no fork and no error),
`${target%/*}` instead of `$(dirname ...)`, `${row%%$'\t'*}` instead of
`| cut -f1`. A few forks per prompt is the whole latency budget.
