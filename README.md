# hi.sh -> sshrc superset

Chainloader to unify local configuration with portable variations for ssh hosts. Order of execution:
First, `~/.sshrc` is executed, which chainloads `~/.sshrc.d/ssh.rc`. The second loader determines the shell, loads aliases, and then starts a session. For local configurations, stubs are used to load the shared files under `~/.sshrc.d/`. Local-only changes should remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc.

configured vim to actually be `ln /home/$USER/.vimrc /home/$USER/sshrc.d/.vimrc`
`du -sb --exclude .git --exclude .gitignore --exclude README.md --exclude hi.sh --exclude install.sh --exclude stubs --apparent-size` -> filesize (needs to be under 64k)

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

## Required Stubs (view stubs folder)

Reminder - place local only changes after the "`# sshrc-config`" comment in the local files. **Anything in this directory will be copied to all hosts connected to via `sshrc` (or the "hi" alias).**

#### Supported Configs

Shell Configurations

- `bash.rc`
- `zsh.rc`
- `.config/fish/config.fish`

Editor Configurations

- `nano.rc`
- `vim.rc`

##### Other Features

- `ssh.rc` - chainloader
- `aliases.rc` - shared aliases between bash, zsh, and fish
- `check.rc` - check for commonly used commands
