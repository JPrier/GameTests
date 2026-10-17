# Shared UI: audit and before/after notes

## Audit (before)

Eleven games draw their whole UI by hand in `_draw()`; Plans Tonight builds Control nodes. Every daily
game carried its own copy of the same header, help dialog, "Past puzzles" picker and toast, each
restyled differently.

| Inconsistency | Examples |
|---|---|
| Corner radii | 2–24 px per game; Seating Chart alone used 2, 3, 4, 8, 12, 14, 20 |
| Font sizes | Ticker Time 13 distinct sizes, Flightle 17, Bloom 10, Bistro 11 |
| Touch targets | 36 px help/calendar icons (Flightle, X-Ray), 36–46 px keyboard keys, 32–40 px chips and filters (Bistro), 9–11 px labels |
| Icon buttons | circles (Bloom, Earthquake), outlined circles (Flightle), rounded squares (Bouquet, Drinkle, Ticker, Seating), emoji (Plans Tonight); every game drew its own calendar glyph |
| Header order | help-then-calendar in some games, calendar-then-help in others; titles 24–52 px |
| Dialogs | centred titles in some, left in others; radii 14–22; drop shadows (Seating, Drinkle, Bouquet); no close button in most; Escape did nothing in most |
| Buttons | two competing primaries in one view (Drinkle amber + pink, Ticker blue + yellow); drop-shadowed buttons (Seating, Bouquet); pill toasts and badges |
| Keyboard | no focus visuals anywhere (Plans Tonight's focus style was transparent); Tab bound to game actions in Earthquake, Flightle and X-Ray |
| Scale | each 720-wide game shipped ~35 px buttons and ~11 px text on phones; Daily Bridge and Bouquet Toss had each invented their own UI-scale variable |
| Home page | 14 px rounded cards with hover lift, pill badges on artwork, radial-gradient fallback art, card grid |

## The system

`ui/gametests_ui/gtui.gd` (GTUI): tokens, a per-game palette, drawing primitives for `_draw()` games,
a Theme for Control games, shared interaction (hover, press, keyboard focus, Escape) and a physical
dp scale. See `VISUAL_GUIDE.md`.

## Home page

- Card grid → a curated list: rows separated by 1 px rules, two columns on desktop, one on phones.
- Hover lift → a flat background tint; focus-visible outline.
- Pill badges on artwork → "New today" / "Played today · result" as text in the row.
- 14 px cards → 6 px thumbnails / 8 px row hover; radial gradient fallback → flat boot colour.
- Real 16:9 thumbnails (each game's first screen, help closed) for every game, so the flat
  fallback is only a safety net; spacing and type on the shared scale.
- Taglines are never cut off with "…" on phones (the 3-line clamp is gone; ui-lint rejects
  `line-clamp` / `text-overflow: ellipsis`).
- Kitchen Crawl got a homepage tagline (the README blurb mentioned the Godot renderer).

## Games

All games: header icon buttons are the shared 44 dp squares (calendar, then help, rightmost); dialogs
are one card with title + × and close on Escape; "Past puzzles" uses the shared list rows; toasts
are the shared inverted snackbar; buttons have hover/press/disabled/focus states; Tab moves focus.

| Game | Product UI changes | Kept as game art |
|---|---|---|
| Bloom | Header on the standard two rows; tutorial is a standard dialog with Back/Next and ×; shape chips are square-cornered chips (were pills); Playground button is a standard secondary button (was a purple pill with shadow); text on the type scale (was ~11 px on phones) | Board, cells, stars, walls, tutorial diagrams, title lettering |
| Daily Bridge | Its private `ui` scale now follows GTUI; header panel with meta line ("3 tries left" moved into it); piece length is a segmented control; tool chips show material swatches; Lock is a chip; zoom uses icon buttons | Sky, terrain, water, beams, vehicle, loupe |
| Earthquake Test | Same header/panel structure as Bloom/Bridge; material chips with swatches; segmented piece length; primary action moved right; Tab no longer switches material (M still does) | Site, seismogram, beams, stress colours |
| Seating Chart | Header with timer and standard icons; shadows removed from buttons/dialogs; hint card flat with gold edge; results dialog with Past days / View tables / Share; clue text dp-aware (was ~10 px on phones) | Paper palette, tables, guest cards, clue cards, confetti |
| Bouquet Toss | UI layer scale now GTUI's; header icons standard (sound, calendar, help); throws strip on shared radius; results stats flat (were cards inside the dialog) | Venue, actors, bouquet logo mark, hole cards' colours |
| Drinkle | One primary colour (amber); pink "accent" buttons → primary; keys ≥ 44 dp tall; search field styled as the shared input; suggestion list on panel radius; dialogs keep their scrolling body | Glasses, colour-coded cells, arrows, keyboard layout |
| Flightle | Icons 36 → 44 dp; keys ≥ 44 dp; FROM/TO fields reachable with Tab (replaces the Tab binding); help rewritten as paragraphs in a standard dialog; clue labels 9 → 12 px; toast was a sharp accent rectangle | Radar map, plane mark, wordmark, guess rows |
| X-Ray Shift | Archive icon 44 dp; Clear/Flag use success/danger button variants with key hints; legend is an overlay with ×; Tab no longer opens the legend (L still does) | Monitor, bags, x-ray colours, contraband legend art |
| Ticker Time | 13 font sizes → the six-step scale; one primary colour (yellow); ± are icon buttons; Up/Down are success/danger with arrows; Menu is a standard button | Charts, bars logo, progress dots, sparklines |
| Plans Tonight | Theme from GTUI (focus ring now visible for keyboard); buttons focusable; icon buttons use shared glyphs (were emoji); dialogs get × and Tab stays inside; win stats flat | Emoji avatars and rule icons, purple palette, plan cards |
| Bistro Empire | Shared radii and button states; buy amount is a segmented control; filters, Buy all and challenge buttons 44 dp; tab bar focusable; scrim/toast standard; its own text-overlap tests still pass | Restaurant scene, awning, nav icons, economy HUD |
| Kitchen Crawl | Blinking "Press Enter" text → real "Open your doors" / "Start a new run" buttons; upgrade cards flat (no drop shadow), focusable, shared radius; dim uses the shared scrim | Kitchen, chef, food, HUD, joystick |

## Known limits

- Kitchen Crawl is a fixed 960×540 landscape game: on a portrait phone it is letterboxed small. Its UI
  scale is pinned (1.25) rather than following the screen, so controls never overflow the canvas.
- Gameplay boards keep their own text sizes (e.g. Drinkle's guess rows, Earthquake Test's "to beat"
  marker). Those lines are tagged `# gt:art`; every game's ratchet baseline is 0 untagged literal font
  sizes, so any new product text has to use `GTUI.FS_*`.
- Flightle's airport suggestion list (product UI) moved from 12/15/17 px to the caption/label/body steps.
