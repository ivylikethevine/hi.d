# File list

| file                                            | what it does                                                                                                                                                            |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hi.sh`                                         | runs on the client: pick the target, copy hi.d, chainload `load.sh`                                                                                                     |
| `load.sh`                                       | runs on the target: header, rc grafting, shell handoff, cleanup                                                                                                         |
| `common/paths.sh`                               | every path hi uses (the only file fish and sh both source)                                                                                                              |
| `common/core.sh`                                | the entry point every bash/zsh script sources: settings, paths, palette, `_hi_cecho`, color resolution                                                                  |
| `common/header.sh`                              | the connect/disconnect banner, shared by every shell, plus the `misc/packages` check it ends with                                                                       |
| `common/git_prompt.sh`                          | bash/zsh git prompt, matching fish's built-in `fish_vcs_prompt`                                                                                                         |
| `common/targets.sh`                             | every `hi` target (ssh/docker/podman/nomad/kube), for all three completions - cached and timeout-bounded                                                                |
| `shells/osc52.sh`                               | stdin to the _client's_ clipboard over OSC 52 - tmux/screen passthrough, raw under zellij - behind `hi_copy` and `vim.rc`'s yank autocmd, off via `_HI_DISABLE_OSC52=1` |
| `shells/bash.sh`                                | bash config                                                                                                                                                             |
| `shells/zsh.zsh`                                | zsh config                                                                                                                                                              |
| `shells/config.fish`                            | fish config                                                                                                                                                             |
| `shells/config.nu`                              | nushell config - shells out to bash for the header, palette and git segment                                                                                             |
| `shells/ksh.sh`                                 | the ksh/mksh tier's POSIX git segment, the one prompt piece written without bash                                                                                        |
| `misc/aliases.sh`                               | personal aliases shared by bash, zsh and fish - freely editable, off wholesale via `_HI_DISABLE_ALIASES=1`                                                              |
| `misc/vim.rc`, `misc/nano.rc`, `misc/theme.yml` | vim, nano and eza configs                                                                                                                                               |
| `misc/tmux.conf`                                | tmux config, reached via the `tmux` alias - override in `~/.config/hi.d/tmux.conf`, off via `_HI_DISABLE_TMUX=1`                                                        |
| `misc/packages`                                 | default for the packages check, as `cmd:priority[,alternative:priority]` - override in `~/.config/hi.d/packages`                                                        |
| `misc/colors`                                   | default color pins for hostnames/usernames/hosttags - override in `~/.config/hi.d/colors`                                                                               |
| `scripts/install.sh`                            | configure the local shells, install, update and uninstall - `--prefix`/`$DESTDIR` for packagers                                                                         |
| `scripts/uninstall.sh`                          | one-line shim onto `install.sh --uninstall` (`hi_uninstall`)                                                                                                            |
| `scripts/color_preview.sh`                      | preview what every ssh host/user resolves to (`hi_color_preview`)                                                                                                       |
| `scripts/packages_preview.sh`                   | preview the packages check: each priority, its colors, a real example of each, then the check itself (`hi_packages_preview`)                                             |
| `scripts/table.sh`                              | the boxed table both preview scripts draw with - sourced, never run, and deliberately outside the shipped `common/`                                                      |
| `scripts/doctor.sh`                             | pre-flight report: tree, config, timed backend probes, and a target's resolution + ssh reachability (`hi_doctor`, `hi --doctor`)                                        |
| `packaging/`                                    | build-time only, never installed: `mkpkg.sh`, `stamp.sh`, `bump.sh`, and the AUR/Homebrew/nfpm manifests                                                                |
| `bin/hi`                                        | the basher shim - resolves through the cellar symlink and exports `_HI_HOME`                                                                                            |
| `tests/test_runner.sh`                          | unified runner - times and summarizes every test below (or a chosen subset) (`hi_test`)                                                                                 |
| `tests/test_lib.sh`                             | the whole suite skeleton: asserts/counters, scratch dir, skip preamble, probe commands, poll/pty helpers                                                                |

The test suites are deliberately not repeated here: each suite's opening
comment block says exactly what it covers, and `tests/test_runner.sh --list-paths`
prints the live list — group, name, and path — so the truth can't drift the
way a second copy of it in this table once did.
