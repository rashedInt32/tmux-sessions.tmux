#!/bin/sh
# Render the numbered session list as a tmux status segment.
#
# Called from status-right as:
#
#   #(/path/to/list.sh #{client_session})
#
# tmux substitutes the format before running us, so $1 is the *client's* current
# session. That is why the "you are here" highlight stays correct with more than
# one client attached, which a hook computing `set -g status-right` could not be.
set -eu

# shellcheck source=scripts/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

current=${1-}

max=$(ts_opt sessions_max 9)
width=$(ts_opt sessions_name_width 0)
sep=$(ts_opt sessions_separator '  ')
fmt=$(ts_opt sessions_format '#[fg=#f5d76e]%d#[fg=#9f9ca6] %s#[default]')
cur_fmt=$(ts_opt sessions_current_format '#[fg=#7fe08a]%d %s#[default]')
more_fmt=$(ts_opt sessions_more_format '#[fg=#6b6772]+%d#[default]')

# Iterating a variable rather than a pipeline, because `... | while read` runs
# the loop in a subshell and the accumulator would not survive it.
sessions=$(ts_sessions)

total=0
shown=0
out=''

OLDIFS=$IFS
IFS='
'
for row in $sessions; do
  if [ -z "$row" ]; then
    continue
  fi

  id=${row%%"${TAB}"*}
  # Everything after the second tab, so a name containing tabs cannot happen
  # (tmux rejects them) but a name containing anything else survives whole.
  name=${row#*"${TAB}"}
  name=${name#*"${TAB}"}

  # A row we cannot trust is dropped before it counts, so it can neither be
  # numbered nor inflate the `+N` overflow.
  if ! ts_is_id "$id"; then
    continue
  fi

  total=$((total + 1))
  if [ "$shown" -ge "$max" ]; then
    continue
  fi
  shown=$((shown + 1))

  name=$(ts_truncate "$name" "$width")
  # Escape the name only. Our own format strings carry the #[...] directives
  # that colour this, and must reach tmux intact.
  name=$(ts_escape "$name")

  # SC2059: the format *is* the configurable thing here -- @sessions_format is a
  # printf template the user supplies. What matters is that the index and the
  # name are arguments, never part of the format, so a session named '%s' is
  # data. That is asserted in tests/specs/03_render.sh.
  if [ "$id" = "$current" ]; then
    # shellcheck disable=SC2059
    entry=$(printf "$cur_fmt" "$shown" "$name")
  else
    # shellcheck disable=SC2059
    entry=$(printf "$fmt" "$shown" "$name")
  fi

  if [ -z "$out" ]; then
    out=$entry
  else
    out="${out}${sep}${entry}"
  fi
done
IFS=$OLDIFS

hidden=$((total - shown))
if [ "$hidden" -gt 0 ]; then
  # shellcheck disable=SC2059
  out="${out}${sep}$(printf "$more_fmt" "$hidden")"
fi

printf '%s' "$out"
