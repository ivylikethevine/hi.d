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
