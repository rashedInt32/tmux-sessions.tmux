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
contains "$("${LIST}" '$32' --current)" "$(ts_opt sessions_current_color '#90b99f')"

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
