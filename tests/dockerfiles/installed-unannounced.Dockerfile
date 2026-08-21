# A system-wide install with its announcement taken away: the tree
# `install.sh --prefix` left under /usr/local/share, minus the
# /etc/profile.d/say-hi.sh snippet that says where it is. An admin who tidied
# /etc/profile.d, a tree restored from a backup, a package built without the
# snippet - the tree is there and nothing points at it.
#
# Built on the --prefix image rather than the .deb one on purpose. The scenario
# is the same either way, and dpkg has nothing left to prove here (the .deb case
# already covers it), but this way the tier the case exists for is still tested
# on a machine with no nfpm to build packages with - and it exercises a second
# standard prefix, where the brew case covers the keg one.
#
# Before the probe learned the standard install prefixes this answered "nothing
# installed", and hi copied its whole payload over a tree already on the target.
ARG BASE=hi-test-installed-prefix
FROM ${BASE}
RUN rm -f /etc/profile.d/say-hi.sh \
    && test -x /usr/local/share/say-hi/hi.sh \
    && test ! -e /home/hitest/say-hi \
    && ! grep -rq _HI_HOME /home/hitest/.bashrc /home/hitest/.zshrc 2>/dev/null
