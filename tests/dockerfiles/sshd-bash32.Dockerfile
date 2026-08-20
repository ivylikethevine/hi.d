# A bash 3.2 target - the version macOS still ships, and the one every bash 4
# builtin hi might reach for (mapfile, `declare -A`, namerefs, globstar) is
# missing from. Built on the official bash:3.2 image with sshd on top, and
# bash 3.2 as hitest's login shell, so both halves of a session run under it:
# the payload sshd hands the login shell, and the interactive `bash --rcfile`
# load.sh chainloads into.
FROM bash:3.2@sha256:3a13e5da38baa575985778cd09ce8ac736d4b4dafc91a430e71271f6e5311b89
RUN apk add --no-cache openssh \
    && ln -sf /usr/local/bin/bash /bin/bash \
    && adduser -D -s /usr/local/bin/bash hitest
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
