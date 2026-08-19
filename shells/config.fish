#!/bin/fish

# === start required configuration ===
set -q _HI_HOME; or set -gx _HI_HOME ~
# GLOSSARY: toggle defaulting - defaulted (never assigned) so bare reads are
# safe and settings.sh/the gate still override. Mirrors core.sh's _HI_TOGGLES.
for _hi_toggle in _HI_DISABLE_LOCAL _HI_REMOTE_SESSION _HI_DISABLE_HEADER \
    _HI_DISABLE_PROMPT _HI_DISABLE_PERSONAL _HI_DISABLE_GIT_STATUS \
    _HI_DISABLE_EDITORS _HI_DISABLE_ALIASES _HI_DISABLE_OSC52 _HI_DISABLE_TMUX
  set -q $_hi_toggle; or set -gx $_hi_toggle 0
end
set -e _hi_toggle
# the overlay's home (fish can't expand the XDG default, so each entry point
# sets it); only when unset, so hi.sh can point a target at its shipped copy
if not set -q _HI_CONFIG_DIR
  set -q XDG_CONFIG_HOME; and set -gx _HI_CONFIG_DIR $XDG_CONFIG_HOME/hi.d
  set -q _HI_CONFIG_DIR; or set -gx _HI_CONFIG_DIR ~/.config/hi.d
end
# install.sh's settings ahead of paths.sh, whose gate reads them - plain
# `export NAME=value` lines, which fish parses natively
if test -f $_HI_CONFIG_DIR/settings.sh
  source $_HI_CONFIG_DIR/settings.sh
end
source $_HI_HOME/hi.d/common/paths.sh
source $_HI_ALIASES

# misc/aliases.sh (and yours in the overlay) stay `alias` for bash/zsh/fish
# compatibility, so fish turns them into opaque functions - no preview of
# what they expand to before you run them. `alias` with no args lists every
# one it defined, in `alias name 'value'` form, which is itself valid fish
# syntax; swapping the leading word for `abbr -a --` and eval'ing it reuses
# fish's own quoting round-trip rather than re-escaping by hand.
function hi_abbr_aliases --description 'add a fish abbr for every alias hi defined, so it expands in place'
  for hi_abbr_line in (alias)
    set -l hi_abbr_name (string match -rg '^alias (\S+) ' -- $hi_abbr_line)
    test -n "$hi_abbr_name"; or continue
    abbr -q -- $hi_abbr_name; and continue
    eval "abbr -a -- "(string replace -r '^alias \S+ ' "$hi_abbr_name " -- $hi_abbr_line)
  end
end
# TODO: investigate using autosuggest text, not rewriting buffer
# off by default - turning every alias into an abbr changes what your command
# line and your history literally look like, so it is opt-in; fish-only, so
# it isn't in core.sh's shared _HI_TOGGLES list either. `hi_abbr_aliases` is
# still there to call by hand in a shell that hasn't asked for it.
set -q _HI_ENABLE_FISH_ALIAS_ABBR; or set -gx _HI_ENABLE_FISH_ALIAS_ABBR 0
test "$_HI_ENABLE_FISH_ALIAS_ABBR" = 1; and hi_abbr_aliases

complete -c hi -f -a '(sh $_HI_TARGETS)' # "<target>\ttype" lines
complete exa --wraps eza

# fish can't run the bash/zsh side of hi, so the greeting, the package check
# and the color resolution all come from one bash call each
function fish_greeting
  # on a hi session load.sh already printed this and sets $fish_greeting to
  # suppress us; locally, nothing sets it and we print the header ourselves
  set -q fish_greeting; or bash -c "source $_HI_HEADER; hi_header Online"
end

# a whole process for two color names: memoized in a universal variable keyed
# on user@host+colors-mtime, so only the first shell after a change pays it
set -l hi_key "$USER@"(prompt_hostname)
test -f $_HI_COLORS; and set hi_key "$hi_key:"(command stat -c %Y $_HI_COLORS 2>/dev/null; or command stat -f %m $_HI_COLORS 2>/dev/null)
if not set -q __hi_colors_key; or test "$__hi_colors_key" != "$hi_key"
  set -l hi_colors (bash -c "source $_HI_CORE; _hi_user_color; _hi_host_color")
  set -U __hi_color_user $hi_colors[1]
  set -U __hi_color_host $hi_colors[2]
  set -U __hi_colors_key "$hi_key"
end
set -gx fish_color_user $__hi_color_user
set -gx fish_color_host $__hi_color_host
set -gx fish_color_host_remote $fish_color_host

# wrapper so aliases (functions, in fish) work under sudo; args ride fish's
# own argv after --, never a re-parsed string - that invites injection.
function sudo
  if functions -q -- "$argv[1]"
    set -lx hi_sudo_fn $argv[1]
    set -lx function_src (string join "\n" (string escape --style=var (functions -- $hi_sudo_fn)))
    command sudo -E fish -c 'string unescape --style=var (string split "\n" $function_src) | source; $hi_sudo_fn $argv' -- $argv[2..]
  else
    command sudo $argv
  end
end

# the prompt's end character, mirroring core.sh's _hi_prompt_end (fish can't
# call it): fish setting, then all-three, then default; empty counts as
# unset, and root still gets '#'.
set -g _hi_prompt_end '|'
set -q _HI_PROMPT_END; and test -n "$_HI_PROMPT_END"; and set -g _hi_prompt_end $_HI_PROMPT_END
set -q _HI_PROMPT_END_FISH; and test -n "$_HI_PROMPT_END_FISH"; and set -g _hi_prompt_end $_HI_PROMPT_END_FISH

# prompt: "<chroot> user@host cwd (git) [status] |", @ turning yellow over ssh
# skipped entirely when disabled, leaving fish's own default prompt in place
if test "$_HI_DISABLE_PROMPT" != 1

# deference, chosen in settings.sh - the same rule core.sh's
# _hi_wants_starship states for bash/zsh (fish can't call it); a missing
# starship falls back to hi's prompt below, silently
if test "$_HI_PROMPT" = starship; and command -q starship
starship init fish | source
else

# https://no-color.org (fish has no rule of its own): non-empty $NO_COLOR
# shadows set_color with a no-op - every call below, and fish_vcs_prompt's
# own, renders the same prompt with no escapes in it.
if test -n "$NO_COLOR"
  function set_color
  end
end

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
  set -l suffix " $_hi_prompt_end"
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

# the same ASCII fallback _hi_choose_glyphs gives bash/zsh, _HI_ASCII
# overriding the locale probe both ways like everywhere else
if test "$_HI_ASCII" = 1
    or begin
        test "$_HI_ASCII" != 0
        and not string match -qri 'utf-?8' -- "$LC_ALL$LC_CTYPE$LANG"
    end
    set -g __fish_git_prompt_char_upstream_ahead '^'
    set -g __fish_git_prompt_char_upstream_behind 'v'
    set -g __fish_git_prompt_char_stagedstate '*'
    set -g __fish_git_prompt_char_dirtystate '+'
    set -g __fish_git_prompt_char_invalidstate 'x'
    set -g __fish_git_prompt_char_untrackedfiles '?'
    set -g __fish_git_prompt_char_stashstate '$'
    set -g __fish_git_prompt_char_cleanstate 'ok'
end

end
