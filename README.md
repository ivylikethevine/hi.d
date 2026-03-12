# hi.sh -> sshrc superset

**One config directory to rule them all, uniting all shells from all hosts!**

## How it works:

1. `~/.hi.d/hi.sh` is executed on the client, which archives (tar) and sends `~/.hi.d/` (except for .git files, this README, and the `local` directory) to the target via ssh/openssl. The target unarchives these files to a `/tmp` directory. (known as `$HI_TMPDIR`) `HI_ROOT` will be `~/.hi.d` on the client and `$HI_TMPDIR/.hi.d` on the target.
2. On the target, `$HI_ROOT/hi.bashrc` is executed, which runs `$HI_ROOT/load.sh`
3. `load.sh` determines the shells available on the target, loads `aliases.sh`, runs `check.sh`, copies the configurations for shells from the `$HI_ROOT` folder to the host, and then starts a session on the target in the highest priority shell (fish > zsh > bash).
4. When the ssh session is broken, the `load.sh` changes are cleaned up automatically via a `trap`, and the `/tmp` directory itself is deleted by part of the code copied from the client to the target in `hi.sh`.

**_IMPORTANT: Local-only changes MUST remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc._**

### Installation/Usage

- clone this repo to `~/`
- `mv ~/sshrc.d ~/.hi.d`
- `~/.hi.d/local/install.sh`
- reload your shell!
- configure `~/.ssh/config` tags via sshm
- configure `~/.hi.d/local/group_colors` to preferences
- say `hi`!
- [optional] `~/.hi.d/local/unlink.sh` to remove git tracking, etc.
- [optional] modify `~/.hi.d/aliases.sh`, `~/.hi.d/common/check.sh`, `~/.hi.d/misc/*`, and `~/.hi.d/shells/*` to your liking! (required parts of those files are commented as such)

--
Usage: `hi foo` (just like ssh!)
--

Reminder - place local only changes after the "`# hi-config-end`" comment in the local files. **Anything in this directory will be copied to all hosts connected to via `hi`.**

#### Supported Configs/File List

- `bash.sh`
- `zsh.zsh`
- `config.fish`
- `misc/nano.rc`
- `misc/vim.rc`
- `misc/tmux.conf`
- `hi.sh` - run on client
- `load.sh` - chainloader executed on target
- `common/aliases.sh` - shared aliases between bash, zsh, and fish
- `common/check.sh` - check for commonly used commands and displays results in header
- `common/prompt_colors.sh` - unified coloration for usernames & hosts (see `local/create_host_colors`)
- `local/install.sh` - configure local shells to use hi.d configurations, install, and update
- `local/unlink.sh` - remove identifiable information
- `local/create_host_colors.sh` - generates `common/user_colors` and `common/host_colors` from `~/.ssh/config` and `local/group_colors`
- `local/group_colors` - user defined coloration for hostnames/usernames (not copied to targets)

##### Hostname, Username, and Group/Tag Colors

`hi` uses the _leftmost_ tag in your `~/.ssh/config` tags for each host to determine which color to apply to the prompt hostname in all 3 shells.

The following will apply the `laptop` tag coloring to the hostname `foo` and the `root` username coloring as defined in `local/group_colors`. (This file will be automatically generated on first use of `hi`, or manually via `hi_colorgen` after installation).

`~/.ssh/config` example

```bash
# Tags: laptop, work
Host foo
  HostName bar.com
  User root
```

`~/.hi.d/local/group_colors` example

```csv
# hostname tag color_bash color_fish
hostname,laptop,\e[0;34m,brred

# username name color_bash color_fish
username,root,\e[0;31m,red
```

The above `~/.ssh/config` and `~/.hi.d/local/group_colors` will generate the following

`~/.hi.d/common/host_colors` result

```csv
# hostname color_bash color_fish
laptop,\e[0;34m,brred
```

`~/.hi.d/common/user_colors` result

```csv
# username color_bash color_fish
root,\e[0;31m,red
```

###### Built from/with:

- sshrc - https://github.com/cdown/sshrc (built into `hi.sh`)
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but _highly_ recommended to configure `~/.ssh/config`)

TBD Features:

- nomad alloc exec
- docker exec
- tmux
- screen
