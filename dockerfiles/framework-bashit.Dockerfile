# bash-it, the bash-side counterpart to oh-my-zsh. --no-modify-config
# leaves the rc graft to the explicit append below, so the file hi appends
# after is one this image wrote deliberately.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq git ca-certificates >/dev/null
USER hitest
RUN git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it \
 && ~/.bash_it/install.sh --silent --no-modify-config \
 && printf 'export BASH_IT="$HOME/.bash_it"\nexport BASH_IT_THEME="bobby"\nsource "$BASH_IT"/bash_it.sh\n' >>~/.bashrc
USER root
