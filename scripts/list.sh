#!/bin/sh
# Render the numbered session list as a tmux status segment.
#
# Called from status-right as:
#
#   #(/path/to/list.sh #{client_session} list #{client_width})
#
# and, when the current session lives on the left, from status-left as:
#
#   #(/path/to/list.sh #{client_session} current)
#
# tmux substitutes the formats before running us, so $1 is the *client's*
# current session and $3 is that client's width. $1 is a session NAME, not an
# id -- see the match below.
set -eu

# shellcheck source=scripts/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

current=${1-}
case "${2-}" in
--current | current) mode=current ;;
*) mode=list ;;
esac
client_width=${3-0}
case "${client_width}" in
'' | *[!0-9]*) client_width=0 ;;
esac

max=$(ts_opt sessions_max 9)
width=$(ts_opt sessions_name_width 0)
sep=$(ts_opt sessions_separator '  ')
style=$(ts_opt sessions_style pill)
position=$(ts_opt sessions_current_position left)

palette=$(ts_opt sessions_colors "${TS_PALETTE}")
pill_fg=$(ts_opt sessions_pill_fg '#131314')
# Orchid, at hue 288. Chosen by measuring the palette rather than by eye: its
# ten colours leave one 76-degree gap, between purple (250) and magenta (326),
# and this sits in the middle of it. White receded instead of standing out --
# it was the least saturated thing on a bar of saturated names.
current_color=$(ts_opt sessions_current_color '#df65ff')
more_color=$(ts_opt sessions_more_color '#6c6874')

# No session may take a colour near the one that means "here", or the two read
# as the same at a glance -- which is exactly what happened with the current
# orchid against session 1's #ff79c6, 38 degrees and a deltaE of 41 apart.
# 0 disables the reservation.
reserve_hue=$(ts_opt sessions_reserve_hue 45)
if [ "${reserve_hue}" -gt 0 ]; then
  palette=$(ts_palette_excluding "${current_color}" "${palette}" "${reserve_hue}")
fi

# The index badge. `off` goes back to a plain "N name" pill.
badge=$(ts_opt sessions_badge on)
badge_color=$(ts_opt sessions_badge_color '#ffffff')
badge_fg=$(ts_opt sessions_badge_fg '#131314')
# Cells between the pill's cap and the badge. Whole cells -- a terminal has no
# sub-cell geometry, so this cannot be expressed in pixels, and there is no
# vertical equivalent at all: the bar is one cell tall.
badge_pad=$(ts_opt sessions_badge_pad 1)
# The current session stays a filled pill even in flat style, unless told
# otherwise: one filled entry against a row of plain text is what makes "here"
# read instantly, and an all-flat row loses that for nothing.
flat_current=$(ts_opt sessions_flat_current text)
# Cells before the current entry. status-left starts hard against the terminal
# edge, which reads as clipped rather than aligned.
left_pad=$(ts_opt sessions_left_pad 2)
# The current session's number is the one number that is not a key you can
# press: prefix+4 while already in 4 does nothing. Showing it advertises an
# action that does not exist, so it is hidden by default. Position carries
# "here" on its own -- that slot only ever holds the current session.
current_number=$(ts_opt sessions_current_number off)
# `pill` nests a second cap pair (works everywhere, stadium shaped).
# `glyph` uses a real circled-digit character, which has margin on every side
# including above and below -- but relies on terminal font fallback.
badge_style=$(ts_opt sessions_badge_style pill)
circle_color=$(ts_opt sessions_circle_color '#131314')
# dingbat (small, CJK fallback) | sans (larger, Latin fallback) | outline
circle_set=$(ts_opt sessions_circle_set sans)

fmt=$(ts_opt sessions_format '#[fg=#f5d76e]%d#[fg=#9f9ca6] %s#[default]')
cur_fmt=$(ts_opt sessions_current_format '#[fg=#7fe08a]%d %s#[default]')
more_fmt=$(ts_opt sessions_more_format '#[fg=#6b6772]+%d#[default]')

# Cells to leave for everything else on the bar. status-left and the window
# list sit to our left and we cannot measure either from here, so this is a
# reservation rather than a calculation.
reserve=$(ts_opt sessions_reserve 34)

NL='
'

# Pass 1 -- decide what each row would be, without rendering it yet, so the
# widths are known before anything is committed to.
rows=''
total=0
shown=0

OLDIFS=$IFS
IFS=$NL
for row in $(ts_sessions); do
  [ -n "$row" ] || continue

  id=${row%%"${TAB}"*}
  name=${row#*"${TAB}"}
  name=${name#*"${TAB}"}

  ts_is_id "$id" || continue

  total=$((total + 1))
  [ "$shown" -lt "$max" ] || continue
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

  if [ "${mode}" = 'current' ]; then
    [ "${is_current}" = yes ] || continue
  elif [ "${is_current}" = yes ] && [ "${position}" = 'left' ]; then
    continue
  fi

  label=$(ts_truncate "$name" "$width")
  # Escape after truncating: escaping first would let a cut land between a '##'
  # pair and leave a live '#' for tmux to act on.
  label=$(ts_escape "$label")

  # The raw name rides along so the colour hashes from it, not from the
  # truncated label: otherwise changing name_width would reshuffle every
  # colour, and the whole point is that a session keeps its own.
  rows="${rows}${shown}${TAB}${is_current}${TAB}${name}${TAB}${label}${NL}"
done
IFS=$OLDIFS

# Pass 2 -- drop from the end until the segment fits the client.
#
# Without this the bar does not degrade, it disappears: tmux renders
# status-right only if the whole thing fits beside status-left and the window
# list, so one session too many takes the entire list off screen with no hint
# why. Dropping the tail into the `+N` marker is the same behaviour as
# sessions_max, just driven by the terminal rather than by configuration.
hidden=$((total - shown))

if [ "${mode}" != 'current' ] && [ "${client_width}" -gt 0 ]; then
  budget=$((client_width - reserve))
  [ "${budget}" -lt 10 ] && budget=10

  # A pill costs its label plus four cells of chrome; plain costs the label plus
  # the number and a space. Measure the real thing rather than guessing.
  while [ -n "${rows}" ]; do
    used=0
    n=0
    OLDIFS=$IFS
    IFS=$NL
    for r in $rows; do
      [ -n "$r" ] || continue
      idx=${r%%"${TAB}"*}
      lbl=${r##*"${TAB}"}
      n=$((n + 1))
      # Chrome is per style, not a constant. Charging pill chrome for a flat
      # entry made the estimate drop sessions that would have fit -- visibly so,
      # since untruncated names then showed FEWER sessions than truncated ones.
      used=$((used + $(printf '%s %s' "$idx" "$lbl" | wc -m | tr -d ' ')))
      case "${style}" in
      flat)
        : # glyph and space are already counted by the printf above
        ;;
      plain)
        : # the format supplies its own spacing
        ;;
      *)
        # Two caps and two spaces of pill.
        used=$((used + 4))
        if [ "${badge}" = 'on' ]; then
          if [ "${badge_style}" = 'glyph' ]; then
            used=$((used + 1))
          else
            used=$((used + 2 + badge_pad))
          fi
        fi
        ;;
      esac
      [ "$n" -gt 1 ] && used=$((used + ${#sep}))
    done
    IFS=$OLDIFS
    # Room for the `+N` pill too, when one will be shown.
    [ "${hidden}" -gt 0 ] && used=$((used + 6 + ${#sep}))

    [ "${used}" -le "${budget}" ] && break
    [ "$n" -le 1 ] && break

    # Drop the last row and count it as hidden instead.
    rows=$(printf '%s' "${rows}" | sed '$d')
    hidden=$((hidden + 1))
  done
fi

# Pass 3 -- render what survived.
out=''
used_colors=''
append() {
  if [ -z "${out}" ]; then out=$1; else out="${out}${sep}$1"; fi
}

OLDIFS=$IFS
IFS=$NL
for r in $rows; do
  [ -n "$r" ] || continue
  idx=${r%%"${TAB}"*}
  rest=${r#*"${TAB}"}
  is_current=${rest%%"${TAB}"*}
  rest=${rest#*"${TAB}"}
  rawname=${rest%%"${TAB}"*}
  label=${rest#*"${TAB}"}

  if [ "${style}" = 'flat' ] && { [ "${is_current}" != yes ] || [ "${flat_current}" != 'pill' ]; }; then
    if [ "${is_current}" = yes ]; then
      color=${current_color}
    else
      color=$(ts_color_for "$rawname" "$palette")
      if [ "$(ts_opt sessions_unique_colors on)" = 'on' ]; then
        color=$(ts_free_color "$color" "$used_colors" "$palette")
      fi
      used_colors="${used_colors} ${color}"
    fi
    if [ "${is_current}" = yes ] && [ "${current_number}" != 'on' ]; then
      append "$(ts_flat '' "$label" "$color" bold)"
    elif [ "${is_current}" = yes ]; then
      g=$(ts_badge_glyph "${idx}" "${circle_set}" 2>/dev/null) || g="${idx}"
      append "$(ts_flat "$g" "$label" "$color" bold)"
    else
      g=$(ts_badge_glyph "${idx}" "${circle_set}" 2>/dev/null) || g="${idx}"
      append "$(ts_flat "$g" "$label" "$color")"
    fi
  elif [ "${style}" = 'plain' ]; then
    if [ "${is_current}" = yes ]; then
      # shellcheck disable=SC2059
      append "$(printf "$cur_fmt" "$idx" "$label")"
    else
      # shellcheck disable=SC2059
      append "$(printf "$fmt" "$idx" "$label")"
    fi
  else
    if [ "${is_current}" = yes ]; then
      color=${current_color}
    else
      color=$(ts_color_for "$rawname" "$palette")
      # Two pills in the same colour defeats the point of colouring them, so a
      # collision probes forward to the next free entry.
      if [ "$(ts_opt sessions_unique_colors on)" = 'on' ]; then
        color=$(ts_free_color "$color" "$used_colors" "$palette")
      fi
      used_colors="${used_colors} ${color}"
    fi
    # The current session is deliberately left plain. Its pill is already a
    # different colour from every other, so the badge added nothing but a dark
    # blob on a light background.
    if [ "${badge}" = 'on' ] && [ "${is_current}" != yes ] && [ "${badge_style}" = 'glyph' ] &&
      g=$(ts_pill_glyph "${idx}" "${label}" "${color}" "${pill_fg}" \
        "$(ts_badge_color "${circle_color}" "${color}" "${pill_fg}")" "${circle_set}"); then
      # Only indices 1..9 have a glyph; anything else falls through to the
      # nested-cap badge rather than losing its number.
      append "$g"
    elif [ "${badge}" = 'on' ] && [ "${is_current}" != yes ]; then
      bc=$(ts_badge_color "${badge_color}" "${color}" "${pill_fg}")
      append "$(ts_pill_badge "${idx}" "${label}" "${color}" "${pill_fg}" "${bc}" "${badge_fg}" "${badge_pad}")"
    else
      append "$(ts_pill "${idx} ${label}" "${color}" "${pill_fg}")"
    fi
  fi
done
IFS=$OLDIFS

# The overflow marker belongs to the list, never to the single current pill.
if [ "${mode}" != 'current' ] && [ "${hidden}" -gt 0 ]; then
  if [ "${style}" = 'plain' ]; then
    # shellcheck disable=SC2059
    append "$(printf "$more_fmt" "${hidden}")"
  else
    append "$(ts_pill "+${hidden}" "${more_color}" "${pill_fg}")"
  fi
fi

if [ "${mode}" = 'current' ] && [ -n "$out" ]; then
  pad=''
  i=0
  while [ "$i" -lt "${left_pad}" ]; do
    pad="${pad} "
    i=$((i + 1))
  done
  out="${pad}${out}"
fi

printf '%s' "$out"
