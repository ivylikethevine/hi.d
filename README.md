# hi.sh -> sshrc superset

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

## How it works

1. `~/hi.d/hi.sh` runs on the client. It archives `~/hi.d/` (minus `.git`, this README, and `scripts/`) and sends it to the target, which unpacks it into a `/tmp` directory. `_HI_ROOT` is `~/hi.d` on the client and `$_HI_TMPDIR/hi.d` on the target.
2. On the target, `$_HI_ROOT/hi.bashrc` sources `$_HI_ROOT/load.sh` and calls `load`.
3. `load.sh` prints the header, appends hi's shell configs to the host's own rc files, and starts a session in the highest priority shell available (fish > zsh > bash).
4. When the session ends, `load.sh`'s `trap` strips those additions back out, and the `/tmp` directory is removed by the cleanup trap `hi.sh` set up on connect.
5. `hi <target> 'some command'` skips the interactive session and just runs the command there, like `ssh` does.

The setup in steps 1-2 is plain POSIX and runs under `sh`, so it works even if the target has no `bash` at all - `hi` still copies the whole of `~/hi.d` over in that case, but hands off to the best plain shell available (`zsh`/`fish`/`sh`) with just our aliases loaded, instead of the full `load.sh` experience, which needs `bash`.

**_IMPORTANT: Local-only changes MUST stay in `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, etc. - anything in this directory is copied to every host you say `hi` to._**

### Docker containers

`hi <name>` also works against a running docker container - if `<name>` isn't a `Host` in `~/.ssh/config` but is a running container (by name or ID), `hi` copies `~/hi.d` in and chainloads `load.sh` exactly like the ssh path, for an identical session (colors, prompt, aliases, vim/nano configs, etc). No openssl armoring is needed here (`docker exec -i` passes stdin through as raw bytes), and cleanup happens once you exit. The container needs `bash` for the full experience; without it, `hi` drops you into the best plain shell available (`zsh`/`fish`/`sh`) with our aliases and a warning.

### Windows hosts

`hi <target>` works against Windows OpenSSH targets too, at whatever level the target supports:

- **WSL, Git Bash, Cygwin or MSYS2 reachable on `PATH`**: the full experience (header, colors, git prompt, aliases) - same code path as any other ssh host.
- **Stock Windows OpenSSH with no `bash` at all**: `hi` falls back to a plain interactive PowerShell session (no hi.d styling - that's bash-only) instead of failing outright. This still happens over the _same single ssh connection_, since `cmd.exe` (Windows' default `DefaultShell`) understands `||` the same way a POSIX shell does; a target with `DefaultShell` set to PowerShell directly is outside what this fallback can detect.

### Nomad allocations

`hi <alloc-id>` also works against a running Nomad allocation (matched by ID/prefix, checked after the ssh-host and docker-container checks) - same idea, same session, same code path as docker. Since `nomad alloc exec` has no `docker cp`/`-e` equivalent, files are streamed in with `exec -i` + `cat >` and env vars are set through a `sh -c "export ...; exec ..."` wrapper. Multi-task allocations would need `nomad alloc exec -task <name>`, which `hi` doesn't pass through, so they need a single unambiguous task.

### Installation/Usage

- clone this repo to `~/`
- `~/hi.d/scripts/install.sh` (re-run it any time; it repairs its own lines, even if hi.d moved)
- reload your shell!
- configure `~/.ssh/config` tags via sshm
- [optional] pin specific colors in `~/hi.d/data/color_overrides` - everything else gets a color automatically
  - run `hi_colors` to preview what every ssh host/your user resolves to
- configure `~/hi.d/data/packages` to your preferences
- [optional] in `header.sh` set any of `_HI_HEADER_TIMESTAMP`, `_HI_HEADER_SYSINFO`, `_HI_HEADER_IDENTITY`, and `_HI_HEADER_CHECK` to `0` to turn off that piece of the header/greeting across shells
- [optional] in `git_prompt.sh` set `_HI_GIT_PROMPT` to `0` to turn off the git prompt across shells
- [optional] in `colors.sh` set `_HI_MAX_WIDTH` to your preferred terminal width (default is 80)
- say `hi`!
- [optional] modify `~/hi.d/misc/*` and `~/hi.d/shells/*` to your liking!

--
Usage: `hi foo` (just like ssh!)
--

Reminder - place local only changes after the "`# hi-config-end`" comment in the local files.

#### File list

| file                      | what it does                                                        |
| ------------------------- | ------------------------------------------------------------------- |
| `hi.sh`                   | runs on the client: pick the target, copy hi.d, chainload `load.sh` |
| `load.sh`                 | runs on the target: header, rc grafting, shell handoff, cleanup     |
| `common/paths.sh`         | every path hi uses (the only file fish and sh both source)          |
| `common/bootstrap.sh`     | one-line entry point for bash/zsh: paths + colors                   |
| `common/colors.sh`        | palette, `cecho`, host/user color resolution (see below)            |
| `common/check.sh`         | reads `data/packages`, reports what the host has                    |
| `common/header.sh`        | the connect/disconnect banner, shared by every shell                |
| `common/git_prompt.sh`    | bash/zsh git prompt, matching fish's built-in `fish_vcs_prompt`     |
| `common/targets.sh`       | every `hi` target (ssh/docker/nomad), for all three completions     |
| `shells/aliases.sh`       | aliases shared by bash, zsh and fish                                |
| `shells/bash.sh`          | bash config                                                         |
| `shells/zsh.zsh`          | zsh config                                                          |
| `shells/config.fish`      | fish config                                                         |
| `misc/*`                  | vim, nano and eza configs                                           |
| `data/packages`           | what `check.sh` looks for, as `cmd:priority[,alternative:priority]` |
| `data/color_overrides`    | optional color pins for hostnames/usernames/hosttags                |
| `scripts/install.sh`      | configure the local shells, install and update                      |
| `scripts/test_aliases.sh` | check `aliases.sh` still loads in dash/bash/zsh/fish                |

##### Hostname, username, and group/tag colors

Every username and hostname gets a color automatically, deterministically derived from its name - there's nothing to generate and nothing that can go missing. To pin a specific color instead, add a line to `~/hi.d/data/color_overrides` (`username,root,red` / `hostname,prod-db,yellow` / `hosttag,desktop,green`); `hosttag` entries match the _leftmost_ tag in a `# Tags: ...` comment placed directly above a `Host` line in `~/.ssh/config`. Run `hi_colors` any time to preview what every ssh host and your user currently resolve to, rendered in their actual color.

###### Built from/with

- sshrc - https://github.com/cdown/sshrc (forked/became `hi.sh`)
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but _highly_ recommended to configure `~/.ssh/config`)
