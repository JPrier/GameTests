# GameTests visual guide

GameTests games should look like **different games made by one team**. Each game keeps its own art
direction; the *product UI* around it (buttons, dialogs, headers, help, results, focus, spacing) is
shared and behaves the same everywhere.

Read this, then look at `ui/gametests_ui/gtui.gd` (GTUI). Five minutes is enough.

## 1. Product UI vs game art

| Product UI — follows this guide | Game art — the game's own language |
|---|---|
| Header: game name size, meta line, help / calendar / sound buttons | Logo lettering, marks and colours (Flightle's plane, Ticker's bars, Bouquet's posy) |
| Buttons, icon buttons, chips, segmented controls, inputs | Boards, scenery, venues, charts, maps, x-ray monitors |
| Dialogs: help, results, "Past puzzles", dev menu | Pieces, tokens, cards *in* the puzzle (guests, plans, beams) |
| Toasts, tooltips, focus rings, hover/press/disabled | Particles, confetti, popups, shake, game-specific motion |
| Spacing, type sizes, radii, touch targets | Special typography inside the play area |

When the two pull in different directions, keep the game's identity and standardise only the
product behaviour around it. Mark a deliberate rule-breaking line of game art with `# gt:art`.

## 2. Tokens

All sizes are **dp**: CSS pixels. `GTUI.dp(n)` turns dp into canvas units for the current screen
(`GTUI.S` = canvas px per CSS px, ≥ 1), so a 44 dp button is ~44 CSS px tall on a phone *and* a
desktop whatever the project's base viewport (400×760, 720×720, 960×540).

| | Values | Use |
|---|---|---|
| Spacing | `SP_XS 4` `SP_S 8` `SP_M 12` `SP_L 16` `SP_XL 24` `SP_2XL 32` `SP_3XL 48` | gaps, padding, margins |
| Radius | `R_CONTROL 6` buttons, inputs, chips, rows, toasts · `R_PANEL 8` panels/cards · `R_OVERLAY 12` dialogs only | never pills |
| Border | `BORDER 1` | prefer borders + contrast to shadows |
| Target | `TARGET 44` min height (and width) of anything tappable · keyboard keys may be 32 wide | |
| Type | `FS_CAPTION 12` `FS_LABEL 14` `FS_BODY 16` `FS_TITLE 20` `FS_HEADING 26` `FS_DISPLAY 36` | six sizes, one family (Godot's default sans) |
| Motion | `T_FAST 0.10 s` hover/press · `T_NORMAL 0.16 s` dialogs, toasts | game animation is free |

## 3. Palette (per game)

Every game passes its own semantic colours to `GTUI.setup(self, {...})`:

`bg` `surface` `surface_high` `text` `text_muted` `border` `accent` `on_accent` `success` `danger`
(+ optional `focus`, `scrim`). Missing ones are derived. Colours are the game's; *roles* are shared:
`accent` = the one primary action, `surface_high` = secondary controls, `focus` = keyboard ring.

## 4. Components

| Need | Immediate-mode (`_draw`) games | Control-node games |
|---|---|---|
| Button | `GTUI.button(ci, id, rect, label, "primary"/"secondary"/"quiet"/"danger"/"success")` | `Button` + `theme_type_variation = "GTPrimary"` (default = secondary) |
| Icon button | `GTUI.icon_button(ci, id, rect, "help"/"calendar"/"close"/"sound_on"/…)` | `GTUI.make_icon_button("help")` |
| Header icons | `GTUI.icon_row(right, y, ["sound", "calendar", "help"])` | same order in an HBox |
| Chip / toggle | `GTUI.chip(...)` | `GTChip` |
| Segmented | `GTUI.segmented(ci, id, rect, labels, selected)` | — |
| Panel | `GTUI.panel(ci, rect)` | `GTPanel` / `GTPanelHigh` |
| Dialog | `GTUI.modal(ci, card, title, close_id)` → content rect; `modal_rect`, `modal_height`, `modal_buttons_rect` | `GTOverlay` + `GTUI.mark_overlay()` |
| List row ("Past puzzles") | `GTUI.list_row(ci, id, rect, "#16", "Fri Oct 16", "Impact 412", current)` | Button rows |
| Toast | `GTUI.toast(ci, msg, alpha, bottom_y)` | inverted label, `R_CONTROL` |
| Tooltip | `GTUI.tooltip(ci, anchor, msg)` | `TooltipPanel` (theme) |
| Big result | `GTUI.stat(...)`, `FS_DISPLAY` | `GTHeading` |
| Text | `GTUI.text`, `text_in`, `paragraph` (sizes are `FS_*`) | `GTCaption` `GTLabel` `GTTitle` `GTHeading` |

## 5. Standard chrome and patterns

- **Header**: game name (`FS_HEADING`, the game's own lettering/colour) + a muted meta line
  (`#16 · Fri Oct 16`). Icon buttons on the right, left to right: game-specific (sound) → calendar
  ("Past puzzles") → help. All `TARGET` square, `R_CONTROL`.
- **Dialogs** are the only `R_OVERLAY` surfaces: scrim, one card, title left + close (×) right, content,
  one button row at the bottom. Every dismissible dialog closes on × and **Escape**.
- **Button rows**: full width, `SP_S` gaps, at most one primary; the primary is on the right.
- **Results**: one big number (`FS_DISPLAY`), a short summary line, then `[secondary…] [Share]`; next
  puzzle countdown as a caption (`GTUI.countdown()`).
- **Past puzzles**: rows of `#n · date · result`, current day outlined in accent, Newer / Older below.
- **Help**: short paragraphs or bullets at `FS_BODY`; illustrations are game art; one primary button.
- **Toasts**: inverted (text colour fill), `R_CONTROL`, just above the bottom action area.
- No cards inside cards, no glow, no glass, no gradients or drop shadows on product UI, no pill
  shapes, no explanatory copy where a label will do. Left-align text in dialogs.

## 6. Interaction and accessibility

- Feed input through `GTUI.handle_input(make_input_local(ev))` at the top of `_input`:
  - `{"activate": id, "pos": p}` → replay as a tap: `for e in GTUI.tap_events(p): _input(e)`
  - `{"cancel": true}` → close the top-most dialog
  - `{"consumed": true}` → `get_viewport().set_input_as_handled()`
- Call `GTUI.begin()` at the top of every `_draw()` that draws product UI (pass the canvas when it
  isn't the one given to `setup`).
- **Tab / Shift+Tab** move focus (inside the open dialog only); **Enter/Space** press the focused
  control; the focus ring shows only after keyboard use. Tab is reserved: never bind it to a game
  action. While `GTUI.focused_id() != ""`, don't also run Enter/Space game shortcuts.
- Hover, pressed and disabled states come from GTUI (disabled = 40 % fill, 45 % text).
- Custom-drawn tappables: `GTUI.register(id, rect)` + `GTUI.focus_ring(ci, id, rect)`.

## 7. Checks

- `tests/test_gtui.gd` (copied into every game): palette supplied, controls registered, nothing under
  the 44 dp target, Tab focuses and Escape cancels.
- `.github/scripts/ui-lint.py`: GTUI used for product helpers, token sizes/radii, no Tab bindings,
  no shadows/gradients in product helpers, a ratchet on literal font sizes, and the home page's
  radii/spacing/shadow rules.
- `.github/scripts/sync-ui.py --check`: every game's `addons/gametests_ui/` matches `ui/`.

Edit the shared code in `ui/`, then run `.github/scripts/sync-ui.py` to copy it into the games.

## 8. New game checklist

1. `GTUI.setup(self, palette)` in `_ready`; `GTUI.begin()` in `_draw`; route `_input` through GTUI.
2. Header via `icon_row`; dialogs via `GTUI.modal`; buttons via `GTUI.button`.
3. Run `.github/scripts/sync-ui.py` (adds the addon and `tests/test_gtui.gd`) and the game's tests.
4. Check a 390×844 phone and a desktop window.
