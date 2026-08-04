# hi.sh -> sshrc superset

**One config directory to rule them all, uniting all shells from all hosts!**

_Don't `ssh`ush your hosts, say `hi`!_

## How it works:

1. `~/hi.d/hi.sh` is executed on the client, which archives (tar) and sends `~/hi.d/` (except for .git files, this README, and the `local` directory) to the target via ssh/openssl. The target unarchives these files to a `/tmp` directory. (known as `$_HI_TMPDIR`) `_HI_ROOT` will be `~/hi.d` on the client and `$_HI_TMPDIR/hi.d` on the target.
2. On the target, `$_HI_ROOT/hi.bashrc` is executed, which runs `$_HI_ROOT/load.sh`
3. `load.sh` determines the shells available on the target, loads `aliases.sh`, runs `check.sh`, copies the configurations for shells from the `$_HI_ROOT` folder to the host, and then starts a session on the target in the highest priority shell (fish > zsh > bash).
4. When the ssh session is broken, the `load.sh` changes are cleaned up automatically via a `trap`, and the `/tmp` directory itself is deleted by part of the code copied from the client to the target in `hi.sh`.

**_IMPORTANT: Local-only changes MUST remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc._**

### Installation/Usage

- clone this repo to `~/`
- `~/hi.d/scripts/install.sh`
- reload your shell!
- configure `~/.ssh/config` tags via sshm
- configure `~/hi.d/data/group_config` to preferences
  - then run `hi_colorgen` to regenerate colors
- configure `~/hi.d/data/packages_config` to preferences
- say `hi`!
- [optional] modify `~/hi.d/misc/*`, and `~/hi.d/shells/*` to your liking!

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
- `hi.sh` - run on client
- `load.sh` - chainloader executed on target
- `shells/aliases.sh` - shared aliases between bash, zsh, and fish
- `common/check.sh` - check for commonly used commands and displays results in header
- `common/colors.sh` - unified coloration for usernames & hosts (see `scripts/colorgen`)
- `scripts/install.sh` - configure local shells to use hi.d configurations, install, and update
- `scripts/colorgen.sh` - generates `data/user_colors` and `data/host_colors` from `~/.ssh/config`, `data/travel_config`, and `data/group_config`
- `data/group_config` - user defined coloration for hostnames/usernames (not copied to targets)

##### Hostname, Username, and Group/Tag Colors

`hi` uses the _leftmost_ tag in your `~/.ssh/config` tags for each host to determine which color to apply to the prompt hostname in all 3 shells on the client device.

###### Built from/with:

- sshrc - https://github.com/cdown/sshrc (forked/became `hi.sh`)
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but _highly_ recommended to configure `~/.ssh/config`)
