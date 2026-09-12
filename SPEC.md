# tmux-sessions.tmux — Specification

Status: draft, awaiting approval
Date: 2026-09-12
Verified against: tmux 3.7c, macOS (darwin 24.6.0), the author's live config

---

## 1. Objective

The numbered tmux session list in the status bar, and `Alt+N` to jump to any of
them, from **any** pane — shell, TUI, long-running command, anything.

This exists because [tmux-sessions.nvim](../tmux-sessions.nvim) only works
inside Neovim. In a plain shell pane there is no list and no keybinding, so the
habit breaks and you fall back to `prefix + f`.

tmux is the right layer for this, and zsh is not:

- A zsh prompt only draws at the prompt. Run `htop`, `less`, a build, or a dev
  server and both the list and the keybinding are gone. That is most of the time
  you would want them.
- zsh keybindings are ZLE widgets. They only fire at the prompt, so you cannot
  jump while a command is running.
- tmux draws its status bar in every pane regardless of what is running inside
  it, and tmux already owns session switching.

### Non-goals

- Creating, renaming or killing sessions. `tmux-sessionizer` and
  `tmux-worktree` already do that in this config.
- Replacing `prefix + f` (`choose-session`). This is the zero-keystroke path;
  that stays the browse-and-search path.
- Window or pane navigation. Session granularity only.

### Relationship to tmux-sessions.nvim

Both derive the index the same way, so `3` means the same session in both. The
nvim plugin stays installed for now; the user decides after living with both
whether to set `ghost.enabled = false` and keep only its keymaps.

---

## 2. Measured basis

All timings on this machine, 5 live sessions.

| Operation | Cost |
|---|---|
| Resolve one index to a session id | 7.6 ms |
| Render the full status string | 9.7 ms |
| `tmux list-sessions` alone | 3.7 ms |

The resolve is paid once per keypress, which is imperceptible. The render is
paid on `status-interval` and on each hook-driven refresh; at the default 15s
interval it is noise, and hooks make it event-driven anyway.

Neither number justifies caching or a daemon. Keep it a script.

---

## 3. Verified tmux behaviour

Everything below was confirmed on tmux 3.7c before being specified.

### 3.1 `#{S:...}` iterates in creation order

```
$0=main(1788718199)  $30=effective-tutorial(1789181871)
$32=solo-effect(1789185033)  $33=packages(1789185097)  $44=zz_probe(1789191924)
```

tmux assigns session ids monotonically, so id order **is** creation order. A new
session always appends. This is the same ordering tmux-sessions.nvim computes,
which is why the two agree.

The list is still built by sorting explicitly on `session_created` with a
numeric id tiebreak, rather than relying on `#{S:}` ordering being stable across
tmux versions.

### 3.2 `#()` in `status-right` receives format substitutions

`status-right "#(script #{client_session})"` passes the *client's* current
session to the script. This matters: the highlight for "you are here" is
per-client, and a global `set -g status-right "…"` computed in a hook could not
be.

### 3.3 `status-right-length` defaults to 40

Too short for the list; it must be raised or the tail is silently cut.

### 3.4 `prefix + 0`–`9` is already taken

tmux binds those to `select-window` by default. `Alt+1`–`Alt+9` is free: the
root key table here has 24 bindings and zero `M-<digit>`.

### 3.5 Session names can inject tmux format syntax

This is the security finding, and it drives section 7.

tmux **accepts** session names containing `#`, including `#[fg=red]styled` and
`#(touch /tmp/x)`. Status content is re-parsed by tmux for `#[...]` directives —
that is how this plugin's own colours work — so a name flows straight into that
parser.

Confirmed unescaped, the name recolours the bar:

```
7 #[fg=red]styled        <- interpreted as a colour directive
```

Confirmed escaped (`#` → `##`), it renders literally:

```
7 #[fg=red]styled        <- printed as text
```

No command execution was observed via a `#()` name in this path; the name came
back empty and the file was never created. That is **not** treated as proof that
`#()` is safe. Escaping every `#` neutralises `#[`, `#(` and `#{` uniformly, so
the plugin does that rather than reasoning about which are dangerous.

---

## 4. Core decisions

### 4.1 Resolve at press time, never rebind

`Alt+1`–`Alt+9` are bound **once**, statically, each to a resolver invoked with
its index. The resolver maps index → session id at the moment of the press.

The alternative — rebinding all nine keys whenever the session list changes — is
what the nvim plugin does, because nvim keymaps are cheap and in-process. In
tmux it would mean nine `bind-key` calls per hook firing, and a window where a
key points at a dead session. Resolving on press costs 7.6 ms once and is always
correct.

A resolve that finds no session at that index does nothing, silently. Pressing
`Alt+7` on a four-session machine should be a no-op, not an error message.

### 4.2 Target by session id

Same reasoning as the nvim plugin, same verification: with `main` and `main2`
alive, `tmux -t main` resolves by prefix match. The resolver emits `$<digits>`
and the switch targets that.

### 4.3 Render through `#(…  #{client_session})`

Per-client current-session highlighting, and tmux handles the caching. The
alternative, recomputing `set -g status-right` inside each hook, cannot know
which client is asking.

### 4.4 Refresh on hooks, not on a fast interval

`session-created`, `session-closed` and `client-session-changed` each run
`refresh-client -S`, which re-evaluates the status line immediately. The
`status-interval` stays at its existing value as a backstop.

Hooks are appended with `set-hook -ga` and tagged, so the plugin never clobbers
an existing hook on those events — including the ones tmux-sessions.nvim
installs if the user enables them there.

### 4.5 Never overwrite an existing `status-right`

`status-right` is currently empty in this config, but the plugin must not assume
that. It appends its segment to whatever is already configured, and records what
it appended so it can be removed cleanly.

---

## 5. Interface

### Files

```
tmux-sessions.tmux/
  SPEC.md
  README.md
  tmux-sessions.tmux          -- TPM entry point; wires options, keys, hooks
  scripts/
    list.sh                   -- render the status segment
    resolve.sh                -- index -> session id
    switch.sh                 -- resolve, then switch-client
    install-hooks.sh
    uninstall-hooks.sh
  tests/
    run.sh                    -- bats-style harness, no real tmux required
    fixtures/
```

### tmux options

| Option | Default | Effect |
|---|---|---|
| `@sessions_key_prefix` | `M-` | gives `M-1` .. `M-9` |
| `@sessions_last_key` | `M-0` | `switch-client -l` |
| `@sessions_max` | `9` | past this, collapse to `+N` |
| `@sessions_name_width` | `0` | `0` = untruncated; else cap in cells |
| `@sessions_format` | `#[fg=#f5d76e]%d#[fg=#9f9ca6] %s` | one entry |
| `@sessions_current_format` | `#[fg=#7fe08a]%d %s` | the session you are in |
| `@sessions_separator` | `  ` | between entries |
| `@sessions_hooks` | `on` | install the refresh hooks |
| `@sessions_status` | `on` | `off` to place the segment yourself |

Colours default to the same palette as tmux-sessions.nvim and
claude-sessions.nvim, so all three read as one system.

### Manual placement

With `@sessions_status off`, the user puts `#(…/list.sh #{client_session})`
wherever they want in `status-left` or `status-right`.

---

## 6. Testing strategy

The harness is plain `sh` with a tiny assert helper, run from `make test`. No
test touches a real tmux server: `list.sh` and `resolve.sh` take their session
data from a `TMUX_SESSIONS_FIXTURE` file when it is set, falling back to
`tmux list-sessions` otherwise. That seam is the whole reason the logic lives in
scripts rather than inline in `tmux.conf`.

| Spec | Covers |
|---|---|
| `01_order` | creation-order sort; new session appends; numeric id tiebreak for same-second creations; `$10` after `$9` |
| `02_resolve` | index → id; out-of-range is a silent no-op; non-numeric input rejected; ids validated as `$<digits>` |
| `03_render` | numbering; current-session highlight; separator; `+N` overflow at `@sessions_max` |
| `04_escape` | a name containing `#[fg=red]`, `#(cmd)`, `#{x}` renders literally; `#` → `##` applied to names and never to our own directives |
| `05_truncate` | `@sessions_name_width` caps display cells; multibyte names are not cut mid-codepoint |
| `06_hooks` | install uses `set-hook -ga` and a tag; uninstall removes only tagged hooks; install is idempotent |
| `07_status` | an existing `status-right` is preserved, not overwritten; `@sessions_status off` places nothing |

### Acceptance criteria

1. With four sessions, `status-right` reads `1 main  2 effective-tutorial
   3 solo-effect  4 packages`, with the current one highlighted.
2. `Alt+3` switches to session 3 from a **shell** pane, with no nvim running.
3. `Alt+0` returns to the previous session.
4. A session created in another pane appears without any manual refresh.
5. Killing session 2 renumbers 3 and 4 to 2 and 3, and `Alt+4` becomes a no-op.
6. A session named `#[fg=red]evil` renders literally and does not recolour the
   bar or execute anything.
7. The numbers shown match tmux-sessions.nvim's for the same session set.
8. An existing `status-right` survives installation.
9. `Alt+7` with four sessions does nothing, silently.
10. Uninstalling removes the hooks and the status segment, leaving the config as
    it was.

---

## 7. Security boundaries

The trust boundary is the **session name**, which reaches a format parser.

### Always

- **Escape `#` to `##`** in every session name before it enters a status string.
  Applied to the name only, never to the plugin's own `#[...]` directives.
  Verified to render `#[fg=red]styled` as literal text.
- **Target by `#{session_id}`**, validated against `^\$[0-9]+$` before use.
- **Quote every shell expansion** in the scripts. `"$name"`, never `$name`.
- **Validate the index** as a single digit before it reaches `sed -n "${n}p"`.

### Never

- Interpolate a session name into a command, a `run-shell`, or an `eval`.
- Overwrite `status-right`, or remove a hook the plugin did not install.
- Run any destructive tmux command. Read-only except `switch-client`, the
  status option, and the tagged hooks.

Out of scope: no network, no secrets, no persistence, no privilege. The plugin
writes nothing to disk.

---

## 8. Open risks

| Risk | Severity | Mitigation |
|---|---|---|
| `Alt+N` is intercepted by the terminal emulator before tmux sees it | Medium | `@sessions_key_prefix` is configurable; document a `prefix`-table fallback. Needs testing in the user's actual terminal. |
| Long session names push the status bar past its width | Medium | `@sessions_name_width`, and `status-right-length` raised on install. |
| Status segment duplicates the nvim ghost text | Low | Expected. The user decides after living with both. |
| `#{S:}` ordering changes in a future tmux | Low | Never relied on; the sort is explicit. |

---

## 9. Build order

1. `scripts/resolve.sh` + fixture seam → spec 01, 02
2. `scripts/list.sh` rendering → spec 03, 05
3. `#` escaping → spec 04
4. `scripts/switch.sh` + key bindings
5. `tmux-sessions.tmux` entry point, status placement → spec 07
6. hooks install/uninstall → spec 06
7. README, real-config verification in a shell pane

Each step lands green before the next starts.
