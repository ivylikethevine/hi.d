# Glossary of deliberate oddities

hi.d's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `misc/aliases.sh` and
`settings.sh` natively). On top of that, targets split between **GNU and BSD
userlands**. Each entry below is a construct that looks odd until you know
which master it serves.

Every entry carries a stable `HI.NN` code, and shipped files reference it with a
short `# GLOSSARY: HI.NN` tag instead of re-explaining - every byte in
`common/`, `shells/`, `misc/` and `load.sh` rides over the wire on each `hi`.
The code is what the tags point at, so an entry can be retitled without touching
a single shipped file; codes are never reused once retired.
`tests/shells/shellcheck_test.sh` fails the build if a tag names a code this
file doesn't define. This file never ships (the payload is `$_HI_PAYLOAD` in
`hi.sh`; `docs/` isn't in it).

## Contents

- [HI.01 empty-array guard](#hi01-empty-array-guard)
- [HI.02 _hi_read_lines](#hi02-_hi_read_lines)
- [HI.03 parallel arrays](#hi03-parallel-arrays)
- [HI.04 dynamic-name assignment](#hi04-dynamic-name-assignment)
- [HI.05 printf -v out-var](#hi05-printf--v-out-var)
- [HI.06 source guard](#hi06-source-guard)
- [HI.07 toggle defaulting](#hi07-toggle-defaulting)
- [HI.08 sed tempfile rewrite](#hi08-sed-tempfile-rewrite)
- [HI.09 cat-over-mv](#hi09-cat-over-mv)
- [HI.10 strftime %e over %-e](#hi10-strftime-e-over--e)
- [HI.11 LC_ALL=C sort](#hi11-lc_allc-sort)
- [HI.12 bytes vs columns](#hi12-bytes-vs-columns)
- [HI.13 command -v fallthrough](#hi13-command--v-fallthrough)
- [HI.14 _hi_on_exit](#hi14-_hi_on_exit)
- [HI.15 strict-mode bracketing](#hi15-strict-mode-bracketing)
- [HI.16 no-fork reads](#hi16-no-fork-reads)
- [HI.17 base64 armor](#hi17-base64-armor)
- [HI.18 sh -c wrapping](#hi18-sh--c-wrapping)
- [HI.19 stdin transport](#hi19-stdin-transport)
- [HI.20 fallback rc](#hi20-fallback-rc)
- [HI.21 split-quoted prompt segment](#hi21-split-quoted-prompt-segment)
- [HI.22 TERM fallback probe](#hi22-term-fallback-probe)
- [HI.23 bash --rcfile -i](#hi23-bash---rcfile--i)
- [HI.24 graft crash guard](#hi24-graft-crash-guard)
- [HI.25 session-shell ranking](#hi25-session-shell-ranking)
- [HI.26 completion probe knobs](#hi26-completion-probe-knobs)
- [HI.27 tmux server-start rules](#hi27-tmux-server-start-rules)
- [HI.28 ksh git segment](#hi28-ksh-git-segment)
- [HI.29 apostrophes in substitution comments](#hi29-apostrophes-in-substitution-comments)
- [HI.30 indirect invocation](#hi30-indirect-invocation)
- [HI.31 porcelain branch.oid](#hi31-porcelain-branchoid)
- [HI.32 starship deference](#hi32-starship-deference)
- [HI.33 derived tree location](#hi33-derived-tree-location)

## HI.01 empty-array guard

`${a[@]+"${a[@]}"}` wherever an array may be empty under `set -u`: bash 3.2
treats expanding an _empty_ array as a fatal "unbound variable". Plain
`"${a[@]}"` is only safe when at least one element is guaranteed.

**Exception - the index form.** `"${!a[@]}"` is already empty-safe and must
NOT get the guard: bash 3.2 reads `${!a[@]+...}` as expanding to nothing
whatever the array holds, and bash 5 reads it as an indirect reference and
errors outright. The lint table in `tests/shells/shellcheck_test.sh` rejects
the guarded index form.

## HI.02 _hi_read_lines

`mapfile`/`readarray` are bash 4; on 3.2 the builtin simply doesn't exist.
`_hi_read_lines <array-name>` (`common/core.sh`) is the stand-in: a `while
read` loop assigning through `eval`, keeping a last line without a trailing
newline the way `mapfile -t` does. Use it exactly like
`_hi_read_lines lines < <(cmd)`.

## HI.03 parallel arrays

Associative arrays (`declare -A`/`local -A`) are bash 4 - on 3.2 the
_declaration alone_ is a fatal "invalid option". Where a map is needed,
either parallel indexed arrays sharing one index with a keys array as the
lookup table (`_hi_group_index` in `scripts/color_preview.sh`), or
`"<key>=<value>"` strings via `_hi_kv_get`/`_hi_kv_set` (`tests/test_lib.sh`).

## HI.04 dynamic-name assignment

bash 3.2 has no namerefs (`declare -n`, bash 4.3), so writing into a
caller-named variable goes through `eval` (see `_hi_read_lines`,
`_hi_widen`) or `printf -v` where the value is a single formatted string.
Reading a caller's `local` works through bash's dynamic scoping, which is why
some helpers deliberately live beside their one caller instead of taking the
array as an argument.

## HI.05 printf -v out-var

`out="$(fn)"` forks a subshell per call; `fn outvar` with `printf -v "$outvar"`
doesn't. Used on hot paths (`_hi_git_prompt`'s optional out-var, `_hi_repeat`)

- but only in bash: zsh's `printf` has no `-v`, so zsh callers keep the
  stdout form.

## HI.06 source guard

`[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` above a script's imperative
tail: sourcing the file defines its functions and stops there, which is how
the test suites reach the functions without running an install/bump/render.
`scripts/install.sh`, `packaging/bump.sh`, `packaging/mkpkg.sh`,
`scripts/color_preview.sh` and `scripts/packages_preview.sh` all carry it.

## HI.07 toggle defaulting

fish has no `${X:-0}`, and it sources `aliases.sh`/`paths.sh`/`settings.sh`
natively - so every `_HI_DISABLE_*` toggle is read _bare_, and a bare read of
an unset variable is fatal under bash's `set -u`. Therefore the toggles must
always exist: `common/core.sh` defaults the `_HI_TOGGLES` list (defaulted,
never assigned, so settings.sh and paths.sh's gate still win),
`shells/config.fish` mirrors it with `set -q X; or set -gx X 0` (fish can't
read a bash array), and `hi.sh`'s `_hi_fallback_rc` emits `export X=0` lines
from the same list for bash-less targets.

## HI.08 sed tempfile rewrite

Never `sed -i`: its in-place flag takes an argument on BSD and not on GNU.
Rewrites go `sed > tmpfile` then write back. See also cat-over-mv below for
why the write-back is `cat`, not `mv`.

## HI.09 cat-over-mv

Writing a tempfile back over an existing file goes through the existing
inode: `cat "$tmp" > "$target"; rm -f "$tmp"` (`_hi_write_back` in
`scripts/install.sh`, `rewrite` in `packaging/bump.sh`). `mv` would transplant
mktemp's 0600 mode onto the target and sever any hardlink/ACL on it - a
dotfile manager's hardlinked `~/.bashrc` must see the new content.
Non-atomicity is acceptable for single-user rc files; `common/targets.sh`'s
cache swap keeps `mv` deliberately, for atomicity over a file it owns.

## HI.10 strftime %e over %-e

`date +%-e` (no-padding) is a GNU extension; BSD strftime prints the literal
characters. `%e` is the portable day-of-month.

## HI.11 LC_ALL=C sort

Under a UTF-8 locale, BSD `sort` exits "Illegal byte sequence" on non-UTF-8
input - and does so having printed nothing while the pipeline carries on.
Any sort whose input isn't guaranteed clean UTF-8 is pinned to `LC_ALL=C`.

## HI.12 bytes vs columns

`${#var}` counts bytes, not display columns, and in the C locale multibyte
characters inflate it - a banner padded by `${#...}` comes out narrow. Width
math around user-visible strings computes column counts explicitly (see
`changes_w` in `common/header.sh`, `_hi_visible_len` in `scripts/install.sh`).

## HI.13 command -v fallthrough

`alias x="$(command -v tool-a || command -v tool-b || command -v fallback)"`
in `misc/aliases.sh`: resolved at source time, valid in sh, bash, zsh _and_
fish (modern fish parses `$(...)`), and never leaves the alias pointing at a
missing binary. The `|| command -v echo` tail keeps `set -u`/`set -e` shells
alive when nothing matches.

## HI.14 _hi_on_exit

zsh doesn't run bash-style `trap ... EXIT` the same way; it has `TRAPEXIT`.
`_hi_on_exit` (`common/core.sh`) picks per shell, and is the only way cleanup
traps are registered in shared code.

## HI.15 strict-mode bracketing

Files that run inside an interactive shell (`common/core.sh`, `hi.sh`,
`shells/bash.sh`, `common/git_prompt.sh`, ...) set `set -euo pipefail` at the
top _and disable it at the end of their own code_: left on, any later
non-zero status or unset variable kills the user's session. The bootloader
and fallback rc do the same on targets - forgetting it there is what once
broke `hi <target> <command>` outright.

## HI.16 no-fork reads

On per-prompt/per-startup paths, builtins over binaries: `read -r x < file`
instead of `$(cat file)` (a miss costs no fork and no error),
`${target%/*}` instead of `$(dirname ...)`, `${row%%$'\t'*}` instead of
`| cut -f1`. A few forks per prompt is the whole latency budget.

## HI.17 base64 armor

The payload is armored with `base64`, not `openssl`: it is pure ASCII
transport encoding (no crypto), and base64 ships on strictly more targets -
coreutils, busybox, macOS/BSD, Git Bash. Decode tries GNU/busybox `-d` first,
then old BSD/macOS `-D`; the failed flag parse consumes no stdin, so the
fallback still sees the whole stream. `tr` runs first because GNU `base64 -d`
tolerates the armor's newlines but not spaces, and a transport that folds
newlines into spaces would otherwise break it. `$_HI_UNARMOR` only ever runs
inside the sh bootloader - the login shell never parses its braces (fish
couldn't).

## HI.18 sh -c wrapping

Every command hi sends meets the target's *login* shell first, and that shell
may be fish, which parses neither `x=1` nor `{ ...; }` nor `||` as sh does.
Wrapping everything in `sh -c '...'` is therefore the transport's job, not
per-site care - the alternative is finding out one function at a time (the
install probe answered "nothing installed" on every fish-login host until it
was wrapped). The quoting is single-quote-and-escape rather than `printf %q`:
`%q` escapes every space with a backslash, which the login shell then has to
unescape - readable in neither the code nor an `ssh -v` log, and one more
thing for fish to differ about. Callers write plain sh and never count quotes.

## HI.19 stdin transport

The bootloader travels over **stdin of the first of two ssh calls multiplexed
on one connection** (so still one authentication), never as a command-line
argument: Linux caps a *single* argv entry at 128KB (`MAX_ARG_STRLEN`)
however large `ARG_MAX` is, and the payload had grown within a few KB of it.
stdin has no ceiling. It has to be two calls because the second one's stdin
belongs to the interactive session - feed it a pipe and the remote shell
reads EOF. It goes over that pipe as the plain script and is `cat` into
place: only the three streams *inside* it are armored, because only they are
binary. Armoring the assembled script on top of them - which the argv era
needed, one shell-safe token - spent a third of every session's bytes to
re-encode text that was already ASCII. The write doubles as the probe: a
target where `sh -c` won't run has no POSIX shell at all (stock Windows
OpenSSH), and one without `base64` cannot unpack what the script carries;
either way the session falls through to the PowerShell branch rather than
half-landing.

## HI.20 fallback rc

The no-bash target's rc is consumed by sh, zsh *and* fish (`_say_hi`'s
`fish -C` branch), so every line in it must be valid in all three - `export
NAME=value` and `[ -f x ] && . x` are. Anything shell-specific is appended by
that shell's own arm. Toggle defaults come first so the files after them
still win. `_HI_REMOTE_SESSION=1` is exported because this path never reaches
`load.sh`, which normally exports it - unset, `paths.sh`'s gate reads the
target as local and strips hi for anyone with `_HI_DISABLE_LOCAL=1`.
`settings.sh` keeps its `[ -f ]` guard because nothing writes it until
install.sh runs, and a bare `.` on a missing file abandons the rest of the
file in ash/dash. `_HI_CONFIG_DIR` points at the target's own `config/`, where
the shipped overlay was unpacked - not a `~/.config/hi.d` belonging to
whoever we logged in as, and not `misc/`, which holds the *shipped* copies of
the same names.

## HI.21 split-quoted prompt segment

The bash-less tiers' PS1 is baked on the client - colors resolved once, the
username read once at source time - because busybox ash does not run command
substitution inside PS1 at all. The ksh/mksh git segment is the exception:
ksh93 and mksh *do* expand `$( )` when the prompt is printed, so the call is
emitted inside a **single-quoted run** of an otherwise double-quoted
assignment - `"…"'$(_hi_ksh_git)'"…"` is one word to the shell - so the shell
stores the substitution literally and expands it per prompt. Double-quoted,
it would be expanded once at rc time and frozen. That split-quoting is the
whole trick, and why the segment stays an opt-in argument: handed to busybox
ash, the substitution's *text* would print instead of running.

## HI.22 TERM fallback probe

ssh forwards the client `TERM` verbatim, and a TERM the target has no
terminfo entry for (ghostty's `xterm-ghostty` is the canonical case, kitty's
`xterm-kitty` the common one) breaks clear/backspace before hi even matters.
The bootloader skips the probe for ubiquitous names; anything else must be
found in a terminfo tree - plain dirs and the BSD/macOS single-hex-char
layout both checked - or is swapped for `xterm-256color`, which every tree
that exists at all carries. `_HI_TERM_FALLBACK=0` keeps the original TERM no
matter what.

## HI.23 bash --rcfile -i

`bash --rcfile X -i` needs both flags, in that order: without `-i` bash
decides it isn't interactive (from stdin, not the flag) and ignores the
rcfile entirely - that was `hi <target> <cmd>` doing nothing from a script or
cron - and `-i` must come *after* `--rcfile`, because bash's long-option pass
ends at the first short option. fish is different again: `exit` inside a
sourced file only unwinds the source, so the fish arm feeds the rc's content
to `-C` instead.

## HI.24 graft crash guard

`clean_all` cannot run after a hard kill, so every rc graft is wrapped in a
tree-exists guard that makes the block vanish on its own when the tree it
points at is gone - otherwise every shell the user opens from then on errors
at its first source line, and in a container sharing `$HOME` (distrobox) that
is the *host's* rc file. The guard re-resolves at shell start, exactly as the
graft's own paths do, so it also silences a bystander shell opened
mid-session with none of the session's env - it asks for `$_HI_HOME` and
stops when there is none, rather than falling back to `$HOME` (HI.33).

## HI.25 session-shell ranking

`$_HI_SHELL_PREFERENCE` is an ordered list of names hi styles, plus the token
`login` for "whatever the user's login shell is"; the first entry that is
installed wins, and bash is the floor because `load.sh` only runs where bash
exists. Its default tail is not a literal: `_hi_session_shell` walks
`common/core.sh`'s `$_HI_SHELL_TREE` (`fish zsh bash mksh ksh dash ash sh`) and
its allow-list `case` drops the tiers that need bash to be *missing* to be
reachable, leaving `fish > zsh > bash`. `hi.sh`'s `$_HI_SHELL_LADDER` is that
same tree with bash removed. One list, two consumers - two literals would be
free to disagree about fish-vs-zsh and ksh-vs-mksh.

The default puts `login` first for a reason found by the framework matrix: a
ranking that leads with fish hands it to anyone whose box has it, so a user
whose login shell is zsh-with-oh-my-zsh never sees their own setup - hi's
configs are grafted onto every rc file either way; the user's are not.

## HI.26 completion probe knobs

`targets.sh` runs on every TAB after `hi ` - the most latency-sensitive path
in hi.d and the slowest (four of five backends are a subprocess each). Two
knobs keep it honest: `_HI_PROBE_TIMEOUT` is the seconds any one backend CLI
gets (default 2, needs GNU `timeout`; shared with `common/core.sh`'s
`_hi_probe`) or an unreachable daemon hangs completion unbounded, and
`_HI_TARGETS_TTL` is the seconds a result is reused (default 5, 0 disables) -
a just-started container may not appear until it expires, the trade for not
paying ~110ms per TAB.

## HI.27 tmux server-start rules

Two rules for `misc/tmux.conf`: `-f` is read when the *server* starts, not
when a client attaches, so attaching to someone else's server applies none of
it; and the `tmux` alias exists only where hi.d is permanent (no
`$_HI_CLEANUP`) - a detached tmux outlives the ssh session, and on a
disposable target the tree it reads is deleted on exit.

## HI.28 ksh git segment

Where bash is present, `common/git_prompt.sh` renders the git segment and
fish reaches it by shelling out to `bash -c`. The ksh/mksh tier is defined by
bash being *absent*, so `shells/ksh.sh` is the segment written a second time,
in POSIX shell - or ksh users would keep the static baked prompt and nothing
else. Only ksh93 and mksh get it because the segment is live (see
split-quoted prompt segment): they expand `$( )` when the prompt is printed,
busybox ash does not do substitution in PS1 at all. What it deliberately does
NOT do is the header - that needs bash, and the README's compatibility table
says so in the ksh row.

## HI.29 apostrophes in substitution comments

bash 3.2 scans a `$( ... )` command substitution with a simple quote
matcher, not the real parser: a comment line _inside_ one containing a lone
`'` (an apostrophe in prose) reads as an unterminated string, and the whole
file dies at parse time with "unexpected EOF while looking for matching
`'`". bash 4+ parses substitutions recursively and is fine, which is why
this only ever surfaces on macOS. Keep comments inside `$( )`
apostrophe-free, or hoist them above the assignment. The lint greps cannot
see this one; `tests/targets/ssh_test.sh` runs `bash -n` over every file in
a real 3.2 container to catch the class.

## HI.30 indirect invocation

Test suites hand their case functions to `_hi_check`/`_hi_case`/`_hi_par_case`
as `"$@"`, or register them as trap hooks, so nothing in the file ever calls
them by name. shellcheck reads that as dead code and raises SC2329 on each one,
which is why every suite carries a file-level `# shellcheck disable=SC2329`.
The disable is the fix; this entry is the reason it is there.

## HI.31 porcelain branch.oid

`git status --porcelain=v2 --branch` already carries HEAD's sha on its
`# branch.oid` line, so the detached-HEAD label reads it out of the stream the
prompt is already parsing instead of forking `git rev-parse`. The `rev-parse`
beneath it is a fallback for a porcelain stream too old to carry that header,
not a third fork in the common path. Implemented twice, in
`common/git_prompt.sh` and `shells/ksh.sh` - see HI.28.

## HI.32 starship deference

`_HI_PROMPT=starship` hands the prompt to [starship](https://starship.rs) when
the target has it, keeping hi's header and aliases. `common/core.sh`'s
`_hi_wants_starship` is the single predicate (the setting *and* the binary);
`shells/bash.sh` and `shells/zsh.zsh` each `eval` their own `starship init`
behind it and skip building hi's PS1. Absent starship, the setting is ignored
silently.

## HI.33 derived tree location

`$_HI_HOME` is the directory *containing* `hi.d`, and every file that needs the
tree derives it from its own path rather than defaulting to `$HOME`. The
default was a guess that is right for a standard install and wrong everywhere
else - and when it was wrong it did not fail, it silently read *another tree*.
Both platform e2e jobs spent their first real run sourcing a
`/Users/runner/hi.d` that was never there.

Each dialect asks the question its own way, and each asks it only when
`$_HI_HOME` is unset, so an outer layer's export (`hi.sh`'s ssh preamble,
`load.sh`, the rc line `scripts/install.sh` writes) still wins and costs no
fork:

Only a handful of files ask. `common/core.sh` owns the answer; everything that
merely *needs* the tree reaches core.sh through its own path rather than
hand-counting a depth from `$_HI_HOME`, so `common/header.sh`, `scripts/` and
the test suites carry no derivation at all.

| where | how |
| --- | --- |
| `common/core.sh` | `${BASH_SOURCE[0]}`, then `cd -P ../.. && pwd`. The one that answers for every file sourced through it |
| `hi.sh`, `scripts/install.sh`, `packaging/lib.sh` | the same, behind a `readlink` walk - `$_HI_LINK` is `/usr/bin/hi`, and the unresolved path answers `/usr`. Three copies, because each must resolve itself before it can source anything |
| `load.sh`, `tests/test_runner.sh` | `${BASH_SOURCE[0]}` - entry points that *export* for children |
| zsh (`shells/zsh.zsh`, and `common/core.sh` reached through it) | `${(%):-%x}` with zsh's `:A:h` modifiers; zsh has no `$BASH_SOURCE`, and bash cannot parse `%x`, so core.sh's arm is `eval`'d |
| fish (`shells/config.fish`) | `sh -c 'cd -P "$1/../.." && pwd'`. Not fish's own `cd`/`pwd`: a builtin-only command substitution runs in the *current* process, so it would move the caller's cwd, and fish's `pwd` is logical where every other dialect here is physical |
| `shells/bash.sh` | `$_HI_HOME`, not its own path - the one file that cannot self-locate, because `load.sh` grafts its *text* into someone else's rc (HI.24), where `$BASH_SOURCE` is that rc |

`common/core.sh`'s zsh arm is `eval`'d for one reason: bash reads `${(%):-%x}`
as a bad substitution, and the file has to *parse* in both shells whichever
one is running it.

Two places keep a fallback, and both say so out loud rather than guessing.
`hi.sh` prints `set _HI_HOME to the directory that holds it` and exits when the
derived path holds no tree. And on a *target* - the one machine with no
checkout to derive from - `_hi_remote_root`'s probe asks in this order:

1. `export _HI_HOME=` / `set -gx _HI_HOME` in `~/.bashrc`, `~/.zshrc`,
   `~/.config/fish/config.fish`, and `/etc/profile.d/hi.d.sh` for a packaged
   install. Read as *files*: the probe runs under `sh -c` over ssh, which is
   neither a login nor an interactive shell and sources none of them.
2. `$HOME/hi.d`.

The first is the point. A curated tree is exactly the one most likely to live
somewhere else, and a probe that only knew `$HOME/hi.d` made those targets
invisible - hi copied its payload over a checkout already sitting there, the
slow path, silently. `--tmux` rides on the same answer, since `load.sh` refuses
it on a disposable tree.

Two details in that probe. Its `sed` uses separate `-e` expressions rather than
one with `\(a\|b\)`, because BRE alternation is a GNU extension and BSD sed is
a target hi has to answer on; and a second `sed` unwraps the value, because
`config_shell` writes the path quoted *and* pads a `# added by hi during
install` marker onto every line it owns. A quoted value is taken as-is (a `#`
inside it survives) and only an unquoted one has a trailing comment stripped.
That second `sed`'s expressions are **ordered**, and the order is the whole
trick: `-e` expressions run in sequence over a single pattern space, so
stripping the comment after unquoting would strip from a `#` that was inside
the quotes. The comment strip therefore runs first, addressed to lines that do
*not* begin with a quote (`/^"/!`), and the unquoting runs second.
`IFS` is a newline for the candidate loop, so an install directory with a
space in it is still one candidate.

The rc grafts (HI.24) are the one shape that cannot derive: `load.sh` inlines
hi's rc *into someone else's rc*, where `$BASH_SOURCE` is that rc. They are
wrapped in a guard that requires `$_HI_HOME` to be set - in a session it always
is, and outside one there is no tree to source.

`tests/shells/shellcheck_test.sh`'s `lint_home_default` greps the tree for the
retired spellings, the way it already greps for bash-4 constructs - over
`.md` too, since docs teaching the old rule are what a packager reads.
