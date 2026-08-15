# hi.sh -> sshrc supercharged

![CI (main)](https://github.com/ivylikethevine/hi.d/actions/workflows/ci.yml/badge.svg)

![CI (develop)](https://github.com/ivylikethevine/hi.d/actions/workflows/ci.yml/badge.svg?branch=develop)

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

## Requirements

- **Client**: `bash` and `openssl` (for ssh targets - armors the bootstrap payload through the login shell) or `docker`/`podman`/`nomad`/`kubectl` for the container/alloc/pod backends.
- **Target**: `openssl` for ssh targets; nothing extra for container/alloc/pod targets. `bash` gets you the full experience (header, colors, git prompt, aliases, vim/nano configs); without it `hi` still lands you in the best available shell (`zsh` > `fish` > `sh`) with just the aliases loaded, rather than failing outright.
- Everything else (client and target) is plain POSIX/bash/zsh/fish shell - no compiled artifacts, no package manager, no build step.

### How it works

1. `hi.sh` runs on the client. It archives `hi.d/` and sends it to the target. What it leaves out is `hi.sh` itself, `.git`, `scripts/`, `tests/`, `.github/`, this README, `LICENSE` and the editor/tooling dotfiles - see `$_HI_EXCLUDE` at the top of `hi.sh` for the authoritative list. The target unpacks it into a `/tmp` directory. `_HI_ROOT` is `$INSTALL_DIR/hi.d` on the client and `$_HI_HOME/hi.d` on the target.
   Your own `settings.sh`, `colors` and `packages` live outside the tree (see [Configuration](#configuration)), so they follow in a second, much smaller archive unpacked over the target's `misc/` - `$_HI_OVERLAY_FILES` in `hi.sh`. Nothing is sent if you haven't overridden anything.
2. On the target, `$_HI_ROOT/hi.bashrc` sources `$_HI_ROOT/load.sh` and calls `load`.
3. `load.sh` prints the header, appends hi's shell configs to the host's own rc files, and starts a session in the highest priority shell available (fish > zsh > bash).
   Note this order is the reverse of the one below, and deliberately so: `load.sh` only runs at all when the target _has_ bash, so it is free to prefer the nicest shell available. The `zsh > fish > sh` order quoted elsewhere is the **no-bash fallback**, which is ranking what's left after bash turned out to be missing.
4. When the session ends, `load.sh`'s `trap` strips those additions back out, and the `/tmp` directory is removed by the cleanup trap `hi.sh` set up on connect.
5. `hi <target> 'some command'` skips the interactive session and just runs the command there, like `ssh` does.

The setup in steps 1-2 is plain POSIX and runs under `sh`, so it works even if the target has no `bash` at all - `hi` still copies the whole of `~/hi.d` over in that case, but hands off to the best plain shell available (`zsh`/`fish`/`sh`) with just our aliases loaded, instead of the full `load.sh` experience, which needs `bash`.

For ssh targets specifically, `hi` first checks (over the same connection, so it costs no extra authentication) whether the target already has its own permanent `~/hi.d` - i.e. `scripts/install.sh` has been run there. If so, it skips the archive/copy step entirely and points `_HI_ROOT` straight at that existing copy instead, leaving it in place when the session ends.

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, etc. - anything in this directory is copied to every host you say `hi` to._**

### Docker / Podman containers

`hi <name>` also works against a running docker or podman container - if `<name>` isn't a `Host` in `~/.ssh/config` but is a running container (by name or ID, docker checked first), `hi` copies `~/hi.d` in and chainloads `load.sh` exactly like the ssh path, for an identical session (colors, prompt, aliases, vim/nano configs, etc). No openssl armoring is needed here (`docker exec -i`/`podman exec -i` pass stdin through as raw bytes), and cleanup happens once you exit. Podman's CLI is close enough to docker's that it reuses the exact same command shapes, just against `podman` instead. The container needs `bash` for the full experience; without it, `hi` drops you into the best plain shell available (`zsh`/`fish`/`sh`) with our aliases and a warning.

### Windows hosts

`hi <target>` works against Windows OpenSSH targets too, at whatever level the target supports:

- **WSL, Git Bash, Cygwin or MSYS2 reachable on `PATH`**: the full experience (header, colors, git prompt, aliases) - same code path as any other ssh host.
- **Stock Windows OpenSSH with no `bash` at all**: `hi` falls back to a plain interactive PowerShell session (no hi.d styling - that's bash-only) instead of failing outright. This still happens over the _same single ssh connection_, since `cmd.exe` (Windows' default `DefaultShell`) understands `||` the same way a POSIX shell does; a target with `DefaultShell` set to PowerShell directly is outside what this fallback can detect.

### Nomad allocations

`hi <alloc-id>` also works against a running Nomad allocation (matched by ID/prefix, checked after the ssh-host and docker/podman-container checks) - same idea, same session, same code path as docker. Since `nomad alloc exec` has no `docker cp`/`-e` equivalent, files are streamed in with `exec -i` + `cat >` and env vars are set through a `sh -c "export ...; exec ..."` wrapper. Multi-task allocations would need `nomad alloc exec -task <name>`, which `hi` doesn't pass through, so they need a single unambiguous task.

### Kubernetes pods

`hi <pod-name>` also works against a running Kubernetes pod (checked last, after ssh/docker/podman/nomad) - same idea again, using `kubectl exec` with `--` separating its own flags from the remote command. Uses whatever context/namespace your `kubectl` is currently pointed at; like Nomad's multi-task allocations above, a multi-container pod needs `-c <name>` to pick one, which `hi` doesn't pass through, so it needs a single unambiguous container (`kubectl` falls back to the pod's first container with a warning rather than failing outright).

### Installation/Usage

- `hi.d/scripts/install.sh` (re-run it any time; it repairs its own lines, even if hi.d moved) - before touching your shell rc files it validates your existing `~/.bashrc`, `~/.zshrc` and `~/.config/fish/config.fish` (whichever are installed) with each shell's own syntax checker, and asks whether to continue if any of them have issues
- reload your shell!
- run `hi_configure` any time afterward to revisit the feature toggle prompts - header, prompt, personal settings, git status, editors, aliases, header details, terminal width, and whether hi styles this machine too or only the hosts you say `hi` to - without touching the shell rc wiring. Answers land in `~/.config/hi.d/settings.sh`; see [Configuration](#configuration) below
- run `hi_check_configs` any time to just re-run that shell rc validation, without the rest of the install
- configure `~/.ssh/config` tags via sshm
- [optional] pin specific colors in `~/.config/hi.d/colors` - everything else gets a color automatically. Copy `hi.d/misc/colors` there to start from the shipped defaults
  - run `hi_color_preview` to preview what every ssh host/your user resolves to
- [optional] copy `hi.d/misc/packages` to `~/.config/hi.d/packages` and edit it to your preferences
- say `hi`!
- [optional] modify `~/hi.d/misc/*` and `~/hi.d/shells/*` to your liking - though anything with an overlay (`settings.sh`, `colors`, `packages`) is better edited in `~/.config/hi.d/`, which keeps the checkout clean for `hi_update`
- done with it? `hi.d/scripts/uninstall.sh` (aliased to `hi_uninstall`, and a one-line shim onto `install.sh --uninstall`) is the inverse of the install: it strips hi's lines back out of your rc files, removes the `settings.sh` it wrote, and unlinks `/usr/bin/hi`. It leaves the `hi.d` directory itself alone - and your `colors`/`packages`, which are yours - delete those yourself if you want them gone

---

Usage: `hi foo` (just like ssh!)

---

Reminder - place local only changes after the "`# hi-config-end`" comment in the local files.

### Configuration

Your config lives **outside the checkout**, in `${XDG_CONFIG_HOME:-$HOME/.config}/hi.d/` (`$_HI_CONFIG_DIR`).
`colors` and `packages` there override the tree's copies, one file at a time - anything you haven't
overridden keeps tracking the default the tree ships, so `hi_update` still delivers changes to the rest.
`settings.sh` has no in-tree counterpart at all: `hi_configure` only ever writes it here.

| overlay file                 | overrides       | what it is                       |
| ---------------------------- | --------------- | -------------------------------- |
| `~/.config/hi.d/settings.sh` | -               | what `hi_configure` writes       |
| `~/.config/hi.d/colors`      | `misc/colors`   | your color pins                  |
| `~/.config/hi.d/packages`    | `misc/packages` | what the package check looks for |

This is what keeps configuring hi.d from dirtying the checkout (so `hi_update`'s `git pull` keeps applying
cleanly), and it is why the tree never has to be writable at all - it can be root-owned, installed by a package
manager. All three ride along to every host you say `hi` to, in their own small archive unpacked over the
target's `misc/`.

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
| `_HI_DISABLE_ALIASES`    | the personal aliases in `shells/aliases.sh`                                     |
| `_HI_DISABLE_LOCAL`      | all of the above **on this machine only** - hi still styles the hosts you visit |

`_HI_DISABLE_LOCAL` is the odd one out: it's for "I want my own machine left alone, but I still want hi everywhere
I connect to". It's told apart from a real session by `_HI_REMOTE_SESSION`, which `load.sh` exports on a target and
a local shell's own rc never does.

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

The last two exist because completion runs on **every TAB** and the header runs **before you get a shell**: a
docker daemon that's down or a `kubectl` pointed at a dead cluster would otherwise hang there with no upper bound.

### Testing

Run everything with `tests/test_runner.sh` (aliased to `hi_test` once installed) - it times each suite and prints a
colored pass/fail summary at the end:

```sh
tests/test_runner.sh                    # every suite
tests/test_runner.sh aliases shellcheck # just the named suite(s)
```

Suite names: `aliases`, `alias_fallthrough`, `shellcheck`, `install`, `hi`, `header`, `core`,
`git_prompt`, `targets`, `paths`, `color_preview`, `load`, `test_lib`, `test_runner` are fast and dependency-free - they're the first thing CI
runs on every push/PR (the last two are the harness testing itself). `ssh`, `ssh_disconnect`, `docker`, `podman`,
`nomad`, `kube` are end-to-end:
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

#### File list

| file                                            | what it does                                                                                               |     |                                               |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --- | --------------------------------------------- |
| `hi.sh`                                         | runs on the client: pick the target, copy hi.d, chainload `load.sh`                                        |     |                                               |
| `load.sh`                                       | runs on the target: header, rc grafting, shell handoff, cleanup                                            |     |                                               |
| `common/paths.sh`                               | every path hi uses (the only file fish and sh both source)                                                 |     |                                               |
| `common/core.sh`                                | the entry point every bash/zsh script sources: settings, paths, palette, `_hi_cecho`, color resolution     |     |                                               |
| `common/header.sh`                              | the connect/disconnect banner, shared by every shell, plus the `misc/packages` check it ends with          |     |                                               |
| `common/git_prompt.sh`                          | bash/zsh git prompt, matching fish's built-in `fish_vcs_prompt`                                            |     |                                               |
| `common/targets.sh`                             | every `hi` target (ssh/docker/podman/nomad/kube), for all three completions - cached and timeout-bounded   |     |                                               |
| `shells/aliases.sh`                             | personal aliases shared by bash, zsh and fish - freely editable, off wholesale via `_HI_DISABLE_ALIASES=1` |     |                                               |
| `shells/bash.sh`                                | bash config                                                                                                |     |                                               |
| `shells/zsh.zsh`                                | zsh config                                                                                                 |     |                                               |
| `shells/config.fish`                            | fish config                                                                                                |     |                                               |
| `misc/vim.rc`, `misc/nano.rc`, `misc/theme.yml` | vim, nano and eza configs                                                                                  |     |                                               |
| `misc/packages`                                 | default for the packages check, as `cmd:priority[,alternative:priority]` - override in `~/.config/hi.d/packages` |     |                                         |
| `misc/colors`                                   | default color pins for hostnames/usernames/hosttags - override in `~/.config/hi.d/colors`                  |     |                                               |
| `scripts/install.sh`                            | configure the local shells, install, update and uninstall - `--prefix`/`$DESTDIR` for packagers            |     |                                               |
| `scripts/uninstall.sh`                          | one-line shim onto `install.sh --uninstall` (`hi_uninstall`)                                               |     |                                               |
| `scripts/color_preview.sh`                      | preview what every ssh host/user resolves to (`hi_color_preview`)                                          |     |                                               |
| `tests/test_runner.sh`                          | unified runner - times and summarizes every test below (or a chosen subset) (`hi_test`)                    |     |                                               |
| `tests/test_lib.sh`                             | the whole suite skeleton: asserts/counters, scratch dir, skip preamble, probe commands, poll/pty helpers   |     |                                               |
| `tests/shells/alias_test.sh`                    | check `aliases.sh` still loads in dash/bash/zsh/fish                                                       |     |                                               |
| `tests/shells/alias_fallthrough_test.sh`        | unit tests for `aliases.sh`'s `command -v a \                                                              | b \ | ...`fallthrough and`_HI_DISABLE_*` flag logic |
| `tests/common/header_test.sh`                   | unit tests for `header.sh`: row-joining, banner padding/floor math, the `_HI_DISABLE_HEADER` gate, and the per-priority found/missing/hide logic of the packages check |     |     |
| `tests/common/core_test.sh`                     | unit tests for `core.sh`'s color-resolution chain (hash/override/hosttag/usertag) and `_hi_sanitize`       |     |                                               |
| `tests/common/git_prompt_test.sh`               | unit tests for `git_prompt.sh`'s status flags, ahead/behind, detached HEAD, and every in-progress state    |     |                                               |
| `tests/common/targets_test.sh`                  | unit tests for `targets.sh` and `bash.sh`'s completion, against fixture ssh configs and fake backend CLIs  |     |                                               |
| `tests/common/paths_test.sh`                    | unit tests for `paths.sh`'s local-only gate, both directions, and that settings reach it                   |     |                                               |
| `tests/scripts/color_preview_test.sh`           | unit tests for `color_preview.sh`'s precedence, table inputs and layout helpers                            |     |                                               |
| `tests/shells/hi_test.sh`                       | unit tests for `hi.sh`'s argument parsing, backend predicates and generated bootloader/fallback rc         |     |                                               |
| `tests/shells/load_test.sh`                     | unit tests for `load.sh`'s rc grafting, marker stripping, and disposable-vs-permanent `$_HI_ROOT` cleanup  |     |                                               |
| `tests/shells/shellcheck_test.sh`               | the lint gate: shellcheck over every `*.sh`, plus `zsh -n`/`fish --no-execute` on every file those shells parse themselves |     |                             |
| `tests/scripts/install_test.sh`                 | unit tests for `install.sh`: marker-based rc rewriting, setting defaults, config validation, packaging mode, and the `--uninstall` half incl. a round-trip |     |     |
| `tests/harness/lib_test.sh`                     | unit tests for `test_lib.sh` itself - the scaffolding every other suite is built on                        |     |                                               |
| `tests/harness/runner_test.sh`                  | drives the real `test_runner.sh` over fixture suites that pass/fail/are missing                            |     |                                               |
| `tests/targets/ssh_test.sh`                     | end-to-end test of hi's ssh path across remote login shells                                                |     |                                               |
| `tests/targets/ssh_disconnect_test.sh`          | end-to-end test that the target-side cleanup trap fires on an abrupt disconnect, not just a clean exit     |     |                                               |
| `tests/targets/docker_test.sh`                  | end-to-end test of hi's docker path across container shell environments (thin wrapper, see `test_lib.sh`)  |     |                                               |
| `tests/targets/podman_test.sh`                  | end-to-end test of hi's podman path across container shell environments (thin wrapper, see `test_lib.sh`)  |     |                                               |
| `tests/targets/nomad_test.sh`                   | end-to-end test of hi's nomad path against a throwaway `nomad agent -dev`                                  |     |                                               |
| `tests/targets/kube_test.sh`                    | end-to-end test of hi's kube path against a throwaway `kind` cluster                                       |     |                                               |

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

TODO: Increase mac compatibility by removing read/mapfile operations not present on bash 3
