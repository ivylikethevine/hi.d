# oh-my-zsh, the framework hi is most likely to be appended after. Its
# array indexing is the collision: `setopt KSH_ARRAYS` was set here for hi's
# convenience, and oh-my-zsh indexes arrays from 1.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq zsh curl ca-certificates git >/dev/null
USER hitest
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
USER root
