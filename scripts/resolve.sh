#!/bin/sh
# Resolve a 1-based index to a tmux session id, in creation order.
#
# Prints the id and exits 0, or prints nothing and exits 1. The caller decides
# what "no session there" means; for a keybinding it means do nothing at all.
set -eu

# shellcheck source=scripts/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

n=${1-}
if ! ts_is_index "$n"; then
  exit 1
fi

id=$(ts_sessions | sed -n "${n}p" | cut -f1)

if ! ts_is_id "$id"; then
  exit 1
fi

printf '%s\n' "$id"
