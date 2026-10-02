# Daily Bridge

Build a bridge, then watch one vehicle try to cross. Everyone gets the same canyon, anchors and vehicle each day, and three attempts. Your score compares the material you used with today's ideal bridge: 100 matches it, more material drifts toward 0, and beating it scores over 100.

**Play:** https://jprier.github.io/GameTests/daily-bridge/

## How it plays

- Drag from a joint to place a beam, or tap a joint and then tap where the beam should go (taps chain, so you can lay a deck panel by panel). Beams snap to a 1 m grid and reach 2.3 m at most. Red joints are anchored to the rock.
- **Road** (15 per metre) is the only thing the vehicle drives on. **Wood** (10 per metre) is lighter and cheaper; use it to brace the road into triangles.
- Press **Go** to send the vehicle. Beams glow red as they strain and snap when overloaded. After a failed attempt the bridge is kept, with snapped beams marked ×, so you can repair it.
- Score = 100 × ideal ÷ material used, on your best crossing; a bridge that falls scores 0. The material bar shows the ideal and your projected score as you build. **Share result** sends your score with a link (`?d=<date>&s=<score>`) that opens the same day's bridge, with your score shown as the one to beat.

Each day picks a gap (8, 10 or 12 m), a vehicle (hatchback 320 kg, camper van 480 kg or pickup truck 620 kg), lower anchors on both cliff faces, and sometimes a rock pillar mid-gap. Puzzle #1 is 2026-10-02.

## How it works

- `bridge_sim.gd` is a small deterministic physics engine: beams are XPBD distance constraints with a stiffness, a weight and a breaking force; the vehicle is two wheels on a rigid chassis that roll on road beams and push load into the joints they touch. Fixed timestep and solve order mean the same bridge plays out identically everywhere (the browser and headless runs match exactly).
- The ideal comes from `BEST_KNOWN` in `main.gd`: the cheapest of a few reference bridges that crosses each level. `tests/test_main.gd` re-runs the physics to keep that table honest, so 100 is always reachable.
- Progress is saved per day in browser storage, so a reload keeps your attempts and your half-built bridge.

Dev menu (hidden): tap the **Daily Bridge** title 5 times quickly, or open with `?dev=1`. It can reset today, reset every day plus the tutorial, or load the reference bridge.

Tests: `gck test daily-bridge` (tests/test_main.gd, tests/test_sim.gd).
