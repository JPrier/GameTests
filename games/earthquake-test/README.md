# Earthquake Test

A daily physics game. Everyone gets the same building site and the same earthquake each day: build a structure from wood and steel beams, start the quake, and score the height still standing when the shaking stops. Three tries a day; your best counts.

**Play:** https://jprier.github.io/GameTests/earthquake-test/

- **Site:** 2–3 ground anchors and a budget ($40–65), seeded from the local date (`generate()` in `main.gd`). Quake #1 is 2026-10-02.
- **Building:** pick a piece length (1, 2 or 3 m), then drag a line from an anchor or joint to any dot — it's built from pieces of that length with a joint between each (pieces snap to grid points on the line; a single piece is at most 3.2 m). Or tap a joint, then tap dots. A whole line is one Undo step. Only anchors may touch the ground.
- **Erasing:** the **Erase** tool removes exactly the pieces you tap or swipe across (one Undo per swipe). Pieces left floating are shown faded red; they don't count and just fall when the quake starts.
- **Zoom:** pinch, mouse wheel / trackpad, or the + / − buttons; drag empty space (or two fingers) to pan.
- **Materials:** wood ($1/m) is light and cheap; steel ($3/m) is heavier but about 5× stronger. Pieces longer than 1.8 m buckle sooner under compression (~(1.8/L)² of full strength), so long pieces are cheap per joint but weaker when squeezed.
- **Quake:** a seeded seismogram (`quake.gd`) — magnitude, duration and dominant frequency vary daily, with the peak ground acceleration set by the magnitude. The seismograph at the top shows today's record before you build.
- **Physics:** `quake_sim.gd` is a small deterministic truss solver (small-step XPBD distance constraints, fixed 60 Hz step, 10 substeps). Anchors ride the moving ground; a beam snaps when its average axial force in a step exceeds its strength. No randomness, so the same design and the same day give the same result for everyone.
- **Score:** height of the highest joint still connected to an anchor through intact beams, after a short settle.
- While the quake runs, ground motion and sway are drawn exaggerated (up to 3×, easing off as the shaking dies) so the movement reads on a phone; the physics and score use true positions.

**Share result** sends your height with a link (`?d=<date>&s=<cm>`) that opens the same day's quake, with your height shown as the line to beat. Progress and your design in progress are saved per day in browser storage.

Dev menu (hidden): tap the title 5 times quickly, or open with `?dev=1`.

Tests: `gck test <id>` (tests/test_main.gd).
