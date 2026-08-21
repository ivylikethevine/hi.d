# hi

> Copy your shell config to a target, start a session there, and clean up on exit.
> Targets resolve in order: SSH host, Docker/Podman container, Nomad allocation, Kubernetes pod.
> More information: <https://github.com/ivylikethevine/say-hi>.

- Start an interactive session on an SSH host, with your own prompt, colors and aliases:

`hi {{host}}`

- Run a single command on a target and exit, like `ssh` does:

`hi {{host}} '{{command}}'`

- Start a session inside a running container, allocation or pod:

`hi {{name_or_id}}`

- Connect through a jump host (every `ssh` option passes through unchanged):

`hi -J {{bastion}} {{host}}`

- Diagnose a slow or failing target (read-only: backends, config, reachability):

`hi --doctor {{host}}`

- Print the installed version:

`hi --version`

- Run the session inside a tmux on the target (needs say-hi installed there), so a drop detaches:

`hi --tmux {{host}}`

- Re-run the feature toggle prompts (header, prompt, git status, aliases, ...):

`hi --configure`
