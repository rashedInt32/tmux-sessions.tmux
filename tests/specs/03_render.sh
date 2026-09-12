# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# The status segment: numbering, the current-session highlight, and overflow.

LIST="${ROOT}/scripts/list.sh"

# Plain text rendering, so assertions read as what you see on the bar.
TS_OPT_sessions_format='%d %s'
TS_OPT_sessions_current_format='>%d %s'
TS_OPT_sessions_more_format='+%d'
TS_OPT_sessions_separator=' '
export TS_OPT_sessions_format TS_OPT_sessions_current_format
export TS_OPT_sessions_more_format TS_OPT_sessions_separator

fixture "$(
  line '$0' 1000 main
  line '$30' 2000 tut
  line '$32' 3000 solo
  line '$33' 4000 pkgs
)"

it "numbers every session in creation order"
eq "1 main 2 tut 3 solo 4 pkgs" "$("${LIST}")"

it "marks the client's current session, and only that one"
eq "1 main 2 tut >3 solo 4 pkgs" "$("${LIST}" '$32')"

it "a session id that matches nothing highlights nothing"
eq "1 main 2 tut 3 solo 4 pkgs" "$("${LIST}" '$999')"

it "honours a custom separator"
eq "1 main | 2 tut | 3 solo | 4 pkgs" "$(TS_OPT_sessions_separator=' | ' "${LIST}")"

it "collapses the tail past sessions_max into +N"
eq "1 main 2 tut +2" "$(TS_OPT_sessions_max=2 "${LIST}")"

it "shows no +N when everything fits"
not_contains "$(TS_OPT_sessions_max=4 "${LIST}")" "+"

it "an empty session list renders as nothing, not as a stray separator"
fixture ""
eq "" "$("${LIST}")"

it "a row with an unusable id is dropped and does not inflate the overflow"
fixture "$(
  line '$1' 1000 good
  line 'by-name' 2000 bad
  line '$2' 3000 alsogood
)"
eq "1 good 2 alsogood" "$("${LIST}")"

it "a name containing spaces renders whole"
fixture "$(
  line '$1' 1000 'my project'
)"
eq "1 my project" "$("${LIST}")"

it "a name that looks like a printf specifier is data, not format"
fixture "$(
  line '$1' 1000 '%s%d%%'
)"
eq "1 %s%d%%" "$("${LIST}")"
