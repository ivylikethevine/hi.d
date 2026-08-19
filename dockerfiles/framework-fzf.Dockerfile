# fzf's Ctrl-R, one of the two bash surfaces hi touches. Debian's fzf
# predates `fzf --bash`, so its packaged key-bindings file is what gets
# sourced - and that lives under /usr/share/doc, a path the slim base image
# tells dpkg to drop, hence the exclusion file going first.
#
# BASE is the sshd image from sshd-debian.Dockerfile; the framework goes on
# top of it and hitest keeps that image's login shell.
ARG BASE=hi-test-sshd
FROM ${BASE}
RUN rm -f /etc/dpkg/dpkg.cfg.d/docker \
 && apt-get update -qq && apt-get install -y -qq fzf >/dev/null
USER hitest
RUN printf 'source /usr/share/doc/fzf/examples/key-bindings.bash\n' >>~/.bashrc
USER root
