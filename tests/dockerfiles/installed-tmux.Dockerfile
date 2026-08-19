# The same permanent install as installed.Dockerfile, plus tmux, for the
# --tmux case.
#
# ARG BASE has no default here on purpose: the base is the $$-suffixed tag
# installed.Dockerfile was just built under (hi-sshtest-debian-installed-$$),
# so there is no correct literal to fall back to - an unpassed arg must fail
# the build rather than resolve to some other run's leftover image.
ARG BASE
FROM ${BASE}
RUN apt-get update -qq && apt-get install -y -qq tmux >/dev/null
