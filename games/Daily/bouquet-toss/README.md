# Bouquet Toss

A daily wedding bouquet trick shot. Everyone gets the same venue each day: drag back, aim, let go, and land the bouquet in the glowing hands of today's guest, around tables, chandeliers, curtain walls, balconies, balloons and (carefully) the cake. Fewest throws wins. 30–90 seconds a day.

**Play:** https://jprier.github.io/GameTests/bouquet-toss/

## Playing

- **Drag back from anywhere** on the screen and let go to throw (pull-back like a slingshot). The arrow shows direction and power and a short dotted preview shows the first moment of the flight, never the whole path. Pull back to where you started to cancel. Keyboard: arrows aim (up/down angle, left/right power), Space throws.
- The aim readout shows whole-number angle (0° straight ahead, 90° straight up) and power, so a near miss is easy to adjust. Your last throw's path stays as a faint ghost.
- Bounce off walls, the ceiling, tables, balloons (very bouncy) and anything else. The cake ends the throw (splat). Throw too hard and the guest fumbles it ("too fast").
- **Score:** the day ends at your first catch. Ranked by throws, then accuracy (how close the bouquet's line of flight passes to the centre of the hands: 100% dead centre, 60% at the edge), then time. Par-style ratings: 1 Perfect, 2 Great, 3 Good, 4–5 Nice.
- After catching, keep throwing for fun (practice never changes the result). **Share** / **Copy result** give a spoiler-free result (outcomes only, never where you threw) and the plain game link; past days are played from the calendar button.
- Progress is saved per day in browser storage. Sound toggle and a one-time coach mark for first-time players.

## Each day

Seeded from the local date (`core/daily.gd`, puzzle #1 is 2026-10-16). The weekday picks the venue, introducing one idea at a time:

| Day | Venue | Idea |
|---|---|---|
| Mon | open | tables and guests between you, lots of headroom |
| Tue | chandelier | a low ceiling with hanging chandeliers |
| Wed | cake | the cake table guards the target |
| Thu | arch | a curtain wall: throw through the floral arch |
| Fri | balcony | the target waves from a balcony |
| Sat | garden | outdoors, no ceiling, a steady breeze (watch the windsock) |
| Sun | bank | a tall divider: lob through the gap or bank off the ceiling |

About a third of days are mirrored (you throw right to left).

## How it works (`core/`)

Everything in `core/` is plain logic with no rendering, testable headless:

| File | What it does |
|---|---|
| `physics.gd` | Deterministic bouquet physics: gravity, light drag, optional wind, bounces with per-surface restitution and friction (circles and boxes), catch detection, splats, fumbles, rest detection. A throw is two integers (angle in whole degrees, power 1–100). Only `+ - * /` and `sqrt` on 64-bit floats, a fixed 1/120 s step with a fixed substep rule (never more than 5 px per substep, so nothing tunnels), and fixed shape order: identical inputs give identical flights everywhere. |
| `units.gd` | Direction vectors for every whole degree written out as literals, so the simulation never calls `sin`/`cos`. |
| `rng.gd` | Integer-only random generator and string hash (no engine `String.hash()`), so generation is stable across platforms and engine versions. |
| `level.gd` | Levels are plain JSON-friendly dictionaries of whole numbers: room, people, solids, decor. Geometry rules (no overlaps, nothing floating, crowding the hand or the catch zone, poking through walls, too thin to collide reliably), mirroring, JSON round trip. |
| `generator.gd` | Builds the day's venue from the seed with weekday archetypes and random clutter. |
| `validator.gd` | Plays the level: a grid of throws (every 4°, every 5% power, including backward wall shots) must contain catches, at least one of them forgiving (every throw within ±2° and ±2 power also catches), and a solve rate inside the archetype's range (easy days generous, Sunday tight). Also counts routes (direct, off the ceiling, off a balloon, ...). |
| `levels.gd` | Attempt 0, 1, 2... until the validator accepts. `attempts.json` lists the accepted attempt and a reference throw for each date through late 2027, so phones build one attempt and check one throw instead of searching (identical result; later dates search and cache locally). |
| `scoring.gd`, `share.gd`, `save.gd` | Accuracy, ratings, ordering, outcome text; spoiler-free share text; local saving (dev mode uses separate `dev_` files). |

`main.gd` is the shell (layout, input, flight playback with a little slow motion into the catch, UI, saving, sharing, dev mode); `art.gd` draws everything with shapes (no image assets) and `audio.gd` synthesizes the sounds at start-up (no audio files).

After changing the physics, generator or validator: bump `GEN_VERSION` in `generator.gd`, regenerate the checksums and the table:

```
godot --headless --path . -s tools/checksums.gd            # paste into tests/test_physics.gd GOLDEN
godot --headless --path . -s tools/precompute.gd -- 400
```

## Testing

- `tests/` (run by CI): daily seeds, rollover, leap days, DST, time zones; physics determinism, gravity, every collision type, no tunnelling, catches, fumbles, wind, preview matching the real flight, and golden flight checksums that also pass in the browser (`gck test --browser`, proving native and WebAssembly agree bit for bit); generator invariants over many attempts, mirroring, serialization, the next 30 days all fair, the attempt table matching a fresh search, the validator rejecting broken levels, difficulty rising through the week; scoring, share text, saving; and the game scene driven by real drag and keyboard input through a full win, misses, reloads, practice, dev controls and the past-days list.
- `tools/sweep.gd` is the headless harness for thousands of levels:
  - `godot --headless --path . -s tools/sweep.gd -- attempts 2000`: acceptance and solve-rate statistics per archetype, and why attempts were rejected.
  - `godot --headless --path . -s tools/sweep.gd -- days 365`: every day's accepted level checked against every invariant (geometry, validator, reference throw, determinism, no fallback). Exits 1 on any failure.
- `tools/bench.gd` times generation; `tools/why.gd` explains a date's rejected attempts.

## Dev mode

Hidden: open with `?dev=1`, tap the title five times, or it's on in debug builds; `` ` `` toggles the panel. Shows seed, attempt, archetype, solve rate, routes and the reference throw; jumps days (±1, today, random, any date via `?d=YYYY-MM-DD`), resets the day, wins instantly with the reference throw, or reveals its path. Dev progress is stored separately and never reaches the home page; share links never carry dev flags.
