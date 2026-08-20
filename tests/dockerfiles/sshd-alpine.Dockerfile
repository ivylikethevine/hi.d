# The busybox-userland sshd target: alpine, openssh, and hitest logging in
# under /bin/ash unless $PKGS brought a shell of its own. This is what proves
# hi's ssh fallback ladder against a machine with no bash.
#
# $PKGS is the extra packages for the variant - empty for plain ash, or a shell
# ("zsh", "fish") and anything it needs ("mksh git", since ksh is the only one
# of these whose prompt renders a live git segment).
#
# ARG *after* FROM: see alpine-shell.Dockerfile for why that placement matters.
FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
ARG PKGS
RUN apk add --no-cache openssh ${PKGS} \
    && adduser -D -s /bin/ash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
