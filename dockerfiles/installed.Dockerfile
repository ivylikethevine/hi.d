# hi.d already installed at ~/hi.d on the target, rather than pushed over the
# wire by the payload - the permanent-install path, where load.sh finds a real
# checkout and skips the copy entirely. The sentinel is what the case greps
# for to prove it took that path and not the payload one.
#
# Build context is the repo root, so `COPY .` is the working tree.
ARG BASE=hi-test-sshd
FROM ${BASE}
COPY --chown=hitest:hitest . /home/hitest/hi.d
RUN chmod +x /home/hitest/hi.d/hi.sh \
    && touch /home/hitest/hi.d/.installed_sentinel \
    && chown hitest:hitest /home/hitest/hi.d/.installed_sentinel
