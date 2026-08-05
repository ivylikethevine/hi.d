#!/bin/bash
# shared bootstrap for every bash consumer: locate hi.d (via $_HI_TMPDIR) and
# load paths.sh + colors.sh. colors.sh is guarded so re-sourcing this file
# within the same process (e.g. load.sh sourcing check.sh sourcing this again)
# is a no-op. fish sources common/paths.sh directly instead of this file.
# shellcheck source=./common/paths.sh
source "$_HI_TMPDIR/hi.d/common/paths.sh"
# shellcheck source=./common/colors.sh
command -v cecho >/dev/null || source "$_HI_COLORS"
