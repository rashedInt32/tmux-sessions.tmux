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
  prefix=$(ts_opt sessions_key_prefix 'M-')
  # Root table (-n): no tmux prefix, so a jump is one chord from any pane.
  # Deliberately not prefix+N, which tmux already binds to select-window.
  i=1
  while [ "${i}" -le 9 ]; do
    tmux bind-key -n "${prefix}${i}" run-shell -b "${SWITCH} ${i}"
    i=$((i + 1))
  done

  last=$(ts_opt sessions_last_key 'M-0')
  if [ -n "${last}" ]; then
    tmux bind-key -n "${last}" switch-client -l
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
