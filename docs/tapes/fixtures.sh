#!/bin/bash
# Demo-tape fixtures: the targets docs/tapes/*.tape connect to, shaped like
# the e2e fixtures (tests/test_lib.sh) but standalone - a tape render happens
# outside the test harness, on a machine that just has the backends installed.
# Everything lands under /tmp/hi-demo so `down` can remove it wholesale, and
# every container carries `--label hi.demo=1` so a crashed render can't leak
# one: `down` sweeps the label rather than a list of names it has to be kept in
# step with. The label and not a `hi-demo-*` name prefix, because **a target is
# named for its own hostname** - the tape types `hi db-prod` and the prompt that
# comes back says `db-prod`, which a prefix would break. Nomad is the exception
# and cannot help it: an alloc is addressed by ID, so `hi <alloc-id>` lands on
# `batch-7` and no naming can make those match.
#
# Not sourced by anything; invoked from the tapes' Hide blocks:
#
#   docs/tapes/fixtures.sh up demo|ssh|docker|podman|nomad|kube|colors
#   docs/tapes/fixtures.sh down
set -euo pipefail

_HI_DEMO_DIR=/tmp/hi-demo
_HI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# a throwaway keypair and an ssh config the ssh tape's `hi -F` points at, so
# the demo never touches the renderer's ~/.ssh
function demo_keypair() {
  [ -f "$_HI_DEMO_DIR/key" ] || ssh-keygen -q -t ed25519 -N "" -f "$_HI_DEMO_DIR/key"
}

function demo_sshd_image() {
  # the image is tests/dockerfiles/demo-sshd.Dockerfile; what this function
  # assembles is its build context - the entrypoint below, the box's own hi
  # settings, and the clean checkout further down

  # The ssh demo's configuration, and the only one that lives on the target.
  # hi.sh's permanent-install branch (_say_hi, the $remote_root arm) sets
  # $_HI_HOME and $_HI_ROOT and stops, leaving core.sh to default
  # $_HI_CONFIG_DIR to the box's own ~/.config/say-hi - no overlay ships, which
  # is the point of a permanent install. So this rides in the image, where the
  # rest of the box's identity already is, and `docker run hi-demo-sshd` alone
  # is the demo's box rather than one that still needs configuring.
  demo_settings "$_HI_DEMO_DIR/ssh-target-settings.sh" <<'EOF'
export _HI_HEADER_TIMESTAMP='0'
export _HI_HEADER_SYSINFO='0'
EOF

  cat >"$_HI_DEMO_DIR/entrypoint.sh" <<'EOF'
#!/bin/bash
set -eu
mkdir -p /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown -R hitest:hitest /home/hitest/.ssh
chmod 700 /home/hitest/.ssh
ssh-keygen -A
exec /usr/sbin/sshd -D -e
EOF
  # A clean copy rather than the live checkout as context: .git and dist/ would
  # bloat the build context and the image alike.
  #
  # From HEAD by default, because a demo should show a state that exists in the
  # history. $HI_DEMO_SOURCE=worktree renders what is in front of you instead -
  # which matters more than it sounds: the *client* side of every tape is the
  # working tree either way, so rendering a dirty tree without this gives you a
  # new client talking to an old target, and the GIF quietly lies.
  rm -rf "$_HI_DEMO_DIR/checkout"
  mkdir -p "$_HI_DEMO_DIR/checkout"
  if [ "${HI_DEMO_SOURCE:-head}" = worktree ]; then
    # tracked files only, uncommitted contents included - the same set
    # `git archive` would take, read from the working tree
    (cd "$_HI_ROOT" && git ls-files -z | tar --null -T - -cf -) |
      tar -x -C "$_HI_DEMO_DIR/checkout"
  else
    (cd "$_HI_ROOT" && git archive HEAD | tar -x -C "$_HI_DEMO_DIR/checkout")
  fi
  docker build -q -t hi-demo-sshd \
    -f "$_HI_ROOT/tests/dockerfiles/demo-sshd.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
}

function up_ssh() {
  demo_keypair
  demo_sshd_image
  docker rm -f web-1 >/dev/null 2>&1 || true
  # --hostname as well as --name: docker's own default hostname is a random
  # 12-char hex ID, which makes for an ugly, meaningless color in the header's
  # user@host line. The two match so the ssh_config Host below, the name the
  # tape types, and the prompt that answers are all one word.
  docker run -d --rm --name web-1 --hostname web-1 --label hi.demo=1 \
    -p 127.0.0.1::22 \
    -e PUBKEY="$(cat "$_HI_DEMO_DIR/key.pub")" hi-demo-sshd >/dev/null
  local port
  port="$(docker port web-1 22/tcp | head -1)"
  port="${port##*:}"
  cat >"$_HI_DEMO_DIR/ssh_config" <<EOF
Host web-1
  HostName 127.0.0.1
  Port $port
  User hitest
  IdentityFile $_HI_DEMO_DIR/key
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
  # wait for sshd to answer before the tape types anything
  for _ in $(seq 1 30); do
    ssh -F "$_HI_DEMO_DIR/ssh_config" web-1 true 2>/dev/null && return 0
    sleep 1
  done
  echo "sshd never answered on port $port" >&2
  return 1
}

# a bare shell-only image per flavor, the docker/podman e2e shape. <name> is
# both the container's name and its hostname: the tape types the first and the
# prompt shows the second, and a demo where those differ reads as a bug in hi.
# It also gives the header's color-hash line something meaningful to hash
# instead of the backend's random container ID.
function up_container() { # <backend> <name> <flavor: debian|zsh|fish|ash>
  local backend="$1" name="$2" flavor="$3" image
  case "$flavor" in
  debian) image=debian:bookworm-slim ;;
  ash) image=alpine:3.24 ;;
  zsh | fish)
    "$backend" build -q -t "hi-demo-$flavor-img" --build-arg "PKGS=$flavor git" \
      -f "$_HI_ROOT/tests/dockerfiles/alpine-shell.Dockerfile" "$_HI_DEMO_DIR" >/dev/null
    image="hi-demo-$flavor-img"
    ;;
  *)
    echo "unknown flavor: $flavor" >&2
    return 1
    ;;
  esac
  "$backend" rm -f "$name" >/dev/null 2>&1 || true
  "$backend" run -d --rm --name "$name" --hostname "$name" --label hi.demo=1 \
    "$image" tail -f /dev/null >/dev/null
}

function up_nomad() {
  command -v nomad >/dev/null || {
    echo "nomad is not installed" >&2
    return 1
  }
  pkill -f 'nomad agent -dev' 2>/dev/null || true
  nomad agent -dev >"$_HI_DEMO_DIR/nomad.log" 2>&1 &
  echo $! >"$_HI_DEMO_DIR/nomad.pid"
  for _ in $(seq 1 30); do
    nomad status >/dev/null 2>&1 && break
    sleep 1
  done
  cat >"$_HI_DEMO_DIR/demo.nomad.hcl" <<'EOF'
job "hi-demo" {
  type = "service"
  group "g" {
    task "box" {
      driver = "docker"
      config {
        image    = "debian:bookworm-slim"
        hostname = "batch-7"
        command  = "tail"
        args     = ["-f", "/dev/null"]
      }
    }
  }
}
EOF
  nomad job run "$_HI_DEMO_DIR/demo.nomad.hcl" >/dev/null
  for _ in $(seq 1 30); do
    nomad job allocs -t '{{ range . }}{{ if eq .ClientStatus "running" }}{{ .ID }}{{ end }}{{ end }}' hi-demo \
      2>/dev/null | cut -c1-8 >"$_HI_DEMO_DIR/alloc"
    [ -s "$_HI_DEMO_DIR/alloc" ] && return 0
    sleep 1
  done
  echo "the hi-demo allocation never reached running" >&2
  return 1
}

function up_kube() {
  command -v kind >/dev/null || {
    echo "kind is not installed" >&2
    return 1
  }
  kind get clusters 2>/dev/null | grep -qx hi-demo ||
    kind create cluster --name hi-demo --wait 120s >/dev/null 2>&1
  # a pod's hostname *is* its name, so naming it for the host is all it takes
  # for `hi api-7` to answer as api-7. The cluster keeps the hi-demo name: it
  # is never on screen, and `kind delete cluster` is what tears it down.
  kubectl --context kind-hi-demo delete pod api-7 --ignore-not-found >/dev/null 2>&1
  kubectl --context kind-hi-demo run api-7 --image=alpine:3.24 \
    --restart=Never --command -- sleep infinity >/dev/null
  kubectl --context kind-hi-demo wait --for=condition=Ready pod/api-7 --timeout=120s >/dev/null
}

# The *client* side of every tape: an rc the tape sources so the outside shell
# has hi's own prompt (vhs starts a bare shell, which otherwise renders the
# blank default) under a chosen identity rather than the renderer's.
#
# The identity needs both halves. $_HI_WHOAMI_CACHE/$_HI_HOSTNAME_CACHE are what
# hi resolves *colors* from, so priming them makes the prompt's colors the ones
# that user@host really would get. The rendered text needs a different lever per
# shell: bash expands \u and \h itself, zsh's %n reads $USERNAME (which zsh will
# not let a script reassign), and fish reads $USER and prompt_hostname. So bash
# and zsh get the two escapes substituted back out of the finished prompt, and
# fish gets the variable and the function. Everything else on the line stays
# hi's real prompt - its colors, its separator, its git segment.
#
# Written through sed rather than an unquoted heredoc so the rc's own ${...}
# survives being generated.
# The per-demo configuration, written as the overlay's settings.sh rather than
# exported into the client shell. That is not a style choice - it is the only
# lever that reaches both ends: _hi_session_env (hi.sh) forwards the target
# color, the tags and the tmux intent and nothing else, so a _HI_DISABLE_* or
# _HI_HEADER_* exported here would style the client and leave the session it
# opens on stock defaults. settings.sh is _HI_OVERLAY_FILES[0], so hi ships it
# to the target and both sides read the same file.
#
# Written to $_HI_SETTINGS's own contract (scripts/install.sh): a `#!/bin/sh`
# line and `export NAME='value'` lines, nothing else - fish sources this file
# too, and doctor.sh fails a settings.sh that only parses as sh.
#
# Body on stdin, destination optional - the ssh demo's copy is baked into its
# image instead of the client's overlay dir, and this is the only writer of the
# format either way. No call at all is itself a configuration: demo.tape ships
# the stock defaults on purpose, as the one shot that shows everything on.
function demo_settings() { # [outfile] - body on stdin
  local out="${1:-$_HI_DEMO_DIR/config/settings.sh}"
  mkdir -p "$(dirname "$out")"
  {
    printf '#!/bin/sh\n'
    printf '# written by docs/tapes/fixtures.sh for this demo only\n'
    cat
  } >"$out"
}

# The rc template's substitutions, in one place rather than once per shell: the
# three rc *bodies* below differ for real, the sed line never did. Reads
# client_rc's locals, so it lives with it and nowhere else.
function rc_sed() { # <outfile> - body on stdin
  sed -e "s/@USER@/$user/g" -e "s/@HOST@/$host/g" \
    -e "s#@HOME@#$home#g" -e "s#@ROOT@#$_HI_ROOT#g" \
    -e "s#@CONFIG@#$_HI_DEMO_DIR/config#g" >"$1"
}

function client_rc() { # <shell> <user> <hostname>
  local shell="$1" user="$2" host="$3" home
  home="$(dirname "$_HI_ROOT")"
  # Every up:* calls this before writing its overlay, so this is the one place
  # that can guarantee a demo gets its own configuration and no one else's.
  # Without it a render of demo.tape straight after docker.tape would inherit
  # docker's overlay from /tmp and quietly stop being the defaults shot. The
  # whole directory, not just settings.sh: `colors` is an overlay file too and
  # would leak the same way.
  rm -rf "$_HI_DEMO_DIR/config"
  mkdir -p "$_HI_DEMO_DIR/config"
  # $_HI_HOME/$_HI_ROOT are baked in rather than inherited: vhs starts a bare
  # shell, and on a machine where /usr/bin/hi points at some other install (or
  # a login profile exports its own $_HI_HOME) an inherited one renders the
  # wrong tree - silently, and the GIF is the only place it would show.
  case "$shell" in
  bash)
    rc_sed "$_HI_DEMO_DIR/clientrc.bash" <<'EOF'
export _HI_HOME='@HOME@' _HI_ROOT='@ROOT@'
export _HI_WHOAMI_CACHE='@USER@' _HI_HOSTNAME_CACHE='@HOST@'
# Unconditional, and it has to be: generate.sh sources common/core.sh, which
# exports $_HI_CONFIG_DIR, and vhs hands that environment straight to this
# shell - so anything conditional here would read the renderer's own overlay
# and silently drop this demo's. Ahead of the rc, which is what sources it.
export _HI_CONFIG_DIR='@CONFIG@'
source "$_HI_ROOT/shells/bash.sh"
_hi_demo_ps1() {
  ps1
  PS1="${PS1//\\u/@USER@}"
  PS1="${PS1//\\h/@HOST@}"
}
PROMPT_COMMAND=_hi_demo_ps1
EOF
    ;;
  zsh)
    rc_sed "$_HI_DEMO_DIR/clientrc.zsh" <<'EOF'
export _HI_HOME='@HOME@' _HI_ROOT='@ROOT@'
export _HI_WHOAMI_CACHE='@USER@' _HI_HOSTNAME_CACHE='@HOST@'
# unconditional, for the reason the bash rc spells out
export _HI_CONFIG_DIR='@CONFIG@'
source "$_HI_ROOT/shells/zsh.zsh"
# %n reads $USERNAME, which zsh will not let a script reassign, so both escapes
# are substituted out of the finished prompt instead. zsh builds PS1 once and
# updates the git segment through a variable, so once is enough.
PS1="${PS1//\%n/@USER@}"
PS1="${PS1//\%m/@HOST@}"
EOF
    ;;
  fish)
    rc_sed "$_HI_DEMO_DIR/clientrc.fish" <<'EOF'
set -gx _HI_HOME '@HOME@'
set -gx _HI_ROOT '@ROOT@'
set -gx _HI_WHOAMI_CACHE '@USER@'
set -gx _HI_HOSTNAME_CACHE '@HOST@'
set -gx USER '@USER@'
# unconditional, for the reason the bash rc spells out
set -gx _HI_CONFIG_DIR '@CONFIG@'
function prompt_hostname
  echo '@HOST@'
end
source "$_HI_ROOT/shells/config.fish"
EOF
    ;;
  esac
}

# The color-preview demo needs no backend at all - just an ssh config with
# enough shape to be worth previewing, and a colors overlay pinning a few of
# them. The two land in different places because they are found in different
# ways: paths.sh:53 assigns $_HI_SSH_CONFIG from $HOME every time it is
# sourced, so that one needs a throwaway $HOME the tape exports, while
# paths.sh:30 reads `colors` out of $_HI_CONFIG_DIR - which is the same overlay
# dir every other demo writes its settings.sh into. Getting the first one right
# is not neatness: reading the renderer's real ~/.ssh/config would put their
# hostnames into a committed GIF.
function up_colors() {
  mkdir -p "$_HI_DEMO_DIR/home/.ssh"
  cat >"$_HI_DEMO_DIR/home/.ssh/config" <<'EOF'
# Tags: prod
Host db-prod web-prod
  User deploy

# Tags: staging
Host db-staging
  User deploy

# Tags: desktop
Host workshop
  User hitest

Host build-box
  User ci

Host bastion
  User root
EOF
  cat >"$_HI_DEMO_DIR/config/colors" <<'EOF'
# pins beat the name hash; everything unpinned still resolves on its own
username,root,red
hostname,bastion,yellow
hosttag,prod,red
hosttag,staging,yellow
hosttag,desktop,green
EOF
}

# The label, not a list of names: a name list has to be edited in step with
# every fixture and silently leaks the one somebody forgot, where the label is
# on every container up_container and up_ssh start. Both backends, because a
# render can crash between docker's fixtures and podman's.
function demo_down() {
  local backend ids
  for backend in docker podman; do
    command -v "$backend" >/dev/null 2>&1 || continue
    ids="$("$backend" ps -aq --filter label=hi.demo=1 2>/dev/null || true)"
    # shellcheck disable=SC2086 # ids is a list of container IDs, split on purpose
    [ -n "$ids" ] && "$backend" rm -f $ids >/dev/null 2>&1
  done
  if [ -f "$_HI_DEMO_DIR/nomad.pid" ]; then
    nomad job stop -purge hi-demo >/dev/null 2>&1 || true
    kill "$(cat "$_HI_DEMO_DIR/nomad.pid")" 2>/dev/null || true
  fi
  if kind get clusters 2>/dev/null | grep -qx hi-demo; then
    kind delete cluster --name hi-demo >/dev/null 2>&1 || true
  fi
  rm -rf "$_HI_DEMO_DIR" /tmp/hi-demo.log
}

mkdir -p "$_HI_DEMO_DIR"
case "${1:-}:${2:-}" in
# Client identities, chosen per tape rather than taken from the renderer. The
# spread is the point: every tape but one says hi somewhere it is not. The
# exception is docker's second target, where client and target are both cache-1
# - the same box reached two ways, which is worth one frame of the set.
up:ssh)
  # No demo_settings here: this demo's trimmed header is baked into the box's
  # own image, because a permanent install reads its own config and never the
  # client's overlay. demo_sshd_image says why.
  client_rc bash ivy workshop
  up_ssh
  ;;
up:docker)
  client_rc zsh dev cache-1
  # demo.tape connects to this same debian box, so the difference between the
  # README's top GIF and this one has to be the *client* - hence a prompt end
  # of its own and no packages check, neither of which touches the fixture.
  demo_settings <<'EOF'
export _HI_PROMPT_END_ZSH='❯'
export _HI_HEADER_CHECK='0'
EOF
  up_container docker db-prod debian
  up_container docker cache-1 zsh
  ;;
up:podman)
  client_rc fish ops bastion
  # fish's own prompt separator. _HI_ENABLE_FISH_ALIAS_ABBR belongs to this
  # demo on paper - it is the one fish-only knob and this is the only tape with
  # fish on both ends - but it cannot be shown here: hi is itself an alias, so
  # the abbr expands the `hi edge-1` the tape types into the shim's
  # absolute path, rewriting the command the GIF exists to show.
  demo_settings <<'EOF'
export _HI_PROMPT_END_FISH='»'
EOF
  up_container podman edge-1 fish
  ;;
up:nomad)
  client_rc bash ivy workshop
  # the header knobs the other demos leave alone. Note what is *not* here:
  # nomad.tape waits on /Disconnected/, which banner() prints, so this is the
  # one demo that cannot turn _HI_HEADER_BANNER or _HI_DISABLE_HEADER off
  # without hanging its own render.
  demo_settings <<'EOF'
export _HI_HEADER_IDENTITY='0'
export _HI_HEADER_GHZ='1'
EOF
  up_nomad
  ;;
up:kube)
  client_rc zsh dev cache-1
  # the git segment off, and only that. A pod reached through the aliases-only
  # fallback draws no header at all, so the client prompt is the only surface
  # this demo can show a knob on - which rules out _HI_DISABLE_PROMPT=1, the
  # obvious pick: it renders a GIF with nothing of hi left in frame.
  demo_settings <<'EOF'
export _HI_DISABLE_GIT_STATUS='1'
EOF
  up_kube
  ;;
up:colors)
  # no settings.sh: this demo's configuration is the `colors` overlay up_colors
  # writes, into the same dir every other demo uses. The tape exports a
  # throwaway $HOME as well, for the ssh config the preview reads.
  client_rc bash ivy workshop
  up_colors
  ;;
up:demo)
  client_rc bash ivy workshop
  # No demo_settings, deliberately. Every other demo turns something off or
  # swaps something out; the README's top GIF is the one that shows what you
  # get having configured nothing, which is only legible if it stays stock.
  up_container docker db-prod debian
  ;;
down:) demo_down ;;
*)
  echo "usage: fixtures.sh up <demo|ssh|docker|podman|nomad|kube|colors> | down" >&2
  exit 1
  ;;
esac
