#!/bin/bash
# forked from sshrc: https://github.com/danrabinowitz/sshrc
# set -eou pipefail

HI_TMPDIR=${HI_TMPDIR:-$HOME}
# shellcheck source=./common/paths.sh
source "$HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"

# This will autogenerate the colors if we don't have any yet.
if [ ! -f "$_HI_HOST_COLORS" ] || [ ! -f "$_HI_USER_COLORS" ]; then
  # shellcheck source=./scripts/colorgen.sh
  source "$_HI_COLORGEN"
  initial_colorgen
fi

# Parse ssh arguments
function hi_parse() {
  while [[ -n ${1+x} ]]; do
    case $1 in
    -b | -c | -D | -E | -e | -F | -I | -i | -L | -l | -m | -O | -o | -p | -Q | -R | -S | -W | -w)
      SSHARGS="$SSHARGS $1 $2"
      shift
      ;;
    -*)
      SSHARGS="$SSHARGS $1"
      ;;
    *)
      if [ -z ${DOMAIN+x} ]; then
        DOMAIN="$1"
      else
        local SEMICOLON=""
        SEMICOLON=$([[ "$*" = *[![:space:]]* ]] && echo '; ')
        CMDARG="$*$SEMICOLON exit"
        return
      fi
      ;;
    esac
    shift
  done
  if [ -z "$DOMAIN" ]; then
    ssh "$SSHARGS"
    exit 1
  fi
}

# Unify as many parts of the process as possible
export HI_EXCLUDE=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh --exclude hi.bashrc --exclude data/group_config --exclude .zed --exclude data/.gitkeep --exclude wip)
export HI_EXCLUDE_MIN=(--exclude README.md --exclude .git --exclude .gitignore --exclude scripts --exclude hi.sh --exclude hi.bashrc --exclude data/group_config --exclude .zed --exclude data/.gitkeep --exclude wip --exclude common --exclude misc --exclude shells --exclude wip --exclude load.sh)
export TR_CMD="tr -s ' ' '\n'"
export OPENSSL_CMD="openssl enc -base64"
export OPENSSL_CHECK="command -v openssl >/dev/null 2>&1 || { echo >&2 \"hi requires openssl to be installed on [$DOMAIN], but it is not. Aborting.\"; exit 1; }"

# Connect to remote host, determine shell, then copy hi.d & run load.sh.
# This could be removed if we required all targets to run bash as the login shell.
# This part takes usually 0.5-2s, which is noticeable and quite annoying.
# Ideally, we could stay on the target if we have login bash, reducing the overall
# connection for most connections, but I haven't figured that out yet.
function say_hi() {
  local shell_start_time
  shell_start_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"

  local remote_shell

  # remote_shell=$(ssh "$DOMAIN" '[ ! -f /etc/os-release ] && dscl . -read ~/ UserShell 2>/dev/null | awk "{ print \$2 }" | xargs basename || cat /etc/passwd | grep -e $(whoami) | xargs basename && [ -d $HOME/hi.d ] && echo -n yes || echo -n no' 2>/dev/null)
  remote_shell=$(ssh "$DOMAIN" '[ ! -f /etc/os-release ] && dscl . -read ~/ UserShell 2>/dev/null | awk "{ print \$2 }" | xargs basename || cat /etc/passwd | grep -e $(whoami) | xargs basename' 2>/dev/null)

  local shell_end_time
  shell_end_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
  cecho " $(echo "$shell_end_time $shell_start_time" | awk '{ printf "shell: %.3fs ", $1 - $2 }')" "$BLUE" 1
  local linux_flags=""
  if [ -f /etc/os-release ]; then
    linux_flags="--apparent-size"
  fi

  case "$remote_shell" in
  bash)
    cecho "-> bash" "$CYAN" 1
    echo -ne " $(du -sh "${HI_EXCLUDE[@]}" $linux_flags ~/.hi.d "$HI_ROOT" | awk '{ print $1 }')"
    say_hi_bash "$@" 2>"$tmp"
    ;;
  zsh)
    cecho "-> zsh" "$PURPLE" 1
    echo -ne " $(du -sh "${HI_EXCLUDE[@]}" $linux_flags ~/.hi.d "$HI_ROOT" | awk '{ print $1 }')"
    say_hi_zsh "$@" 2>"$tmp"
    ;;
  fish)
    cecho "-> fish" "$GREEN" 1
    echo -ne " $(du -sh "${HI_EXCLUDE[@]}" $linux_flags ~/.hi.d "$HI_ROOT" | awk '{ print $1 }')"
    say_hi_bash "$@" 2>"$tmp"
    ;;
  sh)
    cecho "-> sh?" "$YELLOW" 1
    ;;
  *)
    cecho "-> UNKNOWN: $remote_shell!" "$BRRED"
    ;;
  esac
}

# Bash & Fish shell both work with this command
function say_hi_bash() {
  ssh -t "$DOMAIN" "$SSHARGS" "
      $OPENSSL_CHECK
      export HI_TMPDIR=\$(mktemp -d -t $(whoami).hi.XXXX)
      mkdir \$HI_TMPDIR/hi.d
      export HI_ROOT=\$HI_TMPDIR/hi.d
      export HI_CLEANUP=\$HI_TMPDIR
      trap 'rm -rf \$HI_CLEANUP' exit
      echo \"$(cat "$0" | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.sh
      chmod +x \$HI_ROOT/hi.sh
      echo \"$(
    cat <<'EOF' | $OPENSSL_CMD
      if [ -r /etc/profile ]; then source /etc/profile; fi
      if [ -r ~/.bash_profile ]; then source ~/.bash_profile
      elif [ -r ~/.bash_login ]; then source ~/.bash_login
      elif [ -r ~/.profile ]; then source ~/.profile
      fi
      export PATH=$PATH:${HI_ROOT+x}
      source $HI_ROOT/load.sh
      load
EOF
  )\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.bashrc
      echo \"$(tar czf - -h -C "$HI_TMPDIR" "${HI_EXCLUDE[@]}" hi.d | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d | tar mxzf - -C \$HI_TMPDIR
      export HI_TMPDIR=\$HI_TMPDIR
      export HI_ROOT=\$HI_ROOT
      echo \"$CMDARG\" >> \$HI_ROOT/hi.bashrc
      echo \"export hi_copy_time='$(echo "$(perl -MTime::HiRes=time -e 'printf "%.3f", time') $copy_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$HI_ROOT/load.sh
      bash --rcfile \$HI_ROOT/hi.bashrc
      "
}

# Zsh requires a different trap syntax (TRAPEXIT() { ... } vs trap '...' exit)
function say_hi_zsh() {
  ssh -t "$DOMAIN" "$SSHARGS" "
      $OPENSSL_CHECK
      export HI_TMPDIR=\$(mktemp -d -t $(whoami).hi.XXXX)
      mkdir \$HI_TMPDIR/hi.d
      export HI_ROOT=\$HI_TMPDIR/hi.d
      export HI_CLEANUP=\$HI_TMPDIR
      TRAPEXIT() { rm -rf \$HI_CLEANUP; }
      echo \"$(cat "$0" | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.sh
      chmod +x \$HI_ROOT/hi.sh
      echo \"$(
    cat <<'EOF' | $OPENSSL_CMD
      if [ -r /etc/profile ]; then source /etc/profile; fi
      if [ -r ~/.bash_profile ]; then source ~/.bash_profile
      elif [ -r ~/.bash_login ]; then source ~/.bash_login
      elif [ -r ~/.profile ]; then source ~/.profile
      fi
      export PATH=$PATH:${HI_ROOT+x}
      source $HI_ROOT/load.sh
      load
EOF
  )\" | $TR_CMD | $OPENSSL_CMD -d > \$HI_ROOT/hi.bashrc
      echo \"$(tar czf - -h -C "$HI_TMPDIR" "${HI_EXCLUDE[@]}" hi.d | $OPENSSL_CMD)\" | $TR_CMD | $OPENSSL_CMD -d | tar mxzf - -C \$HI_TMPDIR
      export HI_TMPDIR=\$HI_TMPDIR
      export HI_ROOT=\$HI_ROOT
      echo \"$CMDARG\" >> \$HI_ROOT/hi.bashrc
      echo \"export hi_copy_time='$(echo "$(perl -MTime::HiRes=time -e 'printf "%.3f", time') $copy_start_time" | awk '{ printf "%.3f\n", $1 - $2 }')'\" >> \$HI_ROOT/load.sh
      bash --rcfile \$HI_ROOT/hi.bashrc
      "
}

# Check dependencies, start to say hi, handle errors (both hi & ssh)
function run() {
  command -v openssl >/dev/null 2>&1 || {
    cecho >&2 "hi requires openssl to be installed on [$(hostname)], but it is not. Aborting..." "$RED"
    exit 1
  }

  if [ -d "$HI_ROOT" ]; then
    copy_start_time="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
    tmp="/tmp/$(date +%s).hi"
    if [[ -z ${ZSH_VERSION+x} ]]; then
      trap 'rm -rf $tmp' exit
    else
      # shellcheck disable=SC2329
      TRAPEXIT() { rm -rf "$tmp"; }
    fi

    hi_parse "$@"
    say_hi "$@" 2>"$tmp"

    local _exit_code="$?"
    local _errors
    _errors="$(cat "$tmp")"

    if [ "$_exit_code" -ne 0 ]; then
      echo -ne "\r\r\r\r"
      if [[ "$_errors" == *"Could not resolve hostname"* ]] ||
        [[ "$_errors" == *"Broken pipe"* ]] ||
        [[ "$_errors" == *"no such identity"* ]] ||
        [[ "$_errors" == *"Permission denied"* ]]; then
        cecho "| hi: ${_errors#*ssh: }" "$RED"
      else
        cecho "hi failed [code: $_exit_code], falling back to ssh..." "$BRRED"
        cecho "$_errors" "$BRRED"
        ssh "$@"
        exit 1
      fi
    fi
    exit "$_exit_code"

  else
    cecho "No such directory: $HI_ROOT" "$RED" >&2
    exit 1
  fi
}

run "$@"
