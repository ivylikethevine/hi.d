# hi.sh -> sshrc supercharged

![CI (main)](https://github.com/ivylikethevine/hi.d/actions/workflows/ci.yml/badge.svg)
![CI (develop)](https://github.com/ivylikethevine/hi.d/actions/workflows/ci.yml/badge.svg?branch=develop)
[![Coverage](https://github.com/ivylikethevine/hi.d/actions/workflows/coverage.yml/badge.svg)](https://github.com/ivylikethevine/hi.d/actions/workflows/coverage.yml)
![ssh payload](https://img.shields.io/badge/ssh_payload-35KB_gzipped-4c1)
![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![shells](https://img.shields.io/badge/shells-bash%20%7C%20zsh%20%7C%20fish%20%7C%20nu%20%7C%20sh-blue)
![targets](https://img.shields.io/badge/targets-ssh%20%7C%20docker%20%7C%20podman%20%7C%20nomad%20%7C%20k8s-8A2BE2)
![license](https://img.shields.io/badge/license-MIT-blue)

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

![hi connecting to a container: banner, header, packages check, colored prompt, and the cleanup on exit](docs/demo.gif)

More of these — every backend (ssh with a permanent install, docker, podman, nomad, kubernetes) across a
variety of shells on both sides — in [docs/demos.md](docs/demos.md).

Wondering how this compares to `sshrc`, `xxh`, `kyrat` or just using `chezmoi` — including where one of
those is the better tool? [docs/comparison.md](docs/comparison.md).

The payload badge above is enforced, not aspirational: the bench suite rebuilds the real payload
(`$_HI_PAYLOAD` only - no tests, docs or CI ever ride along) and fails CI when the badge drifts more
than a kilobyte from the truth.

## Requirements

- **Client**: `bash` and `base64` (for ssh targets - armors the bootstrap payload through the login shell; coreutils, busybox, macOS/BSD and Git Bash all ship one) or `docker`/`podman`/`nomad`/`kubectl` for the container/alloc/pod backends.
- **bash version**: 3.2 or newer, on both ends. That is what macOS still ships, so hi stays clear of every bash-4-only construct - no `mapfile`/`readarray` (`_hi_read_lines` in `common/core.sh` does that job), no associative arrays, no namerefs, no `${x,,}`. Two things enforce it: `tests/shells/shellcheck_test.sh` greps for those constructs, and `tests/targets/ssh_test.sh` runs a real bash 3.2 target in a container and fails if the session prints so much as one shell error.
- **Target**: `base64` for ssh targets (effectively everywhere - coreutils, busybox, macOS/BSD); nothing extra for container/alloc/pod targets. `bash` gets you the full experience (header, colors, git prompt, aliases, vim/nano configs); without it `hi` still lands you in the best available shell (`zsh` > `fish` > `ksh` > `sh`) with the aliases and, on the POSIX tiers, a colored prompt - rather than failing outright.
- Everything else (client and target) is plain POSIX/bash/zsh/fish shell - no compiled artifacts, no package manager, no build step.

### How it works

1. `hi.sh` runs on the client. It archives `hi.d/` and sends it to the target. What it leaves out is `hi.sh` itself, `.git`, `scripts/`, `tests/`, `docs/`, `.github/`, this README and the editor/tooling dotfiles - see `$_HI_PAYLOAD` at the top of `hi.sh` for the authoritative allow list. The target unpacks it into a `/tmp` directory. `_HI_ROOT` is `$INSTALL_DIR/hi.d` on the client and `$_HI_HOME/hi.d` on the target.
   Your own `settings.sh`, `colors`, `packages`, `tmux.conf` and `aliases.sh` live outside the tree (see [Configuration](#configuration)), so they follow in a second, much smaller archive unpacked over the target's `misc/` - `$_HI_OVERLAY_FILES` in `hi.sh`. Nothing is sent if you haven't overridden anything.
   The whole thing - the tar, `hi.sh` and the bootloader, each base64-armored - is assembled into one script, armored again, and written to the target over the **stdin** of the first of two calls multiplexed on a single ssh connection; the second call runs it. Not as a command-line argument, which is what it used to be: Linux caps a single argv entry at 128KB regardless of `ARG_MAX`, and the payload had grown within a few kilobytes of that. The size hi prints on connect is that armored total - what the connection actually carries, roughly 4/3 of the gzipped payload the badge above measures.
2. On the target, `$_HI_ROOT/hi.bashrc` sources `$_HI_ROOT/load.sh` and calls `load`.
3. `load.sh` prints the header, appends hi's shell configs to the host's own rc files, and starts a session in **your login shell** when hi styles it (bash, zsh or fish), falling back to whichever of `fish > zsh > bash` the target has. `_HI_SHELL_PREFERENCE` is that rule as a setting - see [Configuration](#configuration). The `zsh > fish > ksh > sh` order quoted elsewhere is the **no-bash fallback**, ranking what's left when bash turned out to be missing.
4. When the session ends, `load.sh`'s `trap` strips those additions back out, and the `/tmp` directory is removed by the cleanup trap `hi.sh` set up on connect.
5. `hi <target> 'some command'` skips the interactive session and just runs the command there, like `ssh` does.

The setup in steps 1-2 is plain POSIX and runs under `sh`, so it works even if the target has no `bash` at all - `hi` still copies the whole of `~/hi.d` over in that case, but hands off to the best plain shell available (`zsh`/`fish`/`ksh`/`sh`) with just our aliases loaded, instead of the full `load.sh` experience, which needs `bash`.

For ssh targets specifically, `hi` first checks (over the same connection, so it costs no extra authentication) whether the target already has its own permanent `~/hi.d` - i.e. `scripts/install.sh` has been run there. If so, it skips the archive/copy step entirely and points `_HI_ROOT` straight at that existing copy instead, leaving it in place when the session ends.

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, etc. - anything in this directory is copied to every host you say `hi` to._**

### Docker / Podman containers

`hi <name>` also works against a running docker or podman container - if `<name>` isn't a `Host` in `~/.ssh/config` but is a running container (by name or ID, docker checked first), `hi` copies `~/hi.d` in and chainloads `load.sh` exactly like the ssh path, for an identical session (colors, prompt, aliases, vim/nano configs, etc). No armoring is needed here (`docker exec -i`/`podman exec -i` pass stdin through as raw bytes), and cleanup happens once you exit. Podman's CLI is close enough to docker's that it reuses the exact same command shapes, just against `podman` instead. The container needs `bash` for the full experience; without it, `hi` drops you into the best plain shell available (`zsh`/`fish`/`ksh`/`sh`) with our aliases and a warning.

### Windows hosts

`hi <target>` works against Windows OpenSSH targets too, at whatever level the target supports:

- **WSL, Git Bash, Cygwin or MSYS2 reachable on `PATH`**: the full experience (header, colors, git prompt, aliases) - same code path as any other ssh host.
- **Stock Windows OpenSSH with no `bash` at all**: `hi` falls back to a plain interactive PowerShell session (no hi.d styling - that's bash-only) instead of failing outright. It still costs one authentication: hi writes its bootloader over the first of two calls multiplexed on the _same ssh connection_, and a target where that write can't run `sh -c` at all is a target with no POSIX shell, which is exactly the case the fallback is for. A target with `DefaultShell` set to PowerShell directly lands in the same fallback.

**Installing hi _on_ Windows:** use WSL. The `.deb` from the releases page installs into a WSL distribution unchanged - `/etc/profile.d/hi.d.sh`, `/usr/bin/hi`, everything exactly as on any Debian - and WSL is where a Windows developer already using `ssh`/`docker`/`kubectl` most likely works anyway. Native channels (Scoop and friends) are assessed in `packaging/windows.md` and wait on a green Windows CI job.

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

### Installation/Usage

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

#### Verifying a release download

Releases ship a `SHA256SUMS`, signed build provenance, and a detached [minisign](https://jedisct1.github.io/minisign/)
signature over the sums (the offline half — no `gh`, no network, one static public key):

```sh
sha256sum -c --ignore-missing SHA256SUMS                        # the bytes match the release
minisign -Vm SHA256SUMS -P 'RWT-PLACEHOLDER-see-packaging-README-before-first-release'
gh attestation verify hi.d_*_all.deb --repo ivylikethevine/hi.d # which CI run built them
```

<!-- The -P value above is a placeholder until the first release's keypair is
generated - packaging/README.md's before-first-release checklist replaces it. -->

---

Usage: `hi foo` (just like ssh!)

---

Reminder - place local only changes after the "`# hi-config-end`" comment in the local files.

### Configuration

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
| `~/.config/hi.d/aliases.sh`  | -                | your own aliases, sourced **after** `shells/aliases.sh` so yours win - additive, never a replacement, and in the same POSIX+fish subset |

This is what keeps configuring hi.d from dirtying the checkout (so `hi_update`'s `git pull` keeps applying
cleanly), and it is why the tree never has to be writable at all - it can be root-owned, installed by a package
manager. All of it rides along to every host you say `hi` to, in its own small archive unpacked over the
target's `misc/`.

Want history on it? `hi_overlay_init` makes `~/.config/hi.d` a git repo *in place* - from then on
`hi_configure` commits its own settings writes, `hi_doctor` reports the commit count, and a push remote is one
`git remote add` away. Entirely optional: an overlay you never init never hears about git. (Keeping the same
directory in chezmoi or yadm instead works just as well - see [docs/comparison.md](docs/comparison.md).)

Everything below is an environment variable, checked at the point it's used. `hi_configure` writes your answers to
`~/.config/hi.d/settings.sh`, which every shell sources ahead of `common/paths.sh`. It is a plain `#!/bin/sh`
script of `export NAME=value` lines, valid in sh, bash, zsh and fish alike.

You never have to use `hi_configure` - exporting any of these by hand works just as well, and takes precedence for
that shell.

#### Features

Each is **on by default**; set it to `1` to turn that piece off.

| variable                 | turns off                                                                       |
| ------------------------ | ------------------------------------------------------------------------------- |
| `_HI_DISABLE_HEADER`     | the whole connect/disconnect header, every line of it                           |
| `_HI_DISABLE_PROMPT`     | the colored `user@host` prompt, leaving your shell's own                        |
| `_HI_DISABLE_PERSONAL`   | personal shell settings - history size, keybindings, completion tweaks          |
| `_HI_DISABLE_GIT_STATUS` | the git segment in the prompt                                                   |
| `_HI_DISABLE_EDITORS`    | the `vim`/`nano` config overrides                                               |
| `_HI_DISABLE_ALIASES`    | the personal aliases in `shells/aliases.sh` (not nu's subset - `alias` is parse-time there and cannot be gated; see `shells/config.nu`) |
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

#### tmux

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

#### Header details

Each is **on by default**; set it to `0` to hide that line. All are ignored when `_HI_DISABLE_HEADER=1`.

| variable               | hides                                                            |
| ---------------------- | ---------------------------------------------------------------- |
| `_HI_HEADER_BANNER`    | the `~~~ Connected [host] ~~~` line, on connect _and_ disconnect |
| `_HI_HEADER_TIMESTAMP` | the date/time line                                               |
| `_HI_HEADER_SYSINFO`   | the OS / CPU / RAM line                                          |
| `_HI_HEADER_IDENTITY`  | the git identity / containers / ssh key line                     |
| `_HI_HEADER_CHECK`     | the installed-packages check (`misc/packages`)                   |

#### Everything else

| variable            | default         | what it does                                                                   |
| ------------------- | --------------- | ------------------------------------------------------------------------------ |
| `_HI_MAX_WIDTH`     | `80`            | terminal columns the header and banner are drawn to                            |
| `_HI_HOME`          | `$HOME`         | the **parent** of your `hi.d` directory - everything resolves `$_HI_HOME/hi.d` |
| `_HI_TARGETS_TTL`   | `5`             | seconds `hi <TAB>` reuses its target list for; `0` disables the cache          |
| `_HI_PROBE_TIMEOUT` | `2`             | seconds any one backend CLI gets, during completion and in the header          |
| `_HI_SSH_CONFIG`    | `~/.ssh/config` | where ssh hosts and their `# Tags:` comments are read from                     |
| `_HI_ASCII`         | by locale       | `1` forces ASCII stand-ins for the banner/prompt/packages glyphs (`^ ok x` for `↑ ✓ ✗`), `0` forces the glyphs; unset asks the locale, so a `LANG=C` target degrades cleanly instead of printing mojibake |
| `NO_COLOR`          | unset           | not hi's variable but [the convention](https://no-color.org): any non-empty value renders everything - header, prompts, git segment - without color, and hi ships your client-side choice to the target next to `_HI_ASCII` |
| `_HI_PROMPT`        | unset           | `starship` hands the prompt to [starship](https://starship.rs) when the target has it, keeping hi's header and aliases (bash/zsh/fish; nu keeps hi's prompt). Never auto-detected, and a target without starship silently keeps hi's own. hi does not ship starship - a multi-MB binary against a 35KB payload |
| `_HI_SHELL_PREFERENCE` | `login fish zsh bash` | which shell a session runs in: an ordered list of `bash`/`zsh`/`fish`/`nu`, plus `login` for "your own login shell". First one installed on the target wins; `bash` is the floor, since that is what `load.sh` needs to run at all. `nu` is never picked unless it is your login shell or you name it here |
| `_HI_PROMPT_END`    | per shell       | the character each prompt ends with, when you want the same one everywhere; the three below win over it |
| `_HI_PROMPT_END_BASH` | `\$`         | bash's prompt separator (`\$` is bash's own escape for "`$`, or `#` for root")                          |
| `_HI_PROMPT_END_ZSH` | `>`            | zsh's prompt separator - zsh prompt escapes work here, so `%#` behaves as it does anywhere else in `PS1` |
| `_HI_PROMPT_END_FISH` | `\|`         | fish's prompt separator; root still gets `#` regardless                                                 |
| `_HI_TERM_FALLBACK` | `1`             | on ssh targets missing a terminfo entry for your `TERM` (ghostty's `xterm-ghostty`, typically), swap it for `xterm-256color` before the session starts; `0` keeps the original `TERM` |

The last two exist because completion runs on **every TAB** and the header runs **before you get a shell**: a
docker daemon that's down or a `kubectl` pointed at a dead cluster would otherwise hang there with no upper bound.

### Testing

Run everything with `tests/test_runner.sh` (aliased to `hi_test` once installed) - it times each suite and prints a
colored pass/fail summary at the end:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
```

Suite names: `aliases`, `alias_fallthrough`, `osc52`, `tmux`, `shellcheck`, `install`, `hi`, `header`, `core`,
`git_prompt`, `targets`, `paths`, `color_preview`, `load`, `test_lib`, `test_runner` are fast and dependency-free - they're the first thing CI
runs on every push/PR (the last two are the harness testing itself). `ssh`, `ssh_disconnect`, `docker`, `podman`,
`nomad`, `kube`, `framework` are end-to-end:
they spin up real throwaway containers/clusters/agents and drive `hi.sh`'s actual connection paths against them, so
they're slower and need the relevant backend installed - each skips cleanly with a warning instead of failing if its
backend isn't available. CI runs `ssh`, `ssh_disconnect` and `docker` as a second job once the fast ones pass, which
between them cover both halves of `hi.sh` (`_say_hi` and `_say_hi_container`). Every test script is also directly
executable on its own, e.g. `tests/shells/shellcheck_test.sh`.

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

#### More docs

- [docs/architecture.md](docs/architecture.md) - the file relations, drawn: what ships, what stays home, and the four ways files reach each other
- [docs/GLOSSARY.md](docs/GLOSSARY.md) - the named idioms the code's `GLOSSARY:` comment tags point at; load-bearing for reading `common/`, and drift-checked by the lint suite
- [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) - the test harness and how a change should arrive (PR titles become release notes)
- [docs/SECURITY.md](docs/SECURITY.md) - reporting, and what hi touches on a target
- [docs/ROADMAP.md](docs/ROADMAP.md) - what is planned, and what each item is blocked on
- [docs/demos.md](docs/demos.md) and [docs/comparison.md](docs/comparison.md) - linked from the top too; [docs/tldr.md](docs/tldr.md) is the draft tldr-pages submission

#### File list

| file                                            | what it does                                                                                                                                                           |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hi.sh`                                         | runs on the client: pick the target, copy hi.d, chainload `load.sh`                                                                                                    |
| `load.sh`                                       | runs on the target: header, rc grafting, shell handoff, cleanup                                                                                                        |
| `common/paths.sh`                               | every path hi uses (the only file fish and sh both source)                                                                                                             |
| `common/core.sh`                                | the entry point every bash/zsh script sources: settings, paths, palette, `_hi_cecho`, color resolution                                                                 |
| `common/header.sh`                              | the connect/disconnect banner, shared by every shell, plus the `misc/packages` check it ends with                                                                      |
| `common/git_prompt.sh`                          | bash/zsh git prompt, matching fish's built-in `fish_vcs_prompt`                                                                                                        |
| `common/targets.sh`                             | every `hi` target (ssh/docker/podman/nomad/kube), for all three completions - cached and timeout-bounded                                                               |
| `shells/aliases.sh`                             | personal aliases shared by bash, zsh and fish - freely editable, off wholesale via `_HI_DISABLE_ALIASES=1`                                                             |
| `shells/osc52.sh`                               | stdin to the *client's* clipboard over OSC 52 - tmux/screen passthrough, raw under zellij - behind `hi_copy` and `vim.rc`'s yank autocmd, off via `_HI_DISABLE_OSC52=1` |
| `shells/bash.sh`                                | bash config                                                                                                                                                            |
| `shells/zsh.zsh`                                | zsh config                                                                                                                                                             |
| `shells/config.fish`                            | fish config                                                                                                                                                            |
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

##### Hostname, username, and group/tag colors

Every username and hostname gets a color automatically, deterministically derived from its name - there's nothing to generate and nothing that can go missing. To pin a specific color instead, add a line to `~/hi.d/misc/colors` (`username,root,red` / `hostname,prod-db,yellow` / `hosttag,desktop,green`); `hosttag` entries match the _leftmost_ tag in a `# Tags: ...` comment placed directly above a `Host` line in `~/.ssh/config`. Run `hi_color_preview` any time to preview what every ssh host and your user currently resolve to, rendered in their actual color.

###### Built from/with/in mind

- [sshrc](https://github.com/cdown/sshrc) - _from_ - (became `hi.sh`)
- [sshm](https://github.com/Gu1llaum-3/sshm) - _with_ - (optional, but _highly_ recommended to configure `~/.ssh/config` hosttags)
- [bat](https://github.com/sharkdp/bat) - _in mind_ - (essentially my reason to get the aliases.sh fallthrough logic to work as portably as possible)
- [fish](https://github.com/fish-shell/fish) - _with_ - (my preferred shell because its defaults/built-ins are extremely easy to understand, but one that is not POSIX-compliant)

###### AI Usage

Heavily inspired by: [Dictionarry/Profilarr's AI Transparency Statement](https://v2.dictionarry.dev/ai-transparency)

This code originally started as entirely code written by [me](https://github.com/ivylikethevine), but I have used generative AI to write large parts of it. Regardless, all of the code in this repository is my _responsibility_. AI is a tool, not an owner of a project. I have personally understood, reviewed, and approved all of the AI generated code in this repository. _Mainline releases_ have the same level of accountability to me as any code I write and publish.

###### Publishing Order

1. AUR
2. deb/rpm/apk
3. Homebrew
4. basher
5. fisher?
6. scoop?