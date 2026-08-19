# direnv's PROMPT_COMMAND hook, the same coexistence question as zoxide's.
# One apt package.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq direnv >/dev/null
USER hitest
RUN printf 'eval "$(direnv hook bash)"\n' >>~/.bashrc
USER root
