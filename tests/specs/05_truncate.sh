# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# Name truncation. Multibyte safety is the whole reason this is not `awk substr`
# or a byte slice: on this platform awk's substr counts bytes and would cut a
# name mid-codepoint.

# shellcheck disable=SC1091
. "${ROOT}/scripts/lib.sh"

LIST="${ROOT}/scripts/list.sh"

# These specs describe the flat rendering, which `pill` is now the default over.
# Pinning both keeps them a regression test for the plain style rather than
# silently retargeting them at pills.
TS_OPT_sessions_style=plain
TS_OPT_sessions_current_position=inline
export TS_OPT_sessions_style TS_OPT_sessions_current_position

it "a width of 1 yields just the ellipsis, not a cut error"
eq '…' "$(ts_truncate 'anything' 1 2>&1)"

it "a width of 0 means no limit"
eq 'a-very-long-session-name' "$(ts_truncate 'a-very-long-session-name' 0)"

it "a name that already fits is untouched"
eq 'main' "$(ts_truncate 'main' 12)"

it "a name exactly at the limit is untouched"
eq 'exactlyten' "$(ts_truncate 'exactlyten' 10)"

it "a longer name is cut and given an ellipsis"
eq 'a-very-lo…' "$(ts_truncate 'a-very-long-name' 10)"

it "the result is never longer than the limit"
eq '10' "$(ts_truncate 'a-very-long-name' 10 | wc -m | tr -d ' ')"

it "a multibyte name is cut on a character, never mid-codepoint"
# 8 characters out: 7 kept plus the ellipsis. A byte slice would emit a partial
# UTF-8 sequence here and render as a replacement character.
eq 'héllo-w…' "$(ts_truncate 'héllo-wörld-ünicode' 8)"

it "the multibyte result is still valid utf-8"
eq '8' "$(ts_truncate 'héllo-wörld-ünicode' 8 | wc -m | tr -d ' ')"

it "truncation applies through the renderer"
TS_OPT_sessions_format='%d %s' TS_OPT_sessions_separator=' '
export TS_OPT_sessions_format TS_OPT_sessions_separator
fixture "$(
  line '$1' 1000 'effective-tutorial'
)"
eq '1 effective…' "$(TS_OPT_sessions_name_width=10 "${LIST}")"

it "a hostile name is truncated first, then escaped"
# Order matters. Escaping first would turn '#' into '##' and then let the cut
# land between them, leaving a live '#' for tmux to act on. Truncating first
# means every '#' that survives is escaped as a pair.
#
# '#[fg=red]evil-and-long' capped at 6 chars is '#[fg=' + the ellipsis, which
# escapes to '##[fg=…' -- tmux prints that as the literal text '#[fg=…'.
fixture "$(
  line '$1' 1000 '#[fg=red]evil-and-long'
)"
eq '1 ##[fg=…' "$(TS_OPT_sessions_name_width=6 "${LIST}")"

it "every # in the rendered name is escaped as a pair"
fixture "$(
  line '$1' 1000 '#a#b#c#d#e#f#g'
)"
# Capped at 4: three characters kept, '#a#', plus the ellipsis. The trailing
# '#' is the one that would be dangerous if the escape ran before the cut; here
# it comes out as a pair like every other.
eq '1 ##a##…' "$(TS_OPT_sessions_name_width=4 "${LIST}")"

it "no odd # survives into the segment, whatever the cut lands on"
# The invariant, checked rather than hand-counted: strip every escaped pair and
# nothing should remain that tmux would act on.
for w in 1 2 3 4 5 6 7 8; do
  rendered=$(TS_OPT_sessions_name_width=$w "${LIST}")
  if printf '%s' "$rendered" | sed 's/##//g' | grep -q '#'; then
    fail "width $w left an unescaped # in: [$rendered]"
    break
  fi
  [ "$w" -eq 8 ] && pass
done
