# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# Placing the segment. The rule is that the plugin adds and never overwrites:
# status-right belongs to the user, and re-sourcing tmux.conf is routine.

# shellcheck disable=SC1091
. "${ROOT}/scripts/lib.sh"

SEG='#(/p/list.sh #{client_session})'
MARK='/p/list.sh'

it "an empty status-right becomes just our segment"
eq "${SEG}" "$(ts_merge_status '' "${SEG}" "${MARK}")"

it "an existing status-right is preserved, with our segment appended"
eq "#{=21:pane_title} ${SEG}" "$(ts_merge_status '#{=21:pane_title}' "${SEG}" "${MARK}")"

it "re-sourcing does not stack a second copy"
already="#{=21:pane_title} ${SEG}"
eq "${already}" "$(ts_merge_status "${already}" "${SEG}" "${MARK}")"

it "a status-right that already mentions us anywhere is left exactly alone"
mixed="${SEG} | %H:%M"
eq "${mixed}" "$(ts_merge_status "${mixed}" "${SEG}" "${MARK}")"

it "a user status-right containing # is not mangled"
# We compose, never escape, the user's own value: their directives are theirs.
eq "#[fg=blue]%H:%M#[default] ${SEG}" \
  "$(ts_merge_status '#[fg=blue]%H:%M#[default]' "${SEG}" "${MARK}")"

# status-right-length ---------------------------------------------------------

it "the default 40 is raised, because it silently cuts the list"
eq "200" "$(ts_grow_length 40 200)"

it "an unset length is treated as zero and raised"
eq "200" "$(ts_grow_length '' 200)"

it "a non-numeric length is treated as zero and raised"
eq "200" "$(ts_grow_length 'bogus' 200)"

it "a larger value the user chose is never lowered"
eq "" "$(ts_grow_length 500 200)"

it "an equal value is left alone"
eq "" "$(ts_grow_length 200 200)"
