# hi.sh -> sshrc superset

Chainloader to unify local configuration with portable variations for ssh hosts. Order of execution:
First, `~/.hi.d/hi.sh` is executed on the client, which ssh's into the target device, sends and chainloads `~/.hi.d/load.sh`. The second loader determines the shell, loads aliases, and then starts a session on the target device. For local configurations on the client device, stubs are used to load the shared files under `~/.hi.d/`. Local-only changes should remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc.

- sshrc - https://github.com/cdown/sshrc (built into `hi.sh`)
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but useful to configure `~/.ssh/config`)

TBD Features:

- nomad alloc exec
- docker exec
- tmux
- screen

## Required Stubs (view stubs folder)

Reminder - place local only changes after the "`# hi-config`" comment in the local files. **Anything in this directory will be copied to all hosts connected to via `hi`.**

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
