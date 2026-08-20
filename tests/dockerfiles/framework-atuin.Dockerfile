# atuin's Ctrl-R. Not packaged in debian, so this takes its release
# installer straight - the setup.atuin.sh wrapper around it exits nonzero in a
# container - plus bash-preexec, without which `atuin init bash` warns at every
# shell: noise this suite would (rightly) read as a failure, but atuin's, not
# hi's.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
USER hitest
# `SHELL -o pipefail` ahead of the piped RUN below, so a failed download is a
# failed build. Without it only the right-hand `sh` decides the exit status: a
# curl that 404s pipes nothing, sh succeeds on empty input, and the image ships
# without the framework in it - leaving a green suite testing an absence.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl --proto '=https' --tlsv1.2 -LsSf https://github.com/atuinsh/atuin/releases/latest/download/atuin-installer.sh | sh >/dev/null 2>&1 \
 && curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash-preexec.sh \
 && printf 'source ~/.bash-preexec.sh\n. "$HOME/.atuin/bin/env"\neval "$(atuin init bash --disable-up-arrow)"\n' >>~/.bashrc
USER root
