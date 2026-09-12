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

# Render a pill with the index in a rounded badge against the left edge.
#
#   ts_pill_badge <index> <label> <pill> <text-fg> <badge> <badge-fg>
#
#   ( ⬤3  solo-effect )   -- badge caps nested inside the pill caps
#
# Built from the same half circles as the pill itself, one layer in, so the
# badge picks up the pill's radius instead of approximating it. The obvious
# alternative -- a circled-number glyph such as ❶ (U+2776) or ① (U+2460) -- was
# ruled out by checking the font: JetBrainsMono Nerd Font carries none of
# U+2776.., U+2460.. or U+278A.., so they would all render as tofu. U+E0B6 and
# U+E0B4 are present.
#
# A terminal cell is one fixed size, so the digit cannot be set smaller. The
# badge is what makes it read as smaller.
ts_pill_badge() {
  printf '#[fg=%s,bg=default]%s#[fg=%s,bg=%s]%s#[fg=%s,bg=%s,bold]%s#[fg=%s,bg=%s,nobold]%s#[fg=%s,bg=%s,bold] %s #[fg=%s,bg=default,nobold]%s#[default]' \
    "$3" "${TS_CAP_LEFT}" \
    "$5" "$3" "${TS_CAP_LEFT}" \
    "$6" "$5" "$1" \
    "$5" "$3" "${TS_CAP_RIGHT}" \
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
  if command -v tmux >/dev/null 2>&1; then
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
