# A bare shell-only target: no sshd, no entrypoint, just a shell for the
# docker/podman `exec` path to land in. $PKGS is the shell (plus anything it
# needs), so this one file covers the zsh/fish/mksh fallback images the
# container suites build and the demo tapes' flavors, which add git for the
# prompt's git segment.
#
# ARG *after* FROM on purpose: an ARG declared before FROM is a global, not
# visible inside the build stage, and `apk add ${PKGS}` would quietly install
# nothing at all.
FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
ARG PKGS
RUN apk add --no-cache ${PKGS}
