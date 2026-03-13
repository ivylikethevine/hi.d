#!/bin/fish

# === start required configuration ===
if not set -q HI_TMPDIR
  set -g HI_TMPDIR ~
end
source $HI_TMPDIR/hi.d/common/paths.sh
source $_HI_ALIASES;

complete hi --wraps ssh

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

  set -l color_host $fish_color_host
  set -l color_user $fish_color_user
  set -l color_at normal
  if set -q SSH_TTY; and set -q fish_color_host_remote
    set color_host $fish_color_host_remote
    set color_at yellow
  end

  echo -ns (set_color $color_user) " $USER" (set_color $color_at) @ (set_color $color_host) (prompt_hostname) (set_color normal)
end

# header
function fish_greeting
  if not set -q fish_greeting
    set -l spacer (printf '%s|' (set_color normal))

    set -l human_centric_date_format "+%a %b %-e %Y %H:%M:%S %Z"
    set -l utctime (printf '%s%s' (set_color brblue) (date -u $human_centric_verbose))
    set -l localtime (printf '%s%s' (set_color bryellow) (date $human_centric_verbose))

    set -l distro (printf '%s%s' (set_color green) (grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'))
    set -l arch (printf '%s%s' (set_color brmagenta) (uname -m))
    set -l os_type (printf '%s%s' (set_color bryellow) (uname -s))

    set -l cpus (printf '%sCPUs: %s' (set_color brblue) (nproc))
    set -l ram (printf '%sRAM: %s' (set_color cyan) (free -h --giga | awk '/^Mem:/ {print $2}GB'))
    if [ -f "$_HI_SSH_AUTHORIZED_KEYS" ]
      set -g authorized (printf '%sAuth: %s' (set_color red) (wc -l "$_HI_SSH_AUTHORIZED_KEYS" | awk '{ print $1 }'))
    else
      set -g authorized (printf '%sAuth: 0!' (set_color red))
    end

    set -l public (printf '%sPub: %s' (set_color magenta) (find ~/.ssh -type f -name "*.pub" | wc -l))

    if [ -f "/usr/bin/docker" ]
      set -g containers (printf '%sContainers: %s' (set_color brblue) (docker container ls | wc -l | awk '{print $1 - 1}'))
    else
      set -g containers (printf '%sCounting impossible, no docker :(' (set_color bryellow))
    end

    if [ -f "$_HI_GIT_CONFIG_PATH" ]
      set -g git_identity (printf '%sGit ID: %s%s' (set_color brcyan) (set_color yellow) (grep email "$_HI_GIT_CONFIG_PATH" | tail -n1 | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }'))
    else
      set -g git_identity (printf '%sNo Git ID Found...' (set_color yellow))
    end

    if [ -d "$HI_ROOT/.git" ]
      set -g hi_change_status (printf ' %s%s' (set_color bryellow) (git -C ~/hi.d status --short | wc -l | awk '{ print $1 }')' ↑')
      set -g hi_update_status (printf '%s%s' (set_color brgreen) (git -C ~/hi.d rev-list --count HEAD..origin/$(git -C ~/hi.d rev-parse --abbrev-ref HEAD))' ↓')
    else
      set -g hi_change_status ""
      set -g hi_update_status ""
    end

    set -l _system_info_line $spacer" "$os_type" "$spacer" "$arch" "$spacer" "$distro" "$spacer" "$cpus" "$spacer" "$ram

    set -l _full_check_formatted (string split "newline" (bash -c "source $_HI_CHECK; full_check_fish"))

    echo -n "$hi_change_status $hi_update_status"
    echo (printf '%s~~~~~~~~~~~~~~~~~~ Online %s[%s%s%s]%s ~~~~~~~~~~~~~~~~~~~~~~~~~~%s' (set_color brcyan) (set_color normal) (set_color $fish_color_host) (prompt_hostname) (set_color normal) (set_color brcyan) (set_color normal))
    echo $spacer" "$utctime"   "$spacer"   "$localtime
    echo $spacer" "$git_identity" "$spacer" "$containers" "$spacer" "$authorized" "$spacer" "$public
    echo $_full_check_formatted[1]
    echo $_full_check_formatted[2]
    echo $_full_check_formatted[3]
    echo $_full_check_formatted[4]
  end
end
# === end required configurations ===

function vew --description 'Cat/bat a file or list a directory in detail | spelled vew to avoid calling vi'
  set args (count $argv)
  set path "$argv[$args]"

  if test -z "$path"
    echo "Usage: vew <path> -> ls directory or cat file"
    return 1
  end

  if not test -e "$path"
    echo "Error: '$path' does not exist."
    return 1
  end

  if test -f "$path"
    if [ -f "/usr/bin/batcat" ] || [ -f "/usr/bin/bat" ]
      bat "$argv"
    else
      cat "$argv"
    end
  else if test -d "$path"
    ls "$argv"
  else
    echo "Error: '$path' is not a file or a directory."
    return 1
  end
end

function version --description 'Check if a package/command is installed, then display its version'
  set -l item "$argv"

  if command -v "$item" &>/dev/null
    echo -n "[$(command -v "$item")]: "
    if command -v "dpkg" &>/dev/null
      if dpkg -s "$item" &>/dev/null
        dpkg -s "$item" | grep Version | awk '{ print $2 }';
        return 0
      end
    else if command -v "pacman" &>/dev/null
      if pacman -Qi "$item" &>/dev/null
        pacman -Qi "$item" | grep Version | awk '{ print $3 }'
        return 0
      end
    else if command -v "dnf" &>/dev/null
      if dnf info "$item" &>/dev/null
        dnf info "$item" | grep Version
        return 0
      end
    else if command -v "rpm" &>/dev/null
      if rpm -qi "$item" &>/dev/null
        rpm -qi "$item" | grep Version
        return 0
      end
    else if command -v "zypper" &>/dev/null
      if zypper info "$item" &>/dev/null
        zypper info "$item" | grep Version
        return 0
      end
    else if command -v "apk" &>/dev/null
      if apk info "$item" &>/dev/null
        apk info "$item" | grep Version
        return 0
      end
    end
    if "$item" --version &>/dev/null
      echo -n "$("$item" --version)"
    else if "$item" -V &>/dev/null
      echo -n "$("$item" -V)"
    end
    return 0
  end
  # Messy but weird workaround required for fish shell
  if [ "$item" &>/dev/null ]
    if command -v "$item" &>/dev/null
      if [ (type -t "$item") &>/dev/null = "function" ]
        echo "[$item]: Local function/alias, version unknowable..."
        return 0
      end
    else
      echo "[$item]: Package/command not installed!"
    end
  end
  return 1
end

# keybinds
bind \cH backward-kill-word
bind ctrl-delete kill-word
bind \e\[3\;5~ kill-word
bind \e\[1\;5H beginning-of-line
bind \e\[1\;5F end-of-line
bind \e\[2\;5~ ''

# color/themeing
set -gx fish_color_autosuggestion brblack
set -gx fish_color_cancel --reverse
set -gx fish_color_command blue
set -gx fish_color_comment red
set -gx fish_color_cwd green
set -gx fish_color_cwd_root red
set -gx fish_color_end green
set -gx fish_color_error brred
set -gx fish_color_escape brcyan
set -gx fish_color_history_current --bold
set -gx fish_color_keyword
set -gx fish_color_normal normal
set -gx fish_color_operator brcyan
set -gx fish_color_option
set -gx fish_color_param cyan
set -gx fish_color_quote yellow
set -gx fish_color_redirection cyan --bold
set -gx fish_color_search_match white --background=brblack
set -gx fish_color_selection white --bold --background=brblack
set -gx fish_color_status red
set -gx fish_color_valid_path --underline=single
set -gx fish_pager_color_background
set -gx fish_pager_color_completion normal
set -gx fish_pager_color_description yellow --italics
set -gx fish_pager_color_prefix normal --bold --underline=single
set -gx fish_pager_color_progress brwhite --background=cyan
set -gx fish_pager_color_secondary_background
set -gx fish_pager_color_secondary_completion
set -gx fish_pager_color_secondary_description
set -gx fish_pager_color_secondary_prefix
set -gx fish_pager_color_selected_background --reverse
set -gx fish_pager_color_selected_completion
set -gx fish_pager_color_selected_description
set -gx fish_pager_color_selected_prefix

# TODO: dedupe
set -gx fish_color_user (bash -c "source $_HI_COLORS; user_color")
set -gx fish_color_host (bash -c "source $_HI_COLORS; host_color")
set -gx fish_color_host_remote $fish_color_host
