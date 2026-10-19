# Research notes

What the simulation rests on, what is an approximation, and what was measured. Sources were read
from primary documents (JuPedSim source at commit 6d559df2, Godot 4.7.2 source, papers); see the
links at the end.

## Research table

| Topic | Established finding | Chosen approximation | Implementation assumption | Measured here | Unresolved |
|---|---|---|---|---|---|
| Local movement | JuPedSim CFSM: direction = e0 + Σ a·exp((l−d)/D)·n over neighbours and walls; speed = min(v0, max(0, s/T)), s = gap to nearest neighbour ahead within one body width (Tordeux et al. 2016). Defaults T 1 s, a 8, D 0.1 m, walls 5 / 0.02 m, r 0.2 m. | Same equations and defaults except T. Jacobi update. | Neighbour cutoff 1.5 m (JuPedSim uses 3 m): beyond it repulsion is < 2·10⁻⁴ and spacing cannot bind. | `straight_corridor_free_flow`, `intersecting_streams_cross` pass. | Anticipation (AVM) not implemented. |
| Bottleneck capacity | Specific flow ≈ 1.6–2.0 p/m/s for 0.8–1.2 m doors; total flow grows ~linearly with width (Seyfried et al. 2007). | Calibrate T to match. | Calibration on one geometry (10 m room → door → corridor). | T sweep: 1.0 s → 0.87 p/m/s; 0.8 → 0.98; 0.6 → 1.19; **0.5 → 1.45** (1.6 m door: 2.05); 0.4 → 1.65. T = 0.5 s chosen. | Free-flow speed–density curve not fitted to data. |
| Speed–density | Weidmann (1993): v = v_f[1 − exp(−1.913(1/ρ − 1/5.4))]. | Used for route-choice estimates of travel time through visible crowded areas. | Movement itself does not use it (CFSM produces its own relation). | — | Agreement of CFSM's emergent relation with Weidmann not measured. |
| Counterflow | Bidirectional flow reduces capacity at high density; lanes form spontaneously in experiments. | Keep-right bias term added for head-on encounters (pure CFSM deadlocks symmetric head-on pairs). | Bias strength 0.5 × repulsion. | 160 people in a 4 m corridor, saturated demand: counterflow 54.5 s mean journey vs 44.4 s one-way (+23%). Below saturation the difference vanishes. | Bias is ad hoc, not from a published model. |
| Queues | Managed queues keep personal space (Fruin queue LOS C–D ≈ 1.1–1.5 p/m²); crushes come from uncontrolled pressure. | People knowingly waiting at a metered/fare gate keep an extra 0.35 m gap. | Applies within 30 m upstream of the line. | Without it, metering produced crushes at the hold line in experiments. | Gap value is a design choice. |
| Danger | Still: 2 p/m² usual event assessment level, ~4 moving queue limit, 5 standing; Helbing et al. 2007: turbulence when density × velocity variance > 0.02 s⁻². | Levels: crowded ≥ 1, heavy ≥ 2, dangerous ≥ 4.5 p/m² or (≥ 3 and pressure ≥ 0.02); smoothed over 1.5 s on 2 m cells; an area is heavy/dangerous with ≥ 3/≥ 2 such cells. | Area-level seconds drive score and failure. | Peaks 4–5 p/m² in jammed walkways. | Not a validated crush predictor; thresholds are gameplay settings. |
| Route choice | People herd, follow signs unevenly, prefer familiar and visible routes, rarely turn back. Re-decision frequency in real crowds is not well established. | Cost per person: time (with crowding they can see), visible/posted waits, stairs, uncertainty, sign bonus × compliance, herding bonus × crowd-following × share nearby, commitment, backtracking penalty. | Weights are constants in `routing.rs`. | Signage test: share via the recommended route 0.50 → 0.94. Backtracking was the main source of walkway crushes before the penalty. Outcomes depend strongly on the re-decision interval (see below). | Weights not fitted to observed route data; re-decision interval is the largest sensitivity. |
| Groups | Groups walk at a common pace and regroup. | Shared (slowest) pace, leader waits if a member is > 3 m behind, followers catch up. | Members spawn together. | `groups_stay_together`: mean member–leader distance < 3 m. | No formations. |
| Hybrid levels | HyPedSim and similar couple micro/meso regions with conservation at interfaces. | Stadium interior as an aggregate count released at exit capacity when there is room. | Fidelity never depends on the camera. | Conservation asserted every tick. | No meso/macro implementation yet. |
| Determinism | IEEE basic operations are bit-identical across x86_64 and wasm32; libm differs by platform. | `libm` crate for exp/atan2; no FMA; ordered iteration. | Same build ⇒ identical; cross-platform designed identical. | Replay round trip + tamper test pass. | Native vs wasm compared in CI only (no wasm target in the dev sandbox). |

## Research questions (spec §29)

| Question | Answer and evidence |
|---|---|
| Is Rust worth the integration complexity? | Yes. A plain GDScript version of only the CFSM inner loop (`tools/gdscript_baseline.gd`) costs 6.8 ms/tick for 700 people and 69 ms/tick for 3,000 (over the 50 ms budget); the full Rust step costs ~0.2 ms (≈660 people) and ~1.6 ms p50 at 5,000 population (≈4,300 simultaneously on site). |
| Which local movement model works best? | CFSM, calibrated (T = 0.5 s), plus the documented additions above; it passes all ten reference geometries. The anticipation model was not implemented. |
| Is the simulation rate sufficient? | 20 Hz. See the timestep table: outcomes at 10/20/30 Hz are close, there are no body overlaps at any rate, and 20 Hz costs half of 30 Hz. 10 Hz is viable but makes motion coarser for interpolation. |
| What spatial index is best? | Uniform grid, cell = cutoff (1.5 m), rebuilt by counting sort each tick: 0.01–0.02 ms at 5,000 population, negligible next to movement (~1.5–3 ms). No alternative was worth benchmarking. |
| How often should agents reconsider routes? | Every 4 s (with commitment and backtracking penalties). Cost hardly depends on it; outcomes do: 1–4 s behave alike, 8–16 s remove most surges (interval table). This sensitivity is listed as the main open uncertainty. |
| Does MultiMesh provide the best rendering path? | One MultiMesh with a buffer written in Rust (0.02 ms for 660 people, 0.09 ms at ~4,300) and a shader that interpolates; per-person nodes are excluded by design. Other paths were not benchmarked. |
| How can barriers update navigation efficiently? | Full field rebuild amortised over ticks (all 11 fields: 25–36 ms natively, 3 per tick); walls act physically at once. Localised repair not needed at this scale. |
| Where should aggregation begin? | At the venue exits (aggregate inside, microscopic outside), where it is exact and gives back-pressure. |
| Can hybrid models preserve realistic queues? | The stadium reservoir preserves population and releases at exit capacity only into free space; corridor-level meso models are not implemented. |
| How should safety be calculated? | Density bands plus crowd pressure on smoothed 2 m cells, aggregated per area with minimum cell counts; failure after 90 s of dangerous crowding. |
| What browser population is practical? | Not measured (no wasm build in the sandbox). The browser path was exercised with a stand-in module; real-module performance in browsers is open. |
| Does deterministic replay work across platforms? | Same build: yes (tests). x86_64 vs wasm32: checked by CI on every change. |

## Timestep study (no action, 3 seeds)

| dt (s) | rate | avg journey s | danger s | heavy s | overlapping pairs/tick | ms per sim-second | delivered |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.100 | 10 Hz | 147.1 | 78.8 | 113.6 | 0.00 | 2.62 | 877 |
| 0.050 | 20 Hz | 146.1 | 78.9 | 117.3 | 0.00 | 4.76 | 869 |
| 0.033 | 30 Hz | 144.0 | 78.4 | 115.7 | 0.00 | 6.47 | 865 |

"Delivered" is below 1,000 because the no-action runs end early on dangerous crowding. Outcomes barely move between 10, 20 and 30 Hz, no bodies overlap at any rate, and cost scales with the rate, so 20 Hz is kept (smooth interpolated motion, half the cost of 30 Hz).

## Route reconsideration interval (no action, 3 seeds)

| interval (s) | avg journey s | danger s | heavy s | ms per sim-second |
|---:|---:|---:|---:|---:|
| 1 | 145.8 | 80.2 | 125.7 | 5.01 |
| 2 | 145.7 | 80.3 | 119.4 | 5.02 |
| 4 | 146.1 | 78.9 | 117.3 | 4.52 |
| 8 | 153.9 | 59.7 | 144.0 | 4.07 |
| 16 | 155.4 | 0.3 | 81.3 | 3.65 |

This is the model's largest sensitivity. Reconsidering every 1-4 s gives similar results; at 8-16 s people mostly commit to their first choice, the surges toward whichever queue looks shorter disappear, and the no-action run rarely reaches danger. 4 s is kept because people do watch the crowd around them, and these surges are what the wait-time signs and metering are for, but the real-world rate is unknown.

## Sources

- JuPedSim collision-free speed model: https://github.com/PedestrianDynamics/jupedsim (libsimulator/src/operational_models/collision_free_speed_model/)
- Tordeux, Chraibi, Seyfried (2016), Collision-free speed model: https://arxiv.org/abs/1512.05597
- Seyfried et al. (2007), bottleneck flow: https://arxiv.org/abs/physics/0702004
- Weidmann parameters (via): https://arxiv.org/abs/1512.01426
- Fruin levels of service: https://www.fhwa.dot.gov/publications/research/safety/pedbike/98107/section3.cfm
- Still, crowd densities: https://gkstill.com/Support/crowd-density/CrowdDensity-1.html
- Helbing, Johansson, Al-Abideen (2007), crowd turbulence: https://arxiv.org/abs/physics/0701203
- Godot 4.7.2 JavaScriptBridge: https://github.com/godotengine/godot/blob/4.7.2-stable/platform/web/javascript_bridge_singleton.cpp
- HyPedSim: https://pmc.ncbi.nlm.nih.gov/articles/PMC10934890/
