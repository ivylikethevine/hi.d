# mise's PROMPT_COMMAND hook. Installed from mise.run rather than apt,
# which does not package it.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
USER hitest
RUN curl -fsSL https://mise.run | sh >/dev/null 2>&1 \
 && printf 'eval "$(~/.local/bin/mise activate bash)"\n' >>~/.bashrc
USER root
