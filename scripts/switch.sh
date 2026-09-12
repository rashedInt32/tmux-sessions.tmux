#!/bin/sh
# Jump to the session at the given index.
#
# Bound statically to Alt+N, and resolves the index at press time rather than
# being rebound when the session list changes. Rebinding nine keys on every hook
# leaves a window where a key points at a dead session; resolving on press costs
# one `list-sessions` (~8ms) and is always right.
#
# No session at that index is a silent no-op. Pressing Alt+7 on a four-session
# machine should do nothing, not put an error on your status bar.
set -eu

dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "${dir}/lib.sh"

id=$("${dir}/resolve.sh" "${1-}" 2>/dev/null) || exit 0
ts_is_id "$id" || exit 0

# A session killed between the resolve and here makes this fail; that is the
# common case, not an exceptional one, so it stays quiet.
tmux switch-client -t "$id" 2>/dev/null || exit 0
