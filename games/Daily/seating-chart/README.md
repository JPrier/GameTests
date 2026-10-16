# Seating Chart

A daily wedding seating logic puzzle. Ten guests, two round tables of five, and a list of clues ("Maya must sit next to Chris", "Keep Alex and Jordan at separate tables", "Dante sits at Table 2"). Seat everyone so that every clue is true. Everyone gets the same puzzle each day; Monday is easy and the weekend is hard.

**Play:** https://jprier.github.io/GameTests/seating-chart/

## Playing

- Drag a guest onto a seat, or tap a guest then a seat. Dropping on a taken seat swaps; drag a seated guest back to the list to unseat them. Undo and Reset (undoable) are always there.
- "Next to" means the seats directly either side at the same round table. Rotating or mirroring a table doesn't change who sits next to whom, so any rotation of the answer counts.
- Tap a clue to light up its guests; tap a guest to light up their clues. Clues tick green when they hold and turn red the moment they can't.
- **Hint** is progressive and worked out live from your board: 1 points at the clues to look at, 2 explains the deduction, 3 seats the guest. If someone seated is wrong, the hint says so first.
- **Check** tells you whether everyone seated so far fits the answer. It only costs you (a "wrong check") when someone is misplaced.
- The timer never matters for winning. The result is your time plus hints and wrong checks; "Flawless" means neither.
- **Share** copies a spoiler-free result: one row of squares per table (green = you seated them, yellow = a hint did) and the plain game link. Past days are played from the calendar button.
- Progress is saved per day in browser storage.

## How puzzles are made (`core/`)

Everything except `main.gd` (the UI) is plain logic with no UI dependency:

| File | What it does |
|---|---|
| `model.gd` | Guests, tables, seats as `table * 5 + position`, ring adjacency, the canonical form of a seating (rotation/mirror), best-match against the answer, JSON round trip. |
| `constraints.gd` | Clues as dictionaries (`adjacent`, `not_adjacent`, `same_table`, `different_table`, `at_table`), their text, validation, and `eval` on partial seatings (TRUE / FALSE / UNKNOWN, FALSE is final). The solver, hints and UI all use this. |
| `solver.gd` | Exhaustive backtracking solver with symmetry breaking: the ground truth for "exactly one answer". |
| `logic.gd` | Human-style solver on bitmask notes (tables, same-table, neighbours). Levels: 0 bookkeeping, 1 direct table links, 2 counting / full tables / both neighbours known / ring closing, 3 two-table parity and group sizes, 4 what-if (assume, reach a contradiction). Step mode records explained deductions (hints, rating); bulk mode answers "solvable within level X?" fast (generator). |
| `generator.gd` | Seeded from the date: guests, a random answer, every true clue, weighted draws until reasoning finishes within the tier's level, then prunes every clue it can do without, rates it and re-rolls (deterministically) until it fits the tier. The exhaustive solver double-checks uniqueness. |
| `difficulty.gd` | Tiers: Mon Easy (levels ≤2), Tue–Wed Medium (needs level 3), Thu–Fri Tricky (several level-3 steps, few direct placements), Sat–Sun Hard (needs a what-if, one direct placement). |
| `hints.gd` | Next useful deduction from the clues plus correctly seated guests. |
| `board.gd`, `share.gd`, `save.gd`, `daily.gd`, `names.gd` | Player board with undo/reset/check, share text, local saving (dev mode uses separate `dev_` files, puzzles are cached per day), date/seed/tier logic, guest names and flavour text (never referenced by clues). |

`core/attempts.json` lists which generator attempt each upcoming date lands on, so a phone regenerates one attempt instead of searching (identical result; dates not listed fall back to the full search). After changing the generator, bump `GEN_VERSION` in `generator.gd` (it also keys the per-day puzzle cache) and rerun:

```
godot --headless --path . -s tools/precompute.gd -- 400
```

## Testing

- `tests/` (run by CI): every constraint, both solvers (and that they agree), uniqueness, determinism, date rollover, tiers, serialization, undo/reset, hints solving whole puzzles, drag/tap input through a full win, saving, dev controls, the attempt table.
- `tools/sweep.gd` audits thousands of generator attempts and every puzzle they accept (impossible, multiple solutions, broken or false clues, redundant clues, not deducible, wrong tier):
  `godot --headless --path . -s tools/sweep.gd -- 2000`
- `tools/bench.gd` times generation for a run of dates.

## Dev mode

Hidden: open with `?dev=1`, tap the title five times, or it's on in debug builds; `` ` `` toggles the panel. Shows seed, tier, rating and the answer; jumps days (±1, ±7, today, random), resets the day, reveals, or wins instantly. Dev progress is stored separately and never reaches the home page. `?d=YYYY-MM-DD` opens a day only in dev mode.
