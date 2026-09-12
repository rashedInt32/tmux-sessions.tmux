# Session ids like '$1' are literals here, not shell variables.
# shellcheck disable=SC2016,SC1091
# tmux re-parses status content for #[...] directives, so a session name reaches
# that parser. Verified on tmux 3.7c: a session named '#[fg=red]styled'
# recolours the status bar unescaped, and renders as literal text once escaped.

LIST="${ROOT}/scripts/list.sh"

# shellcheck disable=SC1091
. "${ROOT}/scripts/lib.sh"

it "escapes a lone #"
eq '##' "$(ts_escape '#')"

it "escapes a colour directive so tmux prints it instead of acting on it"
eq '##[fg=red]styled' "$(ts_escape '#[fg=red]styled')"

it "escapes a command substitution"
eq '##(touch /tmp/pwned)' "$(ts_escape '#(touch /tmp/pwned)')"

it "escapes a format expansion"
eq '##{session_name}' "$(ts_escape '#{session_name}')"

it "escapes every # in a name, not just the first"
eq 'a##b##c' "$(ts_escape 'a#b#c')"

it "leaves a name with no # untouched"
eq 'plain-name' "$(ts_escape 'plain-name')"

# End to end through the renderer -------------------------------------------

TS_OPT_sessions_format='%d %s'
TS_OPT_sessions_current_format='>%d %s'
TS_OPT_sessions_separator=' '
export TS_OPT_sessions_format TS_OPT_sessions_current_format TS_OPT_sessions_separator

it "a hostile name is neutralised in the rendered segment"
fixture "$(
  line '$1' 1000 '#[fg=red]evil'
)"
eq '1 ##[fg=red]evil' "$("${LIST}")"

it "a name cannot smuggle a command substitution into the bar"
fixture "$(
  line '$1' 1000 '#(touch /tmp/tmux_sessions_pwned)'
)"
eq '1 ##(touch /tmp/tmux_sessions_pwned)' "$("${LIST}")"

it "our own format directives survive unescaped"
# The escaping must apply to names only; escaping the whole segment would
# render the plugin's own colours as text.
fixture "$(
  line '$1' 1000 plain
)"
contains "$(TS_OPT_sessions_format='#[fg=red]%d %s#[default]' "${LIST}")" '#[fg=red]1 plain#[default]'

it "a hostile name next to our directives escapes only the name"
fixture "$(
  line '$1' 1000 '#[fg=green]x'
)"
eq '#[fg=red]1 ##[fg=green]x#[default]' \
  "$(TS_OPT_sessions_format='#[fg=red]%d %s#[default]' "${LIST}")"
