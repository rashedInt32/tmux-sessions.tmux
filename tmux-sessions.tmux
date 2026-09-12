#!/bin/sh
# TPM entry point. Sourced from tmux.conf:
#
#   run-shell '~/.tmux/plugins/tmux-sessions.tmux/tmux-sessions.tmux'
#
# Wires three things: the status segment, the Alt+N keys, and the refresh hooks.
# Each is individually disableable, and none of them overwrite anything.
set -eu

dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "${dir}/scripts/lib.sh"

LIST="${dir}/scripts/list.sh"
SWITCH="${dir}/scripts/switch.sh"

# --------------------------------------------------------------- status bar

if [ "$(ts_opt sessions_status on)" = 'on' ]; then
  segment="#(${LIST} #{client_session})"
  current=$(tmux show-option -gqv status-right || true)
  tmux set-option -g status-right "$(ts_merge_status "${current}" "${segment}" "${LIST}")"

  # status-right-length defaults to 40, which silently cuts the tail off the
  # list. Raise it, but never lower a larger value the user already chose.
  grow=$(ts_grow_length "$(tmux show-option -gqv status-right-length || echo 0)" "$(ts_opt sessions_status_length 200)")
  if [ -n "${grow}" ]; then
    tmux set-option -g status-right-length "${grow}"
  fi
fi

# ------------------------------------------------------------------- keys

if [ "$(ts_opt sessions_keys on)" = 'on' ]; then
  # `prefix` (default) binds into tmux's prefix table, so the keys are
  # <prefix> 1 .. <prefix> 9. `root` binds with -n for a modifier chord such as
  # M-1, which is one keystroke fewer but has to get past the terminal first.
  #
  # The prefix table is the default because the root table is not reliably
  # reachable: on macOS, Option only sends Alt when the terminal is configured
  # for it, and several terminals decide that from the active keyboard layout.
  # A binding that silently never fires is worse than one extra keystroke.
  #
  # Taking the prefix table does override tmux's own <prefix> 0-9
  # select-window. `<prefix> n` and `<prefix> p` still cycle windows.
  table=$(ts_opt sessions_key_table prefix)
  keymod=$(ts_opt sessions_key_prefix '')

  i=1
  while [ "${i}" -le 9 ]; do
    if [ "${table}" = 'root' ]; then
      tmux bind-key -n "${keymod}${i}" run-shell -b "${SWITCH} ${i}"
    else
      tmux bind-key "${keymod}${i}" run-shell -b "${SWITCH} ${i}"
    fi
    i=$((i + 1))
  done

  last=$(ts_opt sessions_last_key '0')
  if [ -n "${last}" ]; then
    if [ "${table}" = 'root' ]; then
      tmux bind-key -n "${keymod}${last}" switch-client -l
    else
      tmux bind-key "${keymod}${last}" switch-client -l
    fi
  fi
fi

# ------------------------------------------------------------------ hooks

if [ "$(ts_opt sessions_hooks on)" = 'on' ]; then
  "${dir}/scripts/hooks.sh" install
fi

# Paint now rather than waiting out status-interval. Nothing here needs a server
# restart -- options, bindings and hooks all take effect immediately -- but the
# status line itself only re-evaluates #() on its own schedule, so without this
# an install looks like it did nothing for up to 15 seconds.
"${dir}/scripts/refresh.sh"
