# zoxide's PROMPT_COMMAND hook, which has to survive hi chaining its own
# ps1 onto the same variable. One apt package.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq zoxide >/dev/null
USER hitest
RUN printf 'eval "$(zoxide init bash)"\n' >>~/.bashrc
USER root
