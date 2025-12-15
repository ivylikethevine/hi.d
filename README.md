# SSHRC-Config

Chainloader to unify local configuration with portable variations for ssh hosts. Order of execution:
First, `~/.sshrc` is executed, which chainloads `~/.sshrc.d/.sshrc`. The second loader determines the shell, loads aliases, and then starts a session. For local configurations, stubs are used to load the shared files under `~/.sshrc.d/`. Local-only changes should remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc.

configured vim to actually be `ln /home/$USER/.vimrc /home/$USER/sshrc.d/.vimrc`

Built using:

- sshm - github.com/Gu1llaum-3/sshm
  - organize ssh hosts
- sshrc - https://github.com/cdown/sshrc
  - bring local configuration to remote hosts

## Required Stubs

Reminder - place local only changes after the "`# sshrc-config`" comment in the local files. **Anything in this directory will be copied to all hosts connected to via `sshm` (or the "hi" alias).**

### `~/.sshrc`

```bash
#!/bin/bash
source $SSHHOME/.sshrc.d/ssh.rc
```

### `~/.bashrc`

### `~/.zshrc`

### `~/.config/fish/config.fish`

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

Possible todos:

- gitconfig
- gitignore
