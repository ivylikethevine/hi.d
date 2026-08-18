# hi.sh -> sshrc supercharged

![CI (main)](https://github.com/ivylikethevine/hi.d/actions/workflows/ci.yml/badge.svg)
![CI (develop)](https://github.com/ivylikethevine/hi.d/actions/workflows/ci.yml/badge.svg?branch=develop)
[![Coverage](https://github.com/ivylikethevine/hi.d/actions/workflows/coverage.yml/badge.svg)](https://github.com/ivylikethevine/hi.d/actions/workflows/coverage.yml)
![ssh payload](https://img.shields.io/badge/ssh_payload-37KB_gzipped-4c1)
![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![shells](https://img.shields.io/badge/shells-bash%20%7C%20zsh%20%7C%20fish%20%7C%20nu%20%7C%20sh-blue)
![targets](https://img.shields.io/badge/targets-ssh%20%7C%20docker%20%7C%20podman%20%7C%20nomad%20%7C%20k8s-8A2BE2)
![license](https://img.shields.io/badge/license-MIT-blue)

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

![hi connecting to a container: banner, header, packages check, colored prompt, and the cleanup on exit](docs/demo.gif)

More of these — every backend (ssh with a permanent install, docker, podman, nomad, kubernetes) across a
variety of shells on both sides — [just below](#every-target-the-same-session).

Wondering how this compares to `sshrc`, `xxh`, `kyrat` or just using `chezmoi` — including where one of
those is the better tool? [hi.d and the alternatives](#hid-and-the-alternatives).

The payload badge above is enforced, not aspirational: the bench suite rebuilds the real payload
(`$_HI_PAYLOAD` only - no tests, docs or CI ever ride along) and fails CI when the badge drifts more
than a kilobyte from the truth.

## Every target, the same session

The pitch is that `hi` behaves identically whatever is on the other end — an
ssh host, a container, an allocation, a pod — and whatever shell each side
happens to run. One GIF per backend, deliberately varying both sides. Each is
rendered from the tape next to it (`vhs docs/tapes/<name>.tape`, from the repo
root, with the backend running and `hi` on PATH; `docs/tapes/fixtures.sh`
builds every target the tapes connect to and `fixtures.sh down` removes them
all). Manual artifacts, reviewed by eye — regenerate whenever the header or
prompt changes.

Two things to get right when you do: `hi` on `$PATH` must be *this* checkout
(`/usr/bin/hi` may point at another install), and the target image is built
from `HEAD`, so uncommitted work shows on the client side of the GIF but not
the target's. Render from a commit, or set `HI_DEMO_SOURCE=worktree` to build
the target from the working tree instead.

### ssh, with a permanent install

The target carries its own `~/hi.d`, so nothing ships over the wire — hi
loads the tree in place and leaves it alone on exit. Client: bash.

![hi over ssh into a host with a permanent ~/hi.d](docs/demos/ssh.gif)

### docker

A debian/bash container, then an alpine box whose only real shell is zsh —
hi probes and falls back without being told. Client: zsh.

![hi into a debian container, then an alpine zsh-only container](docs/demos/docker.gif)

### podman

A fish-only alpine container from a fish client: no bash anywhere in the
loop. Same session, same code path as docker.

![hi from fish into a fish-only alpine container via podman](docs/demos/podman.gif)

### nomad

A dev agent, one docker-driver job, and `hi <alloc-id-prefix>` straight into
the allocation. Client: bash.

![hi into a nomad allocation by ID prefix](docs/demos/nomad.gif)

### kubernetes

A kind cluster and a bare alpine pod — busybox ash is all it has, which is
hi's aliases-only fallback. Client: zsh.

![hi into a kubernetes pod on a kind cluster](docs/demos/kube.gif)

## Requirements

- **Client**: `bash` and `base64` (for ssh targets - armors the bootstrap payload through the login shell; coreutils, busybox, macOS/BSD and Git Bash all ship one) or `docker`/`podman`/`nomad`/`kubectl` for the container/alloc/pod backends.
- **bash version**: 3.2 or newer, on both ends. That is what macOS still ships, so hi stays clear of every bash-4-only construct - no `mapfile`/`readarray` (`_hi_read_lines` in `common/core.sh` does that job), no associative arrays, no namerefs, no `${x,,}`. Two things enforce it: `tests/shells/shellcheck_test.sh` greps for those constructs, and `tests/targets/ssh_test.sh` runs a real bash 3.2 target in a container and fails if the session prints so much as one shell error.
- **Target**: `base64` for ssh targets (effectively everywhere - coreutils, busybox, macOS/BSD); nothing extra for container/alloc/pod targets. `bash` gets you the full experience (header, colors, git prompt, aliases, vim/nano configs); without it `hi` still lands you in the best available shell (`zsh` > `fish` > `ksh` > `sh`) with the aliases and, on the POSIX tiers, a colored prompt - rather than failing outright.
- Everything else (client and target) is plain POSIX/bash/zsh/fish shell - no compiled artifacts, no package manager, no build step.

### How it works

1. `hi.sh` runs on the client. It archives `hi.d/` and sends it to the target. What it leaves out is `hi.sh` itself, `.git`, `scripts/`, `tests/`, `docs/`, `.github/`, this README and the editor/tooling dotfiles - see `$_HI_PAYLOAD` at the top of `hi.sh` for the authoritative allow list. The target unpacks it into a `/tmp` directory. `_HI_ROOT` is `$INSTALL_DIR/hi.d` on the client and `$_HI_HOME/hi.d` on the target.
   Your own `settings.sh`, `colors`, `packages`, `tmux.conf` and `aliases.sh` live outside the tree (see [Configuration](#configuration)), so they follow in a second, much smaller archive unpacked into a `config/` of its own beside the target's `misc/` - `$_HI_OVERLAY_FILES` in `hi.sh`, and `$_HI_CONFIG_DIR` on the target. Its own directory rather than over `misc/`, so your `aliases.sh` stays additive to the shipped one instead of replacing it. Nothing is sent if you haven't overridden anything.
   The whole thing - the tar, `hi.sh` and the bootloader, each base64-armored - is assembled into one script, armored again, and written to the target over the **stdin** of the first of two calls multiplexed on a single ssh connection; the second call runs it. Not as a command-line argument, which is what it used to be: Linux caps a single argv entry at 128KB regardless of `ARG_MAX`, and the payload had grown within a few kilobytes of that. The size hi prints on connect is that armored total - what the connection actually carries, roughly 4/3 of the gzipped payload the badge above measures.
2. On the target, `$_HI_ROOT/hi.bashrc` sources `$_HI_ROOT/load.sh` and calls `load`.
3. `load.sh` prints the header, appends hi's shell configs to the host's own rc files, and starts a session in **your login shell** when hi styles it (bash, zsh or fish), falling back to whichever of `fish > zsh > bash` the target has. `_HI_SHELL_PREFERENCE` is that rule as a setting - see [Configuration](#configuration). The `zsh > fish > ksh > sh` order quoted elsewhere is the **no-bash fallback**, ranking what's left when bash turned out to be missing.
4. When the session ends, `load.sh`'s `trap` strips those additions back out, and the `/tmp` directory is removed by the cleanup trap `hi.sh` set up on connect.
5. `hi <target> 'some command'` skips the interactive session and just runs the command there, like `ssh` does.

The setup in steps 1-2 is plain POSIX and runs under `sh`, so it works even if the target has no `bash` at all - `hi` still copies the whole of `~/hi.d` over in that case, but hands off to the best plain shell available (`zsh`/`fish`/`ksh`/`sh`) with just our aliases loaded, instead of the full `load.sh` experience, which needs `bash`.

For ssh targets specifically, `hi` first checks (over the same connection, so it costs no extra authentication) whether the target already has its own permanent `~/hi.d` - i.e. `scripts/install.sh` has been run there. If so, it skips the archive/copy step entirely and points `_HI_ROOT` straight at that existing copy instead, leaving it in place when the session ends.

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, etc. - anything in this directory is copied to every host you say `hi` to._**

#### How the files relate

The steps above tell the story in prose; this diagram draws the mechanism.
Boxes are files (or the few directories that act as one), and every arrow is
one of four kinds - the four ways a file in this tree ever reaches another:

- **sources** - shell `source`/`.`, same process
- **shells out** - a `bash -c "source ...; fn"` subprocess (how fish and nu
  reach code written in bash)
- **runs** - executed as its own subprocess, never sourced
- **generates / writes** - the file exists only because another wrote it

Deliberately coarse: file granularity and those four edge kinds only. What is
*not* drawn also matters - `hi.sh` itself, `scripts/`, `tests/`, `docs/`
(the GLOSSARY included) never ship; the payload is `$_HI_PAYLOAD` in `hi.sh`,
and the bench suite enforces its size.

```mermaid
flowchart TB
  subgraph client["client machine (stays home)"]
    hish["hi.sh"]
    overlay["~/.config/hi.d/<br/>settings.sh · colors · packages · tmux.conf · aliases.sh"]
  end

  subgraph target["target (payload, unpacked into /tmp or a permanent ~/hi.d)"]
    subgraph generated["generated per connect"]
      bootrc["hi.bashrc /<br/>.hi_fallback_rc"]
      grafts["rc grafts<br/>(guarded blocks in the host's rc files)"]
    end
    loadsh["load.sh"]
    core["common/core.sh"]
    pathssh["common/paths.sh"]
    headersh["common/header.sh"]
    gitp["common/git_prompt.sh"]
    targetssh["common/targets.sh"]
    aliases["misc/aliases.sh"]
    bashrc["shells/bash.sh"]
    zshrc["shells/zsh.zsh"]
    fishrc["shells/config.fish"]
    nurc["shells/config.nu"]
    kshrc["shells/ksh.sh"]
    osc52["shells/osc52.sh"]
    miscfiles["misc/<br/>colors · packages · theme.yml · vim.rc · nano.rc · tmux.conf"]
    configdir["config/ ($_HI_CONFIG_DIR)<br/>the overlay, as shipped"]
  end

  hish -->|"generates, ships over stdin"| bootrc
  hish -->|"ships (payload stream)"| loadsh
  overlay -->|"ships (second stream, lands in config/)"| configdir

  bootrc -->|sources| loadsh
  loadsh -->|sources| core
  loadsh -->|sources| headersh
  loadsh -->|"writes (from shells/*)"| grafts

  grafts -->|"carry the content of"| bashrc
  grafts -->|"carry the content of"| zshrc
  grafts -->|"carry the content of"| fishrc
  grafts -->|"carry the content of"| nurc

  core -->|sources| pathssh
  pathssh -->|"prefers, per file"| configdir
  bashrc -->|sources| core
  bashrc -->|sources| gitp
  bashrc -->|sources| aliases
  zshrc -->|sources| core
  zshrc -->|sources| gitp
  zshrc -->|sources| aliases
  fishrc -->|sources| pathssh
  fishrc -->|sources| aliases
  fishrc -->|"shells out to"| core
  fishrc -->|"shells out to"| headersh
  nurc -->|"shells out to"| core
  nurc -->|"shells out to"| headersh
  nurc -->|"shells out to"| gitp
  bootrc -.->|"sources (no-bash tier, via $ENV)"| kshrc

  aliases -->|"sources (overlay aliases.sh, last)"| configdir
  aliases -->|"runs (hi_copy)"| osc52
  miscfiles -->|"runs (vim.rc's yank autocmd)"| osc52
  hish -->|"runs (completion, on every TAB)"| targetssh
```

Three edges carry most of the design:

- **`hi.sh` never ships.** Everything on the target side has to work without
  it, which is why `load.sh` is the target's entry point and a peer of
  `hi.sh` at the tree root rather than a `common/` library.
- **fish and nu never source bash.** Their arrows to `core.sh`,
  `header.sh` and `git_prompt.sh` are *shell-outs* - one implementation of
  the header, palette and git segment, rented per call, instead of three
  kept in sync (GLOSSARY: nu session tier).
- **`osc52.sh` is only ever run.** Both `hi_copy` and vim's yank autocmd
  execute it as a file at `$_HI_OSC52`, which is why the tmux/screen/zellij
  wrapping lives in one place and the file cannot be merged into
  `aliases.sh`.

The grafts deserve one footnote: each carries a tree-exists guard
(GLOSSARY: graft crash guard), so an arrow into a deleted `/tmp` tree goes
quiet instead of erroring - the diagram's dashed reality after a hard kill.

### Docker / Podman containers

`hi <name>` also works against a running docker or podman container - if `<name>` isn't a `Host` in `~/.ssh/config` but is a running container (by name or ID, docker checked first), `hi` copies `~/hi.d` in and chainloads `load.sh` exactly like the ssh path, for an identical session (colors, prompt, aliases, vim/nano configs, etc). No armoring is needed here (`docker exec -i`/`podman exec -i` pass stdin through as raw bytes), and cleanup happens once you exit. Podman's CLI is close enough to docker's that it reuses the exact same command shapes, just against `podman` instead. The container needs `bash` for the full experience; without it, `hi` drops you into the best plain shell available (`zsh`/`fish`/`ksh`/`sh`) with our aliases and a warning.

### Windows hosts

`hi <target>` works against Windows OpenSSH targets too, at whatever level the target supports:

- **WSL, Git Bash, Cygwin or MSYS2 reachable on `PATH`**: the full experience (header, colors, git prompt, aliases) - same code path as any other ssh host.
- **Stock Windows OpenSSH with no `bash` at all**: `hi` falls back to a plain interactive PowerShell session (no hi.d styling - that's bash-only) instead of failing outright. It still costs one authentication: hi writes its bootloader over the first of two calls multiplexed on the _same ssh connection_, and a target where that write can't run `sh -c` at all is a target with no POSIX shell, which is exactly the case the fallback is for. A target with `DefaultShell` set to PowerShell directly lands in the same fallback.

**Installing hi _on_ Windows:** use WSL. The `.deb` from the releases page installs into a WSL distribution unchanged - `/etc/profile.d/hi.d.sh`, `/usr/bin/hi`, everything exactly as on any Debian - and WSL is where a Windows developer already using `ssh`/`docker`/`kubectl` most likely works anyway. Native channels (Scoop and friends) are assessed under [Windows channels](#windows-channels) and wait on a green client-side Windows CI job.

### Nomad allocations

`hi <alloc-id>` also works against a running Nomad allocation (matched by ID/prefix, checked after the ssh-host and docker/podman-container checks) - same idea, same session, same code path as docker. Since `nomad alloc exec` has no `docker cp`/`-e` equivalent, files are streamed in with `exec -i` + `cat >` and env vars are set through a `sh -c "export ...; exec ..."` wrapper. Multi-task allocations would need `nomad alloc exec -task <name>`, which `hi` doesn't pass through, so they need a single unambiguous task.

### Kubernetes pods

`hi <pod-name>` also works against a running Kubernetes pod (checked last, after ssh/docker/podman/nomad) - same idea again, using `kubectl exec` with `--` separating its own flags from the remote command. Uses whatever context/namespace your `kubectl` is currently pointed at; like Nomad's multi-task allocations above, a multi-container pod needs `-c <name>` to pick one, which `hi` doesn't pass through, so it needs a single unambiguous container (`kubectl` falls back to the pod's first container with a warning rather than failing outright).

### Compatibility

Three separate questions, because hi answers them at three different moments. **Legend:** ✅ exercised by a
suite on every run · 🟡 expected to work, nobody has proven it · ⚠️ works, reduced · ❌ not supported.

**1. The target's OS** — can hi land a session there at all?

| target OS | result | proven by |
| --- | --- | --- |
| Linux, glibc (Debian/Ubuntu/Fedora/Arch…) | ✅ full session | `tests/targets/ssh_test.sh`, on Debian bookworm |
| Linux, musl + busybox (Alpine…) | ✅ full session with `bash` installed, ⚠️ aliases-only without | `ssh_test.sh`, on Alpine 3.20 |
| macOS | 🟡 full session — bash 3.2 is what it ships, and the suite runs a real bash 3.2 target; the client half (BSD `sed`/`mktemp`/`base64`) is unit-tested only | `ssh_test.sh` bash-3.2 case; `.github/workflows/macos-e2e.yml` is written but has never run |
| WSL | 🟡 it is Linux, and the `.deb` installs into it unchanged | — |
| Windows, with Git Bash/Cygwin/MSYS2 on `PATH` | 🟡 full session, same code path as any ssh host | `.github/workflows/windows-e2e.yml`, written, never run |
| Windows, stock OpenSSH (`cmd.exe`/PowerShell) | ⚠️ plain PowerShell session, no hi styling — the fallback is deliberate, not a failure | same, never run |
| \*BSD, Solaris/illumos | 🟡 nothing in hi is Linux-specific past the header's `/proc` probes, which degrade to `?` | — |

**2. The target's _login_ shell** — the one sshd hands hi's command to, before any of hi runs.

| login shell | result | note |
| --- | --- | --- |
| `bash`, `sh`, `dash`, busybox `ash` | ✅ | the ordinary case |
| `zsh` | ✅ | |
| `fish` | ✅ | the reason hi's remote command is wrapped in `sh -c '…'`: fish parses neither `{ …; }` nor `\|\|` the way sh does |
| `ksh` (ksh93/mksh/pdksh), `tcsh`/`csh` | 🟡 | they only have to run one `sh -c` command; nothing tests them |
| `nushell`, `elvish`, `xonsh`, `ion`, `oil`/`osh` | 🟡 | same — one command, no shell-specific syntax in it |
| PowerShell, `cmd.exe` | ⚠️ | no POSIX shell to write the bootloader with, so hi falls back to a plain PowerShell session |

**3. The shell you end up _in_** — what hi hands you once it is on the target.

| session shell | result | note |
| --- | --- | --- |
| `bash` ≥ 3.2 | ✅ full: header, prompt, git status, aliases, editor configs | 3.2 is the floor because macOS still ships it |
| `zsh` | ✅ full | `shells/zsh.zsh` |
| `fish` | ✅ full | `shells/config.fish` |
| `sh`/`dash`/`ash` (no bash on the target) | ⚠️ aliases and a colored `user@host` prompt, with a warning saying so | no header and no git segment - those need bash |
| `ksh`/`mksh` (no bash on the target) | ⚠️ aliases, the colored prompt **and a live git segment** - no header | it reads `$ENV` as the `sh` tier does, plus `shells/ksh.sh`: ksh93 and mksh expand `$( )` when the prompt is _printed_, which is what lets the segment be live where busybox `ash` cannot have one. The header needs bash. `tests/targets/ssh_test.sh` renders the segment against a real mksh |
| `nushell` | ⚠️ header, prompt, git segment and a **subset** of the aliases | `shells/config.nu`. Needs `bash` on the target: nu can source none of `common/`, so the header, palette and git segment are rendered by shelling out to it, exactly as `config.fish` does. Chosen when nu is your _login_ shell or you name it in `_HI_SHELL_PREFERENCE` - never handed to someone whose login shell is bash. The alias subset, and what was left out and why, is the GLOSSARY's "nu alias subset" entry |
| `elvish`, `xonsh`, `ion`, `oil`/`osh` | ❌ | see below |
| PowerShell | ❌ | bash-only by design |

**Shells hi does not style yet.** Each would need its own rc in `shells/` (prompt, aliases, completion) plus a
tier in the fallback ladder in `hi.sh`'s `_hi_remote_suffix` and `load.sh`'s `load()`:

| shell | why it is not here | what it would take |
| --- | --- | --- |
| `elvish` | same shape, smaller audience | a `shells/rc.elv` |
| `xonsh` | Python, so the prompt and aliases would be a third implementation | a `shells/rc.xsh` |
| `ksh`/`mksh` | **all but the header** — a tier in the no-bash ladder, the POSIX prompt, the aliases, and `shells/ksh.sh`'s git segment | the header, and only the header. `common/header.sh` is bash, and this tier is defined by bash being absent, so it would have to be written a second time in POSIX and then kept in sync forever - the git segment was worth that, a second header is not |
| `tcsh`/`csh` | different rc syntax and no `$ENV` equivalent | its own rc, and honestly: ask whether anyone wants it |
| PowerShell | not a POSIX shell; the greeting hi prints there is the whole extent of it | a separate project, really |

If you use one of these as a *login* shell, hi still works — it lands you in bash (or the best of
zsh/fish/sh) for the session. It is only the session shell that is limited.

**If you use a shell framework**, hi lands you in your own login shell, so your framework loads normally —
that is what `_HI_SHELL_PREFERENCE`'s default (`login fish zsh bash`) means. The frameworks are tested
against hi in `tests/targets/framework_test.sh`: oh-my-zsh, powerlevel10k, starship and bash-it, each
asserting the session comes up with no shell errors and that hi neither changed zsh's array base under them
nor dropped their `PROMPT_COMMAND`.

## hi.d and the alternatives

An honest look at what else solves this problem, where hi.d is genuinely
different, and where one of the others is the better tool. Written for someone
deciding whether to use hi.d, not to sell it.

### The problem being solved

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

### The direct alternatives, side by side

| | **hi.d** | **[sshrc]** | **[xxh]** | **[kyrat]** | **[sshdot]** |
| --- | --- | --- | --- | --- | --- |
| Written in | POSIX/bash shell | shell | Python | bash | shell |
| Client needs | `bash` 3.2+, `base64` | bash, ssh | a Python install (pip/pipx/conda) or the portable binary | `bash` **≥ 4.0**, GNU coreutils | shell, ssh |
| Target needs | `base64`; `bash` for the full session | shell | Linux **x86_64 only** | shell | shell |
| Target OS | Linux (glibc + musl), macOS/BSD, Windows via WSL/Git Bash | broad | Linux x86_64 | Linux, macOS | broad |
| Installs on target | nothing | nothing | a portable shell + plugins under `~/.xxh` | nothing | nothing |
| Cleans up on exit | yes, automatically | leaves `/tmp` dir | no — delete `~/.xxh` yourself | yes, automatically | leaves files |
| Size ceiling | ~37KB gzipped, enforced by CI | **~64KB and the server may block you** | large — it uploads whole shells | small | none (that is its point) |
| Non-ssh targets | **docker, podman, nomad, k8s** | no | no | no | no |
| Can give you a shell the host lacks | no | no | **yes** | no | no |
| Maturity | pre-1.0, not yet published to any channel | **original deleted from GitHub**; [cdown's] fork is the maintained line, argv ceiling inherited | mature, active | quiet | quiet |

### Tool by tool

#### sshrc — the ancestor

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

#### xxh — the one that solves a harder problem

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
- **Weight.** xxh uploads shells; hi.d uploads ~37KB and a CI job fails if that
  number drifts more than a kilobyte from the badge.
- **Footprint.** xxh is hermetic but persistent — `~/.xxh` stays until you
  delete it. hi.d removes itself when the session ends.
- **Dependencies.** xxh needs Python on the client. hi.d needs a shell you
  already have.

#### kyrat — closest in spirit

[kyrat] is the nearest neighbour: a bash ssh wrapper, base64+gzip through the
command line, cleanup on exit, `KYRAT_SHELL` to pick bash/zsh/sh. If the table
above looks like a description of hi.d, that is because it nearly is.

The differences are narrow and concrete: kyrat requires **bash ≥ 4.0**, which
rules out macOS's system bash — the exact constraint hi.d contorts itself to
respect (no `mapfile`, no associative arrays, no namerefs, enforced by a grep in
the lint suite and a real bash-3.2 container in CI). kyrat spawns bash, zsh or
sh; hi.d styles bash, zsh, fish and nushell, and gives the POSIX tiers a colored
prompt and — for ksh/mksh — a live git segment. And kyrat is ssh-only.

#### sshdot

[sshdot] is sshrc without the size limit, achieved by not squeezing through the
command line. Narrower in scope than hi.d, and the honest summary is that it
solves the one problem it names.

### Adjacent tools, and how they compose

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

### What actually makes hi.d different

Two things, and it is worth being precise because the rest is degree, not kind.

**1. It is not an ssh tool.** Every alternative above is an ssh wrapper. `hi`
resolves a name through a ladder — ssh host, then docker container, then podman,
then nomad allocation, then kubernetes pod — and gives you the *same session* on
whichever it finds. `hi web-1` is your shell whether `web-1` is a `Host` in
`~/.ssh/config` or a pod in the namespace your `kubectl` points at. For anyone
who spends the day moving between a server and the containers on it, that is the
feature; nothing else in this space does it.

**2. It degrades in stated tiers rather than failing or lying.** The
[compatibility tables](#compatibility) above answer three separate questions —
can hi land a session here, what does your *login* shell have to survive, and
what do you actually end up in — and mark every cell as proven-by-a-suite,
expected, reduced, or unsupported. A target with no bash gets aliases and a
colored prompt and a warning saying so. A Windows OpenSSH host with no POSIX
shell at all gets a plain PowerShell session rather than an error. That is a
design stance, and it is why the honest cells (🟡 "nobody has proven it") are in
the table at all.

Secondary, but real: a per-user config overlay (settings, colors, packages,
aliases) that rides along without dirtying the tree, `hi --doctor` for when
something is slow, `--tmux` so a dropped connection detaches instead of
losing work, and the ability to detect a permanent `~/hi.d` on the target and
use it in place rather than shipping a copy.

### Where hi.d is the wrong choice

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

### Sources

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

## Installation/Usage

- `hi.d/scripts/install.sh` (re-run it any time; it repairs its own lines, even if hi.d moved) - before touching your shell rc files it validates your existing `~/.bashrc`, `~/.zshrc` and `~/.config/fish/config.fish` (whichever are installed) with each shell's own syntax checker, and asks whether to continue if any of them have issues
  - or `basher install ivylikethevine/hi.d` if [basher](https://github.com/basherpm/basher) manages your shell packages: it clones the repo and links `bin/hi` onto PATH (the shim exports `_HI_HOME` for the cellar location). The shell rc wiring, toggles and validation are still `scripts/install.sh`'s job - run it from the cloned package when you want the full setup
- reload your shell!
- run `hi_configure` any time afterward to revisit the feature toggle prompts - header, prompt, personal settings, git status, editors, aliases, header details, terminal width, and whether hi styles this machine too or only the hosts you say `hi` to - without touching the shell rc wiring. Answers land in `~/.config/hi.d/settings.sh`; see [Configuration](#configuration) below
- run `hi_check_configs` any time to just re-run that shell rc validation, without the rest of the install
- run `hi --help` (or `hi -h`) for the short version of all of this: the synopsis, the target resolution order, and every flag hi answers itself. `man hi` is the long version. Everything hi does not answer is passed to `ssh` unchanged
- run `hi --version` to see what is installed - the packaged version, or `git describe` in a checkout; the doctor and the connect header show it too
- run `hi --tmux <target>` to have the session live inside a named tmux on the target, so a dropped connection detaches instead of losing your work - reconnect with `hi --tmux <target>` again and you're back in it (`_HI_TMUX_ATTACH=1` makes it the default, `--no-tmux` turns it back off, `_HI_TMUX_SESSION` names the session). Offered only where hi.d is permanent on the target: a disposable tree is deleted when the session ends, and hi says so rather than leaving you a tmux pointing at nothing
- run `hi_doctor` (or `hi --doctor <target>`) when something is slow or failing: it reports the tree, the config overlay, every backend probed and timed with the same ceilings the header and completion use, and - with a target - which backend the name resolves to plus an ssh reachability/tooling check, all read-only
- configure `~/.ssh/config` tags via sshm
- [optional] pin specific colors in `~/.config/hi.d/colors` - everything else gets a color automatically. Copy `hi.d/misc/colors` there to start from the shipped defaults
  - run `hi_color_preview` to preview what every ssh host/your user resolves to
- [optional] copy `hi.d/misc/packages` to `~/.config/hi.d/packages` and edit it to your preferences
- say `hi`!
- [optional] modify `~/hi.d/misc/*` and `~/hi.d/shells/*` to your liking - though anything with an overlay (`settings.sh`, `colors`, `packages`, `tmux.conf`, `aliases.sh`) is better edited in `~/.config/hi.d/`, which keeps the checkout clean for `hi_update`
  - tip: `~/hi.d` is just a git checkout, so if you do edit it, push it to your own fork and clone that on your next device - same setup everywhere, and `hi_update`'s `git pull` keeps them in sync
- done with it? `hi.d/scripts/uninstall.sh` (aliased to `hi_uninstall`, and a one-line shim onto `install.sh --uninstall`) is the inverse of the install: it strips hi's lines back out of your rc files, removes the `settings.sh` it wrote, and unlinks `/usr/bin/hi`. It leaves the `hi.d` directory itself alone - and your `colors`/`packages`, which are yours - delete those yourself if you want them gone

---

### Verifying a release download

Releases ship a `SHA256SUMS`, signed build provenance, and a detached [minisign](https://jedisct1.github.io/minisign/)
signature over the sums (the offline half — no `gh`, no network, one static public key):

```sh
sha256sum -c --ignore-missing SHA256SUMS                        # the bytes match the release
minisign -Vm SHA256SUMS -P 'RWT-PLACEHOLDER-see-ROADMAP-secrets-and-keys'
gh attestation verify hi.d_*_all.deb --repo ivylikethevine/hi.d # which CI run built them
```

<!-- The -P value above is a placeholder until the first release's keypair is
generated - the minisign entry in docs/ROADMAP.md's "Secrets & keys" replaces it. -->

---

Usage: `hi foo` (just like ssh!)

---

Reminder - place local only changes after the "`# hi-config-end`" comment in the local files.

## Configuration

Your config lives **outside the checkout**, in `${XDG_CONFIG_HOME:-$HOME/.config}/hi.d/` (`$_HI_CONFIG_DIR`).
`colors` and `packages` there override the tree's copies, one file at a time - anything you haven't
overridden keeps tracking the default the tree ships, so `hi_update` still delivers changes to the rest.
`settings.sh` has no in-tree counterpart at all: `hi_configure` only ever writes it here.

| overlay file                 | overrides        | what it is                       |
| ---------------------------- | ---------------- | -------------------------------- |
| `~/.config/hi.d/settings.sh` | -                | what `hi_configure` writes       |
| `~/.config/hi.d/colors`      | `misc/colors`    | your color pins                  |
| `~/.config/hi.d/packages`    | `misc/packages`  | what the package check looks for |
| `~/.config/hi.d/tmux.conf`   | `misc/tmux.conf` | your tmux config                 |
| `~/.config/hi.d/aliases.sh`  | -                | your own aliases, sourced **after** `misc/aliases.sh` so yours win - additive, never a replacement, and in the same POSIX+fish subset |

This is what keeps configuring hi.d from dirtying the checkout (so `hi_update`'s `git pull` keeps applying
cleanly), and it is why the tree never has to be writable at all - it can be root-owned, installed by a package
manager. All of it rides along to every host you say `hi` to, in its own small archive unpacked over the
target's `misc/`.

Want history on it? `hi_overlay_init` makes `~/.config/hi.d` a git repo *in place* - from then on
`hi_configure` commits its own settings writes, `hi_doctor` reports the commit count, and a push remote is one
`git remote add` away. Entirely optional: an overlay you never init never hears about git. (Keeping the same
directory in chezmoi or yadm instead works just as well - see [hi.d and the alternatives](#hid-and-the-alternatives).)

Everything below is an environment variable, checked at the point it's used. `hi_configure` writes your answers to
`~/.config/hi.d/settings.sh`, which every shell sources ahead of `common/paths.sh`. It is a plain `#!/bin/sh`
script of `export NAME=value` lines, valid in sh, bash, zsh and fish alike.

You never have to use `hi_configure` - exporting any of these by hand works just as well, and takes precedence for
that shell.

### Features

Each is **on by default**; set it to `1` to turn that piece off.

| variable                 | turns off                                                                       |
| ------------------------ | ------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`     | the whole connect/disconnect header, every line of it                           |
| `_HI_DISABLE_PROMPT`     | the colored `user@host` prompt, leaving your shell's own                        |
| `_HI_DISABLE_PERSONAL`   | personal shell settings - history size, keybindings, completion tweaks          |
| `_HI_DISABLE_GIT_STATUS` | the git segment in the prompt                                                   |
| `_HI_DISABLE_EDITORS`    | the `vim`/`nano` config overrides                                               |
| `_HI_DISABLE_ALIASES`    | the personal aliases in `misc/aliases.sh` (not nu's subset - `alias` is parse-time there and cannot be gated; see `shells/config.nu`) |
| `_HI_DISABLE_OSC52`      | the OSC 52 clipboard - yanks in `vim` and the `hi_copy` alias                   |
| `_HI_DISABLE_TMUX`       | the `tmux` config override (offered on permanent installs only)                 |
| `_HI_DISABLE_LOCAL`      | all of the above **on this machine only** - hi still styles the hosts you visit |

`_HI_DISABLE_LOCAL` is the odd one out: it's for "I want my own machine left alone, but I still want hi everywhere
I connect to". It's told apart from a real session by `_HI_REMOTE_SESSION`, which `load.sh` exports on a target and
a local shell's own rc never does.

`_HI_DISABLE_OSC52` turns off the one feature that reaches back _through_ the connection: a yank in `vim` on a
target, or anything piped into `hi_copy`, is base64'd into an [OSC 52](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Operating-System-Commands)
escape and written to the tty, so your local terminal emulator - not the host - puts it on **your** clipboard. No X11
forwarding, no clipboard daemon, nothing installed on the target. Only the unnamed register is sent, so `"ay` stays
local. Terminal support varies (tmux needs `set -g allow-passthrough on`; zellij handles OSC 52 itself, so under
`$ZELLIJ` the escape goes through raw and unwrapped), which is why it's a toggle like
everything else; `shells/osc52.sh` is the whole implementation if you want to read what gets emitted.

### tmux

`misc/tmux.conf` is reached the way `vim.rc` is - through an alias, `tmux -f <conf>` - and overridden the same
way, by dropping your own `~/.config/hi.d/tmux.conf`. Beyond the usual defaults it does one thing specific to
hi: it appends the `_HI_*` variables to tmux's `update-environment`, so a window you open **after** attaching
gets a shell that can still find hi. Without it, `tmux new-window` inside a session on a remote box gives you a
bare prompt, because the tmux server predates the connection and knows nothing about `$_HI_HOME`.

Two limits worth stating plainly:

- `-f` is read when the tmux **server** starts, not when a client attaches. Attach to a server that was already
  running and none of the config applies - that's tmux's rule, not hi's. The `update-environment` half still
  works, since that's refreshed on every attach.
- The alias is defined **only where hi.d is permanent** - your own machine, or a target where
  `scripts/install.sh` has been run. On a disposable target hi deletes the tree on exit, and a detached tmux
  outlives the session; every shell inside it would wake up reading a directory that no longer exists. Plain
  `tmux` still works there, just without hi's config.

### Header details

Each is **on by default**; set it to `0` to hide that line. All are ignored when `_HI_DISABLE_HEADER=1`.

| variable               | hides                                                            |
| ---------------------- | ---------------------------------------------------------------- |
| `_HI_HEADER_BANNER`    | the `~~~ Connected [host] ~~~` line, on connect _and_ disconnect |
| `_HI_HEADER_TIMESTAMP` | the date/time line                                               |
| `_HI_HEADER_SYSINFO`   | the OS / CPU / RAM line                                          |
| `_HI_HEADER_IDENTITY`  | the git identity / containers / ssh key line                     |
| `_HI_HEADER_CHECK`     | the installed-packages check (`misc/packages`)                   |

### Everything else

| variable            | default         | what it does                                                                   |
| ------------------- | --------------- | ------------------------------------------------------------------------------ |
| `_HI_MAX_WIDTH`     | `80`            | terminal columns the header and banner are drawn to                            |
| `_HI_HOME`          | `$HOME`         | the **parent** of your `hi.d` directory - everything resolves `$_HI_HOME/hi.d` |
| `_HI_TARGETS_TTL`   | `5`             | seconds `hi <TAB>` reuses its target list for; `0` disables the cache          |
| `_HI_PROBE_TIMEOUT` | `2`             | seconds any one backend CLI gets, during completion and in the header          |
| `_HI_SSH_CONFIG`    | `~/.ssh/config` | where ssh hosts and their `# Tags:` comments are read from                     |
| `_HI_ASCII`         | by locale       | `1` forces ASCII stand-ins for the banner/prompt/packages glyphs (`^ ok x` for `↑ ✓ ✗`), `0` forces the glyphs; unset asks the locale, so a `LANG=C` target degrades cleanly instead of printing mojibake |
| `NO_COLOR`          | unset           | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything - header, prompts, git segment - without color, and hi ships your client-side choice to the target next to `_HI_ASCII` |
| `_HI_PROMPT`        | unset           | `starship` hands the prompt to [starship](https://starship.rs) when the target has it, keeping hi's header and aliases (bash/zsh/fish; nu keeps hi's prompt). Never auto-detected, and a target without starship silently keeps hi's own. hi does not ship starship - a multi-MB binary against a 37KB payload |
| `_HI_SHELL_PREFERENCE` | `login fish zsh bash` | which shell a session runs in: an ordered list of `bash`/`zsh`/`fish`/`nu`, plus `login` for "your own login shell". First one installed on the target wins; `bash` is the floor, since that is what `load.sh` needs to run at all. `nu` is never picked unless it is your login shell or you name it here |
| `_HI_PROMPT_END`    | per shell       | the character each prompt ends with, when you want the same one everywhere; the three below win over it |
| `_HI_PROMPT_END_BASH` | `\$`         | bash's prompt separator (`\$` is bash's own escape for "`$`, or `#` for root")                          |
| `_HI_PROMPT_END_ZSH` | `>`            | zsh's prompt separator - zsh prompt escapes work here, so `%#` behaves as it does anywhere else in `PS1` |
| `_HI_PROMPT_END_FISH` | `\|`         | fish's prompt separator; root still gets `#` regardless                                                 |
| `_HI_TERM_FALLBACK` | `1`             | on ssh targets missing a terminfo entry for your `TERM` (ghostty's `xterm-ghostty`, typically), swap it for `xterm-256color` before the session starts; `0` keeps the original `TERM` |

The last two exist because completion runs on **every TAB** and the header runs **before you get a shell**: a
docker daemon that's down or a `kubectl` pointed at a dead cluster would otherwise hang there with no upper bound.

## Testing

Run everything with `tests/test_runner.sh` (aliased to `hi_test` once installed) - it times each suite and prints a
colored pass/fail summary at the end:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
tests/test_runner.sh --host-report      # ...prefixed with what this machine is
tests/test_runner.sh --verbose          # every transcript, nothing collapsed
```

A passing suite's transcript collapses to one status line - `--verbose`
(`_HI_VERBOSE=1`) streams every suite's output live instead, which is what you want when a case is failing only
under the runner.

`--host-report` (`_HI_HOST_REPORT=1`) prints bash, the OS, whether the userland is GNU/BSD/busybox, which tree
`$_HI_HOME` resolves to, which backends answer and the lint tools' versions before the first suite runs - the
questions asked every time a suite passes on one machine and fails on another. CI passes it on every job.

Suite names: `aliases`, `alias_fallthrough`, `osc52`, `tmux`, `shellcheck`, `install`, `hi`, `header`, `core`,
`git_prompt`, `targets`, `paths`, `color_preview`, `load`, `test_lib`, `test_runner` are fast and dependency-free - they're the first thing CI
runs on every push/PR (the last two are the harness testing itself). `ssh`, `ssh_disconnect`, `ssh_relay`, `docker`,
`podman`, `nomad`, `kube`, `framework` are end-to-end:
they spin up real throwaway containers/clusters/agents and drive `hi.sh`'s actual connection paths against them, so
they're slower and need the relevant backend installed - each skips cleanly with a warning instead of failing if its
backend isn't available. CI runs `ssh`, `ssh_disconnect`, `ssh_relay` and `docker` as a second job once the fast ones
pass, which between them cover both halves of `hi.sh` (`_say_hi` and `_say_hi_container`). Every test script is also
directly executable on its own, e.g. `tests/shells/shellcheck_test.sh`.

**Relaying.** `hi` chains: from a session on B you can `hi C`, and the second hop is a full hi session like the
first. That works from a *disposable* session too, because `hi.sh` rides every bash-capable one - it is not in the
payload tar, but both transports write it to the target alongside the tree. `ssh_relay` is the proof: A → B → C,
the config intact on the final hop, and the cleanup traps firing on **both** B and C, on a clean exit and on the
link being killed mid-relay. The one tier that cannot relay is the container transport's bash-less fallback, which
ships `aliases.sh` alone and never loads `paths.sh` - there `hi` is simply not defined.

The tests are local-only: `tests/` is one of the directories `hi.sh` strips from the payload, so `hi_test` on a
target tells you so rather than running (the same goes for `hi_install`, `hi_configure`, `hi_check_configs` and
`hi_color_preview`). `hi_update` is the odd one out - it needs a `.git`, which is absent both in a hi session and
in an install a package manager laid down, so it says where to update instead of running `git pull` in a non-repo.

Any script here needs `_HI_HOME` set before it'll source correctly - point it at the _parent_ of your `hi.d`
checkout:

```sh
export _HI_HOME=/path/to/parent-of-hi.d
tests/test_runner.sh
```

## Packaging & releases

Everything needed to ship `hi` through a package manager. Nothing here publishes
on its own — the release workflow's publishing job waits on a manual approval,
and the AUR and the Homebrew tap are copies you make by hand. The **one-time
setup** each channel needs first (the `release` approval gate, branch
protection, the apk and minisign keypairs, the AUR deploy key, the tap token)
is not repeated here: it lives as a checklist, with the exact commands, in
[docs/ROADMAP.md](docs/ROADMAP.md)'s _GitHub repo settings_ and _Secrets & keys_
sections. Until those exist, a pushed `v*` tag publishes unattended and the
release ships unsigned sums.

Every workflow's `runs-on:` reads from a repo/org Actions variable first —
`vars.RUNNER_LABEL` (`vars.MACOS_RUNNER_LABEL` / `vars.WINDOWS_RUNNER_LABEL`
for the two OS-locked e2e jobs) — falling back to the matching GitHub-hosted
label when unset, so nothing changes until you set one. Jobs that install
apt packages or touch the Docker socket (`ci.yml`'s `test`, `bench`,
`packaging-smoke`, `e2e`, `e2e-backends`, and `coverage.yml`) need a
self-hosted runner that provides those; `macos-e2e.yml` and `windows-e2e.yml`
need a same-OS self-hosted runner if substituted.

### The one idea

`hi.sh` does not locate itself. It sources `${_HI_HOME:-$HOME}/hi.d/common/core.sh`, and everything else
resolves against `$_HI_ROOT="$_HI_HOME/hi.d"`. So every channel has to do two things: put the tree in a
directory literally named `hi.d`, and make sure `_HI_HOME` names that directory's **parent** before any
shell sources anything.

| channel | tree | how `_HI_HOME` gets set |
| --- | --- | --- |
| AUR, deb, rpm, apk | `/usr/share/hi.d` | `/etc/profile.d/hi.d.sh`, written by `install_tree` |
| Homebrew | `<keg>/libexec/hi.d` | the `bin/hi` wrapper, plus the rc line `install.sh` writes |

`scripts/install.sh --prefix /usr/share` (with `$DESTDIR`) does all of this and is the single decider of
what a packaged install contains — see `_HI_PACKAGE_CONTENTS` and `install_tree()` in that file. The AUR
PKGBUILDs and `mkpkg.sh` both call it. Only the Homebrew formula repeats the list, because a formula
cannot: `install_tree` hardcodes `/usr/bin` and `/etc/profile.d`, neither of which exists in a brew prefix.
`tests/scripts/packaging_test.sh` fails if that copy drifts.

### Layout

| path | what it is |
| --- | --- |
| `mkpkg.sh` | stages the tree, stamps it, then builds deb/rpm/apk with nfpm |
| `stamp.sh` | writes the version into a built tree's `hi.sh` and man page; every channel calls it |
| `bump.sh` | writes the version + real checksums into every manifest; `--check` verifies |
| `aur/hi.d/` | the versioned AUR package (`PKGBUILD`, `.SRCINFO`) |
| `aur/hi.d-git/` | the same package built from `main` |
| `homebrew/hi.d.rb` | the tap formula |
| `nfpm/nfpm.yaml` | deb/rpm/apk, built from the staged tree |

**The version stamp.** `packaging/stamp.sh` writes `_HI_RELEASE=` into the `hi.sh` a channel installs
and the version into the man page's `.TH` line. All four channels call it - `mkpkg.sh` for deb/rpm/apk,
both `PKGBUILD`s' `package()`, the formula's `install` - so there is one implementation rather than four
seds. It cannot live in git: `bump.sh` runs only after the tag exists (its checksums need the tarball),
so a committed stamp would always be one release stale in the very tarball Homebrew and the AUR build
from. A git checkout answers `hi --version` with `git describe` instead, so the committed line stays
empty. The formula passes `--date <version>` because a brew build has no `SOURCE_DATE_EPOCH` to date the
page by, and `stamp.sh` refuses to guess one. `tests/scripts/packaging_test.sh` guards all of it.

### Cutting a release

```bash
git tag v1.0.0 && git push origin v1.0.0
```

That is the whole local ceremony. The tag never moves: `bump.sh` checksums the GitHub tarball, which only
exists once the tag is pushed — so the release workflow runs the bump itself, against the tarball the tag
just created, instead of requiring a pre-tag bump and a force-retag to reconcile the two.

1. `git tag v1.0.0 && git push origin v1.0.0` — the tarball now exists and the workflow starts.
2. The `build` job runs the fast suites, then `bump.sh 1.0.0` (fetches the tarball, writes `pkgver`,
   `b2sums`, the formula `url`/`sha256`, and the derivable `.SRCINFO` lines), verifies with
   `bump.sh --check`, runs the packaging drift guards against the fresh manifests, and builds the
   deb/rpm/apk plus a `SHA256SUMS` over them. Nothing has published yet.
3. Approve the `publish` job in the Actions UI — this is your review point, over the exact artifacts the
   build produced. Packages, `SHA256SUMS`, and manifests land on the release, and the regenerated
   manifests are committed back to `main` (they are consumed from the AUR/tap repos, not from inside the
   tarball, so they don't need to be in the tagged tree).
4. Both channels update themselves once their secrets exist: the tap gets a PR (`HOMEBREW_TAP_TOKEN`), the
   AUR gets a push (`AUR_SSH_KEY`). Until then, copy the manifests from the release (or from `main`) by hand,
   per the sections below.

`bump.sh 1.0.0` still works by hand if CI is ever unavailable (`--tarball <file>` skips the
download), and `bump.sh --check 1.0.0` stays useful locally to confirm the manifests match a cut release.

**Release notes are the PR titles.** The publish job's `gh release create --generate-notes` drafts the
notes from the PR titles merged since the last tag — there is no separate notes file to write. The
discipline that makes this good enough: title PRs the way you'd want them read in release notes, and skim
`gh pr list --state merged` before tagging to retitle anything that wouldn't. Revisit git-cliff only if
the generated notes start needing curation.

### Publishing each channel

Every channel below is gated on the manual approval in `release.yml`, and two of them (the AUR and the tap)
are pushed by CI once their secrets exist — the checks each section describes are still yours to run first.

#### AUR

Not done yet — no account, no submission. When you do, run the pre-submit gate below for **each**
package — `aur/hi.d-git` today, and `aur/hi.d` once v1.0.0 exists. namcap is the hard step, not a
suggestion: push nothing while either its `PKGBUILD` or its built-package run has complaints.

```bash
cd packaging/aur/hi.d-git        # then again in packaging/aur/hi.d
makepkg -f                       # builds it
namcap PKGBUILD                  # lints the recipe itself
namcap ./*.pkg.tar.zst           # catches hardcoded paths and bad permissions
pacman -Qlp ./*.pkg.tar.zst      # /usr/share/hi.d/..., /usr/bin/hi, /etc/profile.d/hi.d.sh
```

**What a clean run looks like.** `namcap PKGBUILD` is silent. `namcap` on the built package prints exactly
three warnings, all of them namcap being unable to read shell scripts, all correct to keep:

```text
W: Dependency fish detected but optional (programs ['fish'] ...)   # optdepend on purpose - hi works without it
W: Dependency zsh detected but optional (programs ['zsh'] ...)     # same
W: Dependency included, but may not be needed ('openssh')          # hi runs ssh; no shebang says so
```

Anything else is a real finding. (`coreutils` used to appear here too and was dropped from `depends` - it is
in `base`, which packaging guidelines say to assume.)

**The end-to-end check**, which is what caught the `hi.d-git` package shipping no version stamp:

```bash
docker run --rm -v "$PWD:/pkgs:ro" archlinux:base bash -c '
  pacman -Sy --noconfirm openssh && pacman -U --noconfirm /pkgs/*.pkg.tar.zst
  bash -lc "echo \$_HI_HOME; command -v hi; hi --version"'
```

Both packages have been run through all of this against a local clone (the only substitution being
`source=`, since the repo is not published yet): built, linted, installed into a clean Arch container,
exercised, and removed with nothing left behind.

Then push `PKGBUILD` + `.SRCINFO` (only those two files) to `ssh://aur@aur.archlinux.org/hi.d-git.git`.
**This first push is the manual one** — it is where namcap actually gates. After it, `release.yml`'s `aur`
job pushes the versioned `hi.d` package on every release, given the `AUR_SSH_KEY` secret; `hi.d-git` has no
version to bump and is never touched by CI.
`hi.d-git` first — it works today with no tag — and the versioned `hi.d` once v1.0.0 exists.

Never submit with `b2sums=('SKIP')` on the versioned package. `SKIP` is correct and expected on
`hi.d-git`, whose source is a git ref.

#### Homebrew tap

A tap is just a GitHub repo named `homebrew-tap` with a `Formula/` directory. Copy
`packaging/homebrew/hi.d.rb` to `Formula/hi.d.rb` there and `brew install ivy/tap/hi.d` works — no review,
no approval. Before copying, all three must pass — `brew audit --strict` is a hard gate here precisely
because nothing else reviews a tap:

**The copy is automated, the checks are not.** `release.yml`'s `tap` job (behind the same `release`
approval as `publish`) opens a PR against `<owner>/homebrew-tap` with the freshly regenerated formula and
the three commands below as its checklist. It needs a `HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT
scoped to that repo with contents + pull-requests write. Without the secret the job says so and does
nothing, which is the state until the tap repo exists. Merging the PR is still yours, and so is running
these first:

```bash
brew install --build-from-source ./packaging/homebrew/hi.d.rb
brew test hi.d
brew audit --strict --new hi.d
```

`brew audit` needs a *named* formula, so it wants the formula in a tap - `brew tap-new ivy/tap`, copy the
file into its `Formula/`, then `brew audit --strict --new ivy/tap/hi.d`. Passing a path is refused outright.

**What a clean run looks like** (this has been run, in the `homebrew/brew` container, against a local
tarball - the only substitution being `url`/`sha256`, since the repo is not published): install and test
both exit 0, and audit reports only these two, which are the unpublished repo and nothing else:

```text
* The homepage URL https://github.com/ivylikethevine/hi.d is not reachable (HTTP status code 404)
* HEAD: The URL https://github.com/ivylikethevine/hi.d.git is not a valid Git URL
```

Two real findings came out of that first run and are fixed: the description had to start with a capital,
and `uses_from_macos "openssh"` was rejected - that macro is for formulae macOS provides *to Homebrew*, and
openssh is not one. The formula now declares no dependencies at all, which is correct: `ssh` and `base64`
ship with macOS and with any Linux that would install this.

A mac is still worth using before the first publish - the container is Linux, so it exercises Linuxbrew's
paths rather than a keg under `/opt/homebrew` - but nothing about the formula itself is unverified now.

#### basher (shipped) and fisher (assessed, didn't fit)

The two shell-native channels need no manifest here and nothing on release
day - both install straight from the repo at a ref.

**basher** works today: `basher install ivylikethevine/hi.d`. Its contract is
a `package.sh` at the *repo root* - a name basher dictates, and why the
packaging directory's build script is `mkpkg.sh` - whose
`BINS=bin/hi` names what links onto PATH. basher links by filename with no
rename support, which is why `bin/hi` exists at all: a POSIX shim that
resolves through basher's cellar symlink, exports `_HI_HOME` (a basher clone
does not live at `~/hi.d`), and refuses a clone not named `hi.d`. The shim
and the refusal are unit-tested in `tests/shells/hi_test.sh`.

**fisher** was assessed and deliberately not shipped. fisher installs by
copying `functions/`, `completions/` and `conf.d/` out of a repo into the
user's fish config and ignores everything else; hi.d has none of those
directories, and its `shells/config.fish` is a client of the whole tree - it
reaches `common/` by `$_HI_HOME` path and shells out to bash for the header,
palette and git segment. A fisher install would copy the fish half and leave
every one of those paths dangling: a plugin that installs green and does
nothing. "It didn't fit" is the recorded outcome; fish users get the same
full setup as everyone else through `scripts/install.sh` or any package
channel.

#### deb / rpm / apk

Built by `mkpkg.sh` and attached to the GitHub Release. Users install the file:

```bash
sudo apt install ./hi.d_1.0.0_all.deb
```

The apk is signed (once the `APK_SIGNING_KEY` secret exists — see the ROADMAP checklist) with a key apk
verifies against `/etc/apk/keys/`, so Alpine users install the public key once and never pass
`--allow-untrusted`:

```sh
wget -O /etc/apk/keys/hi.d.rsa.pub \
  https://raw.githubusercontent.com/ivylikethevine/hi.d/main/packaging/apk/hi.d.rsa.pub
apk add ./hi.d_1.0.0_noarch.apk
```

A quirk worth knowing: the apk's contents are enumerated per `_HI_PACKAGE_CONTENTS` member in
`nfpm.yaml` instead of riding the `type: tree` entry deb/rpm use — nfpm 2.47.0's tree walker writes
directory modes apk-tools rejects outright. The packaging suite keeps the copy honest, and CI's
packaging-smoke installs the signed apk on Alpine every PR so the channel can't silently regress.

No `apt upgrade` — that is the trade for not maintaining a repository. Revisit
[OBS](https://en.opensuse.org/openSUSE:Build_Service_Debian_builds) only if people start asking for a repo
to subscribe to.

### Windows channels

An assessment, not a plan. Nothing in this section is built. It is the Windows counterpart to the
"Shipping hi.d" distribution review, which covered Arch, macOS and Debian/Ubuntu and never looked at
Windows at all.

#### The question is which POSIX layer, not whether to port

`hi.sh` is `#!/bin/bash` with `set -euo pipefail`, and it shells out to `tar`, `openssl`, `mktemp`, `awk`,
`sed`, `find`, `du`, `hostname` and `ssh`. Native Windows has none of that. So there is no version of this
where a Windows package installs "hi.d" on its own — every channel below really installs *hi.d plus a
dependency on somebody's POSIX userland*, and the channels differ mainly in which one they lean on and how
honestly they admit it.

Worth being clear about what already works, because it is easy to conflate:

- **Windows as a target** is done — the [Windows hosts](#windows-hosts) section above covers it: WSL, Git
  Bash, Cygwin or MSYS2 on the target's `PATH` gets the full session, and stock Windows OpenSSH with no
  bash falls back to a plain PowerShell session over the same connection.
- **Windows as a client** — someone sitting at a Windows box typing `hi prod` — is the gap this section
  is about.

#### The prerequisite: the CI that exists tests the other half

There is now one Windows job, `.github/workflows/windows-e2e.yml`, and it is not the one the channels
below wait on. It exercises Windows **as a target**: a stock OpenSSH server with no bash on its `PATH`,
driven from the runner's own Git Bash, asserting the cmd `||` ladder lands in the PowerShell fallback. It
is dispatch-only and has never been run.

What is still missing is the client-side job: **a `windows-latest` job running the fast suites under Git
Bash**, which is what would tell us whether hi.d works when Windows is the machine you type `hi` on. It
should land before any Windows channel does. GitHub's `windows-latest` runners ship Git for Windows, so
`shell: bash` in a workflow step is Git Bash, and the fast group is pure shell with no daemons. It is a
cheap job, and what it would tell us is currently unknown:

- whether `_hi_read_lines`, `_hi_repeat` and the rest behave under MSYS2's bash (they should — it is bash
  4.4+, well past the 3.2 floor)
- whether the path handling survives `C:`-style paths leaking into `$_HI_HOME` through `cygpath`
  translation
- whether `install.sh`'s rc-file rewriting finds the right `~/.bashrc` (Git Bash's `$HOME` is not always
  `%USERPROFILE%`)
- whether `hi.sh`'s `tar`/`openssl` payload path works with MSYS2's binaries and CRLF-safe pipes

Until that job exists and is green, a Windows package would ship untested by construction.

#### One thing already fixed

`config_hi`'s `sudo ln -sfn "$_HI_LAUNCHER" /usr/bin/hi` has no meaning under Git Bash: there is no `sudo`,
and `/usr/bin` is a virtual path inside the Git for Windows installation that a package has no business
writing to. `scripts/install.sh --no-link` now skips that step. Windows was the third consumer to need it,
after Homebrew and any distro package.

#### The channels

##### WSL — the recommendation

Not a channel at all, which is the point. The `.deb` built by `packaging/mkpkg.sh` installs into WSL
unchanged, `/etc/profile.d/hi.d.sh` works exactly as it does on any Debian, and the user gets the real
thing rather than an approximation. It is also where a Windows developer who already uses `ssh`, `docker`
and `kubectl` is most likely to be working.

Cost: one paragraph in this README. Reaches: most of the plausible audience.

##### Scoop — the only native channel worth building

A bucket is a GitHub repo of JSON manifests with no review queue — structurally the same deal as a
Homebrew tap, which is why it is the cheapest native option. Scoop installs to
`~/scoop/apps/hi.d/current`, so the writability problem is as soft as Homebrew's.

What it needs beyond a manifest:

- `"depends": "git"` — Git for Windows is what supplies bash, `openssl`, `tar` and `ssh`.
- A `hi.cmd` shim, because Scoop's own shims cannot execute a bash script directly. It has to translate the
  install path with `cygpath -u`, export `_HI_HOME` to the parent of the `hi.d` directory, and `exec`
  `hi.sh` — the same job the Homebrew formula's `bin/hi` wrapper does, in a language that makes it harder.
- The shim is the part that will actually break, and it is exactly the part no current CI job exercises.

Verdict: **start here if anything gets built, but only after the client-side Windows CI job is green.**

##### winget — reaches the most people, costs the most per release

Microsoft-blessed and preinstalled on Windows 11, so it has by far the widest reach. The costs are real: it
wants an installer artifact (a `zip` with a portable nested installer is the workable shape for a script
project), each version is a YAML manifest PR into `microsoft/winget-pkgs`, and there is a moderation queue
plus automated validation. Reasonable once hi.d has actual Windows users; premature before that.

##### Chocolatey — no advantage over the two above

A `.nuspec` plus a `chocolateyInstall.ps1`, behind a moderation queue, with a hard dependency on Git for
Windows to supply the userland. It reaches an audience that overlaps heavily with Scoop's and asks for more
per release. `misc/packages` already probes for `choco`, which is the only argument in its favour and not a
strong one.

##### MSYS2 — the best technical fit, the narrowest audience

MSYS2 is a real POSIX userland with a real package manager, so hi.d would work there with no shim and no
dependency hand-waving at all. Two things make it interesting beyond that: its packages are built from
PKGBUILDs in Arch's format, so `packaging/aur/hi.d/PKGBUILD` is most of the work already done, and its
`/etc/profile.d` is real, so the `_HI_HOME` export lands the same way it does on Linux.

Against it: submission goes through `MSYS2/MSYS2-packages` with review, and the audience is small and
technical enough to be comfortable cloning the repo.

##### Cygwin — skip

`cygport` and a maintainer slot, for an audience that has largely moved to WSL or MSYS2.

##### A native PowerShell port — skip, emphatically

Worth naming only to rule out. hi.d is ~2,000 lines of shell whose entire value is that the *same* config
lands on every host; a second implementation in PowerShell would be a second thing to keep in sync forever,
and it still could not run `load.sh` on the target.

#### Side by side

| channel | reaches | needs | auto-updates | setup | per release |
| --- | --- | --- | --- | --- | --- |
| WSL | anyone running WSL | nothing new — the `.deb` | no (same as any deb) | a README paragraph | nothing |
| Scoop | Scoop users | Git for Windows + a `.cmd` shim | yes, `scoop update` | a bucket repo + the shim | bump version + hash |
| winget | all of Windows 11 | a zip/portable artifact | yes, `winget upgrade` | manifest PR + moderation | a PR per release |
| Chocolatey | choco users | Git for Windows + PowerShell script | yes, `choco upgrade` | nuspec + moderation | a push per release |
| MSYS2 | MSYS2 users | nothing — real POSIX | yes, `pacman -Syu` | PKGBUILD + review | bump in their repo |
| Cygwin | few | cygport | yes | maintainer slot | per release |

#### What I would do

1. **Document WSL as the supported Windows path.** Done — it costs a paragraph, and it is honest about
   what hi.d is.
2. **Add the `windows-latest` Git Bash CI job** — the client-side one, running the fast suites. This is
   the actual prerequisite, and it has value even if no Windows package is ever published. (The
   target-side `windows-e2e.yml` is written but is a different job, and has not been dispatched yet.)
3. **Revisit Scoop once that job is green and someone asks.** The manifest is an afternoon; the shim is the
   risk, and the CI job is what turns that risk into something observable.
4. **Leave winget, Chocolatey, MSYS2 and Cygwin until there is demand**, and prefer MSYS2 over the other
   three if the demand comes from people who already have a POSIX userland.

### Verifying a packaged build locally

```bash
tests/test_runner.sh packaging install header   # the offline drift guards
packaging/mkpkg.sh --stage-only               # inspect exactly what ships
find dist/staging \( -type f -o -type l \)
packaging/mkpkg.sh                            # needs nfpm on PATH
dpkg-deb -c dist/hi.d_*_all.deb
```

#### Reproducibility

The same commit builds byte-identical deb/rpm/apk: `mkpkg.sh` exports `SOURCE_DATE_EPOCH` (HEAD's
commit time, respecting a value you set per the [reproducible-builds.org](https://reproducible-builds.org/docs/source-date-epoch/)
convention), clamps the staged tree's mtimes to it, and nfpm 2.47.0 stamps everything else it controls
from the same variable. CI's packaging-smoke job enforces this with a double build on every PR; to check
it locally (sequentially — nfpm.yaml hardcodes `./dist/staging`, so `--outdir` can't run two side by side):

```bash
packaging/mkpkg.sh && mv dist dist.first
packaging/mkpkg.sh && diff dist.first/SHA256SUMS dist/SHA256SUMS
```

One caveat: CI pins nfpm 2.47.0 (`.github/actions/setup-tool/tools.txt`) while `mkpkg.sh` takes whatever
nfpm is on PATH — a different local nfpm can produce different (still internally reproducible) bytes.

The honest end-to-end check for the `/etc/profile.d` snippet, which is the part no unit test can prove:

```bash
docker run --rm -it -v "$PWD/dist:/dist" debian:stable \
  bash -lc 'apt-get update -qq && apt-get install -y /dist/hi.d_*_all.deb && echo "$_HI_HOME" && hi'
```

### After installing from a package

The tree is root-owned and holds nobody's settings. Each user runs, once:

```bash
/usr/share/hi.d/scripts/install.sh --no-link
```

`--no-link` skips the `/usr/bin/hi` symlink, which the package already owns. Their answers go to
`~/.config/hi.d/`, never into the tree, which is what lets a root-owned checkout work at all.
`hi_update` will correctly refuse to `git pull` and tell them to update through their package manager.

## More docs

- [docs/GLOSSARY.md](docs/GLOSSARY.md) - the named idioms the code's `GLOSSARY:` comment tags point at; load-bearing for reading `common/`, and drift-checked by the lint suite
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) - the test harness and how a change should arrive (PR titles become release notes)
- [docs/SECURITY.md](docs/SECURITY.md) - reporting, and what hi touches on a target
- [docs/ROADMAP.md](docs/ROADMAP.md) - what is planned, what each item is blocked on, and the one-time setup the release channels wait on
- [docs/tldr.md](docs/tldr.md) - the draft tldr-pages submission; [docs/hi.1](docs/hi.1) is the man page every package installs

### File list

| file                                            | what it does                                                                                                                                                           |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hi.sh`                                         | runs on the client: pick the target, copy hi.d, chainload `load.sh`                                                                                                    |
| `load.sh`                                       | runs on the target: header, rc grafting, shell handoff, cleanup                                                                                                        |
| `common/paths.sh`                               | every path hi uses (the only file fish and sh both source)                                                                                                             |
| `common/core.sh`                                | the entry point every bash/zsh script sources: settings, paths, palette, `_hi_cecho`, color resolution                                                                 |
| `common/header.sh`                              | the connect/disconnect banner, shared by every shell, plus the `misc/packages` check it ends with                                                                      |
| `common/git_prompt.sh`                          | bash/zsh git prompt, matching fish's built-in `fish_vcs_prompt`                                                                                                        |
| `common/targets.sh`                             | every `hi` target (ssh/docker/podman/nomad/kube), for all three completions - cached and timeout-bounded                                                               |
| `shells/osc52.sh`                               | stdin to the *client's* clipboard over OSC 52 - tmux/screen passthrough, raw under zellij - behind `hi_copy` and `vim.rc`'s yank autocmd, off via `_HI_DISABLE_OSC52=1` |
| `shells/bash.sh`                                | bash config                                                                                                                                                            |
| `shells/zsh.zsh`                                | zsh config                                                                                                                                                             |
| `shells/config.fish`                            | fish config                                                                                                                                                            |
| `misc/aliases.sh`                               | personal aliases shared by bash, zsh and fish - freely editable, off wholesale via `_HI_DISABLE_ALIASES=1`                                                             |
| `misc/vim.rc`, `misc/nano.rc`, `misc/theme.yml` | vim, nano and eza configs                                                                                                                                              |
| `misc/tmux.conf`                                | tmux config, reached via the `tmux` alias - override in `~/.config/hi.d/tmux.conf`, off via `_HI_DISABLE_TMUX=1`                                                        |
| `misc/packages`                                 | default for the packages check, as `cmd:priority[,alternative:priority]` - override in `~/.config/hi.d/packages`                                                       |
| `misc/colors`                                   | default color pins for hostnames/usernames/hosttags - override in `~/.config/hi.d/colors`                                                                              |
| `scripts/install.sh`                            | configure the local shells, install, update and uninstall - `--prefix`/`$DESTDIR` for packagers                                                                        |
| `scripts/uninstall.sh`                          | one-line shim onto `install.sh --uninstall` (`hi_uninstall`)                                                                                                           |
| `scripts/color_preview.sh`                      | preview what every ssh host/user resolves to (`hi_color_preview`)                                                                                                      |
| `scripts/doctor.sh`                             | pre-flight report: tree, config, timed backend probes, and a target's resolution + ssh reachability (`hi_doctor`, `hi --doctor`)                                       |
| `tests/test_runner.sh`                          | unified runner - times and summarizes every test below (or a chosen subset) (`hi_test`)                                                                                |
| `tests/test_lib.sh`                             | the whole suite skeleton: asserts/counters, scratch dir, skip preamble, probe commands, poll/pty helpers                                                               |

The test suites are deliberately not repeated here: each suite's opening
comment block says exactly what it covers, and `tests/test_runner.sh --list-paths`
prints the live list — group, name, and path — so the truth can't drift the
way a second copy of it in this table once did.

#### Hostname, username, and group/tag colors

Every username and hostname gets a color automatically, deterministically derived from its name - there's nothing to generate and nothing that can go missing. To pin a specific color instead, add a line to `~/hi.d/misc/colors` (`username,root,red` / `hostname,prod-db,yellow` / `hosttag,desktop,green`); `hosttag` entries match the _leftmost_ tag in a `# Tags: ...` comment placed directly above a `Host` line in `~/.ssh/config`. Run `hi_color_preview` any time to preview what every ssh host and your user currently resolve to, rendered in their actual color.

##### Built from/with/in mind

- [sshrc](https://github.com/cdown/sshrc) - _from_ - (became `hi.sh`)
- [sshm](https://github.com/Gu1llaum-3/sshm) - _with_ - (optional, but _highly_ recommended to configure `~/.ssh/config` hosttags)
- [bat](https://github.com/sharkdp/bat) - _in mind_ - (essentially my reason to get the aliases.sh fallthrough logic to work as portably as possible)
- [fish](https://github.com/fish-shell/fish) - _with_ - (my preferred shell because its defaults/built-ins are extremely easy to understand, but one that is not POSIX-compliant)

##### AI Usage

Heavily inspired by: [Dictionarry/Profilarr's AI Transparency Statement](https://v2.dictionarry.dev/ai-transparency)

This code originally started as entirely code written by [me](https://github.com/ivylikethevine), but I have used generative AI to write large parts of it. Regardless, all of the code in this repository is my _responsibility_. AI is a tool, not an owner of a project. I have personally understood, reviewed, and approved all of the AI generated code in this repository. _Mainline releases_ have the same level of accountability to me as any code I write and publish.

##### Publishing Order

1. AUR
2. deb/rpm/apk
3. Homebrew
4. basher
5. fisher?
6. scoop?