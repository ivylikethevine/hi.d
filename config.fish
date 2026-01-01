bind \cH backward-kill-word
bind ctrl-delete kill-word
bind \e\[3\;5~ kill-word
bind \e\[1\;5H beginning-of-line
bind \e\[1\;5F end-of-line
bind \e\[2\;5~ ''

complete sshrc --wraps ssh
complete hi --wraps sshrc

function vew --description 'Cat a file or list a directory in detail | spelled vew to avoid calling vi'
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
    set color_user red
  end
  if [ $USER = "team" -o $USER = "edison" ]
    set color_user brblue
  end
  if [ $USER = "ivy" ]
    set color_user bryellow
  end

  echo -ns (set_color $color_user) " $USER" (set_color $color_at) @ (set_color $color_host) (prompt_hostname) (set_color normal)
end

function fish_greeting
  if not set -q fish_greeting
    set -l spacer (printf (_ '%s|' ) (set_color normal))
    set -l header (printf (_ ' %s%s~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Online! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~') (set_color brgreen))
    set -l utctime (printf (_ '%s' (date -u "+%a %b %e %H:%M:%S %Z %Y")) (set_color brblue))
    set -l localtime (printf (_ '%s' (date "+%a %b %e %H:%M:%S %Z %Y")) (set_color bryellow))
    set -l distro (printf (_ '%s' (cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"') '%s') (set_color green) (set_color normal))
    set -l arch (printf (_ '%s' (uname -m) ) (set_color brmagenta))
    set -l authorized (printf (_ '%sAuth: ' (ls ~/.ssh | grep authorized_keys | wc -l)) (set_color red))
    set -l public (printf (_ '%sPub: ' (ls ~/.ssh | grep .pub | wc -l)) (set_color magenta) )

    if [ -f "/usr/bin/docker" ]
      set -g containers (printf (_ '%sContainers: ' (docker container ls | wc -l | awk '{print $1 - 1}')) (set_color brblue))
    else
      set -g containers (printf (_ '%sCounting impossible, no docker :(' ) (set_color bryellow))
    end

    if [ -f "/home/$USER/.gitconfig" ]
      set -g gitidentity (printf (_ '%sGit Identity: %s' (cat ~/.gitconfig | grep email | cut -d= -f2 | tr -d ' ' | awk -F@ '{for(i=0;i<length($2);i++) c=c"●"; print $1"@"c; c=""}')) (set_color brcyan) (set_color yellow))
    else
      set -g gitidentity (printf (_ '%sNo Git Identity Found... %s') (set_color yellow) (set_color normal))
    end

    set -l ssh_root "/home/$USER/.sshrc.d/"
    if [ -f "$ssh_root/check.rc" -a -f "$ssh_root/load.sh" ]
      set -g systems (bash -c "source $ssh_root/load.sh; source $ssh_root/check.rc; systems")
      set -g installed (bash -c "source $ssh_root/load.sh; source $ssh_root/check.rc; installed")
      set -g missing (bash -c "source $ssh_root/load.sh; source $ssh_root/check.rc; missing")
    end

    # set -g fish_greeting $header\n $spacer $utctime   $spacer   $localtime\n $spacer $distro $spacer $arch $spacer $containers\n $spacer $gitidentity $spacer $authorized $spacer $public\n$systems\n$installed\n$missing
    set -g fish_greeting $header\n" "$spacer $utctime"   "$spacer"   "$localtime\n $spacer $gitidentity $spacer $containers $spacer $authorized $spacer $public\n $spacer $installed\n $spacer $systems"| "$missing
  end

  test -n "$fish_greeting"
  and echo $fish_greeting
end

function hi
  sshrc "$argv"
  if [ ! $status -eq 0 ]
    echo \n(printf (_ '%s====================================%s') (set_color brred) (set_color normal))
    echo (printf (_ '%ssshrc failed, falling back to ssh...%s') (set_color bryellow) (set_color normal))
    echo (printf (_ '%s====================================%s') (set_color brred) (set_color normal))\n
    ssh "$argv"
  end
  # TODO: swap to sh & copy over minimal config
end
