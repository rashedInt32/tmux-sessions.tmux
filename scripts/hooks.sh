#!/bin/sh
# Install or remove the hooks that keep the status segment current.
#
#   hooks.sh install [-t <session>]
#   hooks.sh uninstall [-t <session>]
#
# These are the three events tmux fires when the session list or a client's
# session changes. Each runs refresh.sh, which re-evaluates the status line
# immediately, so the bar is right the moment you create, kill or switch a
# session rather than up to status-interval seconds later.
#
# Appended with -a, never plain -g: tmux stores hooks as arrays, and overwriting
# would drop whatever else is bound to these events -- including the hooks
# tmux-sessions.nvim installs when its `refresh.hooks` is enabled.
#
# The hook command is the absolute path to refresh.sh, so it is self-tagging:
# uninstall matches on that path and cannot remove a hook it did not install.
set -eu

dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REFRESH="${dir}/refresh.sh"
HOOKS='session-created session-closed client-session-changed'

action=${1-}
shift 2>/dev/null || true
# Scope: global by default, or one session when given -t. Session scope is what
# the tests use, so they never touch the server-wide configuration.
target=''
if [ "${1-}" = '-t' ] && [ -n "${2-}" ]; then
  target=$2
fi

show_hooks() {
  if [ -n "${target}" ]; then
    tmux show-hooks -t "${target}" 2>/dev/null || true
  else
    tmux show-hooks -g 2>/dev/null || true
  fi
}

set_hook_append() {
  if [ -n "${target}" ]; then
    tmux set-hook -a -t "${target}" "$1" "$2"
  else
    tmux set-hook -ga "$1" "$2"
  fi
}

unset_hook() {
  if [ -n "${target}" ]; then
    tmux set-hook -u -t "${target}" "$1" 2>/dev/null || true
  else
    tmux set-hook -gu "$1" 2>/dev/null || true
  fi
}

# Drop only the entries running our refresh.sh, highest index first so the
# earlier indices do not shift out from under the loop.
remove_ours() {
  hook=$1
  show_hooks |
    grep "^${hook}\[" |
    grep -F "${REFRESH}" |
    sed -n "s/^${hook}\[\([0-9]*\)\].*/\1/p" |
    sort -rn |
    while read -r idx; do
      if [ -n "${idx}" ]; then
        unset_hook "${hook}[${idx}]"
      fi
    done
}

case "${action}" in
install)
  for hook in ${HOOKS}; do
    # Idempotent: clear ours first, so re-sourcing tmux.conf cannot stack
    # duplicate entries.
    remove_ours "${hook}"
    set_hook_append "${hook}" "run-shell -b '${REFRESH}'"
  done
  ;;
uninstall)
  for hook in ${HOOKS}; do
    remove_ours "${hook}"
  done
  ;;
*)
  printf 'usage: %s install|uninstall [-t <session>]\n' "$0" >&2
  exit 2
  ;;
esac
