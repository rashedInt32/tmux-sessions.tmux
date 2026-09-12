# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# What the entry point actually tells tmux to do.
#
# A recording stub named `tmux` goes on PATH, so this exercises the real entry
# point end to end without a server and without binding anything for real.

ENTRY="${ROOT}/tmux-sessions.tmux"

setup_stub() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/calls"
  : >"${STUB_LOG}"
  cat >"${STUB_DIR}/tmux" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "${STUB_LOG}"
# show-option is read back by the entry point; answer as a fresh tmux would.
case "\$*" in
  *"show-option -gqv status-right-length"*) echo 40 ;;
  *"show-option -gqv status-right"*) echo "" ;;
  *"show-option"*) echo "" ;;
esac
exit 0
STUB
  chmod +x "${STUB_DIR}/tmux"
  OLD_PATH=$PATH
  PATH="${STUB_DIR}:${PATH}"
  export PATH
}

teardown_stub() {
  PATH=$OLD_PATH
  export PATH
  rm -rf "${STUB_DIR}"
}

binds() {
  grep '^bind-key' "${STUB_LOG}" || true
}

# --------------------------------------------------- default: prefix table

setup_stub
TS_OPT_sessions_hooks=off
export TS_OPT_sessions_hooks
"${ENTRY}" >/dev/null 2>&1

it "binds into the prefix table by default, not the root table"
eq "bind-key 1 run-shell -b ${ROOT}/scripts/switch.sh 1" "$(binds | head -1)"

it "binds nine digits"
eq "9" "$(binds | grep -c 'switch.sh' | tr -d ' ')"

it "no -n anywhere, so nothing is bound outside the prefix"
eq "0" "$(binds | grep -c -- ' -n ' | tr -d ' ')"

it "the last-session key defaults to prefix 0"
contains "$(binds)" "bind-key 0 switch-client -l"

it "the ninth key resolves index 9, not a hardcoded session"
contains "$(binds)" "switch.sh 9"

it "raises status-right-length from the 40 default"
contains "$(cat "${STUB_LOG}")" "set-option -g status-right-length 300"

it "sets status-right to our segment with the client's session"
contains "$(cat "${STUB_LOG}")" 'set-option -g status-right #('

it "passes #{client_session}, which is what makes the highlight per-client"
contains "$(cat "${STUB_LOG}")" '#{client_session})'

it "repaints immediately rather than waiting out status-interval"
contains "$(cat "${STUB_LOG}")" "refresh-client -S"
teardown_stub

# ------------------------------------------------------ opt-in: root table

setup_stub
TS_OPT_sessions_key_table=root
TS_OPT_sessions_key_prefix='M-'
TS_OPT_sessions_last_key='0'
export TS_OPT_sessions_key_table TS_OPT_sessions_key_prefix TS_OPT_sessions_last_key
"${ENTRY}" >/dev/null 2>&1

it "root table binds with -n and the modifier"
eq "bind-key -n M-1 run-shell -b ${ROOT}/scripts/switch.sh 1" "$(binds | head -1)"

it "root table binds the last key with -n too"
contains "$(binds)" "bind-key -n M-0 switch-client -l"
teardown_stub
unset TS_OPT_sessions_key_table TS_OPT_sessions_key_prefix TS_OPT_sessions_last_key

# ------------------------------------------------------------ keys disabled

setup_stub
TS_OPT_sessions_keys=off
export TS_OPT_sessions_keys
"${ENTRY}" >/dev/null 2>&1

it "sessions_keys = off binds nothing at all"
eq "" "$(binds)"

it "but still places the status segment"
contains "$(cat "${STUB_LOG}")" "set-option -g status-right"
teardown_stub
unset TS_OPT_sessions_keys

# ----------------------------------------------------------- status disabled

setup_stub
TS_OPT_sessions_status=off
export TS_OPT_sessions_status
"${ENTRY}" >/dev/null 2>&1

it "sessions_status = off touches status-right not at all"
eq "0" "$(grep -c 'set-option -g status-right' "${STUB_LOG}" | tr -d ' ')"

it "but still binds the keys"
eq "9" "$(binds | grep -c 'switch.sh' | tr -d ' ')"
teardown_stub
unset TS_OPT_sessions_status TS_OPT_sessions_hooks

# --------------------------------------------------- current session on left

setup_stub
TS_OPT_sessions_hooks=off
export TS_OPT_sessions_hooks
"${ENTRY}" >/dev/null 2>&1

it "places the current session's pill in status-left"
contains "$(cat "${STUB_LOG}")" "set-option -g status-left"

it "the left segment asks for only the current session"
contains "$(cat "${STUB_LOG}")" '--current)'

it "raises status-left-length too, since a pill is wider than a bare name"
contains "$(cat "${STUB_LOG}")" "set-option -g status-left-length 60"
teardown_stub

setup_stub
TS_OPT_sessions_current_position=inline
export TS_OPT_sessions_current_position
"${ENTRY}" >/dev/null 2>&1

it "current_position = inline leaves status-left alone entirely"
eq "0" "$(grep -c 'set-option -g status-left' "${STUB_LOG}" | tr -d ' ')"
teardown_stub
unset TS_OPT_sessions_current_position TS_OPT_sessions_hooks
