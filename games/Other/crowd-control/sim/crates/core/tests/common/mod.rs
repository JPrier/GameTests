//! Builders for small test scenarios (the behavioural reference geometries).
#![allow(dead_code)]

use crowd_core::sim::{LoadOptions, Sim};
use crowd_core::Scenario;
use serde_json::{json, Value};

pub struct Spec {
    pub size: [f32; 2],
    pub walkable: Vec<[f32; 4]>,
    pub walls: Vec<[f32; 4]>,
    pub areas: Vec<Value>,
    pub zones: Vec<Value>,
    pub nodes: Vec<Value>,
    pub edges: Vec<Value>,
    pub gates: Vec<Value>,
    pub dests: Vec<Value>,
    pub sources: Vec<Value>,
    pub signs: Vec<Value>,
    pub transit: Vec<Value>,
    pub events: Vec<Value>,
    pub speed: [f32; 2],
    pub group: [u32; 2],
    pub sign_compliance: [f32; 2],
    pub crowd_following: [f32; 2],
    pub familiarity: [f32; 2],
    pub time_limit: f32,
    pub seed: u64,
    pub time_gap: Option<f32>,
}

impl Default for Spec {
    fn default() -> Self {
        Spec {
            size: [60.0, 20.0],
            walkable: vec![],
            walls: vec![],
            areas: vec![],
            zones: vec![],
            nodes: vec![],
            edges: vec![],
            gates: vec![],
            dests: vec![],
            sources: vec![],
            signs: vec![],
            transit: vec![],
            events: vec![],
            speed: [1.2, 1.4],
            group: [1, 1],
            sign_compliance: [0.5, 0.5],
            crowd_following: [0.0, 0.0],
            familiarity: [1.0, 1.0],
            time_limit: 600.0,
            seed: 1,
            time_gap: None,
        }
    }
}

pub fn node(id: &str, x: f32, y: f32, r: f32) -> Value {
    json!({"id": id, "pos": [x, y], "radius": r})
}
pub fn edge(a: &str, b: &str) -> Value {
    json!({"a": a, "b": b, "one_way": true})
}
pub fn edge_area(a: &str, b: &str, area: &str) -> Value {
    json!({"a": a, "b": b, "one_way": true, "area": area})
}
pub fn area(id: &str, r: [f32; 4]) -> Value {
    json!({"id": id, "name": id, "rect": r})
}
pub fn dest(id: &str, node: &str) -> Value {
    json!({"id": id, "name": id, "node": node})
}
pub fn source(
    id: &str,
    pop: u32,
    door: &str,
    spawn: [f32; 4],
    rate: f32,
    mix: &[(&str, f32)],
) -> Value {
    json!({"id": id, "name": id, "population": pop, "doors": [{"node": door, "spawn": spawn, "rate": rate}],
           "destination_mix": mix.iter().map(|(d, w)| json!([d, w])).collect::<Vec<_>>()})
}

impl Spec {
    pub fn json(&self) -> String {
        let mut areas = self.areas.clone();
        if areas.is_empty() {
            areas.push(area("all", [0.0, 0.0, self.size[0], self.size[1]]));
        }
        let mut tuning = json!({});
        if let Some(t) = self.time_gap {
            tuning = json!({"time_gap": t});
        }
        json!({
            "tuning": tuning,
            "schema_version": 1, "scenario_id": "test", "title": "test", "seed": self.seed,
            "map": {"size": self.size, "cell": 0.5, "walkable": self.walkable, "walls": self.walls,
                    "areas": areas, "barrier_zones": self.zones},
            "nodes": self.nodes, "edges": self.edges, "gates": self.gates, "destinations": self.dests,
            "population_profiles": [{"id": "p", "name": "p", "share": 1.0, "speed": self.speed,
                "familiarity": self.familiarity, "sign_compliance": self.sign_compliance,
                "crowd_following": self.crowd_following, "patience": [7000, 7000], "group_size": self.group}],
            "spawn_schedules": self.sources, "signs": self.signs, "transit_services": self.transit,
            "event_schedule": self.events,
            "player_resources": {"budget": 10000, "fence_cost_per_m": 8, "fence_max_len": 100, "stewards_cost_per_m": 10, "stewards_max_len": 40, "arrow_cost_per_m": 1, "arrow_max_len": 60, "max_placed": 10},
            "objectives": {"time_limit": self.time_limit, "clear_fraction": 0.95, "target_journey": 60, "target_max_wait": 60},
            "failure_conditions": {"max_danger_seconds": 100000},
            "scoring_rules": {"base": 1000, "per_journey_second": 1, "per_wait_second": 1, "per_heavy_second": 1,
                "per_danger_second": 1, "per_cost": 0.1, "per_stranded": 1, "per_satisfaction": 1, "stars": [100, 200, 300]}
        })
        .to_string()
    }

    pub fn sim(&self) -> Sim {
        let sc = Scenario::from_json(&self.json()).expect("valid test scenario");
        Sim::new(sc, &LoadOptions::default()).expect("sim builds")
    }
}

/// Step until everyone has arrived or `max_s` simulated seconds pass. Calls `each` after every tick.
pub fn run_until_done(sim: &mut Sim, max_s: f32, mut each: impl FnMut(&Sim)) {
    let max_ticks = (max_s / sim.dt) as u64;
    while !sim.is_over() && sim.tick < max_ticks {
        sim.step();
        each(sim);
    }
}

/// Physical containment: nobody's body overlaps a wall by more than half its radius, and every
/// centre lies inside the scenario's walkable rectangles. (The navigation grid inflates walls by a
/// cell, so grid walkability is deliberately not the test.)
pub fn all_on_walkable(sim: &Sim) -> bool {
    let rects: Vec<[f32; 4]> = sim.sc.map.walkable.clone();
    (0..sim.agents.len()).all(|i| {
        let p = sim.agents.pos[i];
        let r = sim.agents.radius[i];
        let inside = rects.iter().any(|q| {
            p.x >= q[0] - 1e-3
                && p.y >= q[1] - 1e-3
                && p.x <= q[0] + q[2] + 1e-3
                && p.y <= q[1] + q[3] + 1e-3
        });
        let clear = sim
            .grid
            .walls
            .iter()
            .all(|w| (crowd_core::math::closest_on_segment(p, w.a, w.b) - p).len() >= r * 0.5);
        inside && clear
    })
}
