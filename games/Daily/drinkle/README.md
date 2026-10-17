# Drinkle

Cocktail Wordle meets Mastermind. Every day there is one mystery drink, the same for everyone. Guess drinks from the list; each guess shows how it compares to the mystery drink on six things, and you deduce the answer in six guesses. It rewards reasoning, not trivia: a player who only knows common drinks can still work it out.

**Play:** https://jprier.github.io/GameTests/drinkle/

## Playing

- Type on the on-screen keyboard (or a real one) and pick from the matches, or tap the box to browse all drinks A to Z. Every drink in the list shows its ingredients underneath, so you can test a drink you don't know. Search forgives case, accents, punctuation, word order, `&`/`and` and one typo in longer words: `moj`, `gin t`, `G&T`, `pina`, `margerita` all work.
- Each guess row shows **your guess's** values, coloured against the mystery drink:
  🟩 same · 🟨 related (same group) · 🟥 not it · ⬆️/⬇️ the mystery drink is sweeter/stronger or less so.
- The **Known** row sums up what your guesses have pinned down so far (a value, a group like "Citrus?", or a range like "Sweet or more").
- A free clue appears after guesses 4 and 5. Up to three **hints**: 1 says what to test next, 2 reveals a gentle fact, 3 reveals the most decisive one.
- The end screen shows the drink (glass, ingredients, profile), your **deduction path** (what each guess ruled out or confirmed and how many drinks still fit), and on a loss which clue would have told the remaining drinks apart.
- **Share** gives a spoiler-free grid (one emoji row per guess) and the plain game link; **Copy result** copies it. Past days are in the calendar. Progress is saved per day in browser storage.

## The six attributes

| Column | Kind | Feedback |
|---|---|---|
| Family (Sour, Tiki, Highball, Spritz, Punch, Beer drink, Martini, Lowball, Creamy, Coffee, Hot drink, Soft drink) | categorical | 🟩 / 🟨 same group (Shaken & citrusy, Long & topped up, Spirit-forward, Rich & cozy) / 🟥 |
| Base (main alcohol, "Several spirits" for a Long Island, or main ingredient if alcohol-free) | categorical | 🟨 for rum/cachaça, sparkling wine/wine, any two alcohol-free bases (coffee, tea, cocoa, juice, soda, milk) |
| Fruit (main fruit or juice; garnishes don't count) | categorical | 🟨 within citrus, red berries, tropical (pineapple, passion fruit, mango, coconut) |
| Bubbles | exact | 🟩 / 🟥 |
| Sweet (Dry, Balanced, Sweet, Very sweet) | approximate | 🟩 / ⬆️ / ⬇️ |
| Strength (None, Light, Medium, Strong) | approximate | 🟩 / ⬆️ / ⬇️ |

Values are canonical characteristics, not bar-specific recipes. A drink whose profile is genuinely disputed (G&T lime vs lemon, Pisco Sour lime vs lemon, Dark 'n' Stormy lime, Sangria, Rum Punch, Eggnog's spirit, Gin Fizz vs Tom Collins, …) stays guessable but is never the answer.

## How it's built (`core/`)

`main.gd` is only the UI. Everything else is pure, deterministic and tested:

| File | What it does |
|---|---|
| `data/schema.json`, `schema.gd` | The six attributes: kind (exact / categorical / approximate), labels, related groups, help text. |
| `data/drinks.json`, `db.gd` | 90 drinks: the six values plus aliases, glass, colour, ingredients, profile, fame, and `target` (false + `why` for disputed ones). `validate()` and a fingerprint of everything that affects answers. |
| `compare.gd` | `compare(guess, target) -> feedback[]` |
| `candidates.gd` | `remaining(history, facts) -> drinks[]`: everything still consistent with the feedback (never shown during play). |
| `search.gd` | Normalising, alias resolution, ranked autocomplete. |
| `analysis.gd` | Indistinguishable/near-identical drinks, a greedy perfect-information solver, first-guess statistics, look-alike crowding, a 0-100 difficulty score, tiers by thirds of the answer pool (so they stay balanced as drinks are added), and answer eligibility (rejects disputed, obscure, indistinguishable and "trivial after one guess" drinks). Runs on a precomputed feedback matrix: the whole database in under a second. |
| `daily.gd` | Puzzle number, weekday tier (Mon-Tue Easy, Wed-Fri Medium, Sat-Sun Hard), and the answer for a date: pinned schedule first, otherwise a seeded per-tier rotation that never repeats a drink within two weeks. |
| `hints.gd` | Knowledge from feedback (Known row), automatic clues and three hint levels, all computed from the candidate set. |
| `explain.gd` | Deduction path and loss explanation. |
| `game.gd`, `save.gd`, `share.gd` | One day's game and its save round trip, local storage (dev mode uses separate `dev_` files), share text. |

### Pinned schedule

`data/schedule.json` pins the answer for ~3 years of dates, plus the tier pools, each drink's difficulty and the rotation salt, so a phone never runs the analyser and adding drinks never changes a past puzzle. After editing `drinks.json` or `schema.json`, rerun it. Dates before `pinned_before` (by default two days after today, so every time zone is covered) keep their answers, and the tool picks the first rotation salt that never repeats an answer within two weeks, already-played days included:

```
godot --headless --path . -s tools/schedule.gd -- 1100
```

A test fails if the schedule's fingerprint doesn't match the database.

### Analysis

```
godot --headless --path . -s tools/analyze.gd
```

prints schema errors, indistinguishable groups (must be none), drinks that differ in only one attribute, and every drink's difficulty (greedy solve length, average drinks left after a first guess, share of first guesses that already isolate it, look-alikes) with its tier or why it can't be an answer. Exit code 1 on errors or duplicates.

Current database: 90 drinks, no indistinguishable pairs, 77 possible answers (24 Easy, 27 Medium, 26 Hard). A perfect-information player solves every answer in at most 4 guesses, and from any opening guess within 6.

## Testing

`tests/` (run by CI, about 7 s): comparison and partial-match rules, arrow directions, candidate filtering (the answer always survives, every candidate explains all feedback), search and aliases, hints and clues are true, save round trip, deduction path, spoiler-free sharing, daily determinism, numbering and date rollover, schedule/rule agreement and fingerprint, no repeats within two weeks, the next 60 days are valid answers in the right tier, every answer solvable from any opening, real taps on the on-screen keyboard through a win and a loss, dev controls never touching real saves, past days, every label fitting its cell, every drink's name and ingredients fitting its picker row at every layout, and non-overlapping layouts from tall phones to desktop.

## Dev mode

Hidden: `?dev=1`, tap the title five times, or on in debug builds; `` ` `` toggles the panel. Shows day, tier, score, state, candidates left and (on tap) the answer; moves days (±1, ±7, today, random), resets the day, wins or loses instantly, and simulates midnight rollover. Dev progress is stored separately and never reaches the home page. `?d=YYYY-MM-DD` opens a day only in dev mode.
