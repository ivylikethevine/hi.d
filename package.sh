#!/bin/sh
# basher's manifest, and only basher's - the name is basher's contract, not
# a choice (it reads a package.sh at the repo root; the deb/rpm/apk builder
# is packaging/mkpkg.sh, renamed so nothing shares this name). BINS links
# bin/hi onto PATH as `hi`; without this, basher's inference would link
# every executable in the repo root, i.e. `hi.sh` under the wrong name.
# shellcheck disable=SC2034 # basher sources this file for the variable
BINS=bin/hi
