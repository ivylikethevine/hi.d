# The rpm-family sshd target: fedora, openssh-server, and a `hitest` user whose
# login shell the shared entrypoint rewrites from $LOGIN_SHELL - the same
# contract sshd-debian.Dockerfile has, so install_methods_test.sh can drive
# either with one case runner.
#
# It exists for one reason: to install a real .rpm with a real `rpm`. The
# package's *contents* are the same staging tree the .deb carries (nfpm builds
# both from dist/staging), but "does rpm install it, and does hi find what it
# left behind" is not a question the debian image can answer.
#
# entrypoint.sh is generated per build context by test_lib.sh's
# _hi_sshd_entrypoint - it carries the throwaway pubkey and the sshd flags, so
# it cannot be checked in beside this file.
FROM fedora:41@sha256:f1a3fab47bcb3c3ddf3135d5ee7ba8b7b25f2e809a47440936212a3a50957f3d
RUN dnf install -y --setopt=install_weak_deps=False --nodocs \
      openssh-server bash zsh \
    && dnf clean all \
    && useradd -m -s /bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
