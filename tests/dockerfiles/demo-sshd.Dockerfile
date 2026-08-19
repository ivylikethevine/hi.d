# The demo tapes' ssh target: the e2e sshd image shape (debian + sshd + the
# shells, PUBKEY wired by the entrypoint) and on top of it this checkout
# preinstalled at ~/hi.d - the permanent-install story the README GIF cannot
# otherwise show.
#
# hitest's login shell is fish on purpose: hi follows the login shell now
# (load.sh's _hi_session_shell), so this is what makes the demo land in a shell
# other than the client's - which is the whole point of the GIF.
#
# `checkout` is a clean tree docs/tapes/fixtures.sh exports into the build
# context, not the live working directory: .git and dist/ would bloat the
# context and the image alike.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server bash zsh fish git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /usr/bin/fish hitest
COPY --chown=hitest:hitest checkout /home/hitest/hi.d
RUN chmod +x /home/hitest/hi.d/hi.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
