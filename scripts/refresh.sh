#!/bin/sh
# Re-evaluate the status line now.
#
# This is what the hooks run. It exists as a script rather than an inline
# `refresh-client -S` so the hook entry carries this path, which is how
# uninstall recognises our entries and leaves anyone else's alone.
set -eu
tmux refresh-client -S 2>/dev/null || true
