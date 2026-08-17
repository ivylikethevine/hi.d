# hi.d and the alternatives

An honest look at what else solves this problem, where hi.d is genuinely
different, and where one of the others is the better tool. Written for someone
deciding whether to use hi.d, not to sell it.

## The problem being solved

You have a shell you have spent years tuning. You spend your day on machines
that are not yours: production boxes, a colleague's server, a jump host, a
container that will not exist in an hour. On those machines you get `sh-4.4$`
and no `ll`.

There are two families of answer.

**Install your config there.** Dotfile managers — [chezmoi], [yadm], [GNU Stow],
[dotbot], [rcm] — or config management like Ansible. These are excellent and
hi.d does not compete with them. They assume the machine is yours, that you will
be back, and that leaving files behind is fine. That assumption fails for a
shared production host, a box you touch once, or a container. The line has
blurred at its edge — chezmoi's `--one-shot` applies your dotfiles to an
ephemeral machine and then deletes chezmoi itself, and VS Code's devcontainers
can clone a dotfiles repo into every container they build — but both need the
*target* to reach your repo over the network, both leave the applied files
behind, and neither does anything per-session. hi.d pushes from the client,
needs no network on the target, and cleans up.

**Carry your config with you, per session.** The tool ships your config over the
connection, uses it for that session, and gets out. That is the family hi.d is
in, and everything below is a member of it.

A third thing that looks similar but is not: **terminal emulators that help with
ssh**, like [kitty's ssh kitten] and wezterm's ssh domains (which go further:
an optional persistent `wezterm-mux-server` on the remote). Those solve the
adjacent and very real problem of terminfo and shell integration — kitty's copies the
`xterm-kitty` terminfo database and enables shell integration on the remote, and
it can copy files you list too. If your pain is "backspace is broken over ssh",
that is the fix, and it composes with hi.d rather than competing. hi.d handles
the terminfo half itself (`_hi_remote_preamble` probes the target's terminfo tree
and falls back to `xterm-256color`) precisely so it does not depend on your
choice of terminal.

## The direct alternatives, side by side

| | **hi.d** | **[sshrc]** | **[xxh]** | **[kyrat]** | **[sshdot]** |
| --- | --- | --- | --- | --- | --- |
| Written in | POSIX/bash shell | shell | Python | bash | shell |
| Client needs | `bash` 3.2+, `base64` | bash, ssh | a Python install (pip/pipx/conda) or the portable binary | `bash` **≥ 4.0**, GNU coreutils | shell, ssh |
| Target needs | `base64`; `bash` for the full session | shell | Linux **x86_64 only** | shell | shell |
| Target OS | Linux (glibc + musl), macOS/BSD, Windows via WSL/Git Bash | broad | Linux x86_64 | Linux, macOS | broad |
| Installs on target | nothing | nothing | a portable shell + plugins under `~/.xxh` | nothing | nothing |
| Cleans up on exit | yes, automatically | leaves `/tmp` dir | no — delete `~/.xxh` yourself | yes, automatically | leaves files |
| Size ceiling | ~35KB gzipped, enforced by CI | **~64KB and the server may block you** | large — it uploads whole shells | small | none (that is its point) |
| Non-ssh targets | **docker, podman, nomad, k8s** | no | no | no | no |
| Can give you a shell the host lacks | no | no | **yes** | no | no |
| Maturity | pre-1.0, not yet published to any channel | **original deleted from GitHub**; [cdown's] fork is the maintained line, argv ceiling inherited | mature, active | quiet | quiet |

## Tool by tool

### sshrc — the ancestor

hi.d is a fork of [sshrc] (via [cdown's] and [danrabinowitz's] lines), and the
core idea is unchanged: tar your config, base64 it, hand it to the login shell,
source it on the far side. Russell Stewart's original repository has since been
deleted from GitHub outright — not archived — so the links here point at
[cdown's] fork, which calls itself the maintained continuation and carries the
design (64KB argv ceiling included) unchanged.

**Where sshrc still wins:** it is smaller and simpler, and simplicity is a real
feature in something that runs on every host you touch. If all you want is your
`.bashrc` and `.vimrc` over there, sshrc does that in a fraction of the code, and
you can read all of it in one sitting.

**Where hi.d went further, and why:**

- **Transport.** sshrc's lineage passes the payload as a command-line argument.
  Linux caps a single argv entry at 128KB regardless of `ARG_MAX`, and sshrc's
  own README warns that past ~64KB "the server may block your sshrc attempts".
  hi.d writes the payload over **stdin** of the first of two calls multiplexed on
  one ssh connection, which removes that ceiling as a design constraint rather
  than a documented caveat.
- **Cleanup.** sshrc copies into `/tmp` and leaves it. hi.d's `load.sh` sets a
  trap that strips its own lines back out of the host's rc files and removes the
  tree, so a machine you visited looks untouched.
- **It does not just copy files.** sshrc sources whatever you point it at. hi.d
  ships a designed session — header, hashed per-host colors, a git prompt,
  aliases, editor configs — and degrades in defined tiers when the target cannot
  support all of it.

### xxh — the one that solves a harder problem

[xxh]'s pitch is different and more ambitious: it uploads a **portable build of
the shell itself**, so you can use fish or zsh on a host that has neither.

**Where xxh wins outright:** that capability. hi.d cannot give you a shell the
target does not have — its no-bash ladder (`zsh > fish > ksh > mksh > sh`) picks
the best of what is already installed and tells you it did. If you need *your*
shell on a locked-down box that only ships `sh`, xxh is the answer and hi.d is
not. Its plugin model is also more principled than copying dotfiles blind.

**Where hi.d wins:**

- **Reach.** xxh's target support is "Linux on x86_64" — no ARM, no macOS, no
  BSD. hi.d's floor is bash 3.2 (what macOS still ships) and `base64`, and its
  test suite runs real Debian, Alpine/musl and bash-3.2 targets on every run.
- **Weight.** xxh uploads shells; hi.d uploads ~35KB and a CI job fails if that
  number drifts more than a kilobyte from the badge.
- **Footprint.** xxh is hermetic but persistent — `~/.xxh` stays until you
  delete it. hi.d removes itself when the session ends.
- **Dependencies.** xxh needs Python on the client. hi.d needs a shell you
  already have.

### kyrat — closest in spirit

[kyrat] is the nearest neighbour: a bash ssh wrapper, base64+gzip through the
command line, cleanup on exit, `KYRAT_SHELL` to pick bash/zsh/sh. If the table
above looks like a description of hi.d, that is because it nearly is.

The differences are narrow and concrete: kyrat requires **bash ≥ 4.0**, which
rules out macOS's system bash — the exact constraint hi.d contorts itself to
respect (no `mapfile`, no associative arrays, no namerefs, enforced by a grep in
the lint suite and a real bash-3.2 container in CI). kyrat spawns bash, zsh or
sh; hi.d styles bash, zsh, fish and nushell, and gives the POSIX tiers a colored
prompt and — for ksh/mksh — a live git segment. And kyrat is ssh-only.

### sshdot

[sshdot] is sshrc without the size limit, achieved by not squeezing through the
command line. Narrower in scope than hi.d, and the honest summary is that it
solves the one problem it names.

## Adjacent tools, and how they compose

None of these are alternatives — they touch the same session from a different
side. Listed because people arrive here having conflated one of them with the
family above, or because the composition has a wrinkle worth knowing.

- **[mosh] / [Eternal Terminal]** replace ssh as the *transport*, to survive
  roaming and dropped connections. hi's ssh path is two calls multiplexed on
  one OpenSSH connection, which neither of them is, so `hi` cannot ride them.
  The composition that works: install hi.d permanently on the target
  (`scripts/install.sh`), then mosh in — and note `hi_copy` over mosh needs
  mosh ≥ 1.4, its first release with OSC 52.
- **[Warp]'s SSH extension and "Warpify"** attack the same pain from the
  terminal side: a persistent remote component under `~/.warp*`, plus a hook
  line you are asked to add to the remote's rc files. What it ships is Warp's
  features, not your config. The two coexist — hi.d appends and strips only
  its own marker-delimited lines and leaves Warp's alone.
- **[atuin] / [hishtory]** carry the one thing hi.d deliberately does not:
  your shell history, synced across machines you own. Complementary — and a
  target that already runs one of them binds the same `Ctrl-R` hi's session
  lands you at, so the framework e2e suite proves the coexistence: it boots a
  real atuin (and fzf, zoxide, direnv, mise) target and asserts the tool's
  hooks survive hi's session.
- **[chezmoi]/[yadm] as the overlay's keeper.** hi.d's per-user overlay lives
  at `~/.config/hi.d/`; keep that directory in your dotfile manager and the
  two compose cleanly — chezmoi versions it, hi ships it to every target,
  per-session.
- **[sshx]** shares a terminal you already have with other people through a
  browser — despite the name, not in this family at all. An sshx session
  started inside a hi session simply shares the styled session.
- **[distrobox]/toolbox** containers share your real `$HOME`, so `hi` into one
  grafts into the same rc files your host shells read. The exit trap strips
  them as everywhere else, and an uncleanly killed session is the one case
  where graft lines outlive their tree in a file you care about — which is
  why every graft is wrapped in a tree-exists guard that stands it down
  silently (`load.sh`'s `configure_files`; the load suite proves a dead graft
  makes no noise).

## What actually makes hi.d different

Two things, and it is worth being precise because the rest is degree, not kind.

**1. It is not an ssh tool.** Every alternative above is an ssh wrapper. `hi`
resolves a name through a ladder — ssh host, then docker container, then podman,
then nomad allocation, then kubernetes pod — and gives you the *same session* on
whichever it finds. `hi web-1` is your shell whether `web-1` is a `Host` in
`~/.ssh/config` or a pod in the namespace your `kubectl` points at. For anyone
who spends the day moving between a server and the containers on it, that is the
feature; nothing else in this space does it.

**2. It degrades in stated tiers rather than failing or lying.** The README's
compatibility tables answer three separate questions — can hi land a session
here, what does your *login* shell have to survive, and what do you actually end
up in — and mark every cell as proven-by-a-suite, expected, reduced, or
unsupported. A target with no bash gets aliases and a colored prompt and a
warning saying so. A Windows OpenSSH host with no POSIX shell at all gets a plain
PowerShell session rather than an error. That is a design stance, and it is why
the honest cells (🟡 "nobody has proven it") are in the table at all.

Secondary, but real: a per-user config overlay (settings, colors, packages,
aliases) that rides along without dirtying the tree, `hi --doctor` for when
something is slow, `--tmux` so a dropped connection detaches instead of
losing work, and the ability to detect a permanent `~/hi.d` on the target and
use it in place rather than shipping a copy.

## Where hi.d is the wrong choice

- **You want your shell on a host that does not have it.** Use [xxh].
- **The machine is yours and you will be back.** Use [chezmoi] or [yadm]. Per-session
  copying is the wrong shape for a machine you own; install once instead.
- **You want the smallest thing that works.** [sshrc] or [kyrat] are less code,
  and less code on every host you touch is a legitimate preference.
- **Your problem is terminfo or shell integration, not config.** Use your
  terminal's own helper — [kitty's ssh kitten] is excellent at exactly that.
- **You need nushell, elvish or xonsh on a target with no bash.** hi.d's nushell
  support needs bash present on the target (it shells out to it for the header,
  palette and git segment); elvish and xonsh are not styled at all.
- **You need something published and stable today.** hi.d is pre-1.0 and is not
  yet on the AUR, Homebrew, or any other channel; you install it from a checkout
  or a release artifact. The alternatives above have been installable for years.

## Sources

- [sshrc] — hi.d's ancestor; the link is [cdown's] maintained fork, the
  original having been deleted from GitHub ([danrabinowitz's] is the other
  line hi.d descends through)
- [xxh] — portable shells over ssh
- [kyrat] — bash ssh wrapper with cleanup
- [sshdot] — sshrc without the size limit
- [kitty's ssh kitten] — terminfo and shell integration
- [chezmoi], [yadm], [GNU Stow], [dotbot], [rcm] — the install-it-there family

[sshrc]: https://github.com/cdown/sshrc
[cdown]: https://github.com/cdown/sshrc
[cdown's]: https://github.com/cdown/sshrc
[danrabinowitz]: https://github.com/danrabinowitz/sshrc
[danrabinowitz's]: https://github.com/danrabinowitz/sshrc
[xxh]: https://github.com/xxh/xxh
[kyrat]: https://github.com/fsquillace/kyrat
[sshdot]: https://github.com/PFacheris/sshdot
[kitty's ssh kitten]: https://sw.kovidgoyal.net/kitty/kittens/ssh/
[chezmoi]: https://www.chezmoi.io/
[yadm]: https://yadm.io/
[GNU Stow]: https://www.gnu.org/software/stow/
[dotbot]: https://github.com/anishathalye/dotbot
[rcm]: https://github.com/thoughtbot/rcm
[mosh]: https://mosh.org/
[Eternal Terminal]: https://eternalterminal.dev/
[Warp]: https://docs.warp.dev/terminal/warpify/
[atuin]: https://atuin.sh/
[hishtory]: https://github.com/ddworken/hishtory
[sshx]: https://sshx.io/
[distrobox]: https://distrobox.it/
