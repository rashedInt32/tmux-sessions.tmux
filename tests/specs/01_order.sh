# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# Creation-order numbering. The property the whole plugin rests on is that
# creating a session never renumbers the ones you already know.

# Names in creation order, space separated.
order() {
  ts_sessions 2>/dev/null | cut -f3 | tr '\n' ' ' | sed 's/ $//'
}

# shellcheck disable=SC1091
. "${ROOT}/scripts/lib.sh"

it "orders by creation time, not by name or by tmux's output order"
fixture "$(
  line '$30' 1789181871 tut
  line '$0' 1788718199 main
  line '$33' 1789185097 pkgs
  line '$32' 1789185033 solo
)"
eq "main tut solo pkgs" "$(order)"

it "a new session appends and leaves the existing numbers untouched"
# 'api' sorts first alphabetically; creation order must still put it last.
fixture "$(
  line '$0' 1000 main
  line '$1' 2000 tut
  line '$2' 3000 solo
  line '$3' 4000 api
)"
eq "main tut solo api" "$(order)"

it "killing a session renumbers only what was below it"
fixture "$(
  line '$0' 1000 main
  line '$2' 3000 solo
)"
eq "main solo" "$(order)"

it "sessions born in the same second break the tie on id, not at random"
# session_created has second resolution, so ties are real. An unstable sort
# would swap two keybindings between one render and the next.
fixture "$(
  line '$7' 1000 seventh
  line '$5' 1000 fifth
  line '$6' 1000 sixth
)"
eq "fifth sixth seventh" "$(order)"

it "the same set in a different input order gives the same answer"
fixture "$(
  line '$6' 1000 sixth
  line '$7' 1000 seventh
  line '$5' 1000 fifth
)"
eq "fifth sixth seventh" "$(order)"

it "the id tiebreak is numeric, so \$9 comes before \$10"
fixture "$(
  line '$10' 1000 ten
  line '$9' 1000 nine
)"
eq "nine ten" "$(order)"

it "a name containing spaces survives as one field"
fixture "$(
  line '$1' 1000 'my project'
)"
eq "my project" "$(ts_sessions | cut -f3)"

it "an empty session list is not an error"
fixture ""
eq "" "$(order)"
