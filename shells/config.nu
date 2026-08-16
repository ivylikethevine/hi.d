# hi's nushell config - the session shell tier for nu.
#
# Nu is the first shell hi styles that is not POSIX at all, so nothing in
# shells/aliases.sh or common/ can be sourced here: no `source` of a .sh file,
# no `$( )`, no `[ -f x ]`. What it can do is what shells/config.fish already
# does for the same reason - shell out to `bash -c` for the parts common/ owns,
# so hi's header, palette and git segment are rendered by the one implementation
# rather than a second one written in nu.
#
# That is also why nu lives in load.sh's session-shell ladder and NOT in hi.sh's
# no-bash $_HI_SHELL_LADDER: load.sh only ever runs where bash exists, which is
# exactly the condition these shell-outs need. A nu target without bash gets the
# POSIX fallback tier, same as before.
#
# Cost, stated rather than hidden: one `bash -c` per prompt for the git segment.
# shells/bash.sh avoids that fork with _hi_git_prompt's out-var form, and
# config.fish avoids it by using fish's own fish_vcs_prompt. Nu has neither, so
# the choice is a fork per prompt or a third git implementation - and a third
# implementation that drifts is worse than a fork. The user@host half is
# resolved once at startup, below, because it never changes.
#
# ALIASES: this file ports a *subset* of shells/aliases.sh, listed at the bottom
# with what was left out and why. A silently smaller alias set would be worse
# than a stated one.

$env.config = ($env.config? | default {} | merge {
  show_banner: false
})

# --- what hi exported into the environment ------------------------------------
#
# The toggles and paths come from the env, not from settings.sh: that file is
# POSIX shell, and load.sh has already sourced it on the way here.

def _hi_off [name: string] {
  ($env | get -i $name | default "0") == "1"
}

# --- header -------------------------------------------------------------------
#
# Once, at startup, exactly as config.fish does it (see its `set -q fish_greeting`
# line). load.sh has already printed its own header for the session; this is the
# same call fish makes so a nu session looks like a fish one.

if not (_hi_off "_HI_DISABLE_HEADER") {
  ^bash -c ("source " + $env._HI_HEADER + "; hi_header Online")
}

# --- prompt -------------------------------------------------------------------

if (_hi_off "_HI_DISABLE_PROMPT") {
  # hi is not styling this session's prompt; leave nu's own alone.
  $env.PROMPT_COMMAND_RIGHT = {|| "" }
} else {
  # user@host, resolved once: the escapes are hi's hashed per-user and per-host
  # colors, and neither changes for the life of a session. _hi_prime_identity is
  # what shells/bash.sh calls before reading them.
  #
  # Every bash body below is a plain string, never a $"..." interpolated one:
  # nu reads `(...)` inside an interpolation as its own subexpression, so a
  # bash `$(_hi_user_escape)` written there is run by *nu* as an external
  # command called _hi_user_escape, which is not one. Concatenation it is.
  $env._HI_NU_USERHOST = (^bash -c ("source " + $env._HI_CORE + '
    _hi_prime_identity
    printf "%b" " $(_hi_user_escape)$(_hi_whoami)$(_hi_at_color)@$(_hi_host_escape)$(_hi_hostname)$NC"'))

  # the separator, from the same setting every other shell reads
  $env._HI_NU_END = (^bash -c ("source " + $env._HI_CORE + "; _hi_prompt_end NU '>'"))

  $env.PROMPT_COMMAND = {||
    let dir = ($env.PWD | str replace $nu.home-path "~")
    $"($env._HI_NU_USERHOST) (ansi blue_bold)($dir)(ansi reset)"
  }

  # the git segment, and the one thing recomputed per prompt
  $env.PROMPT_COMMAND_RIGHT = {||
    if (_hi_off "_HI_DISABLE_GIT_STATUS") {
      ""
    } else {
      ^bash -c ("source " + $env._HI_CORE + "; source " + $env._HI_GIT_PROMPT + "; _hi_git_prompt")
    }
  }

  $env.PROMPT_INDICATOR = $" ($env._HI_NU_END) "
  $env.PROMPT_INDICATOR_VI_INSERT = $env.PROMPT_INDICATOR
  $env.PROMPT_INDICATOR_VI_NORMAL = $env.PROMPT_INDICATOR
  $env.PROMPT_MULTILINE_INDICATOR = "  | "
}

# --- editors ------------------------------------------------------------------

if not (_hi_off "_HI_DISABLE_EDITORS") {
  if (which vim | is-not-empty) {
    $env.VIMINIT = $"let $MYVIMRC='($env._HI_VIMRC)' | source $MYVIMRC"
  }
}

# --- aliases ------------------------------------------------------------------
#
# PORTED: the ones whose meaning survives translation - fixed-argument external
# commands. Nu aliases expand to a command, the same shape these have.
#
# DELIBERATELY NOT PORTED, and why:
#   * ls, cat, grep, rm, cp, ps, df  - nu has its own structured builtins for
#     these. Shadowing `ls` with an external `ls -lh` would hand back a string
#     where every downstream nu pipeline expects a table, which breaks the one
#     thing people use nu for. This is the big one.
#   * sudo                           - the POSIX trailing-space trick that makes
#     alias expansion continue is meaningless here; nu has no such rule.
#   * now, ehi, essh, zed, batcat, exa, eza, df, dig, ...
#                                    - these are built at rc time from $( ) and
#     $_HI_* variables in aliases.sh. Nu can build them, but they would then be
#     a second definition to keep in sync; deferred until someone wants them.
#   * .. and ...                     - nu resolves `..` natively in `cd`.
# The full set is always available in this session with `bash -lc '<cmd>'`.

if not (_hi_off "_HI_DISABLE_ALIASES") {
  # docker
  alias dcu = docker compose up
  alias dcud = docker compose up -d
  alias dcd = docker compose down
  alias dsp = docker system prune -fa

  # git - the largest group in aliases.sh that ports cleanly
  alias gl = git log --abbrev-commit --graph
  alias gf = git fetch -a
  alias gch = git checkout
  alias gcl = git clone
  alias gs = git status
  alias gst = git stash

  # archives and misc
  alias ctar = tar -zcvf
  alias utar = tar -zxvf
  alias mkex = chmod +x
  alias mindiff = diff -Bdw
  alias rsync = rsync -zvhPr --info=progress2
  alias scp = scp -Cr

  # hi's own helpers, which are scripts rather than shell functions
  alias hi = ^$env._HI_LAUNCHER
}
