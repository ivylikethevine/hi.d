#!/bin/fish

# === start required configuration ===
if not set -q _HI_TMPDIR
  set -g _HI_TMPDIR ~
end
source $_HI_TMPDIR/hi.d/common/paths.sh
source $_HI_ALIASES;

complete hi --wraps ssh
complete exa --wraps eza

if [ -d $HOME/Android ] && [ -d $HOME/Android/Sdk ]
  set -gx ANDROID_HOME $HOME/Android/Sdk # for android dev on linux
end

set -gx EZA_CONFIG_DIR $_HI_TMPDIR/hi.d/misc # for eza theme customization at misc/theme.yml

# wrapper for aliases to work in fish shell under sudo
function sudo
  if functions -q -- "$argv[1]"
    set cmdline (
      for arg in $argv
        printf "\"%s\" " $arg
      end
    )
    set -x function_src (string join "\n" (string escape --style=var (functions "$argv[1]")))
    set argv fish -c 'string unescape --style=var (string split "\n" $function_src) | source; '$cmdline
    command sudo -E $argv
  else
    command sudo $argv
  end
end

# prompt
function prompt_login --description "display user name for the prompt"
  set -l last_status $status
  if not test $last_status -eq 0
    set_color $fish_color_error
  end

  # fish colors, chroot, and the ssh_tty @ coloring
  if not set -q __fish_machine
    set -g __fish_machine
    set -l debian_chroot $debian_chroot

    if test -r /etc/debian_chroot
      set debian_chroot (cat /etc/debian_chroot)
    end

    if set -q debian_chroot[1]
      and test -n "$debian_chroot"
      set -g __fish_machine "(chroot:$debian_chroot)"
    end
  end

  if set -q __fish_machine[1]
    echo -n -s (set_color yellow) "$__fish_machine" (set_color normal) ' '
  end

  set -g color_at normal
  if set -q SSH_TTY;
    set -g color_at yellow
  end

  echo -ns (set_color $fish_color_user) " $USER" (set_color $color_at) @ (set_color $fish_color_host) (prompt_hostname) (set_color normal)
end

# copied + modified from Lilly Ballard, fish default
function fish_prompt --description 'Write out the prompt'
    set -l last_pipestatus $pipestatus
    set -lx __fish_last_status $status
    set -l normal (set_color normal)

    set -l color_cwd $fish_color_cwd
    set -l suffix ' |'
    if functions -q fish_is_root_user; and fish_is_root_user
        if set -q fish_color_cwd_root
            set color_cwd $fish_color_cwd_root
        end
        set suffix '#'
    end

    set -l bold_flag --bold
    set -q __fish_prompt_status_generation; or set -g __fish_prompt_status_generation $status_generation
    if test $__fish_prompt_status_generation = $status_generation
        set bold_flag
    end
    set __fish_prompt_status_generation $status_generation
    set -l status_color (set_color $fish_color_status)
    set -l statusb_color (set_color $bold_flag $fish_color_status)
    set -l prompt_status (__fish_print_pipestatus "[" "]" "|" "$status_color" "$statusb_color" $last_pipestatus)

    echo -n -s (prompt_login)' ' (set_color $color_cwd) (prompt_pwd) $normal (fish_vcs_prompt) $normal " "$prompt_status $suffix " "
end

# header
function fish_greeting
  if not set -q fish_greeting
    if [ -f "$_HI_LINUX_PATH" ]
      set -g hi_distro (printf '%s%s' (set_color green) (grep PRETTY_NAME "$_HI_LINUX_PATH" | cut -d= -f2 | tr -d '\"'))
      set -g hi_cpus (printf '%sCPUs: %s' (set_color brblue) (nproc))
      set -g hi_ram (printf '%sRAM: %s' (set_color cyan) (free -h --giga | awk '/^Mem:/ {print $2}'))
    else
      set -l hi_system_info $(system_profiler SPHardwareDataType)
      set -g hi_distro "macOS $(sw_vers -productVersion)"
      set -g hi_cpus (printf '%sCPUs: %s' (set_color brblue) (echo "$system_info" | grep -e Cores | awk '{ print $5 }'))
      set -g hi_ram (printf '%sRAM: %s' (set_color cyan) (echo "$system_info" | grep -e Memory | awk '{ print $2 }'))
    end

    set -l authorized_keys ([ -f "$_HI_SSH_AUTHORIZED_KEYS" ] && printf '%sAuth: %s' (set_color red) (wc -l "$_HI_SSH_AUTHORIZED_KEYS" | awk '{ print $1 }') || printf '%sAuth: 0!' (set_color red))
    set -l running_containers ([ -f "/usr/bin/docker" ] && printf '%sContainers: %s' (set_color brblue) (docker container ls | wc -l | awk '{print $1 - 1}') || printf '%sCounting impossible, no docker :(' (set_color bryellow))
    set -l git_identity ([ -f "$_HI_HOME_GIT_CONFIG" ] && printf '%sGit ID: %s%s' (set_color brcyan) (set_color yellow) (grep email "$_HI_HOME_GIT_CONFIG" | tail -n1 | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }') || printf '%sNo Git ID Found...' (set_color yellow))
    set -l hi_change_status ([ -d "$_HI_ROOT/.git" ] && printf ' %s%s' (set_color bryellow) (git -C ~/hi.d status --short | wc -l | awk '{ print $1 }')' ↑' || printf '%s' "")
    set -l spacer (printf '%s|' (set_color normal))
    set -l utctime (printf '%s%s' (set_color brblue) (date -u $_HI_HUMAN_CENTRIC_DATE))
    set -l localtime (printf '%s%s' (set_color bryellow) (date $_HI_HUMAN_CENTRIC_DATE))
    set -l public (printf '%sPub: %s' (set_color magenta) (find ~/.ssh -type f -name "*.pub" | wc -l))
    set -l arch (printf '%s%s' (set_color brmagenta) (uname -m))
    set -l os_type (printf '%s%s' (set_color bryellow) (uname -s))

    printf '%s %s~~~~~~~~~~~~~~~~~~~ Online %s[%s%s%s]%s ~~~~~~~~~~~~~~~~~~~~~~~~~~~%s\n' $hi_change_status (set_color brcyan) (set_color normal) (set_color $fish_color_host) (prompt_hostname) (set_color normal) (set_color brcyan) (set_color normal)
    printf " %s %s   %s   %s   %s\n" $spacer $utctime $spacer $localtime
    printf " %s %s %s %s %s %s %s %s %s %s %s\n" $spacer $os_type $spacer $arch $spacer $hi_distro $spacer $hi_cpus $spacer $hi_ram
    printf " %s %s %s %s %s %s %s %s\n" $spacer $git_identity $spacer $running_containers $spacer $authorized_keys $spacer $public
    check_packages
  end
end

function check_packages --description 'Display a list of installed packages defined by hi.d/data/packages_config'
  for line in (string split "newline" (bash -c "source $_HI_CHECK; full_check_fish"))
    printf " %s\n" $line
  end
end

set -gx _hi_colors (string split " " (bash -c "source $_HI_COLORS; user_color; host_color"))
set -gx fish_color_user $_hi_colors[1]
set -gx fish_color_host $_hi_colors[2]
set -gx fish_color_host_remote $fish_color_host
# === end required configurations ===

# keybinds
bind \cH backward-kill-word
bind ctrl-delete kill-word
bind \e\[3\;5~ kill-word
bind \e\[1\;5H beginning-of-line
bind \e\[1\;5F end-of-line
bind \e\[2\;5~ ''

# color/themeing
# ordered as per the table on:
# https://fishshell.com/docs/4.5/interactive.html#syntax-highlighting-variables
set -gx fish_color_normal normal
set -gx fish_color_command blue
set -gx fish_color_keyword blue #
set -gx fish_color_quote yellow
set -gx fish_color_redirection cyan --bold
set -gx fish_color_end green
set -gx fish_color_error brred
set -gx fish_color_param cyan
set -gx fish_color_valid_path --underline=single
set -gx fish_color_option brgreen #
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

# ordered as per the table on:
# https://fishshell.com/docs/4.5/interactive.html#pager-color-variables
set -gx fish_pager_color_progress brwhite --background=cyan
set -gx fish_pager_color_background #
set -gx fish_pager_color_prefix normal --bold --underline=single
set -gx fish_pager_color_completion normal
set -gx fish_pager_color_description yellow --italics
set -gx fish_pager_color_selected_background --reverse
set -gx fish_pager_color_selected_prefix #
set -gx fish_pager_color_selected_completion #
set -gx fish_pager_color_selected_description #
set -gx fish_pager_color_secondary_background #
set -gx fish_pager_color_secondary_prefix #
set -gx fish_pager_color_secondary_completion #
set -gx fish_pager_color_secondary_description #

# fish git prompt settings
set -g __fish_git_prompt_show_informative_status 1
set -g __fish_git_prompt_color_branch brmagenta
set -g __fish_git_prompt_showupstream "informative"
set -g __fish_git_prompt_showdirtystate "yes"
set -g __fish_git_prompt_color_stagedstate yellow
set -g __fish_git_prompt_color_invalidstate red
set -g __fish_git_prompt_color_cleanstate brgreen
set -g __fish_git_prompt_showuntrackedfiles "yes"
set -g __fish_git_prompt_showstashstate "yes"
set -g __fish_git_prompt_shorten_branch_len 32
set -g __fish_git_prompt_describe_style "contains"
set -g __fish_git_prompt_showcolorhints "yes"
