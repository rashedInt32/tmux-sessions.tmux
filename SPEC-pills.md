# Pill rendering — Specification

Status: draft, awaiting approval
Date: 2026-09-12
Extends: `SPEC.md`, implemented in `tmux-sessions.tmux`
Verified against: tmux 3.7c, Ghostty, JetBrains Mono Nerd Font

---

## 1. Objective

Make the session list read like the user's lualine: each session in a
rounded **pill**, each pill a different colour, and the **current session on the
left** rather than buried in the list.

```
( 4 packages )                              ( 1 main ) ( 2 effective-tut ) ( 3 solo-effect ) ( 5 fiberWatch )
   status-left                                              status-right
```

(`(` and `)` above stand for the half-circle caps, which do not survive in a
plain-text spec.)

### Does this need a new plugin?

**No.** This is a rendering change inside `tmux-sessions.tmux`. The ordering,
resolution, escaping, keys and hooks are all unchanged.

A separate "tmux statusline" plugin would mean owning the *whole* bar — mode,
clock, git, CPU — which is a different product and not what was asked for. The
user's `status-left` is theirs apart from the one segment this now places.

---

## 2. Verified basis

Prototyped on an isolated tmux server before specifying.

**The caps render.** `U+E0B6` () and `U+E0B4` () come through tmux into the
status bar intact, three of each for three pills:

```
 main                          ( 1 main ) ( 2 api ) ( 3 dotfiles )
```

**The escape shape that works:**

```
#[fg=<colour>,bg=<bar>]  #[fg=<dark>,bg=<colour>,bold] 1 main #[fg=<colour>,bg=<bar>,nobold]
```

**The glyphs are fragile in transit.** They are Private Use Area codepoints and
were silently dropped when passed through an intermediate tool, producing pills
with square ends and no error. The implementation must therefore either hold
them as literal bytes in a file under version control, or emit them as explicit
octal escapes (`\356\202\266` and `\356\202\264`), and a spec must assert their
presence rather than assuming it.

### Inherited from the user's lualine

From `~/.config/nvim/lua/plugins/lualine.lua` and the `oldworld` palette:

| Element | Value |
|---|---|
| Caps | `separator = { left = "", right = "" }` |
| Pill text | `fg = colors.bg` / `bg_dark` (`#131314`), `gui = "bold"` |
| Bar background | lualine uses `#01111d`; **tmux `status-bg` is `#011627`** |

That mismatch matters: a hardcoded outer background would draw a visible halo
around every cap. The caps must use `bg=default` so they inherit whatever the
status bar actually is.

Palette (oldworld), the colours lualine already uses for its own pills:

```
blue #92a2d5   green #90b99f   magenta #e29eca   orange #f5a191
purple #aca1cf  cyan #85b5ba   yellow #e6b99d    red #ea83a5
```

---

## 3. Core decisions

### 3.1 Colours are stable per session, not random per render

"Random colours" is taken to mean *varied*, not *re-rolled*.

The bar re-renders on every hook and every `status-interval`. A genuinely random
pick would make every pill change colour several times a minute, which is
flicker, not decoration.

So: **a deterministic hash of the session name selects a palette entry.** It
looks arbitrary, and it never moves. Colour is bound to the session, so it
survives other sessions being created or killed — the same property that makes
the numbers worth memorising.

Hashing the *name* rather than the id is deliberate. Ids are handed out
sequentially (`$30`, `$32`, `$33`), so they cluster into neighbouring palette
slots; names spread. The cost is that renaming a session recolours it, which is
rare and arguably correct.

**Known limitation:** with 8 colours and 5+ sessions, two pills can collide on
the same colour. This is accepted — colour is decoration here, the *number* is
the identifier. `@sessions_colors` lets a user widen the palette.

### 3.2 The current session moves to `status-left`

`status-left` renders the current session's pill; `status-right` renders the
others. The numbering is global, so with five sessions and the third current,
the right side reads `1 2 4 5`. The gap is the point: it says where you are.

This replaces the existing `status-left` content (` #S `), which showed the same
information with less styling. The plugin appends rather than assigns, exactly
as it already does for `status-right`, so anything else in `status-left`
survives.

### 3.3 The overflow marker is a pill too

`+N` renders in the `more` colour with the same caps, so the row stays visually
uniform.

### 3.4 Width

A pill costs 4 cells of chrome (two caps, two spaces) on top of the text. Five
sessions at ~12 characters each is roughly 80 cells, plus `status-left`.

- `@sessions_status_length` default rises from 200 to 300.
- `@sessions_name_width` stays `0` (untruncated) by default, but the README
  gains a note that pills make it worth setting on a narrow terminal.

---

## 4. Options added

| Option | Default | Effect |
|---|---|---|
| `@sessions_style` | `pill` | or `plain` for the current flat rendering |
| `@sessions_pill_left` | `` | left cap glyph |
| `@sessions_pill_right` | `` | right cap glyph |
| `@sessions_pill_fg` | `#131314` | text colour inside a pill |
| `@sessions_colors` | the 8 above, space separated | palette to hash into |
| `@sessions_current_color` | `#90b99f` | fixed colour for the current pill |
| `@sessions_current_position` | `left` | or `inline` to keep it in the list |

`@sessions_style = plain` must reproduce today's output exactly, so the existing
specs keep passing unchanged and anyone without a Nerd Font has a way out.

---

## 5. Testing

New spec file, `09_pills.sh`. Existing specs run with `@sessions_style = plain`
and must not change.

| Test | Asserts |
|---|---|
| caps present | both `U+E0B6` and `U+E0B4` appear once per pill — guards the transit fragility that already bit once |
| pill shape | exact escape sequence for one session, so a regression in fg/bg pairing is visible |
| colour is stable | the same session name yields the same colour across repeated renders |
| colour is varied | a set of realistic names does not collapse to one colour |
| colour survives churn | a session's colour is unchanged after another session is added or removed |
| current is excluded | with `current_position = left`, the current session is absent from the right-hand list |
| numbering has gaps | the remaining pills keep their global numbers (`1 2 4 5`) |
| current pill | `status-left` receives exactly one pill, in `@sessions_current_color` |
| overflow pill | `+N` is rendered as a pill, not bare text |
| hostile name | `#[fg=red]evil` is still escaped to `##[fg=red]evil` inside a pill |
| plain style | `@sessions_style = plain` output is byte-identical to the pre-pill renderer |
| `status-left` preserved | existing `status-left` content is kept, ours appended |

### Acceptance criteria

1. The bar shows one coloured pill per session, with rounded caps.
2. The current session's pill is on the left, and not repeated on the right.
3. Remaining pills keep their global numbers, gap included.
4. Colours differ between neighbouring pills in the common case, and never
   change for a given session between renders.
5. Killing an unrelated session does not recolour the survivors.
6. Caps have no background halo against `status-bg #011627`.
7. `@sessions_style = plain` is byte-identical to today.
8. A session named `#[fg=red]evil` renders literally, inside a pill.
9. Verified visually in a real client, not only by assertion.

---

## 6. Open risks

| Risk | Severity | Mitigation |
|---|---|---|
| The cap glyphs are dropped in transit again and pills render square | **High** | Spec asserts their presence; they live as literal bytes in a committed file |
| Colour collisions with many sessions | Medium | Accepted; number is the identifier. `@sessions_colors` widens the palette |
| Pills overflow a narrow terminal | Medium | `status_length` 300, plus a README note on `name_width` |
| A non-Nerd-Font terminal shows tofu | Low | `@sessions_style = plain` |
| Taking over `status-left` surprises the user | Low | Appends, never assigns; `current_position = inline` opts out |

---

## 7. Build order

1. Palette + stable hash → colour, as a pure function
2. `pill()` renderer, caps as committed bytes → cap and shape specs
3. `@sessions_style = plain` fallback → byte-identical spec
4. Current-session split into `status-left` → position and numbering specs
5. Entry point wiring, `status-left` append
6. Visual verification in a real client, then README
