# hi.sh -> sshrc supercharged

---

## EXPERIMENTAL UNTIL v1.0.0-stable RELEASES

NOTE: Project is in active development, many things are subject to change
and this current state is not a representation of final, published quality.
This is a hobby project.

---

![CI (main)](https://github.com/ivylikethevine/hi.d/actions/workflows/ci.yml/badge.svg)
[![Coverage](https://github.com/ivylikethevine/hi.d/actions/workflows/coverage.yml/badge.svg)](https://github.com/ivylikethevine/hi.d/actions/workflows/coverage.yml)
![ssh payload](https://img.shields.io/badge/ssh_payload-70KB_per_session-4c1)
![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![shells](https://img.shields.io/badge/shells-bash%20%7C%20zsh%20%7C%20fish%20%7C%20ksh%20%7C%20sh-blue)
![targets](https://img.shields.io/badge/targets-ssh%20%7C%20docker%20%7C%20podman%20%7C%20nomad%20%7C%20k8s-8A2BE2)
![license](https://img.shields.io/badge/license-MIT-blue)

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

![hi connecting to a container: banner, header, packages check, colored prompt, and the cleanup on exit](docs/demos/demo.gif)

More of these — every backend (ssh with a permanent install, docker, podman, nomad, kubernetes) across a
variety of shells on both sides — [just below](#every-target-the-same-session). How it compares to `sshrc`,
`xxh`, `kyrat` or `chezmoi`, including where one of those is the better tool:
[docs/ALTERNATIVES.md](docs/ALTERNATIVES.md).

The payload badge is enforced, not aspirational: the bench suite assembles the real connect script — the
same one `hi` prints the size of when you say hi to a target, carrying `$_HI_PAYLOAD` only, with no tests,
docs or CI ever riding along — and fails CI when the badge drifts more than 5% from it.

## Every target, the same session

The pitch is that `hi` behaves identically whatever is on the other end — an
ssh host, a container, an allocation, a pod — and whatever shell each side
runs. One GIF per backend, deliberately varying both sides, each rendered from
the tape beside it (`vhs docs/tapes/<name>.tape` from the repo root, with the
backend running and `hi` on PATH; `docs/tapes/fixtures.sh` builds every target
the tapes connect to, `fixtures.sh down` removes them). Manual artifacts,
reviewed by eye — regenerate whenever the header or prompt changes.

Two things to get right when you do: `hi` on `$PATH` must be _this_ checkout
(`/usr/bin/hi` may point elsewhere), and the target image builds from `HEAD`,
so uncommitted work shows on the client side of the GIF but not the target's.
Render from a commit, or set `HI_DEMO_SOURCE=worktree`.

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
- **bash version**: 3.2 or newer, on both ends - what macOS still ships, so hi stays clear of every bash-4-only construct: no `mapfile`/`readarray` (`_hi_read_lines` in `common/core.sh` does that job), no associative arrays, no namerefs, no `${x,,}`. Enforced twice: `tests/shells/shellcheck_test.sh` greps for those constructs, and `tests/targets/ssh_test.sh` runs a real bash 3.2 container target and fails on so much as one shell error.
- **Target**: `base64` for ssh targets (effectively everywhere - coreutils, busybox, macOS/BSD); nothing extra for container/alloc/pod targets. `bash` gets the full experience (header, colors, git prompt, aliases, vim/nano configs); without it `hi` still lands you in the best available shell (`fish` > `zsh` > `ksh` > `sh`) with the aliases and, on the POSIX tiers, a colored prompt - rather than failing outright.
- Everything else (client and target) is plain POSIX/bash/zsh/fish shell - no compiled artifacts, no package manager, no build step.

### How it works

1. `hi.sh` runs on the client, archives `hi.d/` and sends it to the target, which unpacks it into a `/tmp` directory. Left out: `.git`, `scripts/`, `tests/`, `docs/`, `.github/`, this README and the editor/tooling dotfiles — `$_HI_PAYLOAD` at the top of `hi.sh` is the authoritative allow list. `_HI_ROOT` is `$INSTALL_DIR/hi.d` on the client, `$_HI_HOME/hi.d` on the target.
   Your `settings.sh`, `colors`, `packages`, `tmux.conf` and `aliases.sh` live outside the tree (see [Configuration](#configuration)) and follow in a second, much smaller archive — `$_HI_OVERLAY_FILES` in `hi.sh`, `$_HI_CONFIG_DIR` on the target. It lands in a `config/` of its own beside `misc/` rather than over it, so your `aliases.sh` stays additive. Nothing is sent if you have overridden nothing.
   The tar and the bootloader are each base64-armored, assembled into one script, and written over the **stdin** of the first of two calls multiplexed on one ssh connection; the second runs it. Not as an argv entry: Linux caps a single one at 128KB regardless of `ARG_MAX`, and the payload sits within a few kilobytes of that. The script itself travels unarmored — stdin is a pipe, so only the two streams _inside_ it need armor, and a second pass over the whole thing would cost a third of every session's bytes for nothing. The size hi prints on connect is that script, and it is what the badge above measures: armor is 4/3, so a session costs roughly `(payload + bootloader) × 4/3` — about 1.4× the gzipped tar on its own. `hi.sh` rides _inside_ that tar (it is in `$_HI_PAYLOAD`), gzipped like everything else, so a disposable session has a launcher to relay onward with for ~14KB of wire rather than the ~41KB the same file costs base64-armored as a stream of its own. The size on **disconnect** is a different measurement again: `du --apparent-size` of the unpacked tree on the target, which is why it is bigger still — those files land decompressed. `hi --doctor` prints both, labeled.
2. On the target, `$_HI_ROOT/hi.bashrc` sources `$_HI_ROOT/load.sh` and calls `load`.
3. `load.sh` prints the header, appends hi's shell configs to the host's own rc files, and starts a session in **your login shell** when hi styles it (bash, zsh or fish), else the first of `fish > zsh > bash` the target has. `_HI_SHELL_PREFERENCE` is that rule as a setting. Both halves are one list — `$_HI_SHELL_TREE` in `common/core.sh`, `fish > zsh > bash > mksh > ksh > dash > ash > sh` — read by two consumers: `load.sh` takes the shells it styles out of it, and `hi.sh`'s `$_HI_SHELL_LADDER` is the same list minus bash, which is the **no-bash fallback**: what's left when bash is missing.
4. When the session ends, `load.sh`'s `trap` strips those additions back out, and the `/tmp` directory is removed by the cleanup trap `hi.sh` set up on connect.
5. `hi <target> 'some command'` skips the interactive session and just runs the command there, like `ssh` does.

Steps 1-2 are plain POSIX under `sh`, so they work even where the target has no `bash`. hi still copies the whole tree, but hands off to the best plain shell available (`zsh`/`fish`/`ksh`/`sh`) with just the aliases loaded, rather than the full `load.sh`, which needs bash.

For ssh targets, hi first checks — over the same connection, so it costs no extra authentication — whether the target already has a permanent `~/hi.d` from `scripts/install.sh`. If so it skips the copy entirely, points `_HI_ROOT` at that copy, and leaves it in place at the end.

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, etc. - anything in `${XDG_CONFIG_HOME:-$HOME/.config}/hi.d/` is copied to every host you say `hi` to._**

### Docker / Podman containers

`hi <name>` also works against a running docker or podman container. If `<name>` isn't a `Host` in `~/.ssh/config` but is a running container (by name or ID, docker checked first), `hi` copies `~/hi.d` in and chainloads `load.sh` exactly as the ssh path does, for an identical session. No armoring is needed (`docker exec -i`/`podman exec -i` pass stdin as raw bytes), and cleanup happens on exit. Podman's CLI is close enough to reuse the same command shapes. The container needs `bash` for the full experience; without it `hi` drops you into the best plain shell available (`zsh`/`fish`/`ksh`/`sh`) with the aliases and a warning.

### Nomad allocations

`hi <alloc-id>` also works against a running Nomad allocation (matched by ID/prefix, after the ssh-host and container checks) - same session, same code path as docker. Since `nomad alloc exec` has no `docker cp`/`-e` equivalent, files stream in with `exec -i` + `cat >` and env vars go through a `sh -c "export ...; exec ..."` wrapper. Multi-task allocations would need `nomad alloc exec -task <name>`, which `hi` doesn't pass through, so they need a single unambiguous task.

### Kubernetes pods

`hi <pod-name>` also works against a running Kubernetes pod (checked last, after ssh/docker/podman/nomad) - same idea again, using `kubectl exec` with `--` separating its own flags from the remote command. Uses whatever context/namespace your `kubectl` is currently pointed at; like Nomad's multi-task allocations above, a multi-container pod needs `-c <name>` to pick one, which `hi` doesn't pass through, so it needs a single unambiguous container (`kubectl` falls back to the pod's first container with a warning rather than failing outright).

### Windows hosts

`hi <target>` works against Windows OpenSSH targets too, at whatever level the target supports:

- **WSL, Git Bash, Cygwin or MSYS2 reachable on `PATH`**: the full experience (header, colors, git prompt, aliases) - same code path as any other ssh host.
- **Stock Windows OpenSSH with no `bash` at all**: `hi` falls back to a plain interactive PowerShell session (no hi.d styling - that's bash-only) rather than failing outright. It still costs one authentication: hi writes its bootloader over the first of two calls multiplexed on the _same ssh connection_, and a target where that write cannot run `sh -c` is a target with no POSIX shell, which is exactly what the fallback is for. `DefaultShell` set to PowerShell lands in the same place.

**Installing hi _on_ Windows:** use WSL. The `.deb` from the releases page installs into a WSL distribution unchanged - `/etc/profile.d/hi.d.sh`, `/usr/bin/hi`, everything as on any Debian - and WSL is where a Windows developer already using `ssh`/`docker`/`kubectl` most likely works. Native channels (Scoop and friends) are assessed under [docs/PACKAGING.md](docs/PACKAGING.md#windows-channels) and wait on a green client-side Windows CI job.

### Compatibility

Three questions, because hi answers them at three different moments. **Legend:** ✅ exercised by a suite on
every run · 🟡 expected to work, nobody has proven it · ⚠️ works, reduced · ❌ not supported.

**1. The target's OS** — can hi land a session there at all?

| target OS                                     | result                                                                                                                                                    | proven by                                                                                   |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Linux, glibc (Debian/Ubuntu/Fedora/Arch…)     | ✅ full session                                                                                                                                           | `tests/targets/ssh_test.sh`, on Debian bookworm                                             |
| Linux, musl + busybox (Alpine…)               | ✅ full session with `bash` installed, ⚠️ aliases-only without                                                                                            | `ssh_test.sh`, on Alpine 3.20                                                               |
| macOS                                         | 🟡 full session — bash 3.2 is what it ships, and the suite runs a real bash 3.2 target; the client half (BSD `sed`/`mktemp`/`base64`) is unit-tested only | `ssh_test.sh` bash-3.2 case; `.github/workflows/macos-e2e.yml` is written but has never run |
| WSL                                           | 🟡 it is Linux, and the `.deb` installs into it unchanged                                                                                                 | —                                                                                           |
| Windows, with Git Bash/Cygwin/MSYS2 on `PATH` | 🟡 full session, same code path as any ssh host                                                                                                           | `.github/workflows/windows-e2e.yml`, written, never run                                     |
| Windows, stock OpenSSH (`cmd.exe`/PowerShell) | ⚠️ plain PowerShell session, no hi styling — the fallback is deliberate, not a failure                                                                    | same, never run                                                                             |
| \*BSD, Solaris/illumos                        | 🟡 nothing in hi is Linux-specific past the header's `/proc` probes, which degrade to `?`                                                                 | —                                                                                           |

**2. The target's _login_ shell** — the one sshd hands hi's command to, before any of hi runs.

| login shell                                      | result | note                                                                                                                                                              |
| ------------------------------------------------ | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash`, `sh`, `dash`, busybox `ash`              | ✅     | the ordinary case                                                                                                                                                 |
| `zsh`                                            | ✅     |                                                                                                                                                                   |
| `fish`                                           | ✅     | the reason hi's remote command is wrapped in `sh -c '…'`: fish parses neither `{ …; }` nor `\|\|` the way sh does                                                 |
| `ksh` (ksh93/mksh/pdksh), `tcsh`/`csh`           | 🟡     | they only have to run one `sh -c` command; nothing tests them                                                                                                     |
| `nushell`, `elvish`, `xonsh`, `ion`, `oil`/`osh` | 🟡     | same — one command, no shell-specific syntax in it. Being a fine _login_ shell here is unrelated to being a styled _session_ shell, which the third table answers |
| PowerShell, `cmd.exe`                            | ⚠️     | no POSIX shell to write the bootloader with, so hi falls back to a plain PowerShell session                                                                       |

**3. The shell you end up _in_** — what hi hands you once it is on the target.

| session shell                                    | result                                                                | note                                                                                                                                                                                                                                                                                           |
| ------------------------------------------------ | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash` ≥ 3.2                                     | ✅ full: header, prompt, git status, aliases, editor configs          | 3.2 is the floor because macOS still ships it                                                                                                                                                                                                                                                  |
| `zsh`                                            | ✅ full                                                               | `shells/zsh.zsh`                                                                                                                                                                                                                                                                               |
| `fish`                                           | ✅ full                                                               | `shells/config.fish`                                                                                                                                                                                                                                                                           |
| `sh`/`dash`/`ash` (no bash on the target)        | ⚠️ aliases and a colored `user@host` prompt, with a warning saying so | no header and no git segment - those need bash                                                                                                                                                                                                                                                 |
| `ksh`/`mksh` (no bash on the target)             | ⚠️ aliases, the colored prompt **and a live git segment** - no header | it reads `$ENV` as the `sh` tier does, plus `shells/ksh.sh`: ksh93 and mksh expand `$( )` when the prompt is _printed_, which is what lets the segment be live where busybox `ash` cannot have one. The header needs bash. `tests/targets/ssh_test.sh` renders the segment against a real mksh |
| `nushell`, `elvish`, `xonsh`, `ion`, `oil`/`osh` | ❌ **decided against**, not pending                                   | see the table below. You still get a session — hi lands you in the best of `$_HI_SHELL_TREE` the target has                                                                                                                                                                                    |
| PowerShell                                       | ❌                                                                    | bash-only by design                                                                                                                                                                                                                                                                            |

**Shells hi does not style, and why that is settled.** Each would need its own rc in `shells/` (prompt,
aliases, completion) plus a tier in the fallback ladder in `hi.sh`'s `_hi_remote_suffix` and `load.sh`'s
`load()`. Three of them were open questions; they are answered now, and the answer is no.

| shell        | status                           | why                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------ | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `elvish`     | **decided against** (2026-08-18) | its own language, so the prompt and aliases would be a second implementation to keep in sync forever, for an audience hi has no evidence of. A `shells/rc.elv` is what it would take, and nobody has asked                                                                                                                                                                            |
| `xonsh`      | **decided against** (2026-08-18) | Python — a third implementation, on the same terms as elvish and with the same answer                                                                                                                                                                                                                                                                                                 |
| `tcsh`/`csh` | **decided against** (2026-08-18) | different rc syntax _and_ no `$ENV` equivalent, so there is no hook to land on at all: it would need its own rc and its own delivery mechanism                                                                                                                                                                                                                                        |
| `nushell`    | **removed** (2026-08-18)         | it shipped, as `shells/config.nu`, and came back out. Nu is not POSIX, so it can source none of `common/`: the header, palette and git segment were rendered by shelling out to bash - which means the tier needed bash on the target anyway, and where bash exists, bash/zsh/fish already answer. A whole rc in a fourth language, plus a CI toolchain, for a shell nobody asked for |
| `ksh`/`mksh` | shipped, **all but the header**  | a tier in the no-bash ladder, the POSIX prompt, the aliases, and `shells/ksh.sh`'s git segment. The header, and only the header, is missing: `common/header.sh` is bash, and this tier is defined by bash being absent, so it would have to be written a second time in POSIX and then kept in sync forever - the git segment was worth that, a second header is not                  |
| PowerShell   | not a POSIX shell                | the greeting hi prints there is the whole extent of it; anything more is a separate project, really                                                                                                                                                                                                                                                                                   |

Using one of these as a _login_ shell still works, and always did — hi lands you in the best of
`$_HI_SHELL_TREE` (`fish > zsh > bash > mksh > ksh > dash > ash > sh`) the target actually has. Only the
_session_ shell is limited, and only for the three above.

**If you use a shell framework**, hi lands you in your own login shell, so it loads normally — that is what
`_HI_SHELL_PREFERENCE`'s default (`login`, then the styled head of `$_HI_SHELL_TREE`: `fish zsh bash`) means. `tests/targets/framework_test.sh` tests
oh-my-zsh, powerlevel10k, starship and bash-it against hi, each asserting the session comes up with no shell
errors and that hi neither changed zsh's array base under them nor dropped their `PROMPT_COMMAND`.

## hi.d and the alternatives

How hi.d compares to `sshrc`, `xxh`, `kyrat`, `sshdot` and `homeshick`, which
adjacent tools compose with it rather than compete, what actually makes it
different, and where another tool is the better choice:
[docs/ALTERNATIVES.md](docs/ALTERNATIVES.md).

## Installation/Usage

- `hi.d/scripts/install.sh` (re-run it any time; it repairs its own lines, even if hi.d moved) - before touching your shell rc files it validates whichever of `~/.bashrc`, `~/.zshrc` and `~/.config/fish/config.fish` are installed with each shell's own syntax checker, and asks whether to continue if any have issues
- reload your shell!
- run `hi_configure` any time afterward to revisit the feature toggle prompts - header, prompt, personal settings, git status, editors, aliases, header details, terminal width, and whether hi styles this machine too or only the hosts you say `hi` to - without touching the shell rc wiring. Answers land in `~/.config/hi.d/settings.sh`; see [Configuration](#configuration) below
- run `hi_check_configs` any time to just re-run that shell rc validation, without the rest of the install
- run `hi --help` (or `hi -h`) for the short version of all of this: the synopsis, the target resolution order, and every flag hi answers itself. `man hi` is the long version. Everything hi does not answer is passed to `ssh` unchanged
- run `hi --version` to see what is installed - the packaged version, or `git describe` in a checkout; the doctor and the connect header show it too
- run `hi --tmux <target>` to have the session live inside a named tmux on the target, so a dropped connection detaches instead of losing work - run it again to reattach (`_HI_TMUX_ATTACH=1` makes it the default, `--no-tmux` turns it off, `_HI_TMUX_SESSION` names the session). Offered only where hi.d is permanent on the target: a disposable tree is deleted when the session ends, and hi says so rather than leaving a tmux pointing at nothing
- run `hi_doctor` (or `hi --doctor <target>`) when something is slow or failing: it reports the tree, the config overlay, every backend probed and timed with the same ceilings the header and completion use, and - with a target - which backend the name resolves to plus an ssh reachability/tooling check, all read-only
- configure `~/.ssh/config` tags via sshm
- [optional] pin specific colors in `~/.config/hi.d/colors` - everything else gets a color automatically. Copy `hi.d/misc/colors` there to start from the shipped defaults
  - run `hi_color_preview` to preview what every ssh host/your user resolves to
- [optional] copy `hi.d/misc/packages` to `~/.config/hi.d/packages` and edit it to your preferences
  - run `hi_packages_preview` to see what each priority means, the colors it renders installed and missing packages in, one real example of each from your own file, and the check itself as a connect will print it
- say `hi`!
- [optional] modify `~/hi.d/misc/*` and `~/hi.d/shells/*` to your liking - though anything with an overlay (`settings.sh`, `colors`, `packages`, `tmux.conf`, `aliases.sh`) is better edited in `~/.config/hi.d/`, which keeps the checkout clean for `hi_update`
  - tip: `~/hi.d` is a git checkout, so if you do edit it, push to your own fork and clone that on your next device - same setup everywhere, kept in sync by `hi_update`
- done with it? `hi.d/scripts/uninstall.sh` (aliased to `hi_uninstall`, a one-line shim onto `install.sh --uninstall`) is the install's inverse: it strips hi's lines back out of your rc files, removes the `settings.sh` it wrote, and unlinks `/usr/bin/hi`. It leaves the `hi.d` directory alone, and your `colors`/`packages` too - delete those yourself if you want them gone

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

Your config lives **outside the checkout**, in `${XDG_CONFIG_HOME:-$HOME/.config}/hi.d/`, and rides along to
every host you say `hi` to in its own small archive - `colors`, `packages`, `tmux.conf` and `aliases.sh`
overlay the tree's copies one file at a time, and `settings.sh` (what `hi_configure` writes) has no in-tree
counterpart at all. The full picture - the overlay file table, every `_HI_DISABLE_*` feature toggle, the
header-line toggles, tmux's `update-environment` behavior, and every other environment variable hi reads
(`_HI_SHELL_PREFERENCE`, `_HI_PROMPT`, `_HI_ASCII`, `_HI_HEADER_GHZ`, ...) - is in
[docs/FEATURES.md](docs/FEATURES.md).

## Testing

`tests/test_runner.sh` (aliased to `hi_test` once installed) runs the suite, times each one and prints a
colored pass/fail summary - `--group fast` is what CI runs on every push/PR. The container suites run their
cases in parallel (each one boots its own container), capped at four at a time and saying so in the output;
`_HI_PAR_WIDTH=1` puts a suite back on one case at a time when you are bisecting a flake. The full runbook
(all four suite groups, `--host-report`, `--verbose`, the lint gate, relaying, why the tests are local-only)
is in [docs/TESTING.md](docs/TESTING.md).

```sh
export _HI_HOME=/path/to/parent-of-hi.d  # never your real ~/hi.d
tests/test_runner.sh --group fast
```

## More docs

- [docs/FEATURES.md](docs/FEATURES.md) - the config overlay, every feature toggle and environment variable hi reads
- [docs/ALTERNATIVES.md](docs/ALTERNATIVES.md) - sshrc, xxh, kyrat, sshdot and homeshick side by side; what makes hi.d different, and when another tool is the better choice
- [docs/TESTING.md](docs/TESTING.md) - the test runner, suite groups, parallel cases, the lint gate, relaying
- [docs/GLOSSARY.md](docs/GLOSSARY.md) - the named idioms the code's `GLOSSARY:` comment tags point at; load-bearing for reading `common/`, and drift-checked by the lint suite
- [docs/SECURITY.md](docs/SECURITY.md) - reporting, and what hi touches on a target
- [docs/PACKAGING.md](docs/PACKAGING.md) - the publishing runbook: cutting a release, the per-channel steps, and the Windows channel assessment
- [docs/ROADMAP.md](docs/ROADMAP.md) - what is planned, what each item is blocked on, and the one-time setup the release channels wait on
- [docs/tldr.md](docs/tldr.md) - the draft tldr-pages submission; [docs/hi.1](docs/hi.1) is the man page every package installs

### File list

Every shipped file carries its own opening comment block saying what it does and why, which is the copy
that cannot go stale; `tests/test_runner.sh --list-paths` prints the live suite list — group, name, and
path — so the truth can't drift the way a second copy of it once did.

#### Hostname, username, and group/tag colors

Every username and hostname gets a color deterministically derived from its name - nothing to generate, nothing that can go missing. To pin one instead, add a line to `~/hi.d/misc/colors` (`username,root,red` / `hostname,prod-db,yellow` / `hosttag,desktop,green`); `hosttag` entries match the _leftmost_ tag in a `# Tags: ...` comment directly above a `Host` line in `~/.ssh/config`. `hi_color_preview` shows what every ssh host and your user currently resolve to, in their actual colors.

##### Built from/with/in mind

- [sshrc](https://github.com/cdown/sshrc) - _from_ - (became `hi.sh`)
- [sshm](https://github.com/Gu1llaum-3/sshm) - _with_ - (optional, but _highly_ recommended to configure `~/.ssh/config` hosttags)
- [bat](https://github.com/sharkdp/bat) - _in mind_ - (essentially my reason to get the aliases.sh fallthrough logic to work as portably as possible)
- [fish](https://github.com/fish-shell/fish) - _with_ - (my preferred shell because its defaults/built-ins are extremely easy to understand, but one that is not POSIX-compliant)

##### AI Usage

Heavily inspired by: [Dictionarry/Profilarr's AI Transparency Statement](https://v2.dictionarry.dev/ai-transparency)

This started as code written entirely by [me](https://github.com/ivylikethevine), but I have used generative AI to write large parts of it. All of the code here is my _responsibility_ regardless: AI is a tool, not an owner of a project. I have personally understood, reviewed and approved all of the AI-generated code in this repository, and _mainline releases_ carry the same accountability to me as anything I write and publish myself.
