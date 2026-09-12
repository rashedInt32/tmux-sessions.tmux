# tmux-sessions.tmux

Your tmux sessions, numbered, in the status bar. `Alt+N` jumps to one — from any
pane, whatever is running in it.

```
 packages                          1 main  2 effective-tutorial  3 solo-effect  4 packages
```

- **Stable numbers.** Ordered by creation time, so a new session always appends.
  `Alt+3` is the same session tomorrow.
- **Works everywhere.** A shell, `htop`, a build, a dev server. tmux draws the
  status bar regardless of what is running inside the pane.
- **No prefix.** `Alt+1`–`Alt+9` are one chord. `Alt+0` goes back.
- **Quiet.** Hooks refresh the bar on session create, kill and switch, so there
  is nothing polling between those.
- **Additive.** It appends to your `status-right` and never overwrites it.

## Why not a zsh plugin

A zsh prompt only draws at the prompt. Start `htop` or a build and both the list
and the keybinding are gone, which is most of the time you would want them. zsh
keybindings are ZLE widgets, so they only fire at the prompt too.

tmux is the layer that is always there, and it already owns session switching.

## Requirements

tmux **≥ 3.0**, for the `session_created` format field.

## Install

With [TPM](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'rashedInt32/tmux-sessions.tmux'
```

Or directly:

```tmux
run-shell '~/.tmux/plugins/tmux-sessions.tmux/tmux-sessions.tmux'
```

## Options

Set before the `run-shell` line.

| Option | Default | Effect |
|---|---|---|
| `@sessions_keys` | `on` | `off` to bind nothing |
| `@sessions_key_prefix` | `M-` | gives `M-1` .. `M-9` |
| `@sessions_last_key` | `M-0` | `switch-client -l` |
| `@sessions_max` | `9` | past this, collapse to `+N` |
| `@sessions_name_width` | `0` | `0` = untruncated, else a cap in characters |
| `@sessions_separator` | two spaces | between entries |
| `@sessions_format` | see below | one entry |
| `@sessions_current_format` | see below | the session you are in |
| `@sessions_more_format` | `#[fg=#6b6772]+%d#[default]` | the overflow marker |
| `@sessions_status` | `on` | `off` to place the segment yourself |
| `@sessions_status_length` | `200` | raises `status-right-length` if lower |
| `@sessions_hooks` | `on` | `off` to rely on `status-interval` alone |

Formats are `printf` patterns taking the index and the name:

```tmux
set -g @sessions_format         '#[fg=#f5d76e]%d#[fg=#9f9ca6] %s#[default]'
set -g @sessions_current_format '#[fg=#7fe08a]%d %s#[default]'
```

Colours match [tmux-sessions.nvim](https://github.com/rashedInt32/tmux-sessions.nvim)
and [claude-sessions.nvim](https://github.com/rashedInt32/claude-sessions.nvim),
so all three read as one system.

### If `Alt+N` is taken

Many terminals use `Alt`+digit for tab switching and will swallow it before tmux
sees it. Either rebind it in your terminal, or use a different prefix:

```tmux
set -g @sessions_key_prefix 'C-'    # Ctrl+1 .. Ctrl+9
```

Note that tmux binds `prefix` + `0`–`9` to `select-window` by default, so a
prefix-based scheme means giving that up.

### Placing the segment yourself

```tmux
set -g @sessions_status off
set -g status-left '#S | #(~/.tmux/plugins/tmux-sessions.tmux/scripts/list.sh #{client_session})'
```

The script takes the current session id as its argument. Passing
`#{client_session}` is what makes the "you are here" highlight correct when more
than one client is attached.

## Uninstall

```sh
~/.tmux/plugins/tmux-sessions.tmux/scripts/hooks.sh uninstall
```

Then remove the `run-shell` line and your `status-right` addition, and reload.

## Hostile session names

tmux accepts `#` in a session name, and it re-parses status content for `#[...]`
directives — that is how this plugin's own colours work. So a session named
`#[fg=red]evil` reaches that parser.

Verified on tmux 3.7c: unescaped it recolours your status bar. This plugin
escapes every `#` in a name to `##`, so it renders as literal text:

```
3 #[fg=red]hostile
```

Escaping covers `#[`, `#(` and `#{` in one rule rather than reasoning about
which of them tmux will act on. Truncation runs before escaping, so a cut can
never split an escaped pair back into a live `#`.

Session ids (`$0`, `$33`) are what the switch targets, never names. With `main`
and `main2` both alive, `tmux -t main` resolves by prefix match.

## Pairs with

[tmux-sessions.nvim](https://github.com/rashedInt32/tmux-sessions.nvim) shows the
same list inside Neovim, bound to `<leader>N`. Both derive the index from
creation order, so the numbers agree. If you run both, you may want
`ghost.enabled = false` on the nvim side.

## Development

```sh
make test              # full suite
make test FILTER=escape
make lint              # shellcheck
```

No test starts a tmux server for the logic specs: session data comes from
`TMUX_SESSIONS_FIXTURE` and options from `TS_OPT_*`, which are the same seams the
scripts use in production when those are unset. The hook specs need a server and
scope everything to a throwaway session, never the global configuration.
