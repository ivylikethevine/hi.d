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
#
# ssh-target-settings.sh comes from the same context and is the ssh demo's hi
# configuration. It belongs in the image rather than in a `docker exec` after
# the run: hi's permanent-install path ships no overlay and reads the box's own
# ~/.config/hi.d, so this file is part of what makes the box the demo's box.
FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server bash zsh fish git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /usr/bin/fish hitest
COPY --chown=hitest:hitest checkout /home/hitest/hi.d
COPY --chown=hitest:hitest ssh-target-settings.sh /home/hitest/.config/hi.d/settings.sh
RUN chmod +x /home/hitest/hi.d/hi.sh \
    && chown -R hitest:hitest /home/hitest/.config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
