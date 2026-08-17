# hi's nushell config - the session shell tier for nu, which is not POSIX at
# all: everything common/ owns is reached by shelling out to `bash -c`, the
# way config.fish already does, and the aliases are a stated subset.
# GLOSSARY: nu session tier - why shell-outs, why load.sh's ladder, the cost
# GLOSSARY: nu alias subset - what is ported, what is not, and why

$env.config = ($env.config? | default {} | merge {
  show_banner: false
})

# --- what hi exported into the environment ------------------------------------
#
# The toggles and paths come from the env, not from settings.sh: that file is
# POSIX shell, and load.sh has already sourced it on the way here.

# no `get -i`/`get -o` here: -i was deprecated in nu 0.106 and its replacement
# -o does not exist before it, so flag-free `in` is what works on both sides
def _hi_off [name: string] {
  (if $name in $env { $env | get $name } else { "0" }) == "1"
}

# Live-session gate: a dead graft or bystander nu has none of hi's env, and
# everything reaching $env._HI_* must stand down rather than error.
# GLOSSARY: graft crash guard - why every graft guards, and nu's exception
let _hi_live = ($env._HI_CORE? | default "" | path exists)

# --- the styled session: header, prompt, editors -------------------------------
#
# One gate so a future section cannot forget it; env assignments propagate
# out of nu if-blocks (nested too), which is what makes the wrapper work.

if $_hi_live {
  # --- header: once, at startup, the same call config.fish's greeting makes
  if not (_hi_off "_HI_DISABLE_HEADER") {
    ^bash -c ("source " + $env._HI_HEADER + "; hi_header Online")
  }

  # --- prompt
  if (_hi_off "_HI_DISABLE_PROMPT") {
    # hi is not styling this session's prompt; leave nu's own alone.
    $env.PROMPT_COMMAND_RIGHT = {|| "" }
  } else {
    # user@host, resolved once - hi's hashed colors never change mid-session.
    # Every bash body below is a plain string, never a $"..." interpolated
    # one (see the "one writing rule" in GLOSSARY: nu session tier).
    $env._HI_NU_USERHOST = (^bash -c ("source " + $env._HI_CORE + '
    _hi_prime_identity
    printf "%b" " $(_hi_user_escape)$(_hi_whoami)$(_hi_at_color)@$(_hi_host_escape)$(_hi_hostname)$NC"'))

    # the separator, from the same setting every other shell reads
    $env._HI_NU_END = (^bash -c ("source " + $env._HI_CORE + "; _hi_prompt_end NU '>'"))

    # Decided once out here and captured by the closure - none of it changes
    # mid-session. $HOME rather than $nu.home-path (renamed home-dir; either
    # spelling errors across the rename); a non-empty $NO_COLOR blanks the
    # one color nu adds itself.
    let home = ($env.HOME? | default "")
    let dir_pre = (if (($env.NO_COLOR? | default "") != "") { "" } else { (ansi blue_bold) })
    let dir_post = (if $dir_pre == "" { "" } else { (ansi reset) })
    $env.PROMPT_COMMAND = {||
      let dir = (if $home != "" and ($env.PWD | str starts-with $home) {
        $env.PWD | str replace $home "~"
      } else { $env.PWD })
      $"($env._HI_NU_USERHOST) ($dir_pre)($dir)($dir_post)"
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

  # --- editors
  if not (_hi_off "_HI_DISABLE_EDITORS") {
    if (which vim | is-not-empty) {
      $env.VIMINIT = $"let $MYVIMRC='($env._HI_VIMRC)' | source $MYVIMRC"
    }
  }
}

# --- aliases ------------------------------------------------------------------
#
# The ported subset: fixed-argument external commands, whose meaning survives
# translation. Deliberately absent: nu's structured builtins (ls, cat, grep,
# ps, ...), sudo, the rc-time-built aliases, and `..`/`...`.
# GLOSSARY: nu alias subset - the full what-and-why of each exclusion
#
# Top level and unconditional, necessarily: `alias` is parse-time and
# block-scoped in nu, so a runtime `if` defines these into a scope that
# evaporates before the prompt - the first version did exactly that and no
# alias ever landed. _HI_DISABLE_ALIASES therefore cannot gate this tier.

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
