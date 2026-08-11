# hi.sh -> sshrc superset

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

## How it works

1. `hi.sh` runs on the client. It archives `hi.d/` (minus `.git`, this README, and `scripts/`) and sends it to the target, which unpacks it into a `/tmp` directory. `_HI_ROOT` is `$INSTALL_DIR/hi.d` on the client and `$_HI_HOME/hi.d` on the target.
2. On the target, `$_HI_ROOT/hi.bashrc` sources `$_HI_ROOT/load.sh` and calls `load`.
3. `load.sh` prints the header, appends hi's shell configs to the host's own rc files, and starts a session in the highest priority shell available (fish > zsh > bash).
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
- run `hi_configure` any time afterward to revisit the feature toggle prompts (header, prompt, personal settings, git status, editors, aliases, header details, terminal width) without touching the shell rc wiring
- run `hi_check_configs` any time to just re-run that shell rc validation, without the rest of the install
- configure `~/.ssh/config` tags via sshm
- [optional] pin specific colors in `~/hi.d/misc/colors` - everything else gets a color automatically
  - run `hi_color_preview` to preview what every ssh host/your user resolves to
- configure `~/hi.d/misc/packages` to your preferences
- [optional] in `common/header.sh` set any of `_HI_HEADER_TIMESTAMP`, `_HI_HEADER_SYSINFO`, `_HI_HEADER_IDENTITY`, and `_HI_HEADER_CHECK` to `0` to turn off that piece of the header/greeting across shells
- [optional] in `common/git_prompt.sh` set `_HI_GIT_PROMPT` to `0` to turn off the git prompt across shells
- [optional] in `common/shared.sh` set `_HI_MAX_WIDTH` to your preferred terminal width (default is 80)
- [optional] in `common/paths.sh` set `_HI_DISABLE_LOCAL=1` to keep all of the above off on this machine (the one hi.d is installed on) while still applying it when you `hi` elsewhere - `hi_configure`/`install.sh` ask about this too
- say `hi`!
- [optional] modify `~/hi.d/misc/*` and `~/hi.d/shells/*` to your liking!

--
Usage: `hi foo` (just like ssh!)
--

Reminder - place local only changes after the "`# hi-config-end`" comment in the local files.

#### File list

| file                                            | what it does                                                                                               |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `hi.sh`                                         | runs on the client: pick the target, copy hi.d, chainload `load.sh`                                        |
| `load.sh`                                       | runs on the target: header, rc grafting, shell handoff, cleanup                                            |
| `common/paths.sh`                               | every path hi uses (the only file fish and sh both source)                                                 |
| `common/bootstrap.sh`                           | one-line entry point for bash/zsh: paths, colors, hi's own aliases                                         |
| `common/shared.sh`                              | palette, `_hi_cecho`, host/user color resolution (see below)                                               |
| `common/check.sh`                               | reads `misc/packages`, reports what the host has                                                           |
| `common/header.sh`                              | the connect/disconnect banner, shared by every shell                                                       |
| `common/git_prompt.sh`                          | bash/zsh git prompt, matching fish's built-in `fish_vcs_prompt`                                            |
| `common/targets.sh`                             | every `hi` target (ssh/docker/podman/nomad/kube), for all three completions                                |
| `shells/aliases.sh`                             | personal aliases shared by bash, zsh and fish - freely editable, off wholesale via `_HI_DISABLE_ALIASES=1` |
| `shells/bash.sh`                                | bash config                                                                                                |
| `shells/zsh.zsh`                                | zsh config                                                                                                 |
| `shells/config.fish`                            | fish config                                                                                                |
| `misc/vim.rc`, `misc/nano.rc`, `misc/theme.yml` | vim, nano and eza configs                                                                                  |
| `misc/packages`                                 | what `check.sh` looks for, as `cmd:priority[,alternative:priority]`                                        |
| `misc/colors`                                   | optional color pins for hostnames/usernames/hosttags                                                       |
| `scripts/install.sh`                            | configure the local shells, install and update                                                             |
| `scripts/alias_test.sh`                         | check `aliases.sh` still loads in dash/bash/zsh/fish                                                       |
| `scripts/color_preview.sh`                      | preview what every ssh host/user resolves to (`hi_color_preview`)                                          |
| `scripts/ssh_test.sh`                           | end-to-end test of hi's ssh path across remote login shells                                                |
| `scripts/docker_test.sh`                        | end-to-end test of hi's docker path across container shell environments                                    |
| `scripts/podman_test.sh`                        | end-to-end test of hi's podman path across container shell environments                                    |
| `scripts/nomad_test.sh`                         | end-to-end test of hi's nomad path against a throwaway `nomad agent -dev`                                  |
| `scripts/kube_test.sh`                          | end-to-end test of hi's kube path against a throwaway `kind` cluster                                       |
| `scripts/shellcheck_test.sh`                    | runs shellcheck over every `*.sh` file in the repo                                                         |

##### Hostname, username, and group/tag colors

Every username and hostname gets a color automatically, deterministically derived from its name - there's nothing to generate and nothing that can go missing. To pin a specific color instead, add a line to `~/hi.d/misc/colors` (`username,root,red` / `hostname,prod-db,yellow` / `hosttag,desktop,green`); `hosttag` entries match the _leftmost_ tag in a `# Tags: ...` comment placed directly above a `Host` line in `~/.ssh/config`. Run `hi_color_preview` any time to preview what every ssh host and your user currently resolve to, rendered in their actual color.

###### Built from/with

- sshrc - https://github.com/cdown/sshrc (forked/became `hi.sh`)
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but _highly_ recommended to configure `~/.ssh/config` hosttags)
