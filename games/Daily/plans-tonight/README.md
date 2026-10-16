# Plans Tonight?

A daily deduction puzzle. A group of friends can't agree on what to do tonight, and each one has a rule
or two ("won't spend more than $30", "can't get there before 8pm", "refuses to do karaoke again").
Exactly one plan works for everybody. Find it.

- Tap a plan to pick it, then **Lock it in**. Tap × on a card to cross it off for yourself.
- A wrong pick shows who vetoed it and why, so every miss is a clue. There's no losing.
- Rules and plan cards share icons (💵 price, 🕗 time, 🚶 distance, 🏠/🌳 setting, 🍽 food, 🔉 noise,
  ⏳ duration), so you always know which part of a plan to check.
- Three progressive hints: the most restrictive friend, one plan that can't work, then one exact
  rule a plan breaks. Each asks first and shows up in your result.
- Difficulty follows the week: Monday easy (4 plans) up to Friday/Saturday hard (7–8 plans).
  Saturday is a birthday. Every clue matters and nothing needs outside knowledge.
- Everyone gets the same puzzle each day (UTC). Share links are just the game URL; past days are
  playable from the calendar button.

**Play:** https://jprier.github.io/GameTests/plans-tonight/

```
Plans Tonight? #83
🍻 2/6 · ⏱️ 1:14
🟩🟥🟩🟩
🟩🟩🟩🟩
https://jprier.github.io/GameTests/plans-tonight/
```
One row per guess, one square per friend (green: fine with it, red: vetoed). It never names a plan.

## How it's built

The puzzle engine in `engine/` is plain data and pure functions, with no nodes, so it can be tested
in isolation and later reused for real friend groups.

| File | What it is |
|---|---|
| `rules.gd` | Constraint model + evaluator. A rule is `{type, v}`; `does(plan, rule) -> bool`. Also the wording, violation reasons and `contradicts(a, b)`. |
| `catalog.gd` | Plan templates (activity, menus, prices, times, setting, noise), friend names, avatars, personality lines, themes. |
| `generator.gd` | The seeded pipeline (below). |
| `validator.gd` | Solution counting, necessary/redundant clues, contradictions and every quality reject. |
| `difficulty.gd` | Scores deduction complexity: plans, clues, near misses, how little each clue rules out, arithmetic clues. |
| `hints.gd` | The three hints, computed from the puzzle and what the player already knows. |
| `daily.gd` | UTC dates, puzzle numbers, seeds, the weekly cadence. |
| `share.gd` / `save_state.gd` | Share text, and save encode/decode (a save only restores onto the exact puzzle it was made for). |

`main.gd` is the UI only.

### Generation

1. Pick plan templates and roll each plan's attributes (prices never land on a $5 boundary, so "$30 max" is never ambiguous).
2. Pick the target plan.
3. List every rule the target passes, with the wrong plans each one rules out.
4. Choose rules until every wrong plan is ruled out (weighted set cover; at most one clue that just names a plan).
5. Remove every rule that isn't needed, so each clue is the only thing ruling out at least one plan.
6. Hand the rules to friends (no friend repeats a rule type or contradicts themselves) and give them personalities.
7. Validate and score; re-roll with the next attempt seed until the puzzle matches the day's difficulty.

Rejected: zero or several answers, a clue or a single friend that settles it alone, a plan nearly every
clue rules out, redundant or contradictory clues, more than one "name a plan" clue. All randomness comes
from `hash("plans-tonight|<date>#<attempt>")`, and the web and native builds produce identical puzzles.

### Later: real friend groups

Nothing in the engine assumes a generated puzzle. A real group would supply friends with rules (budget,
availability, food, distance, activity vetoes) and a list of real plans; `PTValidate.solutions()` returns
the plans that work, `PTRules.broken()` explains each veto, and `PTRules.contradicts()` finds pairs of
people who can't both be happy.

## Tests

`tests/` covers every rule type, generator determinism, the exactly-one-answer guarantee,
contradiction and redundancy detection, hint correctness, date rollover, save restoration, share
formatting, the full loop through real input, dev controls, and a fuzz test over 2,500 consecutive days.

```bash
gck test plans-tonight              # headless
gck test plans-tonight --browser    # real web runtime
godot --headless --path . -s tools/calibrate.gd -- 2026-10-16 365   # difficulty stats per weekday
godot --headless --path . -s tools/show.gd -- 2026-10-16             # print a day's puzzle and answer
```

## Dev mode

Tap the title 5 times quickly, or open with `?dev=1`; debug builds start in dev mode. Press `` ` `` or
tap the title 5 times to open the panel: jump to any date, previous/next/random day, reset the day,
reveal the answer, instant win, or the worst run (every wrong plan first). Dev progress is saved apart
from real progress and share links never include `dev=1`.

Agents can call `select_plan(id)`, `lock_in()`, `guess_plan(id)`, `toggle_cross(id)`, `use_hint()`,
`close_modal()`, `dev_set_day()`, `dev_win()`, `dev_worst()`, `dev_reset()` and
`puzzle_signature(date)` via `gck eval`; `get_agent_state()` exposes the day, seed, answer, guesses,
hints, timer and share text. Keys: `1`–`8` pick a plan, `Enter` locks in, `H` asks for a hint.

## Credits

Emoji graphics are [Twemoji](https://github.com/jdecked/twemoji) (CC-BY 4.0), via the `@twemoji/svg`
package.
