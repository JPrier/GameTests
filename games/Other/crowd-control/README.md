# Crowd Control

*You don't control people. You control the system they move through.*

A crowd-management game. In **Stadium Departure**, 12,000 fans leave a cup final for the trains and
the car park. Every person picks their own route and walks it in a pedestrian simulation; you only
change the infrastructure: meter or close the plaza gates and the station's own entrances, draw
temporary barriers, and set the plaza signs. A long train delay is likely, the station halls are
only visible through a camera feed that refreshes every 30 s, and the score weighs journey times,
the longest wait, congestion, dangerous crowding, money spent and how people feel. A run needs one
star to pass: left alone, the delayed station fills, impatient people push, and the halls crush.
Holding people back works only if it is done in the right places: close the station entrances and
the walkways still fill; hold only the plaza and the people already on their way overfill the halls.

Play it on the GameTests page (`/crowd-control/`), or run it locally (below).

## How it is built

```
Godot 4.7.2 game (GDScript, GTUI product UI)          scripts/, shaders/, main.tscn
   │  typed JSON commands  ▲ telemetry JSON, render buffer, density image
   ▼                       │
SimAdapter ── desktop/tests: Rust GDExtension          native/crowd.gdextension
           └─ browsers:     Rust wasm via JavaScriptBridge   web/crowd_glue.js
                                   │
Rust simulation core (no engine dependencies)         sim/crates/core
  scenario validation · nav grid + distance fields · route choice on the gate graph
  · collision-free speed model · gates/queues/service · stadium reservoir → microscopic
  · density, risk, delayed sensors · incidents · scoring · replay checksums
                                   │
Scenario data (versioned JSON)                         scenarios/stadium_departure.json
```

`sim/crates/cli` is the headless harness (`crowd`): validation, runs, replays, benchmarks, strategy
experiments and research studies. Design decisions are in [`docs/decisions.md`](docs/decisions.md);
the research table, calibration and measured answers to the spec's open questions are in
[`docs/research.md`](docs/research.md); benchmark and experiment outputs are in
[`docs/benchmarks/`](docs/benchmarks/).

## Build and run

Requirements: Rust 1.97 (`rustup`), Godot 4.7.2. For the browser build also
`rustup target add wasm32-unknown-unknown`.

```bash
tools/build_native.sh          # Rust GDExtension -> native/libcrowd_gdext.so (needed to run in the editor)
tools/build_web.sh             # Rust wasm -> web/crowd_sim.wasm (needed for the web export)
godot --path .                 # play (desktop)
```

The GameTests site build runs `prebuild.sh` (both scripts) before importing the project, then tests
and exports it like every other game.

Controls: drag / WASD to pan, scroll / pinch / +− to zoom, Space pause, 1–4 speed, B barrier tool,
Esc cancel, F3 diagnostics (seed, checksum, per-system timing, true data toggle, person inspector).

## Test

```bash
cd sim && cargo test --workspace --release            # 35 Rust tests: unit, 10 behavioural reference
                                                      # geometries, invariants on random worlds, replay,
                                                      # whole-scenario behaviour (tests/stadium.rs,
                                                      # ~7 min: full 12,000-person evenings)
godot --headless --path . -- --agent-run-tests        # 17 Godot tests, incl. an end-to-end playthrough
xvfb-run godot --path . -- --capture=shots            # screenshot checkpoints
python3 tools/compare_shots.py check shots tests/visual/baseline
```

CI (`.github/workflows/crowd-control.yml`) also runs rustfmt, clippy, a replay round trip, a
native-vs-wasm checksum comparison, benchmarks against the baseline and the strategy experiments,
and uploads screenshots, reports and a playable web build.

## Benchmark and experiment

```bash
cd sim && cargo build --release -p crowd_cli
./target/release/crowd bench ../scenarios/stadium_departure.json --populations 1200,6000,12000
./target/release/crowd experiments ../scenarios/stadium_departure.json --seeds 3 --only none,expert   # ~1 min per run
./target/release/crowd research ../scenarios/stadium_departure.json     # timestep & route-interval studies
./target/release/crowd trace ../scenarios/stadium_departure.json --strategy reactive --every 30
./target/release/crowd trace ../scenarios/stadium_departure.json --frames frames.jsonl   # positions every 0.5 s
./target/release/crowd run ../scenarios/stadium_departure.json --commands ../tools/check_commands.json --out replay.json
./target/release/crowd replay ../scenarios/stadium_departure.json replay.json
```

## Make a scenario

Copy `scenarios/stadium_departure.json` and validate with `crowd validate`. The schema (version 1)
is defined and documented in `sim/crates/core/src/scenario.rs`:

- `map`: walkable rectangles, extra walls, named measurement `areas` (with optional stairs
  `speed_factor`), `barrier_zones`, presentation-only `decor`.
- `nodes` and `edges`: the route-choice graph (edges may be one-way, stairs, and point at the area
  whose crowding prices them).
- `gates`: a line, lanes × lane rate, controllable or a fixed service point (fare gates), meter
  levels, staff cost, `one_way`, and an optional `schedule`.
- `destinations`, `population_profiles` (trait ranges, group sizes), `spawn_schedules` (exits,
  release rates, destination mix), `signs` (messages: off / route / wait times),
  `transit_services`, `event_schedule` (seed-drawn incidents), `information` (delayed sensors),
  `player_resources`, `objectives`, `failure_conditions`, `scoring_rules`, optional `tuning`.

Validation rejects unknown fields, bad references, impossible geometry, negative capacities and
unsupported versions; the simulation also checks that nodes sit on walkable ground and every
destination is reachable from every exit. Run `crowd experiments` on a new scenario to see whether
interventions matter and whether one strategy dominates.

## Known limitations

- Only the microscopic level and an aggregate stadium reservoir exist. Mesoscopic corridors and
  macroscopic city flows (the 50,000–1,000,000 targets) are not implemented.
- The risk model is a gameplay approximation (density bands after Still and Fruin plus Helbing's
  crowd-pressure indicator), not a validated crush predictor.
- Calibration covers bottleneck flow only (T = 0.5 s); the speed–density relation of free walking
  was not fitted to a dataset.
- The wasm module is built and checked for determinism in CI (the development sandbox has no wasm
  Rust target); browser performance has not been measured.
- Outcomes vary a lot between seeds: near the tipping point, small differences decide whether a
  queue compresses into a crush. The game always plays the scenario's own seed, so a retry is fair.
- The 30,000-person title-screen option is a performance stress test, not a balanced game.
- One scenario. Content, upgrades, daily challenges and larger maps are future work.
