//! Versioned, data-driven scenario definition and validation.
//!
//! The same JSON file is read by the simulation (all fields) and by the Godot map renderer
//! (geometry, names, decor), so there is exactly one source for each value.

// `!(x > 0.0)` is deliberate in validation: unlike `x <= 0.0` it also rejects NaN.
#![allow(clippy::neg_cmp_op_on_partial_ord)]

use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

pub const SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Scenario {
    pub schema_version: u32,
    pub scenario_id: String,
    pub title: String,
    #[serde(default)]
    pub briefing: String,
    pub seed: u64,
    pub map: MapDef,
    pub nodes: Vec<NodeDef>,
    pub edges: Vec<EdgeDef>,
    pub gates: Vec<GateDef>,
    pub destinations: Vec<DestinationDef>,
    pub population_profiles: Vec<ProfileDef>,
    pub spawn_schedules: Vec<SourceDef>,
    #[serde(default)]
    pub signs: Vec<SignDef>,
    #[serde(default)]
    pub transit_services: Vec<TransitDef>,
    #[serde(default)]
    pub event_schedule: Vec<EventDef>,
    pub player_resources: Resources,
    pub objectives: Objectives,
    pub failure_conditions: FailureConditions,
    pub scoring_rules: ScoringRules,
    #[serde(default)]
    pub information: InformationDef,
    #[serde(default)]
    pub tuning: Tuning,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapDef {
    /// World size in metres.
    pub size: [f32; 2],
    /// Navigation grid cell size in metres.
    pub cell: f32,
    /// Union of walkable rectangles [x, y, w, h].
    pub walkable: Vec<[f32; 4]>,
    /// Extra wall segments [x1, y1, x2, y2] inside walkable space (railings, kiosks).
    #[serde(default)]
    pub walls: Vec<[f32; 4]>,
    /// Named measurement regions used by overlays, explanations and scoring.
    pub areas: Vec<AreaDef>,
    /// Where the player may place temporary barriers.
    #[serde(default)]
    pub barrier_zones: Vec<ZoneDef>,
    /// Presentation-only data for the renderer; ignored by the simulation.
    #[serde(default)]
    pub decor: serde_json::Value,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AreaDef {
    pub id: String,
    pub name: String,
    pub rect: [f32; 4],
    #[serde(default)]
    pub kind: String,
    /// Multiplier on desired speed inside the area (stairs < 1).
    #[serde(default = "one")]
    pub speed_factor: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ZoneDef {
    pub id: String,
    pub rect: [f32; 4],
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NodeDef {
    pub id: String,
    pub pos: [f32; 2],
    /// Arrival radius: an agent heading for this node has reached it inside this distance.
    pub radius: f32,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EdgeDef {
    pub a: String,
    pub b: String,
    /// Traversable only a -> b.
    #[serde(default)]
    pub one_way: bool,
    /// Stairs: penalised by profiles with an accessibility need.
    #[serde(default)]
    pub stairs: bool,
    /// Area whose measured density drives this edge's congestion cost.
    #[serde(default)]
    pub area: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GateDef {
    pub id: String,
    pub name: String,
    /// Node just downstream of the gate line; routes "through the gate" pass this node.
    pub node: String,
    /// Gate line [x1, y1, x2, y2]; agents are held upstream of it until served.
    pub line: [f32; 4],
    pub lanes: u32,
    /// Service rate per lane when metered or acting as a fare gate (persons / s).
    pub lane_rate: f32,
    /// Player-controllable gate (else a fixed service point such as station fare gates).
    #[serde(default)]
    pub controllable: bool,
    /// "open", "metered" or "closed".
    #[serde(default = "open_mode")]
    pub default_mode: String,
    /// Selectable metering levels as fractions of lanes * lane_rate.
    #[serde(default)]
    pub meter_levels: Vec<f32>,
    /// Staff cost per minute while metered.
    #[serde(default)]
    pub staff_cost_per_min: f32,
    /// Agents may cross only downstream (toward the gate node); nobody walks back through.
    #[serde(default)]
    pub one_way: bool,
    /// Scheduled operation: changes applied at fixed times (e.g. a gate that opens at 2:00).
    #[serde(default)]
    pub schedule: Vec<GateScheduleDef>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GateScheduleDef {
    /// Time (s).
    pub at: f32,
    /// "open", "metered" or "closed".
    pub mode: String,
    #[serde(default)]
    pub level: Option<f32>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DestinationDef {
    pub id: String,
    pub name: String,
    pub node: String,
    #[serde(default)]
    pub area: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProfileDef {
    pub id: String,
    pub name: String,
    pub share: f32,
    /// Desired walking speed range (m/s).
    pub speed: [f32; 2],
    /// Knowledge of the network: 0 = first visit, 1 = daily commuter.
    pub familiarity: [f32; 2],
    pub sign_compliance: [f32; 2],
    pub crowd_following: [f32; 2],
    /// Seconds of waiting before an agent reconsiders or loses satisfaction quickly.
    pub patience: [f32; 2],
    #[serde(default = "one_one")]
    pub group_size: [u32; 2],
    /// Extra cost weight on stairs (mobility limits).
    #[serde(default)]
    pub stairs_aversion: f32,
    #[serde(default = "default_radius")]
    pub radius: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SourceDef {
    pub id: String,
    pub name: String,
    /// Total people released by this source.
    pub population: u32,
    /// Release begins at this time (s).
    #[serde(default)]
    pub start: f32,
    pub doors: Vec<DoorDef>,
    /// Destination shares (destination id, weight).
    pub destination_mix: Vec<(String, f32)>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DoorDef {
    pub node: String,
    /// Area where released people appear [x, y, w, h].
    pub spawn: [f32; 4],
    /// Maximum release rate (persons / s), further limited by free space.
    pub rate: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SignDef {
    pub id: String,
    pub name: String,
    pub pos: [f32; 2],
    /// Reading distance (m).
    pub radius: f32,
    /// Id of the message shown at the start.
    pub default_mode: String,
    /// Messages the operator can choose between.
    pub modes: Vec<SignModeDef>,
    #[serde(default)]
    pub change_cost: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SignModeDef {
    pub id: String,
    /// Text shown on the sign and in the UI.
    pub label: String,
    /// "off", "route" (recommend `via` to people bound for `destination`) or "wait_times"
    /// (show the operator's measured wait at each node in `compare`).
    pub kind: String,
    #[serde(default)]
    pub destination: Option<String>,
    #[serde(default)]
    pub via: Option<String>,
    #[serde(default)]
    pub compare: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TransitDef {
    pub id: String,
    pub name: String,
    /// Fare gates that feed the service.
    pub gates: Vec<String>,
    pub destination: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EventDef {
    pub id: String,
    pub name: String,
    /// "service_reduction": multiplies a transit service's fare gate rates by `factor`.
    pub kind: String,
    pub target: String,
    pub factor: f32,
    /// Start time range (s); drawn from the incidents stream.
    pub start: [f32; 2],
    /// Duration range (s).
    pub duration: [f32; 2],
    #[serde(default = "one")]
    pub probability: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Resources {
    pub budget: f32,
    pub barrier_cost: f32,
    pub barrier_max_len: f32,
    pub max_barriers: u32,
    /// Barriers removed within this many seconds of placement are refunded in full.
    #[serde(default = "default_undo")]
    pub undo_window: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Objectives {
    /// Scenario ends at this time even if people remain (s).
    pub time_limit: f32,
    /// Fraction of the population that must reach a destination to win.
    pub clear_fraction: f32,
    /// Average journey time considered good (s).
    pub target_journey: f32,
    /// Longest individual wait considered acceptable (s).
    pub target_max_wait: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FailureConditions {
    /// Run fails once dangerous crowd conditions have lasted this long in total (s).
    pub max_danger_seconds: f32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ScoringRules {
    pub base: f32,
    /// Points lost per second of average journey time above target.
    pub per_journey_second: f32,
    /// Points lost per second of maximum wait above target.
    pub per_wait_second: f32,
    /// Points lost per second of crowded-heavy exposure (summed over areas).
    pub per_heavy_second: f32,
    /// Points lost per second of dangerous exposure.
    pub per_danger_second: f32,
    /// Points lost per currency unit spent.
    pub per_cost: f32,
    /// Points lost per person not delivered by the time limit.
    pub per_stranded: f32,
    /// Points per satisfaction point (0..100 average).
    pub per_satisfaction: f32,
    /// Star thresholds (1, 2, 3).
    pub stars: [f32; 3],
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InformationDef {
    /// Areas whose reported measurements lag the true state (s), e.g. CCTV refresh.
    #[serde(default)]
    pub delayed: Vec<DelayedSensor>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DelayedSensor {
    pub area: String,
    /// Reports refresh every `period` seconds.
    pub period: f32,
}

/// Movement and behaviour constants. Defaults follow the collision-free speed model as documented
/// by JuPedSim (Tordeux et al. 2016); see docs/research.md for what is established vs. tuned.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct Tuning {
    /// Fixed simulation step (s).
    pub dt: f32,
    /// CFSM time gap T (s).
    pub time_gap: f32,
    pub neighbor_strength: f32,
    pub neighbor_range: f32,
    pub wall_strength: f32,
    pub wall_range: f32,
    /// Neighbour search radius (m) = spatial grid cell size.
    pub interaction_radius: f32,
    /// How often an agent reconsiders its route (s).
    pub decision_interval: f32,
    /// Speed below which an agent counts as waiting (m/s).
    pub wait_speed: f32,
    /// Density grid cell size (m).
    pub density_cell: f32,
    /// Distance upstream of a gate line where unserved agents stop (m).
    pub gate_hold: f32,
    /// Extra standing gap kept in orderly queues at metered/fare gates (m).
    pub queue_gap: f32,
}

impl Default for Tuning {
    fn default() -> Self {
        Tuning {
            dt: 0.05,
            time_gap: 0.5,
            neighbor_strength: 8.0,
            neighbor_range: 0.1,
            wall_strength: 5.0,
            wall_range: 0.02,
            interaction_radius: 1.5,
            decision_interval: 4.0,
            wait_speed: 0.25,
            density_cell: 2.0,
            gate_hold: 0.6,
            queue_gap: 0.35,
        }
    }
}

fn one() -> f32 {
    1.0
}
fn one_one() -> [u32; 2] {
    [1, 1]
}
fn default_radius() -> f32 {
    0.2
}
fn default_undo() -> f32 {
    10.0
}
fn open_mode() -> String {
    "open".into()
}

pub const SIGN_KINDS: [&str; 3] = ["off", "route", "wait_times"];
pub const GATE_MODES: [&str; 3] = ["open", "metered", "closed"];

#[derive(Debug, Clone, PartialEq)]
pub struct ValidationError(pub String);

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl Scenario {
    pub fn from_json(text: &str) -> Result<Scenario, ValidationError> {
        let sc: Scenario = serde_json::from_str(text)
            .map_err(|e| ValidationError(format!("scenario JSON: {e}")))?;
        sc.validate()?;
        Ok(sc)
    }

    pub fn node_index(&self, id: &str) -> Option<usize> {
        self.nodes.iter().position(|n| n.id == id)
    }
    pub fn area_index(&self, id: &str) -> Option<usize> {
        self.map.areas.iter().position(|a| a.id == id)
    }

    /// Structural validation: versions, unique ids, references, ranges and geometry bounds.
    /// Walkability of node positions is checked when the navigation grid is built.
    pub fn validate(&self) -> Result<(), ValidationError> {
        let err = |m: String| Err(ValidationError(m));
        if self.schema_version != SCHEMA_VERSION {
            return err(format!(
                "unsupported schema_version {} (expected {SCHEMA_VERSION})",
                self.schema_version
            ));
        }
        let [w, h] = self.map.size;
        if !(w > 0.0 && h > 0.0 && w <= 2000.0 && h <= 2000.0) {
            return err(format!("map.size {:?} out of range", self.map.size));
        }
        if !(0.2..=2.0).contains(&self.map.cell) {
            return err(format!("map.cell {} out of range 0.2..2", self.map.cell));
        }
        if self.map.walkable.is_empty() {
            return err("map.walkable is empty".into());
        }
        let in_map = |r: &[f32; 4]| {
            r[2] > 0.0
                && r[3] > 0.0
                && r[0] >= 0.0
                && r[1] >= 0.0
                && r[0] + r[2] <= w + 1e-3
                && r[1] + r[3] <= h + 1e-3
        };
        let pt_in_map = |p: [f32; 2]| p[0] >= 0.0 && p[1] >= 0.0 && p[0] <= w && p[1] <= h;
        for r in &self.map.walkable {
            if !in_map(r) {
                return err(format!("walkable rect {r:?} is empty or outside the map"));
            }
        }
        for s in &self.map.walls {
            if !pt_in_map([s[0], s[1]]) || !pt_in_map([s[2], s[3]]) {
                return err(format!("wall {s:?} outside the map"));
            }
        }
        unique("area", self.map.areas.iter().map(|a| a.id.as_str()))?;
        for a in &self.map.areas {
            if !in_map(&a.rect) {
                return err(format!("area '{}' rect is empty or outside the map", a.id));
            }
            if !(a.speed_factor > 0.0 && a.speed_factor <= 1.5) {
                return err(format!(
                    "area '{}' speed_factor {} out of range",
                    a.id, a.speed_factor
                ));
            }
        }
        unique(
            "barrier zone",
            self.map.barrier_zones.iter().map(|z| z.id.as_str()),
        )?;
        for z in &self.map.barrier_zones {
            if !in_map(&z.rect) {
                return err(format!("barrier zone '{}' outside the map", z.id));
            }
        }
        unique("node", self.nodes.iter().map(|n| n.id.as_str()))?;
        for n in &self.nodes {
            if !pt_in_map(n.pos) {
                return err(format!("node '{}' outside the map", n.id));
            }
            if !(n.radius > 0.0) {
                return err(format!("node '{}' radius must be positive", n.id));
            }
        }
        let node = |id: &str, what: &str| -> Result<(), ValidationError> {
            if self.node_index(id).is_none() {
                Err(ValidationError(format!(
                    "{what} references unknown node '{id}'"
                )))
            } else {
                Ok(())
            }
        };
        let area = |id: &str, what: &str| -> Result<(), ValidationError> {
            if self.area_index(id).is_none() {
                Err(ValidationError(format!(
                    "{what} references unknown area '{id}'"
                )))
            } else {
                Ok(())
            }
        };
        for e in &self.edges {
            node(&e.a, "edge")?;
            node(&e.b, "edge")?;
            if e.a == e.b {
                return err(format!("edge '{}'-'{}' is a loop", e.a, e.b));
            }
            if let Some(a) = &e.area {
                area(a, "edge")?;
            }
        }
        unique("gate", self.gates.iter().map(|g| g.id.as_str()))?;
        for g in &self.gates {
            node(&g.node, &format!("gate '{}'", g.id))?;
            if g.lanes == 0 || !(g.lane_rate > 0.0) {
                return err(format!(
                    "gate '{}' needs lanes > 0 and a positive lane_rate",
                    g.id
                ));
            }
            if g.staff_cost_per_min < 0.0 {
                return err(format!("gate '{}' has a negative cost", g.id));
            }
            if !GATE_MODES.contains(&g.default_mode.as_str()) {
                return err(format!(
                    "gate '{}' default_mode '{}' unknown",
                    g.id, g.default_mode
                ));
            }
            if !g.controllable && g.default_mode != "metered" {
                return err(format!(
                    "fixed gate '{}' must be 'metered' (a service point)",
                    g.id
                ));
            }
            for sch in &g.schedule {
                if !GATE_MODES.contains(&sch.mode.as_str()) || !(sch.at >= 0.0) || !g.controllable {
                    return err(format!(
                        "gate '{}' schedule entry invalid (mode, time, or gate not controllable)",
                        g.id
                    ));
                }
                if sch.mode == "metered" {
                    let l = sch.level.unwrap_or(1.0);
                    if !g.meter_levels.iter().any(|x| (x - l).abs() < 1e-4) {
                        return err(format!(
                            "gate '{}' schedule level {l} is not one of its meter levels",
                            g.id
                        ));
                    }
                }
            }
            for l in &g.meter_levels {
                if !(*l > 0.0 && *l <= 1.0) {
                    return err(format!("gate '{}' meter level {l} must be in (0, 1]", g.id));
                }
            }
            let a = [g.line[0], g.line[1]];
            let b = [g.line[2], g.line[3]];
            if !pt_in_map(a) || !pt_in_map(b) || ((a[0] - b[0]).abs() + (a[1] - b[1]).abs()) < 0.5 {
                return err(format!(
                    "gate '{}' line is degenerate or outside the map",
                    g.id
                ));
            }
        }
        unique(
            "destination",
            self.destinations.iter().map(|d| d.id.as_str()),
        )?;
        if self.destinations.is_empty() {
            return err("scenario has no destinations".into());
        }
        for d in &self.destinations {
            node(&d.node, &format!("destination '{}'", d.id))?;
            if let Some(a) = &d.area {
                area(a, "destination")?;
            }
        }
        unique(
            "profile",
            self.population_profiles.iter().map(|p| p.id.as_str()),
        )?;
        if self
            .population_profiles
            .iter()
            .map(|p| p.share.max(0.0))
            .sum::<f32>()
            <= 0.0
        {
            return err("population profile shares must sum to more than 0".into());
        }
        for p in &self.population_profiles {
            if p.share < 0.0 {
                return err(format!("profile '{}' has a negative share", p.id));
            }
            for (name, r, lo, hi) in [
                ("speed", p.speed, 0.1, 3.0),
                ("familiarity", p.familiarity, 0.0, 1.0),
                ("sign_compliance", p.sign_compliance, 0.0, 1.0),
                ("crowd_following", p.crowd_following, 0.0, 1.0),
                ("patience", p.patience, 1.0, 7200.0),
            ] {
                if !(r[0] <= r[1] && r[0] >= lo && r[1] <= hi) {
                    return err(format!(
                        "profile '{}' {name} range {r:?} invalid (allowed {lo}..{hi})",
                        p.id
                    ));
                }
            }
            if p.group_size[0] == 0 || p.group_size[0] > p.group_size[1] || p.group_size[1] > 8 {
                return err(format!(
                    "profile '{}' group_size {:?} invalid",
                    p.id, p.group_size
                ));
            }
            if !(0.1..=0.4).contains(&p.radius) {
                return err(format!(
                    "profile '{}' radius {} out of range",
                    p.id, p.radius
                ));
            }
        }
        unique("source", self.spawn_schedules.iter().map(|s| s.id.as_str()))?;
        if self.spawn_schedules.is_empty() {
            return err("scenario has no spawn_schedules".into());
        }
        for s in &self.spawn_schedules {
            if s.doors.is_empty() {
                return err(format!("source '{}' has no doors", s.id));
            }
            for d in &s.doors {
                node(&d.node, &format!("source '{}' door", s.id))?;
                if !in_map(&d.spawn) || !(d.rate > 0.0) {
                    return err(format!("source '{}' door spawn/rate invalid", s.id));
                }
            }
            if s.destination_mix.is_empty() || s.destination_mix.iter().any(|(_, w)| *w < 0.0) {
                return err(format!("source '{}' destination_mix invalid", s.id));
            }
            for (d, _) in &s.destination_mix {
                if !self.destinations.iter().any(|x| &x.id == d) {
                    return err(format!(
                        "source '{}' references unknown destination '{d}'",
                        s.id
                    ));
                }
            }
            if s.start < 0.0 {
                return err(format!("source '{}' start must be >= 0", s.id));
            }
        }
        unique("sign", self.signs.iter().map(|s| s.id.as_str()))?;
        for s in &self.signs {
            if !pt_in_map(s.pos) || !(s.radius > 0.0) || s.change_cost < 0.0 {
                return err(format!("sign '{}' position/radius/cost invalid", s.id));
            }
            unique(
                &format!("sign '{}' mode", s.id),
                s.modes.iter().map(|m| m.id.as_str()),
            )?;
            if !s.modes.iter().any(|m| m.id == s.default_mode) {
                return err(format!(
                    "sign '{}' default_mode '{}' is not one of its modes",
                    s.id, s.default_mode
                ));
            }
            for m in &s.modes {
                if !SIGN_KINDS.contains(&m.kind.as_str()) {
                    return err(format!(
                        "sign '{}' mode '{}' kind '{}' unknown",
                        s.id, m.id, m.kind
                    ));
                }
                if m.kind == "route" {
                    let (Some(d), Some(v)) = (&m.destination, &m.via) else {
                        return err(format!(
                            "sign '{}' route mode '{}' needs destination and via",
                            s.id, m.id
                        ));
                    };
                    if !self.destinations.iter().any(|x| &x.id == d) {
                        return err(format!(
                            "sign '{}' mode '{}' unknown destination '{d}'",
                            s.id, m.id
                        ));
                    }
                    node(v, &format!("sign '{}' mode '{}'", s.id, m.id))?;
                }
                if m.kind == "wait_times" {
                    if m.compare.len() < 2 {
                        return err(format!(
                            "sign '{}' wait_times mode needs 2+ nodes to compare",
                            s.id
                        ));
                    }
                    for c in &m.compare {
                        node(c, &format!("sign '{}' mode '{}'", s.id, m.id))?;
                    }
                }
            }
        }
        unique(
            "transit service",
            self.transit_services.iter().map(|t| t.id.as_str()),
        )?;
        for t in &self.transit_services {
            for g in &t.gates {
                if !self.gates.iter().any(|x| &x.id == g) {
                    return err(format!("transit '{}' references unknown gate '{g}'", t.id));
                }
            }
            if !self.destinations.iter().any(|d| d.id == t.destination) {
                return err(format!("transit '{}' references unknown destination", t.id));
            }
        }
        unique("event", self.event_schedule.iter().map(|e| e.id.as_str()))?;
        for e in &self.event_schedule {
            if e.kind != "service_reduction" {
                return err(format!("event '{}' kind '{}' unsupported", e.id, e.kind));
            }
            if !self.transit_services.iter().any(|t| t.id == e.target) {
                return err(format!(
                    "event '{}' targets unknown transit service '{}'",
                    e.id, e.target
                ));
            }
            if !(e.factor >= 0.0 && e.factor <= 1.0)
                || e.start[0] > e.start[1]
                || e.duration[0] > e.duration[1]
                || e.start[0] < 0.0
                || e.duration[0] <= 0.0
            {
                return err(format!("event '{}' factor/start/duration invalid", e.id));
            }
        }
        for d in &self.information.delayed {
            area(&d.area, "information.delayed")?;
            if !(d.period > 0.0) {
                return err("information.delayed period must be positive".into());
            }
        }
        let r = &self.player_resources;
        if r.budget < 0.0 || r.barrier_cost < 0.0 || !(r.barrier_max_len > 0.5) {
            return err("player_resources has a negative value or tiny barrier_max_len".into());
        }
        let o = &self.objectives;
        if !(o.time_limit > 0.0) || !(o.clear_fraction > 0.0 && o.clear_fraction <= 1.0) {
            return err("objectives time_limit/clear_fraction invalid".into());
        }
        if !(self.failure_conditions.max_danger_seconds > 0.0) {
            return err("failure_conditions.max_danger_seconds must be positive".into());
        }
        let t = &self.tuning;
        if !(t.dt >= 0.01 && t.dt <= 0.2)
            || !(t.time_gap > 0.0)
            || !(t.interaction_radius >= 0.5)
            || !(t.density_cell >= 0.5)
        {
            return err("tuning values out of range".into());
        }
        Ok(())
    }
}

fn unique<'a>(what: &str, ids: impl Iterator<Item = &'a str>) -> Result<(), ValidationError> {
    let mut seen = BTreeSet::new();
    for id in ids {
        if id.is_empty() {
            return Err(ValidationError(format!("{what} with an empty id")));
        }
        if !seen.insert(id) {
            return Err(ValidationError(format!("duplicate {what} id '{id}'")));
        }
    }
    Ok(())
}
