# The same package again as an .apk on alpine - the musl/busybox channel, and
# the one whose contents nfpm lays out file-by-file rather than as one tree
# (see nfpm.yaml's note about apk-tools rejecting the directory mode bits).
#
# --allow-untrusted because a local build is unsigned unless mkpkg.sh was given
# HI_APK_KEY; CI signs it, this fixture must work either way.
#
# The login shell moves to bash because the package depends on bash and apk
# just installed it: alpine's `adduser -D -s /bin/ash` put hitest on ash, and
# busybox has no usermod to undo that from the shared entrypoint. With bash
# present the session takes the same tier the deb and rpm cases do, so one
# assertion shape covers all three.
ARG BASE=hi-test-sshd-alpine
FROM ${BASE}
COPY pkg.apk /tmp/pkg.apk
RUN apk add --no-cache --allow-untrusted /tmp/pkg.apk && rm -f /tmp/pkg.apk \
    && sed -i 's#^\(hitest:.*\):/bin/ash$#\1:/bin/bash#' /etc/passwd \
    && test -x /usr/share/say-hi/hi.sh \
    && test -f /etc/profile.d/say-hi.sh
