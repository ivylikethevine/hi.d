#!/bin/fish

# === start required configuration ===
set -q _HI_HOME; or set -gx _HI_HOME ~
# Every toggle this file, paths.sh's local-only gate and aliases.sh read bare.
# fish has no ${X:-0}, so the only way for those reads to be safe is for the
# variables to always exist - defaulted here, never assigned, so the settings
# file and the gate below can both still override.
for _hi_toggle in _HI_DISABLE_LOCAL _HI_REMOTE_SESSION _HI_DISABLE_HEADER \
    _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL _HI_DISABLE_GIT_STATUS \
    _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES
  set -q $_hi_toggle; or set -gx $_hi_toggle 0
end
set -e _hi_toggle
# the settings scripts/install.sh writes, ahead of paths.sh because paths.sh's
# local-only gate reads them (see the note by that gate). They are plain
# `export NAME=value` lines, which fish understands natively.
test -f $_HI_HOME/hi.d/misc/settings.sh; and source $_HI_HOME/hi.d/misc/settings.sh
source $_HI_HOME/hi.d/common/paths.sh
source $_HI_ALIASES

complete -c hi -f -a '(sh $_HI_TARGETS)' # "<target>\ttype" lines
complete exa --wraps eza

# fish can't run the bash/zsh side of hi, so the greeting, the package check
# and the color resolution all come from one bash call each
function fish_greeting
  # on a hi session load.sh already printed this and sets $fish_greeting to
  # suppress us; locally, nothing sets it and we print the header ourselves
  set -q fish_greeting; or bash -c "source $_HI_HEADER; hi_header Online"
end

# That bash call is a whole process for two color names that only change with
# the user, host or misc/colors. Memoized in a universal variable keyed on all
# three, so it runs on the first fish shell after a change and no others.
set -l hi_key "$USER@"(prompt_hostname)
test -f $_HI_COLORS; and set hi_key "$hi_key:"(command stat -c %Y $_HI_COLORS 2>/dev/null; or command stat -f %m $_HI_COLORS 2>/dev/null)
if not set -q __hi_colors_key; or test "$__hi_colors_key" != "$hi_key"
  set -l hi_colors (bash -c "source $_HI_SHARED; _hi_user_color; _hi_host_color")
  set -U __hi_color_user $hi_colors[1]
  set -U __hi_color_host $hi_colors[2]
  set -U __hi_colors_key "$hi_key"
end
set -gx fish_color_user $__hi_color_user
set -gx fish_color_host $__hi_color_host
set -gx fish_color_host_remote $fish_color_host

# wrapper so aliases (which are functions in fish) still work under sudo.
# args are passed through fish's own argv mechanism (after --), never spliced
# into a string that gets re-parsed as fish syntax - anything else invites
# command injection via quotes/parens/semicolons in an argument.
function sudo
  if functions -q -- "$argv[1]"
    set -lx hi_sudo_fn $argv[1]
    set -lx function_src (string join "\n" (string escape --style=var (functions -- $hi_sudo_fn)))
    command sudo -E fish -c 'string unescape --style=var (string split "\n" $function_src) | source; $hi_sudo_fn $argv' -- $argv[2..]
  else
    command sudo $argv
  end
end

# prompt: "<chroot> user@host cwd (git) [status] |", @ turning yellow over ssh
# skipped entirely when disabled, leaving fish's own default prompt in place
if test "$_HI_DISABLE_PROMPT" != 1

function prompt_login --description "display user name for the prompt"
  if not set -q __fish_machine
    set -g __fish_machine ""
    test -r /etc/debian_chroot; and set -g __fish_machine "(chroot:"(cat /etc/debian_chroot)") "
  end
  set -l color_at normal
  set -q SSH_TTY; and set color_at yellow
  echo -ns (set_color yellow) "$__fish_machine" \
    (set_color $fish_color_user) " $USER" \
    (set_color $color_at) @ \
    (set_color $fish_color_host) (prompt_hostname) (set_color normal)
end

# copied + modified from Lilly Ballard, fish default
function fish_prompt --description 'Write out the prompt'
  set -l last_pipestatus $pipestatus
  set -lx __fish_last_status $status
  set -l normal (set_color normal)

  set -l color_cwd $fish_color_cwd
  set -l suffix ' |'
  if functions -q fish_is_root_user; and fish_is_root_user
    set -q fish_color_cwd_root; and set color_cwd $fish_color_cwd_root
    set suffix '#'
  end

  # bold the status only when it changed since the last prompt
  set -l bold_flag --bold
  set -q __fish_prompt_status_generation; or set -g __fish_prompt_status_generation $status_generation
  test $__fish_prompt_status_generation = $status_generation; and set bold_flag
  set __fish_prompt_status_generation $status_generation

  set -l prompt_status (__fish_print_pipestatus "[" "]" "|" \
    (set_color $fish_color_status) (set_color $bold_flag $fish_color_status) $last_pipestatus)

  echo -n -s (prompt_login)' ' (set_color $color_cwd) (prompt_pwd) $normal \
    (test "$_HI_DISABLE_GIT_STATUS" != 1; and fish_vcs_prompt) $normal " "$prompt_status $suffix " "
end

end
# === end required configuration ===

if test "$_HI_DISABLE_PERSONAL" != 1

# keybinds
bind \cH backward-kill-word
bind ctrl-delete kill-word
bind \e\[3\;5~ kill-word
bind \e\[1\;5H beginning-of-line
bind \e\[1\;5F end-of-line
bind \e\[2\;5~ ''

# syntax colors, ordered as per
# https://fishshell.com/docs/4.5/interactive.html#syntax-highlighting-variables
# (anything not listed keeps fish's default)
set -gx fish_color_normal normal
set -gx fish_color_command blue
set -gx fish_color_keyword blue
set -gx fish_color_quote yellow
set -gx fish_color_redirection cyan --bold
set -gx fish_color_end green
set -gx fish_color_error brred
set -gx fish_color_param cyan
set -gx fish_color_valid_path --underline=single
set -gx fish_color_option brgreen
set -gx fish_color_comment red
set -gx fish_color_selection white --bold --background=brblack
set -gx fish_color_operator brcyan
set -gx fish_color_escape brcyan
set -gx fish_color_autosuggestion brblack
set -gx fish_color_cwd green
set -gx fish_color_cwd_root red
set -gx fish_color_status red
set -gx fish_color_cancel --reverse
set -gx fish_color_search_match white --background=brblack
set -gx fish_color_history_current --bold

# pager colors, as per
# https://fishshell.com/docs/4.5/interactive.html#pager-color-variables
set -gx fish_pager_color_progress brwhite --background=cyan
set -gx fish_pager_color_prefix normal --bold --underline=single
set -gx fish_pager_color_completion normal
set -gx fish_pager_color_description yellow --italics
set -gx fish_pager_color_selected_background --reverse

# git prompt, matched by common/git_prompt.sh for bash & zsh
set -g __fish_git_prompt_show_informative_status 1
set -g __fish_git_prompt_showupstream informative
set -g __fish_git_prompt_showdirtystate yes
set -g __fish_git_prompt_showuntrackedfiles yes
set -g __fish_git_prompt_showstashstate yes
set -g __fish_git_prompt_showcolorhints yes
set -g __fish_git_prompt_describe_style contains
set -g __fish_git_prompt_shorten_branch_len 32
set -g __fish_git_prompt_color_branch brmagenta
set -g __fish_git_prompt_color_stagedstate yellow
set -g __fish_git_prompt_color_invalidstate red
set -g __fish_git_prompt_color_cleanstate brgreen

end
