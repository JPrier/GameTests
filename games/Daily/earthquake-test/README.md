# Earthquake Test

A daily physics game. Everyone gets the same building site and the same earthquake each day: build a structure from wood and steel beams, start the quake, and score the height still standing when the shaking stops. Three tries a day; your best counts.

**Play:** https://jprier.github.io/GameTests/earthquake-test/

- **Daily challenge:** each date gets a curated challenge — a quake archetype, a soil, a terrain shape, a footing (anchor) layout, a budget and, on some days, an engineering condition — built by `challenge/generator.gd` from the local date. Quake #1 is 2026-10-02. See [Daily challenges](#daily-challenges) below.
- **Building:** pick a max piece length (1, 2 or 3 m), then drag a line from an anchor or joint to any dot, at any angle. It's split into equal pieces no longer than that (a 7 m line in 2 m pieces = 4 × 1.75 m), so joints between pieces can sit between grid dots. Lines that pass over existing joints connect to them, and drawing over existing beams doesn't duplicate them. Or tap a joint, then tap dots. A whole line is one Undo step. Only anchors may touch the ground, and beams can't pass through it (hills, ledges and rocks have to be built over or around). Build points are stored in centimetres.
- **Erasing:** only the **Erase** tool removes pieces (taps on beams while building do nothing). It removes exactly the pieces you tap or swipe across (one Undo per swipe). Pieces left floating are shown faded red; they don't count and just fall when the quake starts.
- **Auto-lock** (the LOCK button on the site, on by default, remembered): while drawing, the line's end snaps onto an existing joint or anchor within ~0.9 m (or 44 px), even over a slightly closer grid dot. Off: it goes to whatever dot or joint is nearest.
- **Magnifier:** while you hold a joint to draw, a 2.6× loupe floats above your finger (beside it near the top of the screen) showing the line, the target (green ring = locked onto a joint), a crosshair at your fingertip, and the piece count and cost.
- **Zoom:** pinch, mouse wheel / trackpad, or the + / − buttons; drag empty space (or two fingers) to pan.
- **Materials:** wood ($1/m) is light and cheap; steel ($3/m) is heavier but about 5× stronger (prices can change on Steel Shortage / Cheap Steel / Timber Shortage days). Pieces longer than 1.8 m buckle sooner under compression (~(1.8/L)² of full strength), so long pieces are cheap per joint but weaker when squeezed.
- **Quake:** a sampled ground-motion record (`quake/quake.gd`, synthesized by `quake/waveform.gd`). The seismograph at the top shows today's record before you build: ground velocity (grey) and vertical shaking (blue), on a shared 30 s time scale so a short Jackhammer looks short next to a long Slow Burner. Its bottom line names the soil and terrain, plus today's condition in orange. Tap it for the briefing card.
- **Physics:** `quake_sim.gd` is a small deterministic truss solver (small-step XPBD distance constraints, fixed 60 Hz step, 10 substeps). Anchors ride the moving ground, and loose joints land on the terrain surface (`ground_at()`), which moves as one rigid block; a beam snaps when its average axial force in a step exceeds its strength. No randomness, so the same design and the same day give the same result for everyone. On Heavy Top days the weight is extra mass on the highest attached joint (`top_joint()`, shown on the board).
- **Score:** height of the highest joint still connected to an anchor through intact beams, after a short settle. Heights are measured from the lowest ground on the site (the ruler's 0), so building from a ledge or a ravine rim starts you higher.
- While the quake runs, ground motion and sway are drawn exaggerated (up to 3×, easing off as the shaking dies) so the movement reads on a phone; the physics and score use true positions.

**Share result** sends your height with a link (`?d=<date>&s=<cm>`) that opens the same day's quake, with your height shown as the line to beat. Progress and your design in progress are saved per day in browser storage.

Dev menu (hidden): tap the title 5 times quickly, or open with `?dev=1`. It steps to any day (including future ones), resets progress and shows the generator's pick for the day (archetypes, candidate, score, novelty, difficulty).

Tests: `gck test <id>` — `tests/test_main.gd` (game + UI), `tests/test_challenge.gd` (generator: determinism, archetypes, sites, selection, novelty, waveforms, solver stability, a 3000-day fuzz, modifiers, briefing).

## Daily challenges

The generator is a small curator, not a dice roller: it aims for days that need a *different structure*, not just a slightly stronger quake.

### What a day is made of (`challenge/challenge.gd`)

`DailyChallenge` holds everything that defines a day: date, generator version + winning seed, quake archetype + full quake spec, site archetype + anchors, soil, budget, modifier (+ its parameters and material prices), analytic response metrics, fingerprint and novelty. `to_dict()` serialises it for tests and debugging; the dev menu shows the key numbers.

| Quake archetype | Character | What it punishes |
| --- | --- | --- |
| Long Roller | 0.3–1 Hz, 14–25 s, big sustained sways | tall, flexible towers |
| Jackhammer | 2–5 Hz, 5–10 s, sharp and violent | stiff, short builds |
| Fault Pulse | mild shaking plus one (sometimes two) huge directional kicks at a seeded time | anything near its sway period |
| Double Tap | a quake, a 2.5–4 s lull, a second strong burst at a shifted frequency | builds damaged by the first hit |
| Vertical Jolt | vertical shaking 1.1–1.5× the horizontal | long members in compression |
| Slow Burner | moderate, 19–29 s of sustained shaking | marginal designs |
| All-Rounder | broadband energy | a balanced day |

- **Soil:** Bedrock keeps the fast shaking, Soft Soil resonates near a seeded site frequency, filters the fast stuff and draws the quake out; Firm Ground is neutral. It changes the frequency content of the record, not just the label.
- **Sites (footings):** Wide, Narrow, Three-Point, Lopsided, Tight Cluster, Split — each a family of seeded layouts (`site/site_generator.gd`), always buildable.
- **Terrain** (from 2026-10-19, `site/terrain.gd`): a heightfield sampled every metre, shaped around the day's anchors so the feature always matters. Hillside (a 2–4 m tilt), Ledge (a 2–3 m shelf between two anchors, on the side with fewer of them), Hump (a mound between two anchors), Ravine (a 2.5–4 m gap; on some three-anchor days the middle anchor stands at the bottom), Terraces (three anchors on three levels), Rock Outcrop (a 3–5 m spike in the way). Terrain is drawn in its soil's look: grey layered Bedrock, packed tan Firm Ground, dark wet Soft Soil. Hump, Ravine and Outcrop days get $5 extra.
- **Conditions (about 1 day in 5, never two days running):** Steel Shortage ($4/m steel), Cheap Steel ($2/m), Timber Shortage ($2/m wood), Heavy Top (30 kg on your highest joint), Aftershock (a smaller second quake after a few seconds of calm, visible on the seismograph), Minimum Height (build 4–6 m before the quake can start). Everything that matters is shown on the briefing card and the seismograph before you build.

### Ground motion (`quake/waveform.gd`)

seeded random-phase sinusoids → log-gaussian band shaping + soil gain → per-event envelopes (several events per quake: rise / strong / lull / strong / decay) → optional explicit near-fault velocity pulses → horizontal + vertical components → normalised so the peak horizontal acceleration is exactly the day's PGA. It is built in displacement space so the ground always ends at rest (no drift), sampled at a fixed 120 Hz and interpolated (Catmull-Rom) for the solver. There's no randomness after generation.

`estimate()` gives a cheap analytic response spectrum (6 reference oscillators from 0.12 s stiff to 2.4 s flexible) used to score candidates; the calibration tool checks it against a time-domain response spectrum (log correlation ≈ 0.97).

### Picking a day (`challenge/generator.gd`)

1. **Plan** (exact and recursion-free): the quake archetype comes from a shuffled two-week bag (each archetype twice a fortnight, never twice in a row); a second bag suggests a site; the soil is drawn with the archetype's soil odds; a hash decides whether the day may carry a condition.
2. **20 candidates**, each seeded from the date, vary the site, condition and every quake parameter.
3. **Budget:** from an estimated difficulty (a pseudo-velocity response sum, calibrated against the canonical structures) plus a site allowance (spread-out footings buy less height per dollar) and the condition: about $40–75, mostly $50–65.
4. **Validate** (`challenge/validator.gd`): buildable site, budget, duration and dominant frequency inside the archetype, PGA, ground displacement, condition fits the quake.
5. **Score:** archetype × site / soil / condition fit, how differently stiff and flexible structures are loaded (response spread), estimated difficulty in band, and penalties for repeating the earlier days of its 14-day run (same site or terrain as yesterday, same condition within the run, fingerprint too close — `challenge/fingerprint.gd`).
6. **Pick** the best valid candidate (lowest index on ties); a fixed fallback search guarantees a day.

Days are curated in 14-day runs from the cutover, so a day's novelty is measured against exactly the days published before it in its run; any date generated cold, in any order, gives the same result (a test checks this). Generating a day costs ~5 ms per day of its run.

**Versioning:** terrain (v3) starts at `TERRAIN_FROM` (2026-10-19) and draws from its own seed, so 2026-10-18, the first v2 day, is unchanged. Days before `CUTOVER` (2026-10-18) use the frozen v1 generator (`challenge/legacy_v1.gd`, `quake/quake_v1.gd`), so old days and their saved designs replay exactly as played. Changing any v2 rule must move `CUTOVER` forward and bump `VERSION`/`SALT`; `test_generator_snapshot` fails if generated days change.

### Calibration (`tools/calibrate.gd`, `reference/canonical.gd`)

Ten canonical reference structures (tall wood tower, steel tower, wide braced frame, A-frame, squat steel block, steel spine, flexible lattice, leaning tower, steel-base tower, pyramid) are built for any site and budget and run through the real solver. They are never shown to players; they show whether a day treats every design the same.

```
godot --headless --path . --script res://tools/calibrate.gd -- --days=365 --check --canon=1
```

prints archetype / site / soil / condition / budget distributions, repeat rates, numeric spreads, rejection and fallback counts, analytic-vs-time-domain agreement, the canonical response matrix (which structure keeps the most height under which quake), and the extreme days. `--out=file.jsonl` + `--merge=a,b` run it in parallel shards.
