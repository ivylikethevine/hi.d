# bash
version() {
  # 'Check if a package/command is installed, then display its version'
  local item="${1:-}"

  if command -v "$item" &>/dev/null; then
    echo -n "[$(command -v "$item")]: "
    if command -v "dpkg" &>/dev/null; then
      if dpkg -s "$item" &>/dev/null; then
        dpkg -s "$item" | grep Version | awk '{ print $2 }';
        return 0;
      fi
    elif command -v "pacman" &>/dev/null; then
      if pacman -Qi "$item" &>/dev/null; then
        pacman -Qi "$item" | grep Version | awk '{ print $3 }';
        return 0;
      fi
    elif command -v "dnf" &>/dev/null; then
      if dnf info "$item" &>/dev/null; then
        dnf info "$item" | grep Version;
        return 0;
      fi
    elif command -v "rpm" &>/dev/null; then
      if rpm -qi "$item" &>/dev/null; then
        rpm -qi "$item" | grep Version;
        return 0;
      fi
    elif command -v "zypper" &>/dev/null; then
      if zypper info "$item" &>/dev/null; then
        zypper info "$item" | grep Version;
        return 0;
      fi
    elif command -v "apk" &>/dev/null; then
      if apk info "$item" &>/dev/null; then
        apk info "$item" | grep Version;
        return 0;
      fi
    fi
    if "$item" --version &>/dev/null; then
      echo -n "$("$item" --version)"
      return 0;
    elif "$item" -V &>/dev/null; then
      echo -n "$("$item" -V)"
      return 0;
    fi
    echo "Local function/alias, version unknowable..."
    return 0
  fi
  if "$item" &>/dev/null; then
    echo "[$item]: Package/command not installed!"
  fi
  return 1
}

# zsh
# version() {
#   # 'Check if a package/command is installed, then display its version'
#   local item="${1:-}"

#   if command -v "$item" &>/dev/null; then
#     echo -n "[$(command -v "$item")]: "
#     if command -v "dpkg" &>/dev/null; then
#       if dpkg -s "$item" &>/dev/null; then
#         dpkg -s "$item" | grep Version | awk '{ print $2 }';
#         return 0;
#       fi
#     elif command -v "pacman" &>/dev/null; then
#       if pacman -Qi "$item" &>/dev/null; then
#         pacman -Qi "$item" | grep Version | awk '{ print $3 }';
#         return 0;
#       fi
#     elif command -v "dnf" &>/dev/null; then
#       if dnf info "$item" &>/dev/null; then
#         dnf info "$item" | grep Version;
#         return 0;
#       fi
#     elif command -v "rpm" &>/dev/null; then
#       if rpm -qi "$item" &>/dev/null; then
#         rpm -qi "$item" | grep Version;
#         return 0;
#       fi
#     elif command -v "zypper" &>/dev/null; then
#       if zypper info "$item" &>/dev/null; then
#         zypper info "$item" | grep Version;
#         return 0;
#       fi
#     elif command -v "apk" &>/dev/null; then
#       if apk info "$item" &>/dev/null; then
#         apk info "$item" | grep Version;
#         return 0;
#       fi
#     fi
#     if "$item" --version &>/dev/null; then
#       echo -n "$("$item" --version)"
#       return 0;
#     elif "$item" -V &>/dev/null; then
#       echo -n "$("$item" -V)"
#       return 0;
#     fi
#     echo "Local function/alias, version unknowable..."
#     return 0
#   fi
#   if [ "$item" &>/dev/null ]; then
#     echo "[$item]: Package/command not installed!"
#   fi
#   return 1
# }


# fish
#
# function version --description 'Check if a package/command is installed, then display its version'
#   set -l item "$argv"

#   if command -v "$item" &>/dev/null
#     echo -n "[$(command -v "$item")]: "
#     if command -v "dpkg" &>/dev/null
#       if dpkg -s "$item" &>/dev/null
#         dpkg -s "$item" | grep Version | awk '{ print $2 }';
#         return 0
#       end
#     else if command -v "pacman" &>/dev/null
#       if pacman -Qi "$item" &>/dev/null
#         pacman -Qi "$item" | grep Version | awk '{ print $3 }'
#         return 0
#       end
#     else if command -v "dnf" &>/dev/null
#       if dnf info "$item" &>/dev/null
#         dnf info "$item" | grep Version
#         return 0
#       end
#     else if command -v "rpm" &>/dev/null
#       if rpm -qi "$item" &>/dev/null
#         rpm -qi "$item" | grep Version
#         return 0
#       end
#     else if command -v "zypper" &>/dev/null
#       if zypper info "$item" &>/dev/null
#         zypper info "$item" | grep Version
#         return 0
#       end
#     else if command -v "apk" &>/dev/null
#       if apk info "$item" &>/dev/null
#         apk info "$item" | grep Version
#         return 0
#       end
#     end
#     if "$item" --version &>/dev/null
#       echo -n "$("$item" --version)"
#     else if "$item" -V &>/dev/null
#       echo -n "$("$item" -V)"
#     end
#     return 0
#   end
#   # Messy but weird workaround required for fish shell
#   if [ "$item" &>/dev/null ]
#     if command -v "$item" &>/dev/null
#       if [ (type -t "$item") &>/dev/null = "function" ]
#         echo "[$item]: Local function/alias, version unknowable..."
#         return 0
#       end
#     else
#       echo "[$item]: Package/command not installed!"
#     end
#   end
#   return 1
# end
