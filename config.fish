bind \cH backward-kill-token # ctrl-backspace with an odd '\c' keycode, equivalent to '^' or 'ctrl'

complete sshrc --wraps ssh
complete hi --wraps sshrc

function view --description 'Cat a file or list a directory in detail'
  set args (count $argv)
  set path "$argv[$args]"

  if test -z "$path"
    echo "Usage: view <path> -> ls directory or cat file"
    return 1
  end

  if not test -e "$path"
    echo "Error: '$path' does not exist."
    return 1
  end

  if test -f "$path"
    cat $argv
  else if test -d "$path"
    ls "$path"
  else
    echo "Error: '$path' is not a file or a directory."
    return 1
  end
end

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

  # Prepend the chroot environment if present
  if set -q __fish_machine[1]
    echo -n -s (set_color yellow) "$__fish_machine" (set_color normal) ' '
  end

  # If we're running via SSH, change the @ sign color.
  set -l color_host $fish_color_host
  set -l color_at normal
  if set -q SSH_TTY; and set -q fish_color_host_remote
    set color_host $fish_color_host_remote
    set color_at yellow
  end

  if [ (prompt_hostname) = "swervy" -o (prompt_hostname) = "melchior" -o  (prompt_hostname) = "lenny" -o (prompt_hostname) = "clyde" ]
    set color_host red
  end
  if [ (prompt_hostname) = "bertha" -o (prompt_hostname) = "liona" -o (prompt_hostname) = "mavie" ]
    set color_host purple
  end
  if [ (prompt_hostname) = "minty" -o (prompt_hostname) = "sherrie" ]
    set color_host blue
  end
  if [ (prompt_hostname) = "gendo" -o (prompt_hostname) = "ryoji" -o (prompt_hostname) = "shinji" -o (prompt_hostname) = "edison" ]
    set color_host green
  end
  if [ $USER = "root" -o $USER = "admin" ]
    set fish_color_user red
  end

  echo -n -s (set_color $fish_color_user) "$USER" (set_color $color_at) @ (set_color $color_host) (prompt_hostname) (set_color normal)
end
