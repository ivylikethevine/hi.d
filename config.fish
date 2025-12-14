bind \cH backward-kill-token # ctrl-backspace with an odd '\c' keycode, equivalent to '^' or 'ctrl'

function view --description 'Cat a file or list a directory in detail'
    set path $argv[1]

    if test -z "$path"
        echo "Usage: view <path> -> ls directory or cat file"
        return 1
    end

    if not test -e "$path"
        echo "Error: '$path' does not exist."
        return 1
    end

    # Dispatch based on file type
    if test -f "$path"
        cat "$path"
    else if test -d "$path"
        # Directory
        ls -alch "$path"
    else
        echo "Error: '$path' is not a file or a directory."
        return 1
    end
end
