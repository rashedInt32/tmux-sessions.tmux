# Shared helpers. Sourced by every script; not executable on its own.
#
# Two seams exist purely so the suite never needs a running tmux server:
# TMUX_SESSIONS_FIXTURE replaces `tmux list-sessions`, and TS_OPT_<name>
# replaces a `@<name>` tmux option. Both fall through to real tmux when unset,
# so the production path is the same code the tests exercise.

TAB=$(printf '\t')

# Pill caps: U+E0B6 and U+E0B4, the half circles the user's lualine uses.
#
# Written as octal UTF-8 rather than as literal characters. These are Private
# Use Area codepoints, and they were silently stripped in transit while this was
# being prototyped -- producing square-ended pills with no error anywhere. Octal
# escapes cannot be mangled that way. tests/specs/09_pills.sh asserts both caps
# actually reach the rendered output.
TS_CAP_LEFT=$(printf '\356\202\266')
TS_CAP_RIGHT=$(printf '\356\202\264')

# Bright, saturated colours, deliberately NOT the editor's palette.
#
# The first version reused oldworld's muted tones, which is what lualine uses
# inside nvim. Sharing a palette across the editor and the bar below it makes
# the two hard to tell apart at a glance -- the bar should read as a different
# surface, not as more editor. These are vivid enough to separate from each
# other and from anything nvim draws, and all take dark text legibly.
#
# Ten rather than eight, because collisions scale with the square of the session
# count and five or six sessions is normal.
TS_PALETTE='#ff6188 #fc9867 #ffd866 #a9dc76 #78dce8 #ab9df2 #ff79c6 #7bd88f #f8a5c2 #6ec7ff'

# Pick a palette colour for a name. Deterministic, not random.
#
# "Random colours" means varied, not re-rolled: the bar re-renders on every hook
# and every status-interval, so an actual random pick would change every pill
# several times a minute. Hashing binds the colour to the session instead, so it
# survives other sessions being created or killed -- the same property that
# makes the numbers worth memorising.
#
# Hashed on the name, not the id: ids are handed out sequentially ($30, $32,
# $33) and would cluster into neighbouring palette slots. Renaming a session
# recolours it, which is rare and arguably right.
#
#   ts_color_for <name> <palette>
ts_color_for() {
  ts_color__name=$1
  ts_color__pal=${2:-${TS_PALETTE}}
  # IFS is forced back to whitespace for the split. Callers render inside a
  # `IFS=<newline>` loop, and with that still in effect `set --` treats the
  # whole palette as one word: every session then lands on entry 1 and the bar
  # comes out in a single colour.
  ts_color__ifs=$IFS
  IFS=' '
  # shellcheck disable=SC2086
  set -- ${ts_color__pal}
  IFS=${ts_color__ifs}
  ts_color__n=$#
  if [ "${ts_color__n}" -eq 0 ]; then
    return 0
  fi
  # cksum is POSIX and stable across runs; the value only has to be spread, not
  # cryptographic.
  ts_color__h=$(printf '%s' "${ts_color__name}" | cksum | cut -d' ' -f1)
  ts_color__i=$((ts_color__h % ts_color__n + 1))
  eval "printf '%s' \"\${${ts_color__i}}\""
}

# First palette colour at or after `preferred` that is not already used.
#
#   ts_free_color <preferred> <used-colours> <palette>
#
# The hash alone collides: ten colours and six sessions is a coin flip, and two
# pills in the same colour defeats the reason for colouring them. Probing
# forward guarantees every visible pill differs while there are colours left.
#
# The cost is that a colour is no longer purely a function of the name -- the
# session that loses a collision moves when the set changes. Only the loser
# moves, and telling two pills apart matters more than one of them never
# shifting. Falls back to `preferred` once the palette is exhausted.
ts_free_color() {
  ts_free__want=$1
  ts_free__used=$2
  ts_free__ifs=$IFS
  IFS=' '
  # shellcheck disable=SC2086
  set -- ${3:-${TS_PALETTE}}
  IFS=${ts_free__ifs}

  # Start at the preferred colour so the hash still decides where to look.
  ts_free__start=1
  ts_free__k=1
  for ts_free__c in "$@"; do
    if [ "${ts_free__c}" = "${ts_free__want}" ]; then
      ts_free__start=${ts_free__k}
      break
    fi
    ts_free__k=$((ts_free__k + 1))
  done

  ts_free__n=$#
  ts_free__k=0
  while [ "${ts_free__k}" -lt "${ts_free__n}" ]; do
    ts_free__i=$(((ts_free__start - 1 + ts_free__k) % ts_free__n + 1))
    eval "ts_free__c=\${${ts_free__i}}"
    case " ${ts_free__used} " in
    *" ${ts_free__c} "*) ;;
    *)
      printf '%s' "${ts_free__c}"
      return 0
      ;;
    esac
    ts_free__k=$((ts_free__k + 1))
  done
  printf '%s' "${ts_free__want}"
}

# Render a pill with the index in a rounded badge near the left edge.
#
#   ts_pill_badge <index> <label> <pill> <text-fg> <badge> <badge-fg> <pad>
#
#   (  (1) main )   -- badge caps nested inside the pill caps, `pad` spaces in
#
# Two things a terminal cannot do, so that nobody tries again:
#
#   * The badge is not a circle and cannot be. It is three cells wide (cap,
#     digit, cap) and one cell tall, and a cell is roughly twice as tall as it
#     is wide, so the shape is a stadium about 1.5 times wider than high. A
#     circle would need a badge half a cell wide.
#   * There is no padding above or below it. The status bar is one character
#     cell tall and the half circles are drawn to fill that cell's full height.
#     "2-3px" is not expressible; there is no sub-cell geometry to spend.
#
# The single-glyph escape from both -- a circled-digit character -- does not
# exist in this font. Its cmap has 6860 codepoints and not one enclosed digit:
# no U+2776.., no U+2460.., no U+278A.., and no Material Design
# numeric-N-circle. Only bare circles with nothing in them.
#
# What is adjustable is the horizontal gap, which is whole cells. `pad` spaces
# sit between the pill's cap and the badge so it is not flush to the edge.
ts_pill_badge() {
  ts_badge__pad=''
  ts_badge__i=0
  while [ "${ts_badge__i}" -lt "${7:-1}" ]; do
    ts_badge__pad="${ts_badge__pad} "
    ts_badge__i=$((ts_badge__i + 1))
  done
  printf '#[fg=%s,bg=default]%s#[fg=%s,bg=%s]%s#[fg=%s,bg=%s]%s#[fg=%s,bg=%s,bold]%s#[fg=%s,bg=%s,nobold]%s#[fg=%s,bg=%s,bold] %s #[fg=%s,bg=default,nobold]%s#[default]' \
    "$3" "${TS_CAP_LEFT}" \
    "$4" "$3" "${ts_badge__pad}" \
    "$5" "$3" "${TS_CAP_LEFT}" \
    "$6" "$5" "$1" \
    "$5" "$3" "${TS_CAP_RIGHT}" \
    "$4" "$3" "$2" \
    "$3" "${TS_CAP_RIGHT}"
}

# The index as a single circled-digit glyph.
#
#   ts_badge_glyph <1..9> [set]
#
# This is the only way to get what a nested cap pair cannot: a real circle with
# margin on every side, including above and below. The margin is drawn into the
# glyph itself, so it needs no sub-cell geometry the terminal has not got.
#
# JetBrainsMono Nerd Font carries none of these -- 6860 codepoints, not one
# enclosed digit -- but other fonts on the machine do and the terminal falls
# back per glyph. Which font it lands on decides how the circle looks, and the
# sets differ sharply because they resolve to different families:
#
#   dingbat  U+2776..  filled, 45 fonts, falls back to Hiragino Sans -- a CJK
#                      family, so the circle is drawn small and tight in the cell
#   sans     U+278A..  filled, 31 fonts, falls back to Arial Unicode MS -- a
#                      Latin family, so the circle fills more of the cell
#   outline  U+2460..  hollow, 56 fonts, digit in the circle colour rather than
#                      knocked out
#
# `sans` is the bigger circle; `dingbat` the tighter one. Neither can be scaled,
# since a terminal has one font size per cell.
#
# Filled sets are knockouts: the circle takes the foreground colour and the
# digit shows whatever is behind it, so the digit comes out in the pill's own
# colour. A white circle therefore gives a pale digit in a pastel; a dark circle
# gives the digit in the pill's bright colour, which is far more legible.
#
# Written as octal so the codepoints cannot be mangled in transit, the same way
# the caps were lost once already.
ts_badge_glyph() {
  case "${2:-dingbat}" in
  sans)
    case "$1" in
    1) printf '\342\236\212' ;;
    2) printf '\342\236\213' ;;
    3) printf '\342\236\214' ;;
    4) printf '\342\236\215' ;;
    5) printf '\342\236\216' ;;
    6) printf '\342\236\217' ;;
    7) printf '\342\236\220' ;;
    8) printf '\342\236\221' ;;
    9) printf '\342\236\222' ;;
    *) return 1 ;;
    esac
    ;;
  outline)
    case "$1" in
    1) printf '\342\221\240' ;;
    2) printf '\342\221\241' ;;
    3) printf '\342\221\242' ;;
    4) printf '\342\221\243' ;;
    5) printf '\342\221\244' ;;
    6) printf '\342\221\245' ;;
    7) printf '\342\221\246' ;;
    8) printf '\342\221\247' ;;
    9) printf '\342\221\250' ;;
    *) return 1 ;;
    esac
    ;;
  *)
    case "$1" in
    1) printf '\342\235\266' ;;
    2) printf '\342\235\267' ;;
    3) printf '\342\235\270' ;;
    4) printf '\342\235\271' ;;
    5) printf '\342\235\272' ;;
    6) printf '\342\235\273' ;;
    7) printf '\342\235\274' ;;
    8) printf '\342\235\275' ;;
    9) printf '\342\235\276' ;;
    *) return 1 ;;
    esac
    ;;
  esac
}

# Pill with a real circled-digit glyph as the badge.
#
#   ts_pill_glyph <index> <label> <pill> <text-fg> <circle> [set]
ts_pill_glyph() {
  ts_glyph__g=$(ts_badge_glyph "$1" "${6:-dingbat}") || return 1
  printf '#[fg=%s,bg=default]%s#[fg=%s,bg=%s,bold]%s#[fg=%s,bg=%s,bold] %s #[fg=%s,bg=default,nobold]%s#[default]' \
    "$3" "${TS_CAP_LEFT}" \
    "$5" "$3" "${ts_glyph__g}" \
    "$4" "$3" "$2" \
    "$3" "${TS_CAP_RIGHT}"
}

# A badge colour that is never the pill's own, or the badge vanishes into it.
# Falls back to the pill's text colour, which is chosen to contrast with it.
ts_badge_color() {
  if [ "$1" = "$2" ]; then
    printf '%s' "$3"
  else
    printf '%s' "$1"
  fi
}

# Render one pill.  ts_pill <text> <colour> <text-fg>
#
# The caps use bg=default so they inherit whatever status-bg actually is. A
# hardcoded outer background draws a visible halo, and lualine's bar_bg
# (#01111d) is not this tmux's status-bg (#011627) -- close enough to look like
# a rendering bug rather than a mismatch.
ts_pill() {
  printf '#[fg=%s,bg=default]%s#[fg=%s,bg=%s,bold] %s #[fg=%s,bg=default,nobold]%s#[default]' \
    "$2" "${TS_CAP_LEFT}" "$3" "$2" "$1" "$2" "${TS_CAP_RIGHT}"
}

# Render one entry as coloured text with no filled background.
#
#   ts_flat <index-glyph> <label> <colour>
#
# The lightest treatment available, for when the bar is reference rather than a
# thing being acted on. A filled pill is the heaviest, and stacking two rows of
# them -- lualine above, this below -- gives both the same weight and lets
# neither win. Colour still carries the session identity and the circled digit
# still carries the number; only the background goes.
#
# The digit glyph is a knockout, so against no fill the circle takes the
# session's colour and the digit shows the bar through it. That is the same
# shape as the pill version, just inverted.
ts_flat() {
  printf '#[fg=%s,bold]%s#[fg=%s,nobold] %s#[default]' "$3" "$1" "$3" "$2"
}

# Visible width of a rendered segment: what it costs on screen once tmux has
# consumed the #[...] directives.
#
# This is the number that matters for fitting. A pill is ~1400 bytes of escape
# for ~20 cells of screen, so byte length is off by two orders of magnitude.
ts_visible_width() {
  printf '%s' "$1" | sed 's/#\[[^]]*\]//g' | wc -m | tr -d ' '
}

# Read a tmux user option, with a default.
#
#   ts_opt sessions_max 9
ts_opt() {
  ts_opt__name=$1
  ts_opt__default=$2
  eval "ts_opt__v=\${TS_OPT_${ts_opt__name}-}"
  if [ -n "${ts_opt__v}" ]; then
    printf '%s' "${ts_opt__v}"
    return 0
  fi
  # TS_NO_TMUX_OPTS makes the lookup hermetic. Without it the suite reads the
  # developer's own live tmux options, so a `@sessions_name_width` set on their
  # real server silently changed spec results.
  if [ -z "${TS_NO_TMUX_OPTS-}" ] && command -v tmux >/dev/null 2>&1; then
    ts_opt__v=$(tmux show-option -gqv "@${ts_opt__name}" 2>/dev/null || true)
    if [ -n "${ts_opt__v}" ]; then
      printf '%s' "${ts_opt__v}"
      return 0
    fi
  fi
  printf '%s' "${ts_opt__default}"
}

# Every session as "id<TAB>created<TAB>name", in creation order.
#
# Sorted explicitly rather than trusting tmux's output order. The tiebreak is
# the numeric part of the session id: session_created has second resolution, so
# two sessions born in the same second tie, and an unstable order there would
# silently swap two keybindings between one render and the next. Sorting on
# `1.2` skips the leading '$' so the compare is numeric, putting $9 before $10.
ts_sessions() {
  if [ -n "${TMUX_SESSIONS_FIXTURE-}" ]; then
    cat "${TMUX_SESSIONS_FIXTURE}"
  else
    tmux list-sessions -F "#{session_id}${TAB}#{session_created}${TAB}#{session_name}" 2>/dev/null || true
  fi | sort -t"${TAB}" -k2,2n -k1.2,1n
}

# Neutralise tmux format syntax in text we did not write.
#
# tmux re-parses status content for '#[...]' directives -- that is how this
# plugin's own colours work -- so a session name reaches that parser verbatim.
# Verified on 3.7c: a session named '#[fg=red]styled' recolours the status bar
# unescaped, and renders as literal text once '#' becomes '##'. Escaping every
# '#' covers '#[', '#(' and '#{' at once, rather than reasoning about which of
# them tmux will act on.
ts_escape() {
  printf '%s' "$1" | sed 's/#/##/g'
}

# True when the argument is a well-formed session id.
#
# Checked at the boundary rather than trusted from the list, because this is the
# value that becomes a tmux command argument.
ts_is_id() {
  case "${1-}" in
  '$'[0-9]*)
    case "${1#$}" in
    *[!0-9]*) return 1 ;;
    *) return 0 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

# True when the argument is a positive integer.
ts_is_index() {
  case "${1-}" in
  '' | *[!0-9]*) return 1 ;;
  0) return 1 ;;
  *) return 0 ;;
  esac
}

# Compose the status-right value: append our segment unless it is already there.
#
#   ts_merge_status "<current>" "<segment>" "<marker>"
#
# Pure, so the entry point's one interesting decision is testable without a tmux
# server. The marker is the list.sh path, which is what makes a re-source
# idempotent: sourcing tmux.conf twice must not stack two copies of the segment
# onto the user's own status-right.
ts_merge_status() {
  ts_merge__current=$1
  ts_merge__segment=$2
  ts_merge__marker=$3
  case "${ts_merge__current}" in
  *"${ts_merge__marker}"*)
    printf '%s' "${ts_merge__current}"
    return 0
    ;;
  esac
  if [ -z "${ts_merge__current}" ]; then
    printf '%s' "${ts_merge__segment}"
  else
    printf '%s %s' "${ts_merge__current}" "${ts_merge__segment}"
  fi
}

# The status-right-length to set, or nothing when the current value already
# suffices. Never lowers a larger value the user chose deliberately.
ts_grow_length() {
  ts_grow__have=$1
  ts_grow__want=$2
  case "${ts_grow__have}" in
  '' | *[!0-9]*) ts_grow__have=0 ;;
  esac
  if [ "${ts_grow__have}" -lt "${ts_grow__want}" ]; then
    printf '%s' "${ts_grow__want}"
  fi
}

# Truncate to N characters, appending an ellipsis. N of 0 means no limit.
#
# `cut -c` counts characters, so a multibyte name is never cut mid-codepoint;
# awk's substr on this platform is byte-based and would. Note this counts
# characters, not display cells, so a CJK name still renders up to twice as
# wide as the number suggests.
ts_truncate() {
  ts_truncate__s=$1
  ts_truncate__n=$2
  if [ "${ts_truncate__n}" -le 0 ]; then
    printf '%s' "${ts_truncate__s}"
    return 0
  fi
  if [ "$(printf '%s' "${ts_truncate__s}" | wc -m | tr -d ' ')" -le "${ts_truncate__n}" ]; then
    printf '%s' "${ts_truncate__s}"
    return 0
  fi
  # A width of 1 leaves no room for anything but the ellipsis, and `cut -c1-0`
  # is an error rather than an empty result.
  if [ "${ts_truncate__n}" -eq 1 ]; then
    printf '…'
    return 0
  fi
  printf '%s…' "$(printf '%s' "${ts_truncate__s}" | cut -c"1-$((ts_truncate__n - 1))")"
}
