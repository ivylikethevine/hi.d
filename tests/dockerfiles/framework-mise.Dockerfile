# mise's PROMPT_COMMAND hook. Installed from mise.run rather than apt,
# which does not package it.
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
RUN curl -fsSL https://mise.run | sh >/dev/null 2>&1 \
 && printf 'eval "$(~/.local/bin/mise activate bash)"\n' >>~/.bashrc
USER root
