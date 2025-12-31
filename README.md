# hi.sh -> unity of sshm + sshrc

Chainloader to unify local configuration with portable variations for ssh hosts. Order of execution:
First, `~/.sshrc` is executed, which chainloads `~/.sshrc.d/ssh.rc`. The second loader determines the shell, loads aliases, and then starts a session. For local configurations, stubs are used to load the shared files under `~/.sshrc.d/`. Local-only changes should remain in `~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish`, etc.

configured vim to actually be `ln /home/$USER/.vimrc /home/$USER/sshrc.d/.vimrc`
`du -s --exclude .git --exclude .gitignore --exclude README.md --exclude hi.sh --apparent-size` -> filesize (needs to be under 64k)

Built using:

- sshm - https://github.com/Gu1llaum-3/sshm (optional, but useful to configure `~/.ssh/config`)
  - organize ssh hosts
- sshrc - https://github.com/cdown/sshrc (built into `hi.sh`)
  - bring local configuration to remote hosts

Had to modify sshrc `/usr/bin/sshrc` -> hi.sh
Possible features:

- nomad alloc exec
- docker exec
- install/check script that diffs users files against a stubs directory in this project?

```bash
sudo mv /usr/bin/sshrc /usr/bin/sshrc.bak
chmod +x ~/.sshrc.d/hi.sh
sudo ln ~/.sshrc.d/hi.sh /usr/bin/sshrc
```

## Required Stubs

Reminder - place local only changes after the "`# sshrc-config`" comment in the local files. **Anything in this directory will be copied to all hosts connected to via `sshrc` (or the "hi" alias).**

### `~/.sshrc`

```bash
#!/bin/bash
source $SSHHOME/.sshrc.d/ssh.rc
source $SSHHOME/.sshrc.d/aliases.rc
run_sshrc
```

### `~/.bashrc`

```bash
# LOCAL
source ~/.sshrc.d/aliases.rc
source ~/.sshrc.d/bash.rc
alias config="nano ~/.sshrc.d/bash.rc"
alias local_config="nano ~/.bashrc"
alias aliases="nano ~/.sshrc.d/aliases.rc"
# sshrc-config
```

### `~/.zshrc`

```bash
# LOCAL
source ~/.sshrc.d/aliases.rc
source ~/.sshrc.d/zsh.rc
alias config="nano ~/.sshrc.d/zsh.rc"
alias local_config="nano ~/.zshrc"
alias aliases="nano ~/.sshrc.d/aliases.rc"
# sshrc-config
```

### `~/.config/fish/config.fish`

```bash
# LOCAL
source ~/.sshrc.d/aliases.rc
source ~/.sshrc.d/config.fish
alias config="nano ~/.sshrc.d/config.fish"
alias local_config="nano ~/.config/fish/config.fish"
alias aliases="nano ~/.sshrc.d/aliases.rc"
# sshrc-config
```

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
