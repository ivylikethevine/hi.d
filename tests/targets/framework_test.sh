#!/bin/bash
# hi against the shell frameworks people actually have installed.
#
# Almost nobody's ~/.zshrc is empty, and load.sh appends hi's block to the *end*
# of it - so hi runs after the framework and is the one positioned to break it.
# It has: `setopt KSH_ARRAYS` was set here for hi's convenience, and oh-my-zsh
# indexes arrays from 1.
#
# Each case boots a container with the framework installed per its own README,
# connects for real, and asserts the marker landed, the probe below says the
# specific collision is absent, and the transcript carries no shell error noise.
# A collision is rarely fatal - it just prints at you every prompt, which is
# what no other suite would notice.
#
# Each image keeps every shell the base has: load() follows the *login* shell
# now (see _hi_session_shell), so the framework's own shell is the one hi lands
# in - which is also what makes these cases a test of that. Builds need the
# network; a failed one skips its case rather than failing the suite.
#
# Nearly every function below is invoked indirectly, through _hi_case's "$@",
# which SC2329 can't see.
# shellcheck disable=SC2329
set -euo pipefail

# shellcheck source=../../common/core.sh
source "${_HI_HOME:-$HOME}/hi.d/common/core.sh"
# shellcheck source=../test_lib.sh
source "$_HI_TEST_LIB"

# "<label>=<0|1>", the same kv shape the other target suites use
_HI_FRAMEWORK_OK=""

# <label>:<login shell>:<Dockerfile body>. Each installs the framework
# unattended and leaves a *real* rc file behind - an empty ~/.zshrc would prove
# nothing, since the whole question is what happens when hi's block is appended
# after someone else's.
_HI_FRAMEWORKS=(
  "omz:/usr/bin/zsh:zsh"
  "p10k:/usr/bin/zsh:zsh"
  "starship:/bin/bash:bash"
  "bashit:/bin/bash:bash"
  # The env tools, which hook the same two surfaces hi's bash half touches -
  # each probed by the family:<needle> in its third field: bind:* is a
  # `bind -x` key binding (fzf's and atuin's Ctrl-R), hook:* a PROMPT_COMMAND
  # hook, the needle being the tool's handler name. zoxide's hook is
  # _zoxide_hook in debian's 0.8 and __zoxide_hook upstream; the
  # underscore-less needle matches both.
  "fzf:/bin/bash:bind:fzf"
  "zoxide:/bin/bash:hook:zoxide_hook"
  "direnv:/bin/bash:hook:_direnv_hook"
  "atuin:/bin/bash:bind:atuin"
  "mise:/bin/bash:hook:mise"
)

# The line each case types into the live session, once hi and the framework are
# both loaded. Built from two arguments because a pty echoes the input, so the
# token must be assembled by the shell. zsh checks the array base (hi must not
# leave KSH_ARRAYS on under omz/p10k); bash checks that hi's `ps1` is still
# chained onto the framework's PROMPT_COMMAND rather than replacing it.
function _hi_framework_probe() {
  case "$1" in
  zsh) printf '%s\n' "setopt | grep -q ksharrays && printf 'HI_FW-%s\\n' LEAKED || printf 'HI_FW-%s\\n' CLEAN" ;;
  bash) printf '%s\n' "[[ \$PROMPT_COMMAND == *ps1* ]] && printf 'HI_FW-%s\\n' CLEAN || printf 'HI_FW-%s\\n' LOST" ;;
  # the tool's Ctrl-R must still be its own after hi loads - `bind -X` lists
  # the bind -x bindings, and the handlers carry their tool's name
  bind:*) printf '%s\n' "bind -X 2>/dev/null | grep -q ${1#bind:} && printf 'HI_FW-%s\\n' CLEAN || printf 'HI_FW-%s\\n' LOST" ;;
  # both hooks in one PROMPT_COMMAND: the tool's (by its hook's name) still
  # there, and hi's ps1 *chained* on rather than having replaced it. The [*]
  # expansion reads the whole thing whether the tool appended to it as a
  # string or as bash 5.1's array form - bare $PROMPT_COMMAND would show
  # element 0 alone and cry LOST over a coexistence that is fine.
  hook:*) printf '%s\n' "[[ \${PROMPT_COMMAND[*]} == *${1#hook:}* && \${PROMPT_COMMAND[*]} == *ps1* ]] && printf 'HI_FW-%s\\n' CLEAN || printf 'HI_FW-%s\\n' LOST" ;;
  esac
}

function _hi_framework_dockerfile() {
  case "$1" in
  omz)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq zsh curl ca-certificates git >/dev/null
USER hitest
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
USER root
EOF
    ;;
  # oh-my-zsh plus the prompt everyone pairs it with. powerlevel10k is the
  # sharpest test of the array base: it is thousands of lines of zsh that all
  # assume the native one.
  p10k)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq zsh curl ca-certificates git >/dev/null
USER hitest
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
 && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k \
 && sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc \
 && printf 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n' >>~/.zshrc
USER root
EOF
    ;;
  # a prompt that owns PROMPT_COMMAND, which is the bash-side collision:
  # shells/bash.sh chains onto it rather than replacing it, and this is what
  # says whether that chaining actually holds
  starship)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null \
 && curl -fsSL https://starship.rs/install.sh | sh -s -- --yes >/dev/null
USER hitest
RUN printf 'eval "$(starship init bash)"\n' >>~/.bashrc
USER root
EOF
    ;;
  bashit)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq git ca-certificates >/dev/null
USER hitest
RUN git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it \
 && ~/.bash_it/install.sh --silent --no-modify-config \
 && printf 'export BASH_IT="$HOME/.bash_it"\nexport BASH_IT_THEME="bobby"\nsource "$BASH_IT"/bash_it.sh\n' >>~/.bashrc
USER root
EOF
    ;;
  # the three below are one apt package each; debian's fzf predates
  # `fzf --bash`, so its packaged key-bindings file is what gets sourced -
  # which lives under /usr/share/doc, a path the slim base image tells dpkg
  # to drop, hence the exclusion file going first
  fzf)
    cat <<'EOF'
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker \
 && apt-get update -qq && apt-get install -y -qq fzf >/dev/null
USER hitest
RUN printf 'source /usr/share/doc/fzf/examples/key-bindings.bash\n' >>~/.bashrc
USER root
EOF
    ;;
  zoxide)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq zoxide >/dev/null
USER hitest
RUN printf 'eval "$(zoxide init bash)"\n' >>~/.bashrc
USER root
EOF
    ;;
  direnv)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq direnv >/dev/null
USER hitest
RUN printf 'eval "$(direnv hook bash)"\n' >>~/.bashrc
USER root
EOF
    ;;
  # atuin is not packaged in debian. Its release installer, straight - the
  # setup.atuin.sh wrapper around it exits nonzero in a container - plus
  # bash-preexec, without which `atuin init bash` warns at every shell:
  # noise this suite would (rightly) read as a failure, but atuin's, not hi's
  atuin)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
USER hitest
RUN curl --proto '=https' --tlsv1.2 -LsSf https://github.com/atuinsh/atuin/releases/latest/download/atuin-installer.sh | sh >/dev/null 2>&1 \
 && curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash-preexec.sh \
 && printf 'source ~/.bash-preexec.sh\n. "$HOME/.atuin/bin/env"\neval "$(atuin init bash --disable-up-arrow)"\n' >>~/.bashrc
USER root
EOF
    ;;
  mise)
    cat <<'EOF'
RUN apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
USER hitest
RUN curl -fsSL https://mise.run | sh >/dev/null 2>&1 \
 && printf 'eval "$(~/.local/bin/mise activate bash)"\n' >>~/.bashrc
USER root
EOF
    ;;
  esac
}

function _hi_build_frameworks() {
  local spec label ctx
  for spec in "${_HI_FRAMEWORKS[@]}"; do
    label="${spec%%:*}"
    ctx="$_HI_WORKDIR/$label"
    mkdir -p "$ctx"
    {
      printf 'FROM %s\n' "$_HI_SSHD_IMAGE"
      _hi_framework_dockerfile "$label"
    } >"$ctx/Dockerfile"
    if _hi_build_image "$label" "hi-fwtest-$label-$$" "the $label case" \
      -f "$ctx/Dockerfile" "$ctx"; then
      _hi_kv_set _HI_FRAMEWORK_OK "$label" 1
    else
      _hi_kv_set _HI_FRAMEWORK_OK "$label" 0
    fi
  done
}

# the shared driver's feeder hook: types the probe for the framework family
# under test into the live session (see _hi_interactive_case's -f)
function _hi_type_framework_probe() {
  _hi_framework_probe "$_HI_FW_FAMILY"
}

# One interactive session per framework - a command-shaped run replaces load()
# outright and never reaches the rc graft, which is where collisions live. The
# probe (a second typed line) rides _hi_interactive_case's feeder hook.
function _hi_run_framework_case() {
  local label="$1" login_shell="$2" name ok=0
  # both case-scoped, and both for the same reason: cases run concurrently, and
  # bash's dynamic scoping is what carries the family down to the feeder hook
  # _hi_interactive_case calls on this case's behalf
  local _HI_SSH_PORT=""
  local _HI_FW_FAMILY="$3"

  # checked before the container boots, not after: with no pty to drive there
  # is nothing a booted container could add to the skip
  if [ "${#_HI_PTY_FORCED[@]}" -eq 0 ]; then
    _hi_skip "[$label]" "no python3 to drive an interactive pty"
    return 0
  fi

  name="hi-fwtest-$label-c-$$"
  _hi_h3 "Testing framework: $label ($login_shell)"
  _hi_sshd_container "$name" "hi-fwtest-$label-$$" -e "LOGIN_SHELL=$login_shell" || return 1
  _hi_ssh_launch "$_HI_SSH_PORT"

  if _hi_interactive_case -f _hi_type_framework_probe -m "HI_FW-CLEAN" \
    "$label" framework "$_HI_TEST_MARKER" 90 "${_HI_SSH_LAUNCH_BARE[@]}"; then
    # the assertion this suite exists for: hi and the framework coexisting
    # without either one printing at the user
    _hi_transcript_is_clean "$label" "$_HI_WORKDIR/$label.interactive.out" && ok=1
  fi

  _hi_rm_container "$name"
  [ "$ok" -eq 1 ]
}

function run_framework_tests() {
  _hi_require_backend docker

  _hi_workdir fwtest
  _hi_h1 "Testing hi alongside the common shell frameworks"
  _hi_ssh_keypair

  _hi_h2 "Building test images"
  _hi_sshd_image "the framework cases" || _hi_stand_down "no base image"
  _hi_build_frameworks

  _HI_TEST_MARKER="HI_FRAMEWORK_TEST_OK"
  _hi_pty_stdin auto "no tty and no python3 to fake one - results may be unreliable"

  _hi_suite_begin

  # Nine frameworks, nine containers, nothing shared between them - the widest
  # fan-out in the tree and the one this suite is almost entirely made of.
  local spec label shell family
  _hi_par_begin "framework cases"
  for spec in "${_HI_FRAMEWORKS[@]}"; do
    IFS=: read -r label shell family <<<"$spec"
    if [ "$(_hi_kv_get _HI_FRAMEWORK_OK "$label")" = 1 ]; then
      _hi_par_case "$label" _hi_run_framework_case "$label" "$shell" "$family"
    else
      _hi_skip "[$label]" "image did not build"
    fi
  done
  _hi_par_wait

  for spec in "${_HI_FRAMEWORKS[@]}"; do
    docker image rm -f "hi-fwtest-${spec%%:*}-$$" >/dev/null 2>&1 || true
  done

  _hi_suite_end "" \
    "hi coexists with every framework tested ($_HI_TOTAL cases)" \
    "hi collides with $_HI_FAILED/$_HI_TOTAL frameworks"
}

run_framework_tests
