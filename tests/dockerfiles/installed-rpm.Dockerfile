# The same package as installed-deb.Dockerfile, in rpm form, installed with a
# real `rpm` on a real fedora. --nodeps because the base image already carries
# bash and openssh, and the rpm names its openssh dependency `openssh-clients`
# (nfpm.yaml's rpm override) - resolving it would pull a mirror for packages
# that are already there.
ARG BASE=hi-test-sshd-fedora
FROM ${BASE}
COPY pkg.rpm /tmp/pkg.rpm
RUN rpm -i --nodeps /tmp/pkg.rpm && rm -f /tmp/pkg.rpm \
    && test -x /usr/share/say-hi/hi.sh \
    && test -f /etc/profile.d/say-hi.sh
