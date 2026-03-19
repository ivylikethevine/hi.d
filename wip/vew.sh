
# bash
# Spelled vew to avoid calling vi
vew() {
  local p="${1:-}"

  if [[ -z "$p" ]]; then
    printf 'Usage: %s <file_or_directory>\n' "${FUNCNAME[0]}" >&2
    return 1
  fi

  if [[ -f "$p" ]]; then
    if [ -f "/usr/bin/batcat" ] || [ -f "/usr/bin/bat" ]; then
      bat "$@"
    else
      cat -- "$p"
    fi
  elif [[ -d "$p" ]]; then
    ls "$@"
  else
    printf 'Error: %s is not a regular file or directory.\n' "$p" >&2
    return 2
  fi
}

# zsh
# # Spelled vew to avoid calling vi
# vew() {
#   local p="${1:-}"

#   if [[ -z "$p" ]]; then
#     printf 'Usage: %s <file_or_directory>\n' "${FUNCNAME[0]}" >&2
#     return 1
#   fi

#   if [[ -f "$p" ]]; then
#     if [ -f "/usr/bin/batcat" -o -f "/usr/bin/bat" ]; then
#       bat "$@"
#     else
#       cat -- "$p"
#     fi
#   elif [[ -d "$p" ]]; then
#     ls "$@"
#   else
#     printf 'Error: %s is not a regular file or directory.\n' "$p" >&2
#     return 2
#   fi
# }

# fish
# function vew --description 'Cat/bat a file or list a directory in detail | spelled vew to avoid calling vi'
#   set args (count $argv)
#   set path "$argv[$args]"

#   if test -z "$path"
#     echo "Usage: vew <path> -> ls directory or cat file"
#     return 1
#   end

#   if not test -e "$path"
#     echo "Error: '$path' does not exist."
#     return 1
#   end

#   if test -f "$path"
#     if [ -f "/usr/bin/batcat" ] || [ -f "/usr/bin/bat" ]
#       bat "$argv"
#     else
#       cat "$argv"
#     end
#   else if test -d "$path"
#     ls "$argv"
#   else
#     echo "Error: '$path' is not a file or a directory."
#     return 1
#   end
# end
