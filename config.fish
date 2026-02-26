#!/bin/fish
if test -f "$SSHHOME/.sshrc.d/aliases.sh"
  source "$SSHHOME/.sshrc.d/aliases.sh"
end
if test -f ~/.sshrc.d/aliases.sh
  source ~/.sshrc.d/aliases.sh
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

  # TODO: Unified colors
  if [ (prompt_hostname) = "swervy" ] || [ (prompt_hostname) = "melchior" ] || [ (prompt_hostname) = "lenny" ] || [ (prompt_hostname) = "clyde" ]
    set color_host brred
  end
  if [ (prompt_hostname) = "bertha" ] || [ (prompt_hostname) = "liona" ] || [ (prompt_hostname) = "mavie" ]
    set color_host brmagenta
  end
  if [ (prompt_hostname) = "minty" ] || [ (prompt_hostname) = "sherrie" ]
    set color_host brblue
  end
  if [ (prompt_hostname) = "gendo" ] || [ (prompt_hostname) = "ryoji" ] || [ (prompt_hostname) = "shinji" ] || [ (prompt_hostname) = "edison" ]
    set color_host brgreen
  end
  if [ $USER = "root" ] || [ $USER = "admin" ]
    set color_user red
  end
  if [ $USER = "team" ] || [ $USER = "edison" ]
    set color_user brblue
  end
  if [ $USER = "ivy" ]
    set color_user bryellow
  end

  echo -ns (set_color $color_user) " $USER" (set_color $color_at) @ (set_color $color_host) (prompt_hostname) (set_color normal)
end

# header
function fish_greeting
  if not [ (prompt_hostname) = "mavie" ]
    set -g smaller_header true
  end
  if not set -q fish_greeting
    set -l spacer (printf (_ '%s|' ) (set_color normal))
    set -l header (printf (_ ' %s%s~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Online! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~') (set_color brgreen))

    set -l utctime (printf (_ '%s' (date -u "+%a %b %e %H:%M:%S %Z %Y")) (set_color brblue))
    set -l localtime (printf (_ '%s' (date "+%a %b %e %H:%M:%S %Z %Y")) (set_color bryellow))

    set -l distro (printf (_ '%s' (grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"') '%s') (set_color green) (set_color normal))
    set -l arch (printf (_ '%s' (uname -m) ) (set_color brmagenta))
    set -l os_type (printf (_ '%s' (uname -s)) (set_color bryellow))

    set -l cpus (printf (_ '%sCPUs: ' (nproc)) (set_color brblue))
    set -l ram (printf  (_ '%sRAM: ' (free -h --giga | awk '/^Mem:/ {print $2}GB')) (set_color cyan))
    if [ -f ~/.ssh/authorized_keys ]
      set -g authorized (printf (_ '%sAuth: ' (wc -l ~/.ssh/authorized_keys | awk '{ print $1 }')) (set_color red))
    else
      set -g authorized (printf (_ '%sAuth: 0!') (set_color red))
    end

    set -l public (printf (_ '%sPub: ' (find ~/.ssh -type f -name "*.pub" | wc -l)) (set_color magenta) )

    if [ -f "/usr/bin/docker" ]
      set -g containers (printf (_ '%sContainers: ' (docker container ls | wc -l | awk '{print $1 - 1}')) (set_color brblue))
    else
      set -g containers (printf (_ '%sCounting impossible, no docker :(' ) (set_color bryellow))
    end

    if [ -f "/home/$USER/.gitconfig" ]
      set -g git_identity (printf (_ '%sGit ID: %s' (grep email ~/.gitconfig | cut -d= -f2 | tr -d ' ' | awk -F@ '{ for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c="" }')) (set_color brcyan) (set_color yellow))
    else
      set -g git_identity (printf (_ '%sNo Git ID Found... %s') (set_color yellow) (set_color normal))
    end

    set -l ssh_root "/home/$USER/.sshrc.d/"
    if [ -d "$ssh_root/.git" ]
      set -g sshrc_change_status (printf (_ '%s' (git -C ~/.sshrc.d status --short | wc -l | awk '{ print $1 }')' ↑') (set_color bryellow))
      set -g sshrc_update_status (printf (_ '%s' (git -C ~/.sshrc.d rev-list --count HEAD..origin/$(git -C ~/.sshrc.d rev-parse --abbrev-ref HEAD))' ↓') (set_color brgreen))
    else
      set -g sshrc_change_status ""
      set -g sshrc_update_status ""
    end

    set -l _timer_line $spacer" "$utctime"   "$spacer"   "$localtime
    set -l _git_key_change_line $spacer" "$git_identity" "$spacer" "$containers" "$spacer" "$authorized" "$spacer" "$public
    set -l _system_info_line $spacer" "$os_type" "$spacer" "$arch" "$spacer" "$distro" "$spacer" "$cpus" "$spacer" "$ram

    # # TODO: DEDUPE
    set -l _systems (bash -c "source $ssh_root/check.sh; systems")
    set -l _tools (bash -c "source $ssh_root/check.sh; tools")
    if [ $smaller_header ]
      set -g _check_header_lines $_systems\n$_tools
    else
      set -l _packages (bash -c "source $ssh_root/check.sh; packages")
      set -l _basics (bash -c "source $ssh_root/check.sh; basics")
      set -g _check_header_lines $_packages\n$_basics\n$_systems\n$_tools
    end

    set -g fish_greeting $header" "$sshrc_change_status" "$sshrc_update_status\n $_timer_line\n $_git_key_change_line\n$_check_header_lines

  end

  test -n "$fish_greeting"
  and echo $fish_greeting
end

# user customization goes below =============

# conditionally load since bat is sometimes batcat on debian systems
if [ -f "/usr/bin/bat" ]
  alias batcat="bat"
  alias bat="bat $bat_opts"
  complete batcat --wraps bat
end

if [ -f "/usr/bin/batcat" ]
  alias bat="batcat"
  alias batcat="batcat $bat_opts"
  complete bat --wraps batcat
end

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

# https://itsfoss.gitlab.io/post/how-to-find-a-package-version-in-linux
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


bind \cH backward-kill-word
bind ctrl-delete kill-word
bind \e\[3\;5~ kill-word
bind \e\[1\;5H beginning-of-line
bind \e\[1\;5F end-of-line
bind \e\[2\;5~ ''

complete hi --wraps ssh

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
set -gx fish_color_host normal
set -gx fish_color_host_remote yellow
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
set -gx fish_color_user brgreen
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
# set -gx fish_color_search_match --background='333'
