//! Read-only views of the simulation for the game: telemetry, render buffers, explanations.
//! Nothing here mutates simulation state, so toggling overlays can never change the outcome.

use crate::agents::{State, NONE16, NONE32};
use crate::math::Vec2;
use crate::metrics::Level;
use crate::sim::{GateMode, Sim};
use serde_json::{json, Value};

/// Floats per agent in the render buffer: Godot's 2D MultiMesh layout with colours and custom data.
pub const FLOATS_PER_AGENT: usize = 16;

fn level_name(l: u8) -> &'static str {
    match l {
        0 => "comfortable",
        1 => "crowded",
        2 => "heavy",
        _ => "danger",
    }
}

impl Sim {
    /// Godot `MultiMesh` buffer (transform 2D + colour + custom data per instance):
    ///   transform: [scale, 0, 0, x, 0, scale, 0, y]
    ///   colour:    [destination / 8, profile / 8, state / 4, stress 0..1]   (decoded by the shader)
    ///   custom:    [(x - prev x) / scale, (y - prev y) / scale, heading angle, stable hash 0..1]
    /// (the motion delta is in the quad's local units so the shader can interpolate between ticks)
    /// The shader maps the data channels to colours, so overlay modes never need a new buffer.
    pub fn render_buffer(&self, out: &mut Vec<f32>) {
        let n = self.agents.len();
        out.clear();
        out.reserve(n * FLOATS_PER_AGENT);
        let a = &self.agents;
        for i in 0..n {
            let p = a.pos[i];
            let d = p - a.prev[i];
            let s = a.radius[i] * 2.0;
            let stress = (a.wait_now[i] / a.patience[i].max(1.0))
                .min(1.0)
                .max(1.0 - a.satisfaction[i] / 100.0);
            let h = a.heading[i];
            let hash = ((a.id[i].wrapping_mul(2_654_435_761)) >> 8) as f32 / 16_777_216.0;
            out.extend_from_slice(&[
                s,
                0.0,
                0.0,
                p.x,
                0.0,
                s,
                0.0,
                p.y,
                a.dest[i] as f32 / 8.0,
                a.profile[i] as f32 / 8.0,
                a.state[i] as u8 as f32 / 4.0,
                stress,
                d.x / s,
                d.y / s,
                crate::math::atan2(h.y, h.x),
                hash,
            ]);
        }
    }

    /// RGBA8 image of the density grid: R = density (x50, 5.1 p/m² = 255), G = level (x85),
    /// B/A = smoothed flow velocity (x60 + 128).
    pub fn density_image(&self, out: &mut Vec<u8>) {
        let g = &self.density;
        out.clear();
        out.reserve(g.cols * g.rows * 4);
        for i in 0..g.cols * g.rows {
            let d = (g.density[i] * 50.0).round().clamp(0.0, 255.0) as u8;
            let l = g.level[i] as u8 * 85;
            let fx = (g.flow[i].x * 60.0 + 128.0).round().clamp(0.0, 255.0) as u8;
            let fy = (g.flow[i].y * 60.0 + 128.0).round().clamp(0.0, 255.0) as u8;
            out.extend_from_slice(&[d, l, fx, fy]);
        }
    }

    pub fn density_dims(&self) -> (usize, usize, f32) {
        (self.density.cols, self.density.rows, self.density.cell)
    }

    /// Compact state for the operations UI (about 4 times per second).
    pub fn telemetry(&self, since_log: usize) -> Value {
        let gates: Vec<Value> = self
            .gates
            .iter()
            .map(|g| {
                let reported = !self.perfect_info && (g.area as usize) < self.areas.len() && self.reported[g.area as usize].delayed;
                let wait = if reported { self.reported_wait(g.node) } else { g.wait_estimate() };
                json!({
                    "id": g.id, "name": g.name, "controllable": g.controllable,
                    "mode": match g.mode { GateMode::Open => "open", GateMode::Metered => "metered", GateMode::Closed => "closed" },
                    "level": g.level, "levels": g.meter_levels,
                    "rate_pm": if g.rate().is_finite() { g.rate() * 60.0 } else { -1.0 },
                    "flow_pm": g.passed.per_minute(),
                    "queue": if reported { -1 } else { g.queue as i64 },
                    "wait": wait, "delayed": reported,
                    "service_factor": g.service_factor,
                    "staff_cost_per_min": g.staff_cost_per_min,
                })
            })
            .collect();
        let areas: Vec<Value> = (0..self.areas.len())
            .map(|i| {
                let a = &self.areas[i];
                let r = &self.reported[i];
                let delayed = r.delayed && !self.perfect_info;
                json!({
                    "id": self.area_ids[i], "name": self.area_names[i],
                    "occupancy": if delayed { r.occupancy } else { a.occupancy },
                    "density": if delayed { r.density } else { a.density },
                    "level": level_name(if delayed { r.level } else { a.level as u8 }),
                    "age": if delayed { self.time - r.at } else { 0.0 },
                    "delayed": delayed,
                    "in_pm": a.inflow.per_minute(), "out_pm": a.outflow.per_minute(),
                })
            })
            .collect();
        let signs: Vec<Value> = self
            .signs
            .iter()
            .map(|s| {
                let m = &s.modes[s.mode];
                json!({"id": s.id, "name": s.name, "mode": m.id, "label": m.label, "reads": s.reads,
                       "modes": s.modes.iter().map(|m| json!({"id": m.id, "label": m.label})).collect::<Vec<_>>(),
                       "shown": s.shown_waits, "cost": s.change_cost})
            })
            .collect();
        let incidents: Vec<Value> = self.incidents.iter().filter(|e| e.active).map(|e| json!({"id": e.id, "name": e.name, "ends_in": e.start + e.duration - self.time})).collect();
        let log: Vec<Value> = self
            .log
            .iter()
            .skip(since_log)
            .map(|e| serde_json::to_value(e).unwrap())
            .collect();
        let (res, active, done, total) = self.population_balance();
        let mut heading = serde_json::Map::new();
        let mut counts = vec![0u32; self.graph.nodes.len()];
        for i in 0..self.agents.len() {
            let nn = self.agents.next_node(i);
            if (nn as usize) < counts.len() {
                counts[nn as usize] += 1;
            }
        }
        for (k, n) in self.graph.nodes.iter().enumerate() {
            heading.insert(n.id.clone(), json!(counts[k]));
        }
        json!({
            "heading": heading,
            "tick": self.tick, "time": self.time, "outcome": self.outcome,
            "population": {"inside": res, "active": active, "completed": done, "total": total},
            "by_dest": self.dest_ids.iter().zip(&self.completed_by_dest).map(|(d, c)| json!({"id": d, "completed": c})).collect::<Vec<_>>(),
            "budget": self.sc.player_resources.budget, "spent": self.spent, "staff": self.staff_spent,
            "danger_seconds": self.danger_seconds, "heavy_seconds": self.heavy_seconds,
            "danger_limit": self.sc.failure_conditions.max_danger_seconds,
            "time_limit": self.sc.objectives.time_limit,
            "gates": gates, "areas": areas, "signs": signs, "incidents": incidents,
            "barriers": self.barriers,
            "log": log, "log_len": self.log.len(),
            "fields_pending": self.fields_pending(),
            "perfect_info": self.perfect_info,
            "fidelity": [
                {"region": "Stadium bowl", "model": "aggregate reservoir (released through exits at capacity)", "count": res},
                {"region": "Exterior", "model": "microscopic collision-free speed model", "count": active}
            ],
        })
    }

    /// Causal indicators for one area, from telemetry and the event log only.
    pub fn explain(&self, area_id: &str) -> Value {
        let Some(ai) = self.area_ids.iter().position(|a| a == area_id) else {
            return json!({"error": "unknown area"});
        };
        let a = &self.areas[ai];
        let rep = &self.reported[ai];
        let delayed = rep.delayed && !self.perfect_info;
        let mut lines: Vec<String> = Vec::new();
        let inflow = a.inflow.per_minute();
        let outflow = a.outflow.per_minute();
        if delayed {
            lines.push(format!(
                "Camera feed: data is {:.0} s old",
                self.time - rep.at
            ));
        }
        if inflow > outflow + 10 {
            lines.push(format!(
                "Filling up: {} arrive per minute but only {} leave",
                inflow, outflow
            ));
        } else if outflow > inflow + 10 {
            lines.push(format!(
                "Clearing: {} leave per minute, {} arrive",
                outflow, inflow
            ));
        }
        // limiting downstream component: gates whose queue sits in this area, then crowded
        // areas on edges that leave it
        let mut limiting: Option<String> = None;
        // gates at the end of walkways measured by this area, or physically inside it
        let feeds = |g: &crate::sim::Gate| -> bool {
            g.area as usize == ai
                || self
                    .graph
                    .edges
                    .iter()
                    .any(|e| e.area == Some(ai as u8) && e.b == g.node)
        };
        let mut gates: Vec<&crate::sim::Gate> = self
            .gates
            .iter()
            .filter(|g| feeds(g) && g.queue > 0)
            .collect();
        gates.sort_by_key(|g| std::cmp::Reverse(g.queue));
        if let Some(g) = gates.first() {
            let r = g.rate();
            // behind a delayed camera feed the operator sees no live queue count
            let waiting = if delayed {
                String::new()
            } else {
                format!(" ({} waiting)", g.queue)
            };
            limiting = Some(match g.mode {
                GateMode::Closed => format!("{} is closed", g.name),
                GateMode::Metered if g.service_factor < 1.0 => format!(
                    "{} is slowed to {:.0}/min by an incident{waiting}",
                    g.name,
                    r * 60.0
                ),
                GateMode::Metered => format!(
                    "{} lets {:.0} people through per minute{waiting}",
                    g.name,
                    r * 60.0
                ),
                GateMode::Open => format!("{}{waiting}", g.name),
            });
        }
        if limiting.is_none() {
            let mut worst: Option<(usize, f32)> = None;
            for e in &self.graph.edges {
                let from_here = self.graph.nodes[e.a as usize].pos;
                if self.areas[ai].rect.contains(from_here) {
                    if let Some(da) = e.area {
                        let da = da as usize;
                        if da != ai
                            && self.areas[da].density > 1.5
                            && worst.map(|w| self.areas[da].density > w.1).unwrap_or(true)
                        {
                            worst = Some((da, self.areas[da].density));
                        }
                    }
                }
            }
            if let Some((da, d)) = worst {
                limiting = Some(format!(
                    "{} downstream is congested ({:.1} people/m²)",
                    self.area_names[da], d
                ));
            }
        }
        if limiting.is_none() && a.density > 1.5 {
            limiting = Some(
                "The space itself: people are arriving faster than this walkway carries them"
                    .into(),
            );
        }
        let recent: Vec<Value> = self
            .log
            .iter()
            .rev()
            .filter(|e| {
                self.time - e.t <= 180.0
                    && matches!(
                        e.kind.as_str(),
                        "gate" | "incident" | "incident_end" | "barrier" | "sign"
                    )
            })
            .take(5)
            .map(|e| json!({"t": e.t, "text": e.text}))
            .collect();
        json!({
            "id": area_id, "name": self.area_names[ai],
            "occupancy": if delayed { rep.occupancy } else { a.occupancy },
            "density": if delayed { rep.density } else { a.density },
            "level": level_name(if delayed { rep.level } else { a.level as u8 }),
            "arrivals_pm": inflow, "departures_pm": outflow,
            "mean_speed": a.mean_speed,
            "limiting": limiting,
            "notes": lines,
            "recent": recent,
            "heavy_seconds": a.heavy_seconds, "danger_seconds": a.danger_seconds,
        })
    }

    /// Debug inspector: the person nearest to `p` (within 3 m).
    pub fn inspect(&self, p: Vec2) -> Value {
        let mut best = (usize::MAX, 9.0f32);
        for i in 0..self.agents.len() {
            let d = (self.agents.pos[i] - p).len_sq();
            if d < best.1 {
                best = (i, d);
            }
        }
        if best.0 == usize::MAX {
            return json!(null);
        }
        let i = best.0;
        let a = &self.agents;
        let route: Vec<String> = (a.route_pos[i]..a.route_len[i])
            .map(|k| self.graph.nodes[a.route[i][k as usize] as usize].id.clone())
            .collect();
        let leader = a.leader[i];
        json!({
            "id": a.id[i],
            "profile": self.sc.population_profiles[a.profile[i] as usize].name,
            "destination": self.dest_names[a.dest[i] as usize],
            "route": route,
            "state": match a.state[i] { State::Walking => "walking", State::Holding => "held at gate", State::Slowed => "slowed", State::Stuck => "no route" },
            "speed": a.speed[i], "desired_speed": a.desired_speed[i],
            "wait": a.wait_total[i], "patience": a.patience[i],
            "satisfaction": a.satisfaction[i],
            "familiarity": a.familiarity[i], "sign_compliance": a.sign_compliance[i], "crowd_following": a.crowd_following[i],
            "sign_advice": if a.sign_via[i] != NONE16 { json!(self.graph.nodes[a.sign_via[i] as usize].id) } else { json!(null) },
            "group": if leader == a.id[i] { json!("leader or alone") } else if self.slot_of[leader as usize] != NONE32 { json!(format!("follows #{leader}")) } else { json!("leader already left") },
            "pos": [a.pos[i].x, a.pos[i].y],
        })
    }

    /// Per-system timing summary (ms per tick).
    pub fn timing_report(&self) -> Value {
        let t = &self.timings;
        let k = if t.ticks > 0 {
            1000.0 / t.ticks as f64
        } else {
            0.0
        };
        json!({
            "ticks": t.ticks,
            "fields_ms": t.fields * k, "spawn_ms": t.spawn * k, "neighbor_index_ms": t.neighbor_index * k,
            "decisions_ms": t.decisions * k, "movement_ms": t.movement * k, "density_ms": t.density * k,
        })
    }

    /// Worst (highest) area level, for the HUD.
    pub fn worst_level(&self) -> Level {
        self.areas
            .iter()
            .map(|a| a.level)
            .max()
            .unwrap_or(Level::Comfortable)
    }
}
