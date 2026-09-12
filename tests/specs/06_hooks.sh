# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# Hook install and uninstall, against a throwaway session scope so the suite
# never writes to the server-wide configuration.
#
# Skipped when there is no tmux server to talk to.

HOOKS="${ROOT}/scripts/hooks.sh"
REFRESH="${ROOT}/scripts/refresh.sh"
SESS='zz_tmux_sessions_spec'

if ! command -v tmux >/dev/null 2>&1 || ! tmux list-sessions >/dev/null 2>&1; then
  it "hook specs need a running tmux server"
  printf '  skip %s\n' "no tmux server"
else
  tmux kill-session -t "${SESS}" 2>/dev/null || true
  tmux new-session -d -s "${SESS}" 2>/dev/null
  # A foreign hook, to prove we never take someone else's with ours.
  tmux set-hook -a -t "${SESS}" session-created "display-message 'FOREIGN'"

  ours() {
    tmux show-hooks -t "${SESS}" 2>/dev/null | grep -cF "${REFRESH}" | tr -d ' '
  }
  foreign() {
    tmux show-hooks -t "${SESS}" 2>/dev/null | grep -cF 'FOREIGN' | tr -d ' '
  }

  it "install adds one entry per event"
  "${HOOKS}" install -t "${SESS}"
  eq "3" "$(ours)"

  it "install appends, leaving an existing hook on the same event alone"
  eq "1" "$(foreign)"

  it "installing twice does not stack duplicates"
  "${HOOKS}" install -t "${SESS}"
  eq "3" "$(ours)"

  it "the hook command is our refresh script, which is what makes it removable"
  contains "$(tmux show-hooks -t "${SESS}" | grep -F "${REFRESH}" | head -1)" 'run-shell'

  it "uninstall removes every entry of ours"
  "${HOOKS}" uninstall -t "${SESS}"
  eq "0" "$(ours)"

  it "uninstall leaves the foreign hook untouched"
  eq "1" "$(foreign)"

  it "uninstalling again is harmless"
  "${HOOKS}" uninstall -t "${SESS}"
  eq "0" "$(ours)"

  it "an unknown action exits non-zero rather than doing something"
  status 2 "${HOOKS}" frobnicate -t "${SESS}"

  tmux kill-session -t "${SESS}" 2>/dev/null || true
fi
