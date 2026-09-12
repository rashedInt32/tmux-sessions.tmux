#!/bin/sh
# Render the numbered session list as a tmux status segment.
#
# Called from status-right as:
#
#   #(/path/to/list.sh #{client_session})
#
# and, when the current session lives on the left, from status-left as:
#
#   #(/path/to/list.sh #{client_session} --current)
#
# tmux substitutes the format before running us, so $1 is the *client's* current
# session. That is why the "you are here" highlight stays correct with more than
# one client attached, which a hook computing `set -g status-right` could not be.
set -eu

# shellcheck source=scripts/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

current=${1-}
case "${2-}" in
--current | current) mode=current ;;
*) mode=list ;;
esac

max=$(ts_opt sessions_max 9)
width=$(ts_opt sessions_name_width 0)
sep=$(ts_opt sessions_separator '  ')
style=$(ts_opt sessions_style pill)
position=$(ts_opt sessions_current_position left)

palette=$(ts_opt sessions_colors "${TS_PALETTE}")
pill_fg=$(ts_opt sessions_pill_fg '#131314')
current_color=$(ts_opt sessions_current_color '#90b99f')
more_color=$(ts_opt sessions_more_color '#6c6874')

# `plain` reproduces the pre-pill rendering exactly, for a terminal with no Nerd
# Font. Those formats stay printf templates; the pill style computes its own.
fmt=$(ts_opt sessions_format '#[fg=#f5d76e]%d#[fg=#9f9ca6] %s#[default]')
cur_fmt=$(ts_opt sessions_current_format '#[fg=#7fe08a]%d %s#[default]')
more_fmt=$(ts_opt sessions_more_format '#[fg=#6b6772]+%d#[default]')

# Iterating a variable rather than a pipeline, because `... | while read` runs
# the loop in a subshell and the accumulator would not survive it.
sessions=$(ts_sessions)

total=0
shown=0
out=''

append() {
  if [ -z "${out}" ]; then
    out=$1
  else
    out="${out}${sep}$1"
  fi
}

OLDIFS=$IFS
IFS='
'
for row in $sessions; do
  if [ -z "$row" ]; then
    continue
  fi

  id=${row%%"${TAB}"*}
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

  # Matched against the id *or* the name on purpose. tmux's `#{client_session}`
  # resolves to the session NAME, not the id -- verified on 3.7c, where a client
  # in `packages` reports client_session=packages and session_id=$3. Comparing
  # only against ids meant the current session was never recognised in
  # production, while every spec passed because it handed in an id.
  is_current=no
  if [ -n "$current" ] && { [ "$id" = "$current" ] || [ "$name" = "$current" ]; }; then
    is_current=yes
  fi

  # --current renders only the current session; the default list then leaves it
  # out, so the two segments never show it twice. The numbering stays global, so
  # the list keeps a gap where the current session was -- that gap is the point.
  if [ "${mode}" = 'current' ]; then
    [ "${is_current}" = yes ] || continue
  elif [ "${is_current}" = yes ] && [ "${position}" = 'left' ]; then
    continue
  fi

  label=$(ts_truncate "$name" "$width")
  # Escape the name only, and after truncating: escaping first would let a cut
  # land between a '##' pair and leave a live '#' for tmux to act on.
  label=$(ts_escape "$label")

  if [ "${style}" = 'plain' ]; then
    if [ "${is_current}" = yes ]; then
      # shellcheck disable=SC2059
      append "$(printf "$cur_fmt" "$shown" "$label")"
    else
      # shellcheck disable=SC2059
      append "$(printf "$fmt" "$shown" "$label")"
    fi
  else
    if [ "${is_current}" = yes ]; then
      color=${current_color}
    else
      color=$(ts_color_for "$name" "$palette")
    fi
    append "$(ts_pill "${shown} ${label}" "${color}" "${pill_fg}")"
  fi
done
IFS=$OLDIFS

# The overflow marker belongs to the list, never to the single current pill.
if [ "${mode}" != 'current' ]; then
  hidden=$((total - shown))
  if [ "$hidden" -gt 0 ]; then
    if [ "${style}" = 'plain' ]; then
      # shellcheck disable=SC2059
      append "$(printf "$more_fmt" "$hidden")"
    else
      append "$(ts_pill "+${hidden}" "${more_color}" "${pill_fg}")"
    fi
  fi
fi

printf '%s' "$out"
