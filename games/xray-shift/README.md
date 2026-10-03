# X-Ray Shift

A daily airport-security game. Ten bags roll through your x-ray; everyone gets the same ten bags each day.

**Play:** https://jprier.github.io/GameTests/xray-shift/

## How it plays

- Each bag stops in the scanner. **Clear** it (Space) if it's clean, or **Flag** it (F) if you spot contraband.
- Flagging opens the bag: the items slide out in real colour and you tap every illegal one (or press 1–9). Find them all and the bag closes itself; otherwise press **Done** (Enter) and anything you missed is shown.
- The contraband legend sits at the top of the screen the whole time. Tap it (or press L) for the full list, with the harmless lookalike for each one and the x-ray colour key: blue is metal, orange is organic, green is plastic.

| Contraband | Harmless lookalike |
|---|---|
| Knife | Fork, spoon |
| Handgun | Hair dryer |
| Ammunition | Batteries |
| Explosives | Power bank and cable |
| Big liquids | Travel bottle |
| Hatchet | Umbrella |

## Scoring

| | Points |
|---|---|
| Each contraband item found | +100 |
| Flagging a clean bag | −100 |
| Tapping a harmless item | −25 |
| Time bonus | +4 per second under 2:30 |

Clearing a bag that had contraband scores nothing and flashes what you missed. The timer runs from Start shift to the last bag.

**Share** copies a spoiler-free summary: one square per bag (green right, yellow flagged but missed items or tapped something harmless, red missed bag or false alarm), the score, contraband found and time, plus a `?day=YYYY-MM-DD` link to the same shift. Shift #1 is 2026-10-03. Progress is saved per day, including a bag you were halfway through.

## Daily generation

The UTC date seeds the generator. Each day has 4–6 contraband bags (a quarter of them with two items), a lookalike in most bags, and items packed so contraband never sits on top of other contraband. Days are re-rolled deterministically until they pass the fairness check (`bags_valid`).

## Dev mode

Hidden from normal play. Tap the **X-Ray Shift** title 5 times quickly to turn it on; after that the same taps, a long-press on the title or `` ` `` toggle the panel. `?dev=1` (or a debug/editor run) starts with it on. The panel lists every bag's contraband and can jump days (±1, ±30, today, random), reset the day, outline the answers, and instantly win or lose. Dev progress is saved separately. Agent methods: `dev_set_day("2026-11-05")`, `dev_shift(n)`, `dev_reset()`, `dev_win()`, `dev_lose()`, plus `start_shift()`, `flag_bag()`, `clear_bag()`, `tap_item(i)`, `done_bag()`.

Tests: `gck test xray-shift` (tests/test_main.gd): catalog, determinism, 30 upcoming days fair, a scripted perfect shift, penalties, resume, legend, keyboard loop and dev controls.
