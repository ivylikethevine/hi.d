# hi.sh -> sshrc superset

First, `~/.hi.d/hi.sh` is executed on the client, which ssh's into the target, sends and chainloads `~/.hi.d/load.sh` as well as the contents of `.hi.d`, except for git files, this README, and the `scripts` directory. `load.sh` determines the shells available on the target, loads aliases, and then starts a session on the target. Local-only changes should remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc.

Built from/with:

- sshrc - https://github.com/cdown/sshrc (built into `hi.sh`)
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but useful to configure `~/.ssh/config`)

TBD Features:

- nomad alloc exec
- docker exec
- tmux
- screen

Reminder - place local only changes after the "`# hi-config-end`" comment in the local files. **Anything in this directory will be copied to all hosts connected to via `hi`.**

## Installation

- clone this repo to `~/`
- `mv ~/sshrc.d ~/.hi.d`
- `./.hi.d/scripts/install.sh`
- reload your shell!
- [optional] `./.hi.d/scripts/unlink.sh` to remove git tracking, etc.
- [optional] configure `~/.ssh/config` tags via sshm
- [optional] configure `~/.group_colors` to preferences

### Hostname Tag Colors

`hi` uses the _leftmost_ tag in your `~/.ssh/config` tags for each host to determine which color to apply to the prompt hostname in all 3 shells.

```bash
# Tags: laptop, work
Host foo
  HostName bar.com
  User root
```

Will apply the `laptop` hostname coloring and the `root` username coloring as defined in `scripts/group_colors`. (This file will be automatically generated on first use of `hi`, or manually via `hi_colorgen` after installation).

#### Supported Configs

- `bash.sh`
- `zsh.zsh`
- `config.fish`
- `optional/nano.rc`
- `optional/vim.rc`
- `optional/tmux.conf`

- `common/aliases.sh` - shared aliases between bash, zsh, and fish
- `common/check.sh` - check for commonly used commands

- `hi.sh` - sshrc-fork executable
- `load.sh` - chainloader
- `scripts/install.sh` - configure local shells to use hi.d configurations, install, and update
- `scripts/unlink.sh` - remove identifiable information
