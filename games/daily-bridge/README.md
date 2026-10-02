# Daily Bridge

Build a bridge on a tiny material budget, then watch one vehicle try to cross. Everyone gets the same canyon, anchors, vehicle and budget each day; you have three attempts, and your score is the material left over on your cheapest successful crossing.

**Play:** https://jprier.github.io/GameTests/daily-bridge/

## How it plays

- Drag from a joint to place a beam, or tap a joint and then tap where the beam should go (taps chain, so you can lay a deck panel by panel). Beams snap to a 1 m grid and reach 2.3 m at most. Red joints are anchored to the rock.
- **Road** (15 per metre) is the only thing the vehicle drives on. **Wood** (10 per metre) is lighter and cheaper; use it to brace the road into triangles.
- Press **Go** to send the vehicle. Beams glow red as they strain and snap when overloaded. After a failed attempt the bridge is kept, with snapped beams marked ×, so you can repair it.
- Cross with material to spare. **Share result** sends your score with a link (`?d=<date>&s=<spare>`) that opens the same day's bridge, with your score shown as the one to beat.

Each day picks a gap (8, 10 or 12 m), a vehicle (hatchback 320 kg, camper van 480 kg or pickup truck 620 kg), lower anchors on both cliff faces, and sometimes a rock pillar mid-gap. Puzzle #1 is 2026-10-02.

## How it works

- `bridge_sim.gd` is a small deterministic physics engine: beams are XPBD distance constraints with a stiffness, a weight and a breaking force; the vehicle is two wheels on a rigid chassis that roll on road beams and push load into the joints they touch. Fixed timestep and solve order mean the same bridge plays out identically everywhere (the browser and headless runs match exactly).
- The daily budget comes from `BEST_KNOWN` in `main.gd`: the cheapest of a few reference bridges that crosses each level, plus a sliver. `tests/test_main.gd` re-runs the physics to keep that table honest, so every day is solvable within budget.
- Progress is saved per day in browser storage, so a reload keeps your attempts and your half-built bridge.

Dev menu (hidden): tap the **Daily Bridge** title 5 times quickly, or open with `?dev=1`. It can reset today, reset every day plus the tutorial, or load the reference bridge.

Tests: `gck test daily-bridge` (tests/test_main.gd, tests/test_sim.gd).
