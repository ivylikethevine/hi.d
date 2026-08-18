# How the files relate

The [README's "How it works"](../README.md#how-it-works) steps are the prose; this diagram is the
mechanism. Boxes are files (or the few directories acting as one), and every arrow is one of the four ways
a file here ever reaches another:

- **sources** - shell `source`/`.`, same process
- **shells out** - a `bash -c "source ...; fn"` subprocess (how fish and nu
  reach code written in bash)
- **runs** - executed as its own subprocess, never sourced
- **generates / writes** - the file exists only because another wrote it

Deliberately coarse: file granularity, those four edge kinds. What is _not_
drawn matters too — `hi.sh` itself, `scripts/`, `tests/` and `docs/` never
ship; the payload is `$_HI_PAYLOAD`, and the bench suite enforces its size.

```mermaid
flowchart TB
  subgraph client["client machine (stays home)"]
    hish["hi.sh"]
    overlay["~/.config/hi.d/<br/>settings.sh · colors · packages · tmux.conf · aliases.sh"]
  end

  subgraph target["target (payload, unpacked into /tmp or a permanent ~/hi.d)"]
    subgraph generated["generated per connect"]
      bootrc["hi.bashrc /<br/>.hi_fallback_rc"]
      grafts["rc grafts<br/>(guarded blocks in the host's rc files)"]
    end
    loadsh["load.sh"]
    core["common/core.sh"]
    pathssh["common/paths.sh"]
    headersh["common/header.sh"]
    gitp["common/git_prompt.sh"]
    targetssh["common/targets.sh"]
    aliases["misc/aliases.sh"]
    bashrc["shells/bash.sh"]
    zshrc["shells/zsh.zsh"]
    fishrc["shells/config.fish"]
    nurc["shells/config.nu"]
    kshrc["shells/ksh.sh"]
    osc52["shells/osc52.sh"]
    miscfiles["misc/<br/>colors · packages · theme.yml · vim.rc · nano.rc · tmux.conf"]
    configdir["config/ ($_HI_CONFIG_DIR)<br/>the overlay, as shipped"]
  end

  hish -->|"generates, ships over stdin"| bootrc
  hish -->|"ships (payload stream)"| loadsh
  overlay -->|"ships (second stream, lands in config/)"| configdir

  bootrc -->|sources| loadsh
  loadsh -->|sources| core
  loadsh -->|sources| headersh
  loadsh -->|"writes (from shells/*)"| grafts

  grafts -->|"carry the content of"| bashrc
  grafts -->|"carry the content of"| zshrc
  grafts -->|"carry the content of"| fishrc
  grafts -->|"carry the content of"| nurc

  core -->|sources| pathssh
  pathssh -->|"prefers, per file"| configdir
  bashrc -->|sources| core
  bashrc -->|sources| gitp
  bashrc -->|sources| aliases
  zshrc -->|sources| core
  zshrc -->|sources| gitp
  zshrc -->|sources| aliases
  fishrc -->|sources| pathssh
  fishrc -->|sources| aliases
  fishrc -->|"shells out to"| core
  fishrc -->|"shells out to"| headersh
  nurc -->|"shells out to"| core
  nurc -->|"shells out to"| headersh
  nurc -->|"shells out to"| gitp
  bootrc -.->|"sources (no-bash tier, via $ENV)"| kshrc

  aliases -->|"sources (overlay aliases.sh, last)"| configdir
  aliases -->|"runs (hi_copy)"| osc52
  miscfiles -->|"runs (vim.rc's yank autocmd)"| osc52
  hish -->|"runs (completion, on every TAB)"| targetssh
```

Three edges carry most of the design:

- **`hi.sh` never ships.** Everything on the target side has to work without
  it, which is why `load.sh` is the target's entry point and a peer of
  `hi.sh` at the tree root rather than a `common/` library.
- **fish and nu never source bash.** Their arrows to `core.sh`,
  `header.sh` and `git_prompt.sh` are _shell-outs_ - one implementation of
  the header, palette and git segment, rented per call, instead of three
  kept in sync (GLOSSARY: nu session tier).
- **`osc52.sh` is only ever run.** Both `hi_copy` and vim's yank autocmd
  execute it as a file at `$_HI_OSC52`, which is why the tmux/screen/zellij
  wrapping lives in one place and the file cannot be merged into
  `aliases.sh`.

The grafts deserve one footnote: each carries a tree-exists guard
(GLOSSARY: graft crash guard), so an arrow into a deleted `/tmp` tree goes
quiet instead of erroring - the diagram's dashed reality after a hard kill.
