# hi.sh -> sshrc superset

Chainloader to unify local configuration with portable variations for ssh hosts. Order of execution:
First, `~/.hi.d/hi.sh` is executed, which chainloads `~/.hi.d/load.sh`. The second loader determines the shell, loads aliases, and then starts a session. For local configurations, stubs are used to load the shared files under `~/.hi.d/`. Local-only changes should remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc.

configured vim to actually be `ln /home/$USER/.vimrc /home/$USER/hi.d/.vimrc`
`du -sb --exclude .git --exclude .gitignore --exclude README.md --exclude hi.sh --exclude install.sh --exclude stubs --apparent-size` -> filesize (needs to be under 64k)

- shellcheck????
  Built using:

- sshrc - https://github.com/cdown/sshrc (built into `hi.sh`)
  - bring local configuration to remote hosts
- sshm - https://github.com/Gu1llaum-3/sshm (optional, but useful to configure `~/.ssh/config`)
  - organize ssh hosts

Possible features:

- nomad alloc exec
- docker exec
- install/check script that diffs users files against a stubs directory in this project?
- investigate sshd config
- tmux
- screen

## Required Stubs (view stubs folder)

Reminder - place local only changes after the "`# hi-config`" comment in the local files. **Anything in this directory will be copied to all hosts connected to via `hi`.**

#### Supported Configs

Shell Configurations

- `bash.sh`
- `zsh.zsh`
- `.config/fish/config.fish`

Editor Configurations

- `nano.rc`
- `vim.rc`

##### Other Features

- `load.sh` - chainloader
- `aliases.sh` - shared aliases between bash, zsh, and fish
- `check.sh` - check for commonly used commands
- `tmux.conf` - tmux configuration/support
- `install.sh` - configure local shells to use hi.d configurations (compare against stubs folder)

Goals:

- maximize amount of tracked configurations

TODO:

- unify colors between all shells
- swap to sh & copy over minimal config if bash not installed
