# say-hi on the target from the .deb - the way a Debian/Ubuntu user gets it.
# The tree lands at /usr/share/say-hi (root-owned, which SECURITY.md promises
# works), /usr/bin/hi is a symlink to it, and the only thing that says where it
# went is the /etc/profile.d/say-hi.sh snippet install.sh's packaging mode
# wrote - so this exercises the probe's profile.d candidate against a real
# package rather than a hand-placed file.
#
# The context is a per-case directory the suite fills with the freshly built
# package under a fixed name, so nothing here has to know the version.
ARG BASE=hi-test-sshd
FROM ${BASE}
COPY pkg.deb /tmp/pkg.deb
RUN dpkg -i /tmp/pkg.deb && rm -f /tmp/pkg.deb \
    && test -x /usr/share/say-hi/hi.sh \
    && test -f /etc/profile.d/say-hi.sh
