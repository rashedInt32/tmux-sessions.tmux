# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# Pill rendering: rounded caps, a stable colour per session, and the current
# session split out to status-left.

. "${ROOT}/scripts/lib.sh"
LIST="${ROOT}/scripts/list.sh"

# The caps, rebuilt here from their codepoints rather than pasted, so this file
# cannot be the thing that loses them.
CAP_L=$(printf '\356\202\266')
CAP_R=$(printf '\356\202\264')

count_of() { printf '%s' "$2" | awk -v s="$1" '{n=0; i=1; while ((p=index(substr($0,i),s))>0) {n++; i+=p} print n}'; }

fixture "$(
  line '$0' 1000 main
  line '$30' 2000 api
  line '$32' 3000 dotfiles
  line '$33' 4000 notes
)"

# ------------------------------------------------------------------ the caps

it "the caps are not empty, which is how they failed before"
eq "3" "$(printf '%s' "${CAP_L}" | wc -c | tr -d ' ')"
eq "3" "$(printf '%s' "${CAP_R}" | wc -c | tr -d ' ')"

it "lib exports the same caps the spec builds independently"
eq "${CAP_L}" "${TS_CAP_LEFT}"
eq "${CAP_R}" "${TS_CAP_RIGHT}"

it "every pill gets a left cap and a right cap"
# Four sessions, current is inline, so four pills.
out=$(TS_OPT_sessions_current_position=inline "${LIST}" '$30')
eq "4" "$(count_of "${CAP_L}" "${out}")"
eq "4" "$(count_of "${CAP_R}" "${out}")"

it "a pill has the exact escape shape, caps on the outside of the colour"
out=$(TS_OPT_sessions_colors='#abcdef' TS_OPT_sessions_current_position=inline \
  TS_OPT_sessions_max=1 TS_OPT_sessions_pill_fg='#111111' "${LIST}" '$99')
eq "#[fg=#abcdef,bg=default]${CAP_L}#[fg=#111111,bg=#abcdef,bold] 1 main #[fg=#abcdef,bg=default,nobold]${CAP_R}#[default]#[fg=#6c6874,bg=default]${CAP_L}#[fg=#111111,bg=#6c6874,bold] +3 #[fg=#6c6874,bg=default,nobold]${CAP_R}#[default]" \
  "$(printf '%s' "$out" | sed "s/  //g")"

# ---------------------------------------------------------------- the colours

it "a name always hashes to the same colour"
a=$(ts_color_for "packages" "${TS_PALETTE}")
b=$(ts_color_for "packages" "${TS_PALETTE}")
eq "$a" "$b"

it "the colour comes from the configured palette, not from nowhere"
c=$(ts_color_for "packages" '#111111 #222222')
case "$c" in '#111111' | '#222222') pass ;; *) fail "got [$c]" ;; esac

it "different names spread across the palette rather than collapsing to one"
seen=$(for n in main api dotfiles notes solo-effect fiberWatch packages tutorial; do
  ts_color_for "$n" "${TS_PALETTE}"
  echo
done | sort -u | wc -l | tr -d ' ')
# 8 names into 8 colours will collide by birthday; 4+ distinct means it spreads.
if [ "$seen" -ge 4 ]; then pass; else fail "only $seen distinct colours from 8 names"; fi

it "a single-colour palette is honoured rather than divided by zero"
eq '#abcdef' "$(ts_color_for "anything" '#abcdef')"

it "a session keeps its colour when another session is created"
before=$(TS_OPT_sessions_current_position=inline "${LIST}" '$99')
fixture "$(
  line '$0' 1000 main
  line '$30' 2000 api
  line '$32' 3000 dotfiles
  line '$33' 4000 notes
  line '$40' 5000 brandnew
)"
after=$(TS_OPT_sessions_current_position=inline "${LIST}" '$99')
# 'main' is pill 1 in both; its colour must not have moved.
eq "$(printf '%s' "$before" | cut -c1-24)" "$(printf '%s' "$after" | cut -c1-24)"

it "a session keeps its colour when an earlier session is killed"
fixture "$(
  line '$30' 2000 api
  line '$32' 3000 dotfiles
)"
killed=$(TS_OPT_sessions_current_position=inline "${LIST}" '$99')
# 'api' is now pill 1, but its colour is hashed from the name, not the index.
contains "$killed" "$(ts_color_for api "${TS_PALETTE}")"

# ------------------------------------------------- current session on the left

fixture "$(
  line '$0' 1000 main
  line '$30' 2000 api
  line '$32' 3000 dotfiles
  line '$33' 4000 notes
)"

it "the current session is left out of the list when it lives on the left"
out=$("${LIST}" '$32')
not_contains "$out" "3 dotfiles"

it "the others keep their global numbers, gap included"
out=$("${LIST}" '$32')
contains "$out" "1 main"
contains "$out" "2 api"
contains "$out" "4 notes"

it "--current renders exactly one pill"
out=$("${LIST}" '$32' --current)
eq "1" "$(count_of "${CAP_L}" "${out}")"
contains "$out" "3 dotfiles"

it "--current uses the fixed current colour, not the hash"
contains "$("${LIST}" '$32' --current)" '#ffffff'

it "--current carries no overflow marker, which belongs to the list"
not_contains "$(TS_OPT_sessions_max=1 "${LIST}" '$0' --current)" "+"

it "--current is empty when the client is in no known session"
eq "" "$("${LIST}" '$999' --current)"

it "current_position = inline keeps it in the list and off the left"
contains "$(TS_OPT_sessions_current_position=inline "${LIST}" '$32')" "3 dotfiles"

# -------------------------------------------------------------- overflow, misc

it "the overflow marker is a pill too, not bare text"
out=$(TS_OPT_sessions_max=2 TS_OPT_sessions_current_position=inline "${LIST}" '$99')
contains "$out" "${CAP_L}"
contains "$out" " +2 "

it "a hostile name is still escaped inside a pill"
fixture "$(
  line '$1' 1000 '#[fg=red]evil'
)"
out=$(TS_OPT_sessions_current_position=inline "${LIST}" '$99')
contains "$out" '1 ##[fg=red]evil'

it "plain style emits no caps at all"
out=$(TS_OPT_sessions_style=plain TS_OPT_sessions_current_position=inline "${LIST}" '$99')
eq "0" "$(count_of "${CAP_L}" "${out}")"

# ------------------------------------- what tmux actually passes us at runtime

fixture "$(
  line '$0' 1000 main
  line '$3' 2000 packages
  line '$9' 3000 notes
)"

it "the current session is recognised when given a NAME"
# Regression: tmux's #{client_session} resolves to the session name, not the id.
# Verified on 3.7c: a client in `packages` reports client_session=packages while
# session_id is $3. Every earlier spec handed in an id, so the production path
# was never exercised and the highlight silently never fired.
not_contains "$("${LIST}" 'packages')" "2 packages"

it "--current by name renders that session's pill"
contains "$("${LIST}" 'packages' --current)" "2 packages"

it "the current session is still recognised when given an id"
not_contains "$("${LIST}" '$3')" "2 packages"

it "a name matching nothing leaves every session in the list"
contains "$("${LIST}" 'nosuchsession')" "2 packages"

it "an empty current marks nothing as current"
eq "" "$("${LIST}" '' --current)"

# ------------------------------------------------- fitting the client's width

fixture "$(
  line '$1' 1000 alpha-session
  line '$2' 2000 beta-session
  line '$3' 3000 gamma-session
  line '$4' 4000 delta-session
  line '$5' 5000 epsilon-session
)"

vis() { printf '%s' "$1" | sed 's/#\[[^]]*\]//g' | wc -m | tr -d ' '; }

it "with no width given, nothing is dropped"
eq "5" "$(count_of "${CAP_L}" "$(TS_OPT_sessions_current_position=inline "${LIST}" '$9')")"

it "a narrow client drops the tail instead of overflowing"
out=$(TS_OPT_sessions_current_position=inline TS_OPT_sessions_reserve=10 "${LIST}" '$9' list 60)
n=$(count_of "${CAP_L}" "$out")
if [ "$n" -lt 5 ] && [ "$n" -ge 1 ]; then pass; else fail "expected some dropped, got $n pills"; fi

it "what survives actually fits the budget"
out=$(TS_OPT_sessions_current_position=inline TS_OPT_sessions_reserve=10 "${LIST}" '$9' list 60)
w=$(vis "$out")
if [ "$w" -le 50 ]; then pass; else fail "rendered $w cells into a 50 budget"; fi

it "dropping for width still reports the count as +N"
out=$(TS_OPT_sessions_current_position=inline TS_OPT_sessions_reserve=10 "${LIST}" '$9' list 60)
contains "$out" "+"

it "the bar never renders empty just because it is tight"
# The failure this guards: tmux drops the whole of status-right when it will not
# fit beside status-left and the window list, so the list vanished with no hint.
out=$(TS_OPT_sessions_current_position=inline TS_OPT_sessions_reserve=10 "${LIST}" '$9' list 20)
if [ -n "$out" ]; then pass; else fail "rendered nothing at all"; fi

it "a wide client keeps every session"
eq "5" "$(count_of "${CAP_L}" "$(TS_OPT_sessions_current_position=inline "${LIST}" '$9' list 400)")"

it "a non-numeric width is ignored rather than breaking arithmetic"
eq "5" "$(count_of "${CAP_L}" "$(TS_OPT_sessions_current_position=inline "${LIST}" '$9' list bogus)")"

it "--current is never trimmed for width"
contains "$("${LIST}" 'alpha-session' current 20)" "1 alpha-session"

# ------------------------------------------------------------- the palette

it "the palette is not the editor's oldworld colours"
# Sharing a palette with lualine made the bar and the editor hard to tell apart.
not_contains "${TS_PALETTE}" '#92a2d5'
not_contains "${TS_PALETTE}" '#90b99f'

it "the palette has ten entries, to cut collisions at five or six sessions"
eq "10" "$(printf '%s' "${TS_PALETTE}" | wc -w | tr -d ' ')"

it "colour follows the name, not the truncated label"
# Otherwise changing name_width would reshuffle every colour on the bar.
a=$(TS_OPT_sessions_current_position=inline TS_OPT_sessions_name_width=30 "${LIST}" '$9')
b=$(TS_OPT_sessions_current_position=inline TS_OPT_sessions_name_width=6 "${LIST}" '$9')
ca=$(printf '%s' "$a" | sed -n 's/^#\[fg=\([^,]*\).*/\1/p')
cb=$(printf '%s' "$b" | sed -n 's/^#\[fg=\([^,]*\).*/\1/p')
eq "$ca" "$cb"

it "the palette still splits when the caller is inside an IFS=newline loop"
# Regression: the renderer loops with IFS set to newline, and `set -- $palette`
# under that IFS treats the whole palette as a single word. Every session then
# hashed to entry 1 and the entire bar came out one colour.
fixture "$(
  line '$1' 1000 alpha
  line '$2' 2000 bravo
  line '$3' 3000 charlie
  line '$4' 4000 delta
  line '$5' 5000 echo-sess
)"
out=$(TS_OPT_sessions_current_position=inline "${LIST}" '$9')
distinct=$(printf '%s' "$out" | grep -o 'bg=#[0-9a-f]\{6\},bold' | sort -u | wc -l | tr -d ' ')
if [ "$distinct" -ge 3 ]; then pass; else fail "only $distinct distinct pill colours across 5 sessions"; fi

it "a shell with IFS=newline still gets a single colour back, not the palette"
old=$IFS
IFS='
'
c=$(ts_color_for "alpha" "${TS_PALETTE}")
IFS=$old
eq "1" "$(printf '%s' "$c" | wc -w | tr -d ' ')"

it "two sessions never share a colour while the palette has room"
fixture "$(
  line '$1' 1000 main
  line '$2' 2000 solo-effect
  line '$3' 3000 packages
  line '$4' 4000 fiberWatch
  line '$5' 5000 effect-v4
  line '$6' 6000 notes
)"
out=$(TS_OPT_sessions_current_position=inline "${LIST}" '$99')
total=$(printf '%s' "$out" | grep -o 'bg=#[0-9a-f]\{6\},bold' | wc -l | tr -d ' ')
uniq=$(printf '%s' "$out" | grep -o 'bg=#[0-9a-f]\{6\},bold' | sort -u | wc -l | tr -d ' ')
eq "$total" "$uniq" "all $total pills should have distinct colours"

it "more sessions than colours still renders, reusing rather than failing"
fixture "$(for i in 1 2 3 4 5 6 7 8 9 10 11 12; do line "\$$i" "$((1000 + i))" "sess$i"; done)"
out=$(TS_OPT_sessions_max=12 TS_OPT_sessions_current_position=inline "${LIST}" '$99')
eq "12" "$(count_of "${CAP_L}" "$out")"

it "unique_colors = off leaves the raw hash in place"
fixture "$(
  line '$1' 1000 main
  line '$2' 2000 solo-effect
)"
a=$(TS_OPT_sessions_unique_colors=off TS_OPT_sessions_current_position=inline "${LIST}" '$99')
# main and solo-effect both hash to the same slot, so with probing off they match.
total=$(printf '%s' "$a" | grep -o 'bg=#[0-9a-f]\{6\},bold' | sort -u | wc -l | tr -d ' ')
eq "1" "$total"
