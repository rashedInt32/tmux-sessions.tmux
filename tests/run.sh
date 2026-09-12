#!/bin/sh
# Test runner.  Usage:  tests/run.sh [name-filter]
#
# No test starts a tmux server. Session data comes from a fixture file and tmux
# options from TS_OPT_* variables, which are the same seams the scripts use in
# production when those are unset.
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export ROOT

# Never read the developer's live tmux options. Only the hook specs talk to a
# real server, and they scope everything to a throwaway session.
TS_NO_TMUX_OPTS=1
export TS_NO_TMUX_OPTS
FILTER=${1-}

PASSED=0
FAILED=0
FAILURES=''
CURRENT=''

# ---------------------------------------------------------------- assertions

it() {
  CURRENT="$1"
}

fail() {
  FAILED=$((FAILED + 1))
  FAILURES="${FAILURES}
  ${CURRENT}
    $1"
  printf '  FAIL %s\n' "${CURRENT}"
}

pass() {
  PASSED=$((PASSED + 1))
  printf '  ok   %s\n' "${CURRENT}"
}

# eq <expected> <actual> [label]
eq() {
  if [ "$1" = "$2" ]; then
    pass
  else
    fail "$(printf '%s\n      expected: [%s]\n      actual:   [%s]' "${3-values differ}" "$1" "$2")"
  fi
}

# contains <haystack> <needle>
contains() {
  case "$1" in
  *"$2"*) pass ;;
  *) fail "$(printf 'missing substring\n      looking for: [%s]\n      in:          [%s]' "$2" "$1")" ;;
  esac
}

# not_contains <haystack> <needle>
not_contains() {
  case "$1" in
  *"$2"*) fail "$(printf 'unexpected substring\n      found: [%s]\n      in:    [%s]' "$2" "$1")" ;;
  *) pass ;;
  esac
}

# status <expected-exit> <command...>
status() {
  want=$1
  shift
  "$@" >/dev/null 2>&1
  got=$?
  eq "${want}" "${got}" "exit status of: $*"
}

# Install the session fixture.  fixture "$(line ...; line ...)"
#
# Takes the content as an argument rather than on stdin: a `... | fixture`
# pipeline runs the function in a subshell, so the exported variable would never
# reach the spec that needs it.
fixture() {
  [ -n "${FIX-}" ] || FIX=$(mktemp)
  if [ -n "$1" ]; then
    printf '%s\n' "$1" >"${FIX}"
  else
    : >"${FIX}"
  fi
  TMUX_SESSIONS_FIXTURE="${FIX}"
  export TMUX_SESSIONS_FIXTURE
}

# A tab-separated fixture line.
line() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

# --------------------------------------------------------------------- runner

for spec in "${ROOT}"/tests/specs/*.sh; do
  [ -f "${spec}" ] || continue
  name=$(basename "${spec}" .sh)
  if [ -n "${FILTER}" ]; then
    case "${name}" in
    *"${FILTER}"*) ;;
    *) continue ;;
    esac
  fi
  # Each spec runs in this shell so assertions can bump the counters, which
  # means one spec's exported options would otherwise leak into the next. Clear
  # every seam between files: a spec that passes alone and fails in the suite is
  # worse than no spec.
  unset TMUX_SESSIONS_FIXTURE 2>/dev/null || true
  for v in $(env | sed -n 's/^\(TS_OPT_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "${v}" 2>/dev/null || true
  done
  # shellcheck disable=SC1090
  . "${spec}"
done

printf '\n%d passed, %d failed\n' "${PASSED}" "${FAILED}"
if [ -n "${FAILURES}" ]; then
  printf '%s\n' "${FAILURES}"
fi
[ "${FAILED}" -eq 0 ]
