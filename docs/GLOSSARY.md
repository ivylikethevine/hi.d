# Glossary of deliberate oddities

hi.d's shell code has three masters: **bash 3.2** (macOS's `/bin/bash`, the
floor CI enforces), **POSIX sh** (dash/ash/busybox source parts of it), and
**fish** (which parses `common/paths.sh`, `misc/aliases.sh` and
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
`scripts/install.sh`, `packaging/bump.sh`, `packaging/mkpkg.sh`,
`scripts/color_preview.sh` and `scripts/packages_preview.sh` all carry it.

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
in `misc/aliases.sh`: resolved at source time, valid in sh, bash, zsh _and_
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

## base64 armor

The payload is armored with `base64`, not `openssl`: it is pure ASCII
transport encoding (no crypto), and base64 ships on strictly more targets -
coreutils, busybox, macOS/BSD, Git Bash. Decode tries GNU/busybox `-d` first,
then old BSD/macOS `-D`; the failed flag parse consumes no stdin, so the
fallback still sees the whole stream. `tr` runs first because GNU `base64 -d`
tolerates the armor's newlines but not spaces, and a transport that folds
newlines into spaces would otherwise break it. `$_HI_UNARMOR` only ever runs
inside the sh bootloader - the login shell never parses its braces (fish
couldn't).

## sh -c wrapping

Every command hi sends meets the target's *login* shell first, and that shell
may be fish, which parses neither `x=1` nor `{ ...; }` nor `||` as sh does.
Wrapping everything in `sh -c '...'` is therefore the transport's job, not
per-site care - the alternative is finding out one function at a time (the
install probe answered "nothing installed" on every fish-login host until it
was wrapped). The quoting is single-quote-and-escape rather than `printf %q`:
`%q` escapes every space with a backslash, which the login shell then has to
unescape - readable in neither the code nor an `ssh -v` log, and one more
thing for fish to differ about. Callers write plain sh and never count quotes.

## stdin transport

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

## fallback rc

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

## split-quoted prompt segment

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

## TERM fallback probe

ssh forwards the client `TERM` verbatim, and a TERM the target has no
terminfo entry for (ghostty's `xterm-ghostty` is the canonical case, kitty's
`xterm-kitty` the common one) breaks clear/backspace before hi even matters.
The bootloader skips the probe for ubiquitous names; anything else must be
found in a terminfo tree - plain dirs and the BSD/macOS single-hex-char
layout both checked - or is swapped for `xterm-256color`, which every tree
that exists at all carries. `_HI_TERM_FALLBACK=0` keeps the original TERM no
matter what.

## bash --rcfile -i

`bash --rcfile X -i` needs both flags, in that order: without `-i` bash
decides it isn't interactive (from stdin, not the flag) and ignores the
rcfile entirely - that was `hi <target> <cmd>` doing nothing from a script or
cron - and `-i` must come *after* `--rcfile`, because bash's long-option pass
ends at the first short option. fish is different again: `exit` inside a
sourced file only unwinds the source, so the fish arm feeds the rc's content
to `-C` instead.

## graft crash guard

`clean_all` cannot run after a hard kill, so every rc graft is wrapped in a
tree-exists guard that makes the block vanish on its own when the tree it
points at is gone - otherwise every shell the user opens from then on errors
at its first source line, and in a container sharing `$HOME` (distrobox) that
is the *host's* rc file. The guard re-resolves at shell start, exactly as the
graft's own paths do, so it also silences a bystander shell opened
mid-session with none of the session's env.

## session-shell ranking

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

## completion probe knobs

`targets.sh` runs on every TAB after `hi ` - the most latency-sensitive path
in hi.d and the slowest (four of five backends are a subprocess each). Two
knobs keep it honest: `_HI_PROBE_TIMEOUT` is the seconds any one backend CLI
gets (default 2, needs GNU `timeout`; shared with `common/core.sh`'s
`_hi_probe`) or an unreachable daemon hangs completion unbounded, and
`_HI_TARGETS_TTL` is the seconds a result is reused (default 5, 0 disables) -
a just-started container may not appear until it expires, the trade for not
paying ~110ms per TAB.

## tmux server-start rules

Two rules for `misc/tmux.conf`: `-f` is read when the *server* starts, not
when a client attaches, so attaching to someone else's server applies none of
it; and the `tmux` alias exists only where hi.d is permanent (no
`$_HI_CLEANUP`) - a detached tmux outlives the ssh session, and on a
disposable target the tree it reads is deleted on exit.

## ksh git segment

Where bash is present, `common/git_prompt.sh` renders the git segment and
fish reaches it by shelling out to `bash -c`. The ksh/mksh tier is defined by
bash being *absent*, so `shells/ksh.sh` is the segment written a second time,
in POSIX shell - or ksh users would keep the static baked prompt and nothing
else. Only ksh93 and mksh get it because the segment is live (see
split-quoted prompt segment): they expand `$( )` when the prompt is printed,
busybox ash does not do substitution in PS1 at all. What it deliberately does
NOT do is the header - that needs bash, and the README's compatibility table
says so in the ksh row.

## apostrophes in substitution comments

bash 3.2 scans a `$( ... )` command substitution with a simple quote
matcher, not the real parser: a comment line _inside_ one containing a lone
`'` (an apostrophe in prose) reads as an unterminated string, and the whole
file dies at parse time with "unexpected EOF while looking for matching
`'`". bash 4+ parses substitutions recursively and is fine, which is why
this only ever surfaces on macOS. Keep comments inside `$( )`
apostrophe-free, or hoist them above the assignment. The lint greps cannot
see this one; `tests/targets/ssh_test.sh` runs `bash -n` over every file in
a real 3.2 container to catch the class.
