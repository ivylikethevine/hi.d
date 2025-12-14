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
source $SSHHOME/.sshrc.d/.sshrc
```

### `~/.bashrc`

```bash
source ~/.sshrc.d/.bashrc
source ~/.sshrc.d/.aliasesrc
alias config="nano ~/.sshrc.d/.bashrc"
alias local_config="nano ~/.bashrc"
# sshrc-config
```

### `~/.zshrc`

```bash
source ~/.sshrc.d/.zshrc
source ~/.sshrc.d/.aliasesrc
alias config="nano ~/.sshrc.d/.zshrc"
alias local_config="nano ~/.zshrc"
# sshrc-config
```

### `~/.config/fish/config.fish`

```bash
source ~/.sshrc.d/config.fish
source ~/.sshrc.d/.aliasesrc
alias config="nano ~/.sshrc.d/config.fish"
alias local_config="nano ~/.config/fish/config.fish"
# sshrc-config
```

#### Supported Configs

Shell Configurations

- `.bashrc`
- `.zshrc`
- `.config/fish/config.fish`

Editor Configurations

- `.nanorc`
- `.vimrc`

##### Other Features

- `.sshrc` - chainloader
- `.aliasesrc` - shared aliases between bash, zsh, and fish
- `.checkrc` - check for commonly used commands

Possible todos:

- gitconfig
- gitignore
