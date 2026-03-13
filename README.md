# hi.sh -> sshrc superset

**One config directory to rule them all, uniting all shells from all hosts!**

## How it works:

1. `~/hi.d/hi.sh` is executed on the client, which archives (tar) and sends `~/hi.d/` (except for .git files, this README, and the `local` directory) to the target via ssh/openssl. The target unarchives these files to a `/tmp` directory. (known as `$HI_TMPDIR`) `HI_ROOT` will be `~/hi.d` on the client and `$HI_TMPDIR/hi.d` on the target.
2. On the target, `$HI_ROOT/hi.bashrc` is executed, which runs `$HI_ROOT/load.sh`
3. `load.sh` determines the shells available on the target, loads `aliases.sh`, runs `check.sh`, copies the configurations for shells from the `$HI_ROOT` folder to the host, and then starts a session on the target in the highest priority shell (fish > zsh > bash).
4. When the ssh session is broken, the `load.sh` changes are cleaned up automatically via a `trap`, and the `/tmp` directory itself is deleted by part of the code copied from the client to the target in `hi.sh`.

**_IMPORTANT: Local-only changes MUST remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc._**

### Installation/Usage

- clone this repo to `~/`
- `mv ~/sshrc.d ~/hi.d`
- `~/hi.d/scripts/install.sh`
- reload your shell!
- configure `~/.ssh/config` tags via sshm
- configure `~/hi.d/data/group_colors` to preferences
  - then run `hi_colorgen` to regenerate colors
- configure `~/hi.d/data/packages_config` to preferences
- say `hi`!
- [optional] `~/hi.d/scripts/unlink.sh` to remove git tracking, etc.
- [optional] modify `~/hi.d/aliases.sh`, `~/hi.d/common/check.sh`, `~/hi.d/misc/*`, and `~/hi.d/shells/*` to your liking! (required parts of those files are commented as such)

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
- `common/colors.sh` - unified coloration for usernames & hosts (see `scripts/colorgen`)
- `scripts/install.sh` - configure local shells to use hi.d configurations, install, and update
- `scripts/unlink.sh` - remove identifiable information
- `scripts/colorgen.sh` - generates `data/user_colors` and `data/host_colors` from `~/.ssh/config`, `data/travel_config`, and `data/group_colors`
- `data/group_colors` - user defined coloration for hostnames/usernames (not copied to targets)

##### Hostname, Username, and Group/Tag Colors

`hi` uses the _leftmost_ tag in your `~/.ssh/config` tags for each host to determine which color to apply to the prompt hostname in all 3 shells on the client device, but will use `$HI_ROOT/data/travel_config` (in the context of the target filesystem) on the target (in-progress).

###### Built from/with:

- sshrc - https://github.com/cdown/sshrc (built into `hi.sh`)
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but _highly_ recommended to configure `~/.ssh/config`)

TBD Features:

- nomad alloc exec
- docker exec
- tmux
- screen
