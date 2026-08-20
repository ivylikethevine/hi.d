# say-hi already installed at ~/say-hi on the target, rather than pushed over the
# wire by the payload - the permanent-install path, where load.sh finds a real
# checkout and skips the copy entirely. The sentinel is what the case greps
# for to prove it took that path and not the payload one.
#
# Build context is the repo root, so `COPY .` is the working tree.
ARG BASE=hi-test-sshd
FROM ${BASE}
COPY --chown=hitest:hitest . /home/hitest/say-hi
RUN chmod +x /home/hitest/say-hi/hi.sh \
    && touch /home/hitest/say-hi/.installed_sentinel \
    && chown hitest:hitest /home/hitest/say-hi/.installed_sentinel
