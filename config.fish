bind \cH backward-kill-word
bind ctrl-delete kill-word
bind \e\[3\;5~ kill-word
bind \e\[1\;5H beginning-of-line
bind \e\[1\;5F end-of-line
bind \e\[2\;5~ ''

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
    set color_host brred
  end
  if [ (prompt_hostname) = "bertha" -o (prompt_hostname) = "liona" -o (prompt_hostname) = "mavie" ]
    set color_host brmagenta
  end
  if [ (prompt_hostname) = "minty" -o (prompt_hostname) = "sherrie" ]
    set color_host brblue
  end
  if [ (prompt_hostname) = "gendo" -o (prompt_hostname) = "ryoji" -o (prompt_hostname) = "shinji" -o (prompt_hostname) = "edison" ]
    set color_host brgreen
  end
  if [ $USER = "root" -o $USER = "admin" ]
    set fish_color_user red
  end
  if [ $USER = "team" -o $USER = "edison" ]
    set fish_color_user bryellow
  end

  echo -n -s (set_color $fish_color_user) "$USER" (set_color $color_at) @ (set_color $color_host) (prompt_hostname) (set_color normal)
end

function fish_greeting
  if not set -q fish_greeting
    set -l line0 (printf (_ '%s%s~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~') (set_color brgreen))
    set -l line1 \n(printf (_ ' %s' (date -u "+%a %b %e %H:%M:%S %Z %Y")) (set_color brcyan))
    set -l line2 (printf (_ ' %s| ' ) (set_color normal))
    set -l line3 (printf (_ '%s' (date "+%a %b %e %H:%M:%S %Z %Y")) (set_color bryellow))
    set -l line4 \n(printf (_ '%s Online!') (set_color brgreen))
    set -l line5 (printf (_ ' %s| ' ) (set_color normal))
    set -l line6 (printf (_ '%sOS: '(uname -s)) (set_color brcyan))
    set -l line7 (printf (_ ' %s| ' ) (set_color normal))
    set -l line8 (printf (_ '%sArch: ' (uname -m) ) (set_color brmagenta))
    set -l line9 (printf (_ ' %s| ' ) (set_color normal))
    set -l line10 (printf (_ '%s' (cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"') '%s') (set_color brblue) (set_color normal))

    set -g fish_greeting "$line0$line1$line2$line3$line4$line5$line6$line7$line8$line9$line10"
  end

  # The greeting used to be skipped when fish_greeting was empty (not just undefined)
  # Keep it that way to not print superfluous newlines on old configuration
  test -n "$fish_greeting"
  and echo $fish_greeting
end

function hi
  sshrc "$argv"
  if [ $status -eq 0 ]
    echo -n "" # no-op
  else
    echo \n(printf (_ '%s====================================%s') (set_color brred) (set_color normal))
    echo (printf (_ '%ssshrc failed, falling back to ssh...%s') (set_color bryellow) (set_color normal))
    echo (printf (_ '%s====================================%s') (set_color brred) (set_color normal))\n
    ssh "$argv"
  end
end
