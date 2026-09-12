# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# index -> session id. This is the value that becomes a tmux command argument,
# so the validation matters more than the lookup.

RESOLVE="${ROOT}/scripts/resolve.sh"

fixture "$(
  line '$0' 1000 main
  line '$30' 2000 tut
  line '$32' 3000 solo
  line '$33' 4000 pkgs
)"

it "resolves each index in creation order"
eq '$0' "$("${RESOLVE}" 1)"
it "resolves index 2"
eq '$30' "$("${RESOLVE}" 2)"
it "resolves the last index"
eq '$33' "$("${RESOLVE}" 4)"

it "an index past the end prints nothing and fails"
eq "" "$("${RESOLVE}" 9 2>/dev/null || true)"
it "an index past the end exits non-zero, so a keybinding is a silent no-op"
status 1 "${RESOLVE}" 9

it "index 0 is rejected"
status 1 "${RESOLVE}" 0
it "a negative index is rejected"
status 1 "${RESOLVE}" -1
it "a non-numeric index is rejected"
status 1 "${RESOLVE}" abc
it "a missing index is rejected"
status 1 "${RESOLVE}"

it "an index that tries to smuggle a command is rejected"
# sed -n "${n}p" would otherwise take anything; ts_is_index is the guard.
status 1 "${RESOLVE}" '1;p'
status 1 "${RESOLVE}" '$(id)'

it "a malformed id in the session data is refused rather than passed on"
fixture "$(
  line 'main' 1000 by-name
)"
status 1 "${RESOLVE}" 1

it "resolving against an empty list fails cleanly"
fixture ""
status 1 "${RESOLVE}" 1

it "a hostile session name does not affect which id comes back"
fixture "$(
  line '$4' 1000 '#[fg=red]evil;rm -rf /'
)"
eq '$4' "$("${RESOLVE}" 1)"
