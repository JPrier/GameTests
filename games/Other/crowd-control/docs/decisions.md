# Architecture decisions

Short records of the choices that shape the code. Each says what was decided, why, and how it is
checked. Measurements are from `docs/benchmarks/` and `docs/research.md`.

## ADR 1: One Rust simulation core, two engine bindings

**Decision.** The simulation is a plain Rust library (`sim/crates/core`) with no engine types. Godot
reaches it through a GDExtension (`crates/gdext`, desktop and headless tests) or a wasm32 module
(`crates/wasm`, browsers) via `JavaScriptBridge`. Both bindings wrap the same `Session` API, which
takes and returns JSON text plus two binary buffers (render data, density image).

**Why.** The spec asks for a Rust core independent of the scene tree and a headless harness. GameTests
ships to the web on GitHub Pages, where a Rust GDExtension would need dlink web templates, an
Emscripten toolchain pinned to Godot's, and cross-origin isolation headers Pages cannot send. A
`wasm32-unknown-unknown` module with a C ABI needs none of that and keeps the browser build
single-threaded.

**Cost.** Two thin bindings and one JS glue file (`web/crowd_glue.js`). JavaScriptBridge passes only
strings and numbers into JS, so inputs are JSON strings; outputs come back as `Uint8Array`, which
`JavaScriptBridge.eval` converts to `PackedByteArray` (verified in Godot 4.7.2's
`javascript_bridge_singleton.cpp` and in the browser build with a stand-in module).

**Checked by.** `tests/test_main.gd` (native), the browser build with `tools/standin/`, and CI's
native-vs-wasm checksum comparison (`tools/wasm_check.mjs`).

**Was Rust worth it?** A GDScript port of just the neighbour/CFSM inner loop
(`tools/gdscript_baseline.gd`) is measured in `docs/research.md`: it is far slower than the whole
Rust step, so the 1,000-5,000 person targets are only realistic with the native core.

## ADR 2: Collision-free speed model, calibrated

**Decision.** Local movement follows JuPedSim's collision-free speed model (Tordeux et al. 2016):
direction = desired direction + exponential neighbour and wall repulsion; speed = min(v0, spacing / T)
where spacing is the gap to the nearest person ahead inside one body width. Positions update with
a Jacobi step (all agents read the previous state). Walls enter only the direction term, as in
JuPedSim, plus a hard collision pass that keeps bodies out of walls.

**Calibration.** With JuPedSim's default T = 1 s, the 1 m bottleneck reference test discharged only
0.87 p/m/s against 1.6-2.0 p/m/s measured by Seyfried et al. (2007). A sweep of T (behaviour test
`calibrate_time_gap`) gave 1.45 p/m/s at T = 0.5 s (2.05 p/m/s for 1.6 m), so T = 0.5 s is the
default.

**Additions (gameplay approximations, labelled in code).** A keep-right bias for head-on encounters
(breaks the symmetric deadlock of the pure model and produces lanes); a queue-discipline gap of
0.35 m for people knowingly waiting at a metered or fare gate (managed queues keep personal space);
group cohesion (shared pace, leader waits, followers catch up).

## ADR 3: Hierarchical routing: node graph for choice, distance fields for paths

**Decision.** Global route *choice* runs on a small infrastructure graph (doors, gates, station
entrances, destinations). Getting to the next node uses one geodesic distance field per node
(8-connected Dijkstra on a 0.5 m grid), shared by everyone heading there. Edge lengths are read from
those fields, so a barrier or closed gate that cuts a connection lengthens or breaks the edge with
no separate graph edit.

**Route cost** per person: travel time with crowding (Weidmann speed-density on visible areas),
queue waits they can see or were told on a sign, stairs aversion, uncertainty for unfamiliar people
on unseen legs, a sign bonus, a herding bonus (share of nearby people choosing an option), a
commitment bonus, and a backtracking penalty for turning around against the flow. Cost-to-go is a
reverse Dijkstra over non-negative costs; the bonuses apply once per first-hop candidate.

**Waypoints** are passed by progress (geodesically closer to the following node than the waypoint
is), not only by touching them; a crowded passage waypoint was otherwise unreachable and caused
milling (found by the strategy experiments, fixed, and covered by the stadium tests).

## ADR 4: Hybrid fidelity starts at the stadium doors

**Decision.** People inside the stadium are an aggregate reservoir per source; they become
microscopic agents when released through an exit, at the exit's rate and only when there is room to
step out. Fidelity does not depend on the camera. The diagnostics panel lists both regions and their
counts.

**Why.** It is the simplest hybrid boundary that is exactly conservative (`inside + on site + home =
total` is asserted every tick in tests) and gives realistic back-pressure: a congested plaza slows
the stadium's emptying. Mesoscopic corridors and macroscopic district flows are future work; the
`fidelity` telemetry entry is where new levels would report.

## ADR 5: Rendering: one MultiMesh, data channels, interpolation in the shader

**Decision.** Rust writes a buffer in Godot's 2D MultiMesh layout (transform + colour + custom data,
16 floats per person). Colour and custom channels carry *data* (destination, profile, state, stress,
last movement, heading), and `shaders/crowd.gdshader` maps them to colours and draws a top-down
figure. The shader interpolates between 20 Hz ticks from the movement delta, so the buffer only
changes when the simulation ticks. Far zoom switches to dots and the density heat layer.

**Why.** No per-person nodes; one buffer upload per tick; overlay modes are uniforms, so they cannot
alter the simulation (`overlays_and_queries_do_not_change_state` test). The MultiMesh needs a custom
AABB covering the map, or Godot culls the whole crowd whenever the origin leaves the screen (found in
a close-zoom screenshot).

## ADR 6: Determinism and replay

**Decision.** State is reproducible from scenario + seed + simulation version + tick-stamped
commands. Rules: separate seeded SplitMix64 streams per concern (arrivals, traits, incidents,
decisions, presentation); deterministic iteration (vectors, sorted service order, no hash maps in
the sim); Jacobi movement; only IEEE basic operations from hardware and `libm` for `exp`/`atan2`; no
fused multiply-add. A checksum is recorded every 100 ticks.

**Guarantee.** Same build: bit-identical (tested, including a tampered-replay test). Native x86_64
vs wasm32: designed to be identical and compared in CI.

## ADR 7: Barrier and gate changes rebuild fields over a few ticks

**Decision.** A geometry change marks every distance field dirty; the sim rebuilds three per tick
(about 2.5 ms each natively) and refreshes graph edges when all are done. Walls take effect
physically at once, so nobody walks through a new barrier while their field is stale; every agent
reconsiders its route right after the rebuild. Placement is refused if it would cut any person or
exit off from their destination (flood fill on the candidate geometry).

**Why not incremental repair.** A full rebuild of all 11 fields measured 26-35 ms natively, so
amortising it removes the hitch without the complexity of localised repair. Revisit for city-scale
maps.

## ADR 8: Imperfect information as a mechanic

**Decision.** Station halls are watched by a camera feed that refreshes every 30 s. The operator's
panels, map labels, explanation panel and the wait-time signs all use the reported values; the true
values are a debug toggle. Sign readers act on the numbers posted when they read the sign.

## ADR 9: Validation layers

Rust unit tests; ten behavioural reference geometries with numeric expectations; property tests on
randomised worlds (conservation, containment, service-rate bounds, no unserved crossings, closed
gates); replay round trips; Godot tests that drive the real simulation through the UI functions;
screenshot checkpoints with tolerant comparison; benchmarks against a baseline; scripted strategy
experiments that flag dominant strategies.
