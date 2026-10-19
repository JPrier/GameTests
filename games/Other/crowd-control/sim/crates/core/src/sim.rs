//! The simulation: world state, the fixed-step update, and player commands.

use crate::agents::{Agents, NewAgent, State, NONE16, NONE32};
use crate::grid::{build_field, reachable, Field, NavGrid, WallOwner};
use crate::math::{closest_on_segment, exp, segments_intersect, Rect, Vec2};
use crate::metrics::{
    AreaStats, DensityGrid, Level, RateRing, AREA_DANGER_CELLS, AREA_HEAVY_CELLS,
};
use crate::rng::{Rng, Stream};
use crate::routing::{choose_route, weidmann_factor, ChoiceInput, Edge, Graph, Node, MAX_NODES};
use crate::scenario::{Scenario, SignModeDef, ValidationError};
use serde::{Deserialize, Serialize};

/// Bumped whenever simulation behaviour changes; part of every replay.
pub const SIM_VERSION: u32 = 1;
/// Distance fields rebuilt per tick after a geometry change (amortises barrier placement).
const FIELDS_PER_TICK: usize = 3;
/// How far upstream of a metered line people behave as an orderly queue (m).
const QUEUE_REACH: f32 = 30.0;
/// Seconds between checksum records in a replay.
pub const CHECKSUM_EVERY: u64 = 100;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LoadOptions {
    /// Override the total population (scaled across sources).
    #[serde(default)]
    pub population: Option<u32>,
    /// Override the scenario seed.
    #[serde(default)]
    pub seed: Option<u64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GateMode {
    Open,
    Metered,
    Closed,
}

pub struct Gate {
    pub id: String,
    pub name: String,
    pub node: u16,
    pub a: Vec2,
    pub b: Vec2,
    pub mid: Vec2,
    /// Unit normal pointing downstream (toward the gate node).
    pub normal: Vec2,
    pub tangent: Vec2,
    pub half_len: f32,
    pub lanes: u32,
    pub lane_rate: f32,
    pub controllable: bool,
    pub mode: GateMode,
    pub level: f32,
    pub meter_levels: Vec<f32>,
    pub staff_cost_per_min: f32,
    /// Multiplier from incidents (train delay).
    pub service_factor: f32,
    pub lane_free: Vec<f32>,
    pub passed: RateRing,
    pub total_passed: u32,
    pub queue: u32,
    pub area: u8,
    /// Crossings by agents that had not been served (must stay 0; checked by tests).
    pub violations: u32,
    /// Service tokens issued (people allowed through a metered line).
    pub served: u32,
    /// Crossable only downstream (fare gates): nobody walks back through.
    pub one_way: bool,
    /// Scheduled operation: (time, mode, level), sorted by time; consumed as it fires.
    pub schedule: Vec<(f32, GateMode, f32)>,
    pub last_change: f32,
}

impl Gate {
    /// Service rate (persons / s); infinite when open, zero when closed.
    pub fn rate(&self) -> f32 {
        match self.mode {
            GateMode::Open => f32::INFINITY,
            GateMode::Closed => 0.0,
            GateMode::Metered => {
                self.lanes as f32 * self.lane_rate * self.level * self.service_factor
            }
        }
    }
    pub fn wait_estimate(&self) -> f32 {
        let r = self.rate();
        if r.is_infinite() {
            0.0
        } else if r <= 0.0 {
            999.0
        } else {
            self.queue as f32 / r
        }
    }
    #[inline]
    pub fn side(&self, p: Vec2) -> f32 {
        (p - self.mid).dot(self.normal)
    }
    #[inline]
    pub fn lateral(&self, p: Vec2) -> f32 {
        (p - self.mid).dot(self.tangent).abs()
    }
}

/// Copyable trait ranges of a population profile (avoids cloning strings per spawn).
#[derive(Clone, Copy)]
struct Traits {
    speed: [f32; 2],
    familiarity: [f32; 2],
    sign_compliance: [f32; 2],
    crowd_following: [f32; 2],
    patience: [f32; 2],
    group_size: [u32; 2],
    stairs_aversion: f32,
    radius: f32,
}

impl From<&crate::scenario::ProfileDef> for Traits {
    fn from(p: &crate::scenario::ProfileDef) -> Traits {
        Traits {
            speed: p.speed,
            familiarity: p.familiarity,
            sign_compliance: p.sign_compliance,
            crowd_following: p.crowd_following,
            patience: p.patience,
            group_size: p.group_size,
            stairs_aversion: p.stairs_aversion,
            radius: p.radius,
        }
    }
}

pub struct Door {
    pub node: u16,
    pub spawn: Rect,
    pub rate: f32,
    pub acc: f32,
}

pub struct Source {
    pub id: String,
    pub name: String,
    pub population: u32,
    pub remaining: u32,
    pub start: f32,
    pub doors: Vec<Door>,
    pub mix: Vec<(u16, f32)>,
}

pub struct Sign {
    pub id: String,
    pub name: String,
    pub pos: Vec2,
    pub radius: f32,
    pub modes: Vec<SignModeDef>,
    pub mode: usize,
    pub change_cost: f32,
    pub reads: u32,
    /// Waits shown by a wait_times message (from the operator's possibly delayed data).
    pub shown_waits: Vec<f32>,
}

#[derive(Clone, Debug, Serialize)]
pub struct Barrier {
    pub id: u32,
    pub a: Vec2,
    pub b: Vec2,
    pub placed_at: f32,
    pub cost: f32,
}

pub struct Incident {
    pub id: String,
    pub name: String,
    pub transit: usize,
    pub factor: f32,
    pub happens: bool,
    pub start: f32,
    pub duration: f32,
    pub active: bool,
    pub done: bool,
}

pub struct Transit {
    pub id: String,
    pub name: String,
    pub gates: Vec<u16>,
}

#[derive(Clone, Debug, Serialize)]
pub struct LogEntry {
    pub t: f32,
    pub tick: u64,
    pub kind: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub area: Option<String>,
}

/// What the operator's sensors report for an area (may lag the truth).
#[derive(Clone, Debug, Default, Serialize)]
pub struct Reported {
    pub occupancy: u32,
    pub density: f32,
    pub level: u8,
    /// Time the reading was taken (s).
    pub at: f32,
    pub delayed: bool,
    pub in_pm: u32,
    pub out_pm: u32,
    /// Camera snapshot: render records of the people inside, and density image texels.
    #[serde(skip)]
    pub render: Vec<f32>,
    #[serde(skip)]
    pub texels: Vec<(u32, [u8; 4])>,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Running,
    Won,
    FailedDanger,
    FailedTimeout,
}

/// A player command. Commands are applied between ticks and recorded with the tick they precede.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Command {
    Gate {
        gate: String,
        mode: GateMode,
        #[serde(default)]
        level: Option<f32>,
    },
    BarrierAdd {
        a: [f32; 2],
        b: [f32; 2],
    },
    BarrierRemove {
        id: u32,
    },
    Sign {
        sign: String,
        mode: String,
    },
    /// Debug: operator sees true values instead of delayed sensor data.
    PerfectInfo {
        on: bool,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct TimedCommand {
    pub tick: u64,
    pub cmd: Command,
}

/// Wall-clock cost of each system, accumulated in seconds (filled only when a clock is supplied).
#[derive(Clone, Debug, Default, Serialize)]
pub struct Timings {
    pub spawn: f64,
    pub neighbor_index: f64,
    pub decisions: f64,
    pub movement: f64,
    pub density: f64,
    pub fields: f64,
    pub ticks: u64,
}

pub struct Sim {
    pub sc: Scenario,
    pub seed: u64,
    pub tick: u64,
    pub time: f32,
    pub dt: f32,
    pub grid: NavGrid,
    pub fields: Vec<Field>,
    fields_dirty: Vec<bool>,
    pub graph: Graph,
    pub agents: Agents,
    /// Stable id -> index (NONE32 when gone).
    pub slot_of: Vec<u32>,
    next_id: u32,
    pub spatial: crate::spatial::SpatialGrid,
    pub density: DensityGrid,
    pub areas: Vec<AreaStats>,
    pub area_ids: Vec<String>,
    pub area_names: Vec<String>,
    pub area_speed: Vec<f32>,
    pub area_static: Vec<f32>,
    profile_traits: Vec<Traits>,
    pub area_center: Vec<Vec2>,
    pub gates: Vec<Gate>,
    pub sources: Vec<Source>,
    pub signs: Vec<Sign>,
    pub barriers: Vec<Barrier>,
    next_barrier: u32,
    pub incidents: Vec<Incident>,
    pub transits: Vec<Transit>,
    pub dest_nodes: Vec<u16>,
    pub dest_names: Vec<String>,
    pub dest_ids: Vec<String>,
    pub log: Vec<LogEntry>,
    rng_arrivals: Rng,
    rng_traits: Rng,
    rng_decisions: Rng,
    // outcome accounting
    pub total_population: u32,
    pub completed: u32,
    pub completed_by_dest: Vec<u32>,
    pub journey_sum: f32,
    pub wait_max: f32,
    pub satisfaction_sum: f32,
    pub spent: f32,
    pub staff_spent: f32,
    pub danger_seconds: f32,
    pub heavy_seconds: f32,
    pub peak_density: f32,
    pub outcome: Outcome,
    pub ended_at: f32,
    pub perfect_info: bool,
    pub reported: Vec<Reported>,
    pub(crate) reported_node_wait: Vec<f32>,
    pub reported_gate_flow: Vec<u32>,
    delayed_period: Vec<f32>,
    area_last_warn: Vec<f32>,
    pub area_prev_level: Vec<Level>,
    second_acc: f32,
    /// Agent believed waits from a wait_times sign: (sign index, values per compare node).
    belief_sign: Vec<u8>,
    belief: Vec<[f32; 4]>,
    pub commands: Vec<TimedCommand>,
    pub checksums: Vec<(u64, u64)>,
    pub timings: Timings,
    // scratch buffers (no allocation in the hot loop)
    new_dir: Vec<Vec2>,
    new_speed: Vec<f32>,
    route_buf: Vec<u16>,
    remove_buf: Vec<usize>,
    vel_buf: Vec<Vec2>,
    near_buf: Vec<(u32, f32)>,
    waiting_buf: Vec<(u16, f32, u32, usize)>,
    pub version_fields: u64,
}

fn r(a: [f32; 4]) -> Rect {
    Rect::from_arr(a)
}

impl Sim {
    pub fn new(sc: Scenario, opts: &LoadOptions) -> Result<Sim, ValidationError> {
        sc.validate()?;
        let err = |m: String| Err(ValidationError(m));
        let seed = opts.seed.unwrap_or(sc.seed);
        let t = sc.tuning.clone();
        let grid = NavGrid::new(sc.map.size, sc.map.cell, &sc.map.walkable, &sc.map.walls);
        for n in &sc.nodes {
            if !grid.is_base_walkable(Vec2::new(n.pos[0], n.pos[1])) {
                return err(format!("node '{}' is not on walkable ground", n.id));
            }
        }
        // areas
        let mut areas = Vec::new();
        for a in &sc.map.areas {
            let rect = r(a.rect);
            let wa = grid.walkable_area(&rect);
            if wa < 1.0 {
                return err(format!("area '{}' has no walkable ground", a.id));
            }
            areas.push(AreaStats {
                rect,
                walk_area: wa,
                speed_factor: a.speed_factor,
                occupancy: 0,
                speed_sum: 0.0,
                density: 0.0,
                mean_speed: 0.0,
                inflow: RateRing::default(),
                outflow: RateRing::default(),
                level: Level::Comfortable,
                heavy_cells: 0,
                danger_cells: 0,
                heavy_seconds: 0.0,
                danger_seconds: 0.0,
                peak_density: 0.0,
                wait_person_seconds: 0.0,
            });
        }
        if areas.len() > 250 {
            return err("too many areas".into());
        }
        let area_rects: Vec<Rect> = areas.iter().map(|a| a.rect).collect();
        let (dc, dr, dwa) = grid.coarse_walkable_area(t.density_cell);
        let density = DensityGrid::new(t.density_cell, dc, dr, dwa, &area_rects);

        // graph
        if sc.nodes.len() > MAX_NODES {
            return err(format!("at most {MAX_NODES} nodes"));
        }
        let ni = |id: &str| sc.node_index(id).unwrap() as u16;
        let mut nodes: Vec<Node> = sc
            .nodes
            .iter()
            .map(|n| Node {
                id: n.id.clone(),
                pos: Vec2::new(n.pos[0], n.pos[1]),
                radius: n.radius,
                gate: None,
                dest: None,
                door: false,
            })
            .collect();
        let mut edges = Vec::new();
        for e in &sc.edges {
            edges.push(Edge {
                a: ni(&e.a),
                b: ni(&e.b),
                one_way: e.one_way,
                stairs: e.stairs,
                area: e.area.as_ref().map(|a| sc.area_index(a).unwrap() as u8),
                length: f32::INFINITY,
            });
        }
        // gates
        let mut gates = Vec::new();
        for (gi, g) in sc.gates.iter().enumerate() {
            let node = ni(&g.node);
            let a = Vec2::new(g.line[0], g.line[1]);
            let b = Vec2::new(g.line[2], g.line[3]);
            let mid = (a + b) * 0.5;
            let tangent = (b - a).norm();
            let mut normal = tangent.perp();
            if (nodes[node as usize].pos - mid).dot(normal) < 0.0 {
                normal = -normal;
            }
            if (nodes[node as usize].pos - mid).dot(normal) < 0.5 {
                return err(format!(
                    "gate '{}' node must lie at least 0.5 m past its line",
                    g.id
                ));
            }
            nodes[node as usize].gate = Some(gi as u16);
            let mode = match g.default_mode.as_str() {
                "metered" => GateMode::Metered,
                "closed" => GateMode::Closed,
                _ => GateMode::Open,
            };
            let area = area_rects
                .iter()
                .position(|ar| ar.contains(mid - normal * 1.0))
                .map(|x| x as u8)
                .unwrap_or(u8::MAX);
            gates.push(Gate {
                id: g.id.clone(),
                name: g.name.clone(),
                node,
                a,
                b,
                mid,
                normal,
                tangent,
                half_len: (b - a).len() * 0.5,
                lanes: g.lanes,
                lane_rate: g.lane_rate,
                controllable: g.controllable,
                mode,
                level: if mode == GateMode::Metered && g.controllable {
                    g.meter_levels.first().copied().unwrap_or(1.0)
                } else {
                    1.0
                },
                meter_levels: g.meter_levels.clone(),
                staff_cost_per_min: g.staff_cost_per_min,
                service_factor: 1.0,
                lane_free: vec![0.0; g.lanes as usize],
                passed: RateRing::default(),
                total_passed: 0,
                queue: 0,
                area,
                violations: 0,
                served: 0,
                one_way: g.one_way,
                schedule: {
                    let mut v: Vec<(f32, GateMode, f32)> = g
                        .schedule
                        .iter()
                        .map(|s| {
                            let m = match s.mode.as_str() {
                                "metered" => GateMode::Metered,
                                "closed" => GateMode::Closed,
                                _ => GateMode::Open,
                            };
                            (s.at, m, s.level.unwrap_or(1.0))
                        })
                        .collect();
                    v.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
                    v
                },
                last_change: -1e9,
            });
        }
        let mut dest_nodes = Vec::new();
        for (di, d) in sc.destinations.iter().enumerate() {
            let n = ni(&d.node);
            nodes[n as usize].dest = Some(di as u16);
            dest_nodes.push(n);
        }
        // sources
        let total_def: u32 = sc.spawn_schedules.iter().map(|s| s.population).sum();
        let target_total = opts.population.unwrap_or(total_def);
        let mut sources = Vec::new();
        let mut assigned = 0u32;
        for (si, s) in sc.spawn_schedules.iter().enumerate() {
            let pop = if si + 1 == sc.spawn_schedules.len() {
                target_total - assigned
            } else {
                ((s.population as u64 * target_total as u64) / total_def.max(1) as u64) as u32
            };
            assigned += pop;
            let mut doors = Vec::new();
            for d in &s.doors {
                let node = ni(&d.node);
                nodes[node as usize].door = true;
                // a bigger crowd implies a bigger venue: exit capacity scales with population
                let scale = (pop as f32 / s.population.max(1) as f32).max(1.0);
                doors.push(Door {
                    node,
                    spawn: r(d.spawn),
                    rate: d.rate * scale,
                    acc: 0.0,
                });
            }
            let mix = s
                .destination_mix
                .iter()
                .map(|(d, w)| {
                    (
                        sc.destinations.iter().position(|x| &x.id == d).unwrap() as u16,
                        *w,
                    )
                })
                .collect();
            sources.push(Source {
                id: s.id.clone(),
                name: s.name.clone(),
                population: pop,
                remaining: pop,
                start: s.start,
                doors,
                mix,
            });
        }
        let signs = sc
            .signs
            .iter()
            .map(|s| Sign {
                id: s.id.clone(),
                name: s.name.clone(),
                pos: Vec2::new(s.pos[0], s.pos[1]),
                radius: s.radius,
                modes: s.modes.clone(),
                mode: s.modes.iter().position(|m| m.id == s.default_mode).unwrap(),
                change_cost: s.change_cost,
                reads: 0,
                shown_waits: Vec::new(),
            })
            .collect::<Vec<_>>();
        if signs.len() > 8 {
            return err("at most 8 signs".into());
        }
        let transits: Vec<Transit> = sc
            .transit_services
            .iter()
            .map(|t| Transit {
                id: t.id.clone(),
                name: t.name.clone(),
                gates: t
                    .gates
                    .iter()
                    .map(|g| sc.gates.iter().position(|x| &x.id == g).unwrap() as u16)
                    .collect(),
            })
            .collect();
        let mut rng_incidents = Rng::stream(seed, Stream::Incidents);
        let incidents = sc
            .event_schedule
            .iter()
            .map(|e| {
                let happens = rng_incidents.f32() < e.probability;
                let start = rng_incidents.range(e.start[0], e.start[1]);
                let duration = rng_incidents.range(e.duration[0], e.duration[1]);
                Incident {
                    id: e.id.clone(),
                    name: e.name.clone(),
                    transit: transits.iter().position(|t| t.id == e.target).unwrap(),
                    factor: e.factor,
                    happens,
                    start,
                    duration,
                    active: false,
                    done: false,
                }
            })
            .collect();
        let delayed_period: Vec<f32> = sc
            .map
            .areas
            .iter()
            .map(|a| {
                sc.information
                    .delayed
                    .iter()
                    .find(|d| d.area == a.id)
                    .map(|d| d.period)
                    .unwrap_or(0.0)
            })
            .collect();
        let n_areas = areas.len();
        let n_gates = gates.len();
        let sc_area_static: Vec<f32> = areas.iter().map(|a| a.speed_factor).collect();
        let area_ids = sc.map.areas.iter().map(|a| a.id.clone()).collect();
        let area_names = sc.map.areas.iter().map(|a| a.name.clone()).collect();
        let area_center = areas.iter().map(|a| a.rect.center()).collect();
        let n_nodes = nodes.len();
        let mut graph = Graph {
            nodes,
            edges,
            out: Vec::new(),
            inc: Vec::new(),
        };
        graph.build_adjacency();
        let spatial = crate::spatial::SpatialGrid::new(sc.map.size, t.interaction_radius);
        let mut sim = Sim {
            seed,
            tick: 0,
            time: 0.0,
            dt: t.dt,
            fields: Vec::new(),
            fields_dirty: vec![true; n_nodes],
            graph,
            agents: Agents::default(),
            slot_of: Vec::new(),
            next_id: 0,
            spatial,
            density,
            areas,
            area_ids,
            area_names,
            area_speed: vec![1.0; n_areas],
            area_static: sc_area_static,
            profile_traits: sc.population_profiles.iter().map(Traits::from).collect(),
            area_center,
            gates,
            sources,
            signs,
            barriers: Vec::new(),
            next_barrier: 1,
            incidents,
            transits,
            dest_nodes,
            dest_names: sc.destinations.iter().map(|d| d.name.clone()).collect(),
            dest_ids: sc.destinations.iter().map(|d| d.id.clone()).collect(),
            log: Vec::new(),
            rng_arrivals: Rng::stream(seed, Stream::Arrivals),
            rng_traits: Rng::stream(seed, Stream::Traits),
            rng_decisions: Rng::stream(seed, Stream::Decisions),
            total_population: target_total,
            completed: 0,
            completed_by_dest: vec![0; sc.destinations.len()],
            journey_sum: 0.0,
            wait_max: 0.0,
            satisfaction_sum: 0.0,
            spent: 0.0,
            staff_spent: 0.0,
            danger_seconds: 0.0,
            heavy_seconds: 0.0,
            peak_density: 0.0,
            outcome: Outcome::Running,
            ended_at: 0.0,
            perfect_info: false,
            reported: vec![Reported::default(); n_areas],
            reported_node_wait: vec![0.0; n_nodes],
            reported_gate_flow: vec![0; n_gates],
            delayed_period,
            area_last_warn: vec![-1e9; n_areas],
            area_prev_level: vec![Level::Comfortable; n_areas],
            second_acc: 0.0,
            belief_sign: Vec::new(),
            belief: Vec::new(),
            commands: Vec::new(),
            checksums: Vec::new(),
            timings: Timings::default(),
            new_dir: Vec::new(),
            new_speed: Vec::new(),
            route_buf: Vec::new(),
            remove_buf: Vec::new(),
            vel_buf: Vec::new(),
            near_buf: Vec::new(),
            waiting_buf: Vec::new(),
            version_fields: 0,
            grid,
            sc,
        };
        // one-way gates constrain path search in their downstream direction
        for g in &sim.gates {
            if g.one_way {
                sim.grid.one_way.push(crate::grid::OneWay {
                    a: g.a,
                    b: g.b,
                    normal: g.normal,
                });
            }
        }
        // closed gates start as walls
        for gi in 0..sim.gates.len() {
            if sim.gates[gi].mode == GateMode::Closed {
                let (a, b) = (sim.gates[gi].a, sim.gates[gi].b);
                sim.grid.add_wall(a, b, WallOwner::Gate(gi as u16));
            }
        }
        // initial fields are built synchronously
        sim.fields = (0..n_nodes).map(|_| Field::empty(0, Vec2::ZERO)).collect();
        for i in 0..n_nodes {
            sim.rebuild_field(i);
        }
        sim.update_edge_lengths();
        // every destination must be reachable from every door at the start
        for s in &sim.sources {
            for d in &s.doors {
                for (di, &dn) in sim.dest_nodes.iter().enumerate() {
                    if !sim.fields[dn as usize]
                        .dist_at(&sim.grid, d.spawn.center())
                        .is_finite()
                    {
                        return err(format!(
                            "destination '{}' unreachable from source '{}'",
                            sim.dest_ids[di], s.id
                        ));
                    }
                }
            }
        }
        for gi in 0..sim.gates.len() {
            let mid = sim.gates[gi].mid;
            if !sim.grid.is_base_walkable(mid) {
                return err(format!(
                    "gate '{}' line is not on walkable ground",
                    sim.gates[gi].id
                ));
            }
        }
        sim.refresh_reports(true);
        sim.log_event(
            "start",
            format!("{}: {} people leaving", sim.sc.title, sim.total_population),
            None,
        );
        Ok(sim)
    }

    fn rebuild_field(&mut self, i: usize) {
        let n = &self.graph.nodes[i];
        self.fields[i] = build_field(&self.grid, &self.grid.walkable, n.pos, n.radius.min(1.5));
        self.fields_dirty[i] = false;
    }

    fn update_edge_lengths(&mut self) {
        for e in self.graph.edges.iter_mut() {
            let a = self.graph.nodes[e.a as usize].pos;
            e.length = self.fields[e.b as usize].dist_at(&self.grid, a);
        }
        self.version_fields += 1;
    }

    fn mark_geometry_changed(&mut self) {
        for d in self.fields_dirty.iter_mut() {
            *d = true;
        }
    }

    pub fn fields_pending(&self) -> usize {
        self.fields_dirty.iter().filter(|d| **d).count()
    }

    pub fn log_event(&mut self, kind: &str, text: String, area: Option<usize>) {
        let area = area.map(|a| self.area_ids[a].clone());
        self.log.push(LogEntry {
            t: self.time,
            tick: self.tick,
            kind: kind.into(),
            text,
            area,
        });
    }

    pub fn active(&self) -> u32 {
        self.agents.len() as u32
    }

    pub fn reservoir(&self) -> u32 {
        self.sources.iter().map(|s| s.remaining).sum()
    }

    // ------------------------------------------------------------------ commands

    /// Apply a player command now (before the next tick) and record it for replay.
    pub fn apply(&mut self, cmd: Command) -> Result<serde_json::Value, String> {
        if self.outcome != Outcome::Running {
            return Err("the scenario has ended".into());
        }
        let res = self.apply_inner(&cmd);
        if res.is_ok() {
            self.commands.push(TimedCommand {
                tick: self.tick,
                cmd,
            });
        }
        res
    }

    fn budget_left(&self) -> f32 {
        self.sc.player_resources.budget - self.spent
    }

    fn apply_inner(&mut self, cmd: &Command) -> Result<serde_json::Value, String> {
        match cmd {
            Command::Gate { gate, mode, level } => {
                let gi = self
                    .gates
                    .iter()
                    .position(|g| &g.id == gate)
                    .ok_or("unknown gate")?;
                if !self.gates[gi].controllable {
                    return Err("this gate is not under your control".into());
                }
                let lvl = match mode {
                    GateMode::Metered => {
                        let l = level.unwrap_or_else(|| {
                            self.gates[gi].meter_levels.first().copied().unwrap_or(0.5)
                        });
                        if !self.gates[gi]
                            .meter_levels
                            .iter()
                            .any(|x| (x - l).abs() < 1e-4)
                        {
                            return Err(format!("metering level {l} not available"));
                        }
                        l
                    }
                    _ => 1.0,
                };
                let was_closed = self.gates[gi].mode == GateMode::Closed;
                let g = &mut self.gates[gi];
                if g.mode == *mode && (g.level - lvl).abs() < 1e-4 {
                    return Ok(serde_json::json!({"unchanged": true}));
                }
                g.mode = *mode;
                g.level = lvl;
                g.last_change = self.time;
                let (a, b, name) = (g.a, g.b, g.name.clone());
                let now_closed = *mode == GateMode::Closed;
                if now_closed && !was_closed {
                    self.grid.add_wall(a, b, WallOwner::Gate(gi as u16));
                    self.mark_geometry_changed();
                } else if was_closed && !now_closed {
                    self.grid.remove_walls(WallOwner::Gate(gi as u16));
                    self.mark_geometry_changed();
                }
                let text = match mode {
                    GateMode::Open => format!("{name} opened fully"),
                    GateMode::Closed => format!("{name} closed"),
                    GateMode::Metered => {
                        let r = self.gates[gi].rate();
                        format!("{name} metered to {:.0} people/min", r * 60.0)
                    }
                };
                let area = self.gates[gi].area;
                self.log_event("gate", text, (area != u8::MAX).then_some(area as usize));
                Ok(serde_json::json!({}))
            }
            Command::BarrierAdd { a, b } => {
                let (a, b) = (Vec2::new(a[0], a[1]), Vec2::new(b[0], b[1]));
                self.check_barrier(a, b)?;
                let cost = self.sc.player_resources.barrier_cost;
                let id = self.next_barrier;
                self.next_barrier += 1;
                self.grid.add_wall(a, b, WallOwner::Barrier(id));
                self.barriers.push(Barrier {
                    id,
                    a,
                    b,
                    placed_at: self.time,
                    cost,
                });
                self.spent += cost;
                self.mark_geometry_changed();
                let area = self.area_at(a);
                self.log_event(
                    "barrier",
                    format!("Barrier placed ({:.0} m)", (b - a).len()),
                    area,
                );
                Ok(serde_json::json!({"id": id}))
            }
            Command::BarrierRemove { id } => {
                let i = self
                    .barriers
                    .iter()
                    .position(|x| x.id == *id)
                    .ok_or("unknown barrier")?;
                let bar = self.barriers.remove(i);
                self.grid.remove_walls(WallOwner::Barrier(*id));
                let refund = if self.time - bar.placed_at <= self.sc.player_resources.undo_window {
                    bar.cost
                } else {
                    0.0
                };
                self.spent -= refund;
                self.mark_geometry_changed();
                let area = self.area_at(bar.a);
                self.log_event(
                    "barrier",
                    if refund > 0.0 {
                        "Barrier undone (refunded)".into()
                    } else {
                        "Barrier removed".into()
                    },
                    area,
                );
                Ok(serde_json::json!({"refund": refund}))
            }
            Command::Sign { sign, mode } => {
                let si = self
                    .signs
                    .iter()
                    .position(|s| &s.id == sign)
                    .ok_or("unknown sign")?;
                let mi = self.signs[si]
                    .modes
                    .iter()
                    .position(|m| &m.id == mode)
                    .ok_or("unknown sign message")?;
                if self.signs[si].mode == mi {
                    return Ok(serde_json::json!({"unchanged": true}));
                }
                let cost = self.signs[si].change_cost;
                if cost > self.budget_left() + 1e-3 {
                    return Err("not enough budget".into());
                }
                self.spent += cost;
                self.signs[si].mode = mi;
                // everyone may read the new message
                let bit = 1u8 << si;
                for f in self.agents.signs_read.iter_mut() {
                    *f &= !bit;
                }
                let text = format!(
                    "{} now shows \"{}\"",
                    self.signs[si].name, self.signs[si].modes[mi].label
                );
                let area = self.area_at(self.signs[si].pos);
                self.log_event("sign", text, area);
                self.refresh_sign_waits();
                Ok(serde_json::json!({}))
            }
            Command::PerfectInfo { on } => {
                self.perfect_info = *on;
                self.refresh_reports(true);
                Ok(serde_json::json!({}))
            }
        }
    }

    pub fn area_at(&self, p: Vec2) -> Option<usize> {
        self.areas.iter().position(|a| a.rect.contains(p))
    }

    /// Placement rules: inside one barrier zone, sensible length, clear of gates and nodes, within
    /// budget, and it must not trap anyone (every person and door keeps a path to its destination).
    pub fn check_barrier(&self, a: Vec2, b: Vec2) -> Result<(), String> {
        let res = &self.sc.player_resources;
        let len = (b - a).len();
        if len < 1.0 {
            return Err("barrier too short".into());
        }
        if len > res.barrier_max_len + 1e-3 {
            return Err(format!(
                "barriers are at most {:.0} m long",
                res.barrier_max_len
            ));
        }
        if self.barriers.len() as u32 >= res.max_barriers {
            return Err(format!("at most {} barriers", res.max_barriers));
        }
        if res.barrier_cost > self.budget_left() + 1e-3 {
            return Err("not enough budget".into());
        }
        let inside = self.sc.map.barrier_zones.iter().any(|z| {
            let zr = r(z.rect);
            zr.contains(a) && zr.contains(b)
        });
        if !inside {
            return Err("barriers go in the marked zones".into());
        }
        for g in &self.gates {
            if segments_intersect(a, b, g.a, g.b)
                || (closest_on_segment(g.mid, a, b) - g.mid).len() < 1.5
            {
                return Err("too close to a gate".into());
            }
        }
        for n in &self.graph.nodes {
            if (closest_on_segment(n.pos, a, b) - n.pos).len() < n.radius.max(1.0) {
                return Err("blocks a walkway point".into());
            }
        }
        for s in &self.sources {
            for d in &s.doors {
                if segments_intersect(
                    a,
                    b,
                    Vec2::new(d.spawn.x, d.spawn.y),
                    Vec2::new(d.spawn.x + d.spawn.w, d.spawn.y + d.spawn.h),
                ) || d.spawn.contains(a)
                    || d.spawn.contains(b)
                {
                    return Err("too close to a stadium exit".into());
                }
            }
        }
        // connectivity check on the candidate geometry
        let mask = self.grid.walkable_with(a, b);
        let reach: Vec<Vec<bool>> = self
            .dest_nodes
            .iter()
            .map(|&n| reachable(&self.grid, &mask, self.graph.nodes[n as usize].pos))
            .collect();
        let ok_at = |p: Vec2, d: usize| -> bool {
            let Some((cx, cy)) = self.grid.cell_of(p) else {
                return false;
            };
            for dy in -2isize..=2 {
                for dx in -2isize..=2 {
                    let x = cx as isize + dx;
                    let y = cy as isize + dy;
                    if x >= 0
                        && y >= 0
                        && (x as usize) < self.grid.cols
                        && (y as usize) < self.grid.rows
                        && reach[d][self.grid.idx(x as usize, y as usize)]
                    {
                        return true;
                    }
                }
            }
            false
        };
        for s in &self.sources {
            for d in &s.doors {
                for di in 0..self.dest_nodes.len() {
                    if !ok_at(d.spawn.center(), di) {
                        return Err(format!(
                            "would cut the exits off from the {}",
                            self.dest_names[di]
                        ));
                    }
                }
            }
        }
        for i in 0..self.agents.len() {
            if !ok_at(self.agents.pos[i], self.agents.dest[i] as usize) {
                return Err("would trap people".into());
            }
        }
        Ok(())
    }

    // ------------------------------------------------------------------ step

    pub fn is_over(&self) -> bool {
        self.outcome != Outcome::Running
    }

    pub fn step(&mut self) {
        self.step_timed(None);
    }

    /// One fixed simulation step. `clock` (seconds) enables per-system timing.
    pub fn step_timed(&mut self, clock: Option<&dyn Fn() -> f64>) {
        if self.outcome != Outcome::Running {
            return;
        }
        let now = || clock.map(|c| c()).unwrap_or(0.0);
        let dt = self.dt;
        let t0 = now();
        self.update_incidents();
        self.update_schedules();
        // amortised field rebuild after geometry changes
        if self.fields_pending() > 0 {
            let mut done = 0;
            for i in 0..self.fields.len() {
                if self.fields_dirty[i] {
                    self.rebuild_field(i);
                    done += 1;
                    if done >= FIELDS_PER_TICK {
                        break;
                    }
                }
            }
            if self.fields_pending() == 0 {
                self.update_edge_lengths();
                // everyone reconsiders soon, staggered
                for i in 0..self.agents.len() {
                    let jitter = (self.agents.id[i] % 20) as f32 * 0.05;
                    self.agents.next_decision[i] =
                        self.agents.next_decision[i].min(self.time + jitter);
                }
            }
        }
        let t1 = now();
        self.spatial.rebuild(&self.agents.pos);
        let before = self.agents.len();
        self.spawn();
        let t2 = now();
        if self.agents.len() != before {
            self.spatial.rebuild(&self.agents.pos);
        }
        let t3 = now();
        self.read_signs();
        self.decide();
        let t4 = now();
        self.movement();
        let t5 = now();
        self.measure();
        let t6 = now();
        self.tick += 1;
        self.time = self.tick as f32 * dt;
        self.check_outcome();
        if self.tick.is_multiple_of(CHECKSUM_EVERY) {
            self.checksums.push((self.tick, self.checksum()));
        }
        if clock.is_some() {
            let tm = &mut self.timings;
            tm.fields += t1 - t0;
            tm.spawn += t2 - t1;
            tm.neighbor_index += t3 - t2;
            tm.decisions += t4 - t3;
            tm.movement += t5 - t4;
            tm.density += t6 - t5;
            tm.ticks += 1;
        }
    }

    /// Scenario-scheduled gate operations (deterministic, not player commands).
    fn update_schedules(&mut self) {
        for gi in 0..self.gates.len() {
            while let Some(&(at, mode, level)) = self.gates[gi].schedule.first() {
                if self.time < at {
                    break;
                }
                self.gates[gi].schedule.remove(0);
                let cmd = Command::Gate {
                    gate: self.gates[gi].id.clone(),
                    mode,
                    level: (mode == GateMode::Metered).then_some(level),
                };
                if let Err(e) = self.apply_inner(&cmd) {
                    self.log_event(
                        "gate",
                        format!("Scheduled change to {} failed: {e}", self.gates[gi].name),
                        None,
                    );
                }
            }
        }
    }

    fn update_incidents(&mut self) {
        for k in 0..self.incidents.len() {
            let (happens, start, duration, active, done) = {
                let e = &self.incidents[k];
                (e.happens, e.start, e.duration, e.active, e.done)
            };
            if !happens || done {
                continue;
            }
            if !active && self.time >= start {
                self.incidents[k].active = true;
                let tr = self.incidents[k].transit;
                let f = self.incidents[k].factor;
                for &g in &self.transits[tr].gates.clone() {
                    self.gates[g as usize].service_factor = f;
                }
                let text = format!(
                    "{}: {} boarding slowed to {:.0}% for about {:.0} min",
                    self.incidents[k].name,
                    self.transits[tr].name,
                    f * 100.0,
                    (duration / 60.0).max(1.0).round()
                );
                let area = self.gates[self.transits[tr].gates[0] as usize].area;
                self.log_event("incident", text, (area != u8::MAX).then_some(area as usize));
            } else if active && self.time >= start + duration {
                self.incidents[k].active = false;
                self.incidents[k].done = true;
                let tr = self.incidents[k].transit;
                for &g in &self.transits[tr].gates.clone() {
                    self.gates[g as usize].service_factor = 1.0;
                }
                let text = format!("{} service restored", self.transits[tr].name);
                self.log_event("incident_end", text, None);
            }
        }
    }

    fn spawn(&mut self) {
        let dt = self.dt;
        let time = self.time;
        let n_profiles = self.sc.population_profiles.len();
        let shares: Vec<f32> = self
            .sc
            .population_profiles
            .iter()
            .map(|p| p.share.max(0.0))
            .collect();
        for si in 0..self.sources.len() {
            if time < self.sources[si].start {
                continue;
            }
            for di in 0..self.sources[si].doors.len() {
                {
                    let d = &mut self.sources[si].doors[di];
                    d.acc = (d.acc + d.rate * dt).min(4.0f32.max(d.rate * dt * 2.0));
                }
                loop {
                    let remaining = self.sources[si].remaining;
                    if remaining == 0 || self.sources[si].doors[di].acc < 1.0 {
                        break;
                    }
                    // who: profile and group size (traits stream); where to: destination (arrivals)
                    let pi = self.rng_traits.weighted(&shares).min(n_profiles - 1);
                    let prof = self.profile_traits[pi];
                    let gsize = (self
                        .rng_traits
                        .int(prof.group_size[0] as i64, prof.group_size[1] as i64)
                        as u32)
                        .min(remaining);
                    if (gsize as f32) > self.sources[si].doors[di].acc + 0.001 && gsize > 1 {
                        // wait until enough release capacity has accumulated for the whole group
                        let d = &self.sources[si].doors[di];
                        if d.acc >= 3.9 {
                            // never block forever behind a big group
                        } else {
                            break;
                        }
                    }
                    let weights: Vec<f32> = self.sources[si].mix.iter().map(|m| m.1).collect();
                    let dest = self.sources[si].mix[self.rng_arrivals.weighted(&weights)].0;
                    let spawn = self.sources[si].doors[di].spawn;
                    let mut spots: Vec<Vec2> = Vec::with_capacity(gsize as usize);
                    let radius = prof.radius;
                    for _ in 0..gsize {
                        let mut found = None;
                        for _try in 0..8 {
                            let (x0, x1, y0, y1) = match spots.first() {
                                // group members appear next to the first member
                                Some(f) => (
                                    (f.x - 1.2).max(spawn.x + radius),
                                    (f.x + 1.2).min(spawn.x + spawn.w - radius),
                                    (f.y - 1.2).max(spawn.y + radius),
                                    (f.y + 1.2).min(spawn.y + spawn.h - radius),
                                ),
                                None => (
                                    spawn.x + radius,
                                    spawn.x + spawn.w - radius,
                                    spawn.y + radius,
                                    spawn.y + spawn.h - radius,
                                ),
                            };
                            let p = Vec2::new(
                                self.rng_arrivals.range(x0, x1),
                                self.rng_arrivals.range(y0, y1),
                            );
                            if !self.grid.is_walkable(p) {
                                continue;
                            }
                            let clear_gap = radius * 2.0 + 0.05;
                            let mut free = spots.iter().all(|q| (*q - p).len() >= clear_gap);
                            if free {
                                let pos = &self.agents.pos;
                                let rad = &self.agents.radius;
                                self.spatial.for_each_near(p, |j| {
                                    if (pos[j] - p).len() < radius + rad[j] + 0.05 {
                                        free = false;
                                    }
                                });
                                // agents spawned earlier this tick are not in the index yet
                                let start = self.agents.len().saturating_sub(16);
                                for j in start..self.agents.len() {
                                    if (self.agents.pos[j] - p).len()
                                        < radius + self.agents.radius[j] + 0.05
                                    {
                                        free = false;
                                    }
                                }
                            }
                            if free {
                                found = Some(p);
                                break;
                            }
                        }
                        match found {
                            Some(p) => spots.push(p),
                            None => break,
                        }
                    }
                    if spots.len() < gsize as usize {
                        // exit congested: people stay inside (aggregate) until there is room
                        break;
                    }
                    let door_node = self.sources[si].doors[di].node;
                    let leader_id = self.next_id;
                    // groups walk at their slowest member's pace
                    let mut group_speed = f32::INFINITY;
                    for _ in 0..gsize {
                        group_speed =
                            group_speed.min(self.rng_traits.range(prof.speed[0], prof.speed[1]));
                    }
                    for p in spots {
                        let id = self.next_id;
                        self.next_id += 1;
                        let tr = &mut self.rng_traits;
                        let na = NewAgent {
                            id,
                            pos: p,
                            desired_speed: if gsize > 1 {
                                group_speed * tr.range(0.98, 1.02)
                            } else {
                                tr.range(prof.speed[0], prof.speed[1])
                            },
                            radius,
                            dest,
                            profile: pi as u8,
                            leader: leader_id,
                            familiarity: tr.range(prof.familiarity[0], prof.familiarity[1]),
                            sign_compliance: tr
                                .range(prof.sign_compliance[0], prof.sign_compliance[1]),
                            crowd_following: tr
                                .range(prof.crowd_following[0], prof.crowd_following[1]),
                            patience: tr.range(prof.patience[0], prof.patience[1]),
                            stairs_aversion: prof.stairs_aversion,
                            last_node: door_node,
                            spawn_time: time,
                            next_decision: time,
                        };
                        self.agents.push(na);
                        let idx = self.agents.len() - 1;
                        let dn = self.dest_nodes[dest as usize] as usize;
                        self.agents.ideal_time[idx] = self.fields[dn].dist_at(&self.grid, p)
                            / self.agents.desired_speed[idx].max(0.3);
                        self.slot_of.push(idx as u32);
                        self.belief_sign.push(u8::MAX);
                        self.belief.push([-1.0; 4]);
                    }
                    let d = &mut self.sources[si].doors[di];
                    d.acc = (d.acc - gsize as f32).max(0.0);
                    self.sources[si].remaining -= gsize;
                }
            }
        }
    }

    fn read_signs(&mut self) {
        if self.signs.is_empty() {
            return;
        }
        for i in 0..self.agents.len() {
            let p = self.agents.pos[i];
            for si in 0..self.signs.len() {
                let bit = 1u8 << si;
                if self.agents.signs_read[i] & bit != 0 {
                    continue;
                }
                let s = &self.signs[si];
                if (s.pos - p).len() > s.radius {
                    continue;
                }
                self.agents.signs_read[i] |= bit;
                let m = &s.modes[s.mode];
                if m.kind == "off" {
                    continue;
                }
                // Not everyone reads every sign; compliance also scales how much they act on it.
                let read_p = 0.35 + 0.65 * self.agents.sign_compliance[i];
                if self.rng_decisions.f32() >= read_p {
                    continue;
                }
                self.signs[si].reads += 1;
                let m = &self.signs[si].modes[self.signs[si].mode];
                match m.kind.as_str() {
                    "route" => {
                        let dest_ok = m
                            .destination
                            .as_ref()
                            .map(|d| self.dest_ids[self.agents.dest[i] as usize] == *d)
                            .unwrap_or(false);
                        if dest_ok {
                            let via = self.sc.node_index(m.via.as_ref().unwrap()).unwrap() as u16;
                            self.agents.sign_via[i] = via;
                            self.agents.next_decision[i] = self.time;
                        }
                    }
                    "wait_times" => {
                        self.belief_sign[self.agents.id[i] as usize] = si as u8;
                        let mut b = [-1.0f32; 4];
                        for (k, w) in self.signs[si].shown_waits.iter().take(4).enumerate() {
                            b[k] = *w;
                        }
                        self.belief[self.agents.id[i] as usize] = b;
                        self.agents.next_decision[i] = self.time;
                    }
                    _ => {}
                }
            }
        }
    }

    fn refresh_sign_waits(&mut self) {
        for si in 0..self.signs.len() {
            let m = &self.signs[si].modes[self.signs[si].mode];
            if m.kind != "wait_times" {
                self.signs[si].shown_waits.clear();
                continue;
            }
            let waits: Vec<f32> = m
                .compare
                .iter()
                .map(|c| self.reported_node_wait[self.sc.node_index(c).unwrap()])
                .collect();
            self.signs[si].shown_waits = waits;
        }
    }

    fn decide(&mut self) {
        let n_nodes = self.graph.nodes.len();
        let mut node_wait = [0.0f32; MAX_NODES];
        for g in &self.gates {
            node_wait[g.node as usize] = g.wait_estimate();
        }
        let mut dist = [f32::INFINITY; MAX_NODES];
        let mut dirs = [Vec2::ZERO; MAX_NODES];
        let mut believed = [-1.0f32; MAX_NODES];
        let mut herd = [0.0f32; MAX_NODES];
        let mut counts = [0u16; MAX_NODES];
        let mut route = std::mem::take(&mut self.route_buf);
        for i in 0..self.agents.len() {
            if self.time < self.agents.next_decision[i] {
                continue;
            }
            let interval = self.sc.tuning.decision_interval;
            self.agents.next_decision[i] = self.time + interval;
            let id = self.agents.id[i];
            let leader = self.agents.leader[i];
            if leader != id {
                // group members follow the leader's route
                let li = self.slot_of[leader as usize];
                if li != NONE32 {
                    let li = li as usize;
                    let lr = self.agents.route[li];
                    let (lp, ll) = (self.agents.route_pos[li], self.agents.route_len[li]);
                    // adopt the leader's remaining route (skipping nodes this member already passed)
                    let lnext = self.agents.next_node(li);
                    if lnext != self.agents.next_node(i) || self.agents.route_len[i] == 0 {
                        self.agents.route[i] = lr;
                        self.agents.route_pos[i] = lp;
                        self.agents.route_len[i] = ll;
                        self.agents.last_node[i] = self.agents.last_node[li];
                    }
                    self.agents.sign_via[i] = self.agents.sign_via[li];
                    continue;
                }
                // leader already arrived: decide alone
            }
            let p = self.agents.pos[i];
            for (u, d) in dist.iter_mut().enumerate().take(n_nodes) {
                *d = self.fields[u].dist_at(&self.grid, p);
                dirs[u] = self.fields[u].direction(&self.grid, p);
            }
            for b in believed.iter_mut() {
                *b = -1.0;
            }
            let bs = self.belief_sign[id as usize];
            if (bs as usize) < self.signs.len() {
                let m = &self.signs[bs as usize].modes[self.signs[bs as usize].mode];
                if m.kind == "wait_times" {
                    for (k, c) in m.compare.iter().take(4).enumerate() {
                        let v = self.belief[id as usize][k];
                        if v >= 0.0 {
                            believed[self.sc.node_index(c).unwrap()] = v;
                        }
                    }
                }
            }
            // herding: what nearby people bound for the same place are doing
            for c in counts.iter_mut() {
                *c = 0;
            }
            let mut total = 0u16;
            let dest = self.agents.dest[i];
            {
                let ag = &self.agents;
                self.spatial.for_each_near(p, |j| {
                    if j != i && ag.dest[j] == dest && (ag.pos[j] - p).len_sq() < 9.0 {
                        let nn = ag.next_node(j);
                        if (nn as usize) < MAX_NODES {
                            counts[nn as usize] += 1;
                            total += 1;
                        }
                    }
                });
            }
            for u in 0..n_nodes {
                herd[u] = if total >= 3 {
                    counts[u] as f32 / total as f32
                } else {
                    0.0
                };
            }
            let impatient = self.agents.wait_now[i] > self.agents.patience[i];
            let inp = ChoiceInput {
                graph: &self.graph,
                pos: p,
                speed: self.agents.desired_speed[i],
                dest_node: self.dest_nodes[dest as usize],
                last_node: self.agents.last_node[i],
                current_next: self.agents.next_node(i),
                familiarity: self.agents.familiarity[i],
                sign_compliance: self.agents.sign_compliance[i],
                crowd_following: self.agents.crowd_following[i],
                stairs_aversion: self.agents.stairs_aversion[i],
                sign_via: self.agents.sign_via[i],
                impatient,
                dist_to_node: &dist[..n_nodes],
                node_wait: &node_wait[..n_nodes],
                believed_wait: &believed[..n_nodes],
                area_speed: &self.area_speed,
                area_static: &self.area_static,
                area_center: &self.area_center,
                herd_share: &herd[..n_nodes],
                dir_to_node: &dirs[..n_nodes],
            };
            if choose_route(&inp, &mut route) {
                let old_next = self.agents.next_node(i);
                if old_next != route[0] || self.agents.route_len[i] == 0 {
                    self.agents.set_route(i, &route);
                    self.agents.gate_pass[i] = if self.agents.gate_pass[i] != NONE16
                        && self.graph.nodes[route[0] as usize].gate
                            == Some(self.agents.gate_pass[i])
                    {
                        self.agents.gate_pass[i]
                    } else {
                        NONE16
                    };
                } else {
                    // same next hop: refresh the tail of the route
                    self.agents.set_route(i, &route);
                }
                if self.agents.state[i] == State::Stuck {
                    self.agents.state[i] = State::Walking;
                }
                if impatient {
                    // they acted on their frustration; give the new choice time to work
                    self.agents.wait_now[i] = 0.0;
                }
            } else {
                self.agents.state[i] = State::Stuck;
                self.agents.next_decision[i] = self.time + 2.0;
            }
        }
        self.route_buf = route;
    }

    fn movement(&mut self) {
        let n = self.agents.len();
        let tuning = self.sc.tuning.clone();
        let dt = self.dt;
        let t_gap = tuning.time_gap;
        self.new_dir.clear();
        self.new_dir.resize(n, Vec2::ZERO);
        self.new_speed.clear();
        self.new_speed.resize(n, 0.0);
        // group cohesion: leaders slow down when members fall behind
        for v in self.agents.leader_slow.iter_mut() {
            *v = false;
        }
        for i in 0..n {
            let l = self.agents.leader[i];
            if l != self.agents.id[i] {
                let li = self.slot_of[l as usize];
                if li != NONE32 && (self.agents.pos[li as usize] - self.agents.pos[i]).len() > 3.0 {
                    self.agents.leader_slow[li as usize] = true;
                }
            }
        }
        // gate queues (people holding at each gate this tick)
        for g in self.gates.iter_mut() {
            g.queue = 0;
        }
        for i in 0..n {
            if self.agents.state[i] == State::Holding {
                let nn = self.agents.next_node(i);
                if (nn as usize) < self.graph.nodes.len() {
                    if let Some(g) = self.graph.nodes[nn as usize].gate {
                        self.gates[g as usize].queue += 1;
                    }
                }
            }
        }
        // service: serve the people closest to each metered line first (deterministic order)
        // Service queue: unserved people at a metered line who are heading through it, whether it
        // is their next waypoint or they are simply pressing into it.
        let mut waiting = std::mem::take(&mut self.waiting_buf);
        waiting.clear();
        for i in 0..n {
            let nn = self.agents.next_node(i);
            let route_gate = if (nn as usize) < self.graph.nodes.len() {
                self.graph.nodes[nn as usize].gate
            } else {
                None
            };
            let p = self.agents.pos[i];
            for (gi, g) in self.gates.iter().enumerate() {
                let gi = gi as u16;
                if g.mode != GateMode::Metered || self.agents.gate_pass[i] == gi {
                    continue;
                }
                let s = g.side(p);
                if s <= -(tuning.gate_hold + self.agents.radius[i] + 0.35)
                    || s >= 0.0
                    || g.lateral(p) >= g.half_len + 1.0
                {
                    continue;
                }
                if route_gate == Some(gi) || self.agents.heading[i].dot(g.normal) > 0.2 {
                    waiting.push((gi, s, self.agents.id[i], i));
                }
            }
        }
        waiting.sort_by(|a, b| {
            a.0.cmp(&b.0)
                .then(b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal))
                .then(a.2.cmp(&b.2))
        });
        for &(gi, _, _, i) in &waiting {
            let g = &mut self.gates[gi as usize];
            let rate = g.lane_rate * g.level * g.service_factor;
            if rate <= 0.0 {
                continue;
            }
            // earliest free lane (lowest index on ties)
            let mut best = 0;
            for l in 1..g.lane_free.len() {
                if g.lane_free[l] < g.lane_free[best] {
                    best = l;
                }
            }
            if g.lane_free[best] <= self.time {
                g.lane_free[best] = self.time + 1.0 / rate;
                g.served += 1;
                self.agents.gate_pass[i] = gi;
            }
        }

        self.waiting_buf = waiting;
        let ag = &self.agents;
        let grid = &self.grid;
        // Beyond the cutoff neighbours neither repel measurably (8 e^-11 at 1.5 m) nor limit speed
        // (spacing only binds below v0 * T + 2r, about 1.2 m at T = 0.5 s).
        let cutoff2 = tuning.interaction_radius * tuning.interaction_radius;
        let mut near = std::mem::take(&mut self.near_buf);
        for i in 0..n {
            let p = ag.pos[i];
            let ri = ag.radius[i];
            let nn = ag.next_node(i);
            let mut e0 = Vec2::ZERO;
            let mut v0 = ag.desired_speed[i];
            if (nn as usize) < self.fields.len() {
                e0 = self.fields[nn as usize].direction(grid, p);
            }
            let area = ag.area[i];
            if (area as usize) < self.areas.len() {
                v0 *= self.areas[area as usize].speed_factor;
            }
            if ag.leader_slow[i] {
                v0 *= 0.4;
            }
            // followers stay near their leader
            let l = ag.leader[i];
            if l != ag.id[i] {
                let li = self.slot_of[l as usize];
                if li != NONE32 {
                    let to = ag.pos[li as usize] - p;
                    let d = to.len();
                    if d > 2.0 && e0 != Vec2::ZERO {
                        e0 = (e0 + to.norm() * 0.6).norm();
                        if d > 3.0 {
                            v0 *= 1.3;
                        }
                    }
                }
            }
            if e0 == Vec2::ZERO {
                continue;
            }
            // --- collision-free speed model: direction
            let mut dir = e0;
            let mut spacing = f32::INFINITY;
            let hi = ag.heading[i];
            // Neighbours within the cutoff, gathered once and reused for the spacing pass.
            near.clear();
            self.spatial.for_each_near(p, |j| {
                if j == i {
                    return;
                }
                let dvec = p - ag.pos[j];
                let d2 = dvec.len_sq();
                if d2 > cutoff2 || d2 < 1e-10 {
                    return;
                }
                let d = d2.sqrt();
                near.push((j as u32, d));
                let l = ri + ag.radius[j];
                let nij = dvec * (1.0 / d);
                let rep = tuning.neighbor_strength * exp((l - d) / tuning.neighbor_range);
                dir += nij * rep;
                // counterflow: keep-right bias breaks head-on symmetry (lane formation)
                if ag.heading[j].dot(hi) < -0.5 && (-nij).dot(e0) > 0.3 {
                    dir += e0.perp() * (-rep * 0.5);
                }
            });
            for &wi in grid.walls_near(p) {
                let w = &grid.walls[wi as usize];
                let q = closest_on_segment(p, w.a, w.b);
                let dv = p - q;
                let d = dv.len();
                if !(1e-5..=1.0).contains(&d) {
                    continue;
                }
                dir += dv * (tuning.wall_strength * exp((ri - d) / tuning.wall_range) / d);
            }
            let e = dir.norm();
            let e = if e == Vec2::ZERO { e0 } else { e };
            // --- speed: spacing to the nearest person ahead (within body width of the path)
            for &(j, d) in near.iter() {
                let j = j as usize;
                let dv = ag.pos[j] - p;
                if dv.dot(e) <= 0.0 {
                    continue;
                }
                let l = ri + ag.radius[j];
                if dv.cross(e).abs() >= l {
                    continue;
                }
                let s = d - l;
                if s < spacing {
                    spacing = s;
                }
            }
            // Queue discipline (gameplay approximation): people knowingly waiting for a metered or fare
            // gate keep a little personal space instead of pressing into body contact, as managed
            // queues do in practice (Fruin queue LOS C-D). Uncontrolled jams still compress fully.
            if (nn as usize) < self.graph.nodes.len() {
                if let Some(gi) = self.graph.nodes[nn as usize].gate {
                    let g = &self.gates[gi as usize];
                    if g.mode == GateMode::Metered && ag.gate_pass[i] != gi {
                        let s = g.side(p);
                        // only the gap to the person ahead grows; the hold line itself is unchanged
                        if s < 0.0 && s > -QUEUE_REACH && spacing.is_finite() {
                            spacing -= tuning.queue_gap;
                        }
                    }
                }
            }
            // (As in JuPedSim's CFSM, walls act only through the direction term above; the hard
            // collision pass below keeps bodies out of walls.)
            // unserved people stop at a metered gate's hold line
            if (nn as usize) < self.graph.nodes.len() {
                if let Some(gi) = self.graph.nodes[nn as usize].gate {
                    let g = &self.gates[gi as usize];
                    if g.mode != GateMode::Open
                        && ag.gate_pass[i] != gi
                        && g.lateral(p) < g.half_len + 1.0
                    {
                        let s = g.side(p);
                        let along = e.dot(g.normal);
                        if along > 0.05 && s < 0.0 {
                            let avail = (-s - tuning.gate_hold - ri).max(0.0);
                            let sp = avail / along;
                            if sp < spacing {
                                spacing = sp;
                            }
                        }
                    }
                }
            }
            let v = v0.min((spacing / t_gap).max(0.0));
            self.new_dir[i] = e;
            self.new_speed[i] = v;
        }
        self.near_buf = near;

        // apply movement, collisions with walls, gate crossings
        let tuning_hold = tuning.gate_hold;
        for i in 0..n {
            let e = self.new_dir[i];
            let v = self.new_speed[i];
            let old = self.agents.pos[i];
            let mut p = old + e * (v * dt);
            let ri = self.agents.radius[i];
            for &wi in self.grid.walls_near(p) {
                let w = &self.grid.walls[wi as usize];
                if segments_intersect(old, p, w.a, w.b) {
                    // slide along the wall instead of stopping dead
                    let t = (w.b - w.a).norm();
                    p = old + t * (p - old).dot(t);
                }
            }
            for &wi in self.grid.walls_near(p) {
                let w = &self.grid.walls[wi as usize];
                if segments_intersect(old, p, w.a, w.b) {
                    p = old;
                }
            }
            for _ in 0..2 {
                for &wi in self.grid.walls_near(p) {
                    let w = &self.grid.walls[wi as usize];
                    let q = closest_on_segment(p, w.a, w.b);
                    let dv = p - q;
                    let d = dv.len();
                    if d < ri {
                        let nrm = if d > 1e-5 {
                            dv * (1.0 / d)
                        } else {
                            (old - q).norm()
                        };
                        let nrm = if nrm == Vec2::ZERO {
                            Vec2::new(0.0, 1.0)
                        } else {
                            nrm
                        };
                        p = q + nrm * ri;
                    }
                }
            }
            // metered line: never cross without service
            let nn = self.agents.next_node(i);
            if (nn as usize) < self.graph.nodes.len() {
                if let Some(gi) = self.graph.nodes[nn as usize].gate {
                    let g = &self.gates[gi as usize];
                    if g.mode != GateMode::Open
                        && self.agents.gate_pass[i] != gi
                        && g.lateral(p) < g.half_len + 1.0
                    {
                        let s = g.side(p);
                        let limit = -tuning_hold - ri * 0.5;
                        if s > limit && g.side(old) <= limit + 1e-4 {
                            p = p - g.normal * (s - limit);
                        }
                    }
                }
            }
            // Every gate line, not just the one on this person's route: crossing downstream needs
            // service at a metered gate; crossing upstream is impossible at a one-way gate.
            for gi in 0..self.gates.len() {
                let g = &self.gates[gi];
                if (closest_on_segment(old, g.a, g.b) - old).len() > 2.5
                    || !segments_intersect(old, p, g.a, g.b)
                {
                    continue;
                }
                let forward = (p - old).dot(g.normal) > 0.0;
                let allowed = if forward {
                    g.mode == GateMode::Open || self.agents.gate_pass[i] == gi as u16
                } else {
                    !g.one_way
                };
                if allowed {
                    if forward {
                        let g = &mut self.gates[gi];
                        g.passed.add(1);
                        g.total_passed += 1;
                        if self.agents.gate_pass[i] == gi as u16 {
                            self.agents.gate_pass[i] = NONE16;
                        }
                    }
                } else {
                    let t = g.tangent;
                    let slid = old + t * (p - old).dot(t);
                    p = if segments_intersect(old, slid, g.a, g.b) {
                        old
                    } else {
                        slid
                    };
                    if segments_intersect(old, p, g.a, g.b) {
                        self.gates[gi].violations += 1;
                    }
                }
            }
            self.agents.prev[i] = old;
            self.agents.pos[i] = p;
            let moved = (p - old).len() / dt;
            self.agents.speed[i] = moved;
            if moved > 0.05 {
                self.agents.heading[i] = (p - old).norm();
            }
        }

        // gate crossings, node arrivals, completions
        self.remove_buf.clear();
        for i in 0..n {
            let nn = self.agents.next_node(i);
            if (nn as usize) >= self.graph.nodes.len() {
                continue;
            }
            let p = self.agents.pos[i];
            let node = &self.graph.nodes[nn as usize];
            let mut reached = (p - node.pos).len() <= node.radius
                || self.fields[nn as usize].dist_at(&self.grid, p) <= node.radius * 0.8;
            if !reached {
                // Progress rule for intermediate waypoints: once the agent is (geodesically) closer to
                // the following node than this waypoint is, it has passed it. Without this, a
                // waypoint in a crowded passage is unreachable and people mill around it.
                let rp = self.agents.route_pos[i] as usize + 1;
                if rp < self.agents.route_len[i] as usize {
                    let after = self.agents.route[i][rp] as usize;
                    let f = &self.fields[after];
                    let d_agent = f.dist_at(&self.grid, p);
                    let d_node = f.dist_at(&self.grid, node.pos);
                    if d_agent.is_finite() && d_agent <= d_node + node.radius * 0.5 {
                        reached = true;
                    }
                }
            }
            let gate_ok = match node.gate {
                Some(gi) => self.gates[gi as usize].side(p) >= 0.0,
                None => true,
            };
            if reached && gate_ok {
                self.agents.last_node[i] = nn;
                self.agents.route_pos[i] += 1;
                if node.dest == Some(self.agents.dest[i]) {
                    self.remove_buf.push(i);
                } else if self.agents.next_node(i) == NONE16 {
                    self.agents.next_decision[i] = self.time;
                }
            }
        }
        // waiting and satisfaction
        for i in 0..n {
            let slow = self.agents.speed[i] < tuning.wait_speed;
            let holding = {
                let nn = self.agents.next_node(i);
                (nn as usize) < self.graph.nodes.len()
                    && self.graph.nodes[nn as usize].gate.map(|g| {
                        let gate = &self.gates[g as usize];
                        let sd = gate.side(self.agents.pos[i]);
                        gate.mode != GateMode::Open
                            && self.agents.gate_pass[i] != g
                            && sd < 0.0
                            && sd > -QUEUE_REACH
                    }) == Some(true)
            };
            if self.agents.state[i] != State::Stuck {
                self.agents.state[i] = if holding && slow {
                    State::Holding
                } else if slow {
                    State::Slowed
                } else {
                    State::Walking
                };
            }
            if slow {
                let a = self.agents.area[i];
                if (a as usize) < self.areas.len() {
                    self.areas[a as usize].wait_person_seconds += dt;
                }
                self.agents.wait_now[i] += dt;
                self.agents.wait_total[i] += dt;
                let over = (self.agents.wait_now[i] / self.agents.patience[i]).min(2.0);
                self.agents.satisfaction[i] -= dt * (0.05 + 0.25 * over);
            } else {
                self.agents.wait_now[i] = (self.agents.wait_now[i] - dt * 2.0).max(0.0);
            }
            let lvl = self.density.level[self.density.index(self.agents.pos[i])];
            self.agents.satisfaction[i] -= dt
                * match lvl {
                    Level::Danger => 1.0,
                    Level::Heavy => 0.25,
                    _ => 0.0,
                };
            if self.agents.satisfaction[i] < 0.0 {
                self.agents.satisfaction[i] = 0.0;
            }
        }
        // remove arrivals (descending index keeps earlier indices valid)
        let mut rm = std::mem::take(&mut self.remove_buf);
        rm.sort_unstable();
        for &i in rm.iter().rev() {
            self.complete(i);
        }
        self.remove_buf = rm;
    }

    fn complete(&mut self, i: usize) {
        let journey = self.time + self.dt - self.agents.spawn_time[i];
        let ideal = self.agents.ideal_time[i].max(1.0);
        let mut sat = self.agents.satisfaction[i];
        let ratio = journey / ideal;
        if ratio > 1.6 {
            sat -= ((ratio - 1.6) * 10.0).min(15.0);
        }
        let sat = sat.max(0.0);
        self.completed += 1;
        self.completed_by_dest[self.agents.dest[i] as usize] += 1;
        self.journey_sum += journey;
        self.satisfaction_sum += sat;
        if self.agents.wait_total[i] > self.wait_max {
            self.wait_max = self.agents.wait_total[i];
        }
        let area = self.agents.area[i];
        if (area as usize) < self.areas.len() {
            self.areas[area as usize].outflow.add(1);
        }
        let id = self.agents.id[i];
        self.slot_of[id as usize] = NONE32;
        self.agents.swap_remove(i);
        if i < self.agents.len() {
            let moved = self.agents.id[i];
            self.slot_of[moved as usize] = i as u32;
        }
    }

    fn measure(&mut self) {
        let dt = self.dt;
        // velocity estimate from last displacement
        let mut vel = std::mem::take(&mut self.vel_buf);
        vel.clear();
        vel.extend(
            (0..self.agents.len()).map(|i| (self.agents.pos[i] - self.agents.prev[i]) * (1.0 / dt)),
        );
        self.density.update(&self.agents.pos, &vel, dt);
        self.vel_buf = vel;
        let peak = self.density.peak();
        if peak > self.peak_density {
            self.peak_density = peak;
        }
        // area membership and flows
        for a in self.areas.iter_mut() {
            a.occupancy = 0;
            a.speed_sum = 0.0;
            a.heavy_cells = 0;
            a.danger_cells = 0;
        }
        for i in 0..self.agents.len() {
            let p = self.agents.pos[i];
            let mut na = u8::MAX;
            for (k, a) in self.areas.iter().enumerate() {
                if a.rect.contains(p) {
                    na = k as u8;
                    break;
                }
            }
            let old = self.agents.area[i];
            if na != old {
                if (old as usize) < self.areas.len() {
                    self.areas[old as usize].outflow.add(1);
                }
                if (na as usize) < self.areas.len() {
                    self.areas[na as usize].inflow.add(1);
                }
                self.agents.area[i] = na;
            }
            if (na as usize) < self.areas.len() {
                let a = &mut self.areas[na as usize];
                a.occupancy += 1;
                a.speed_sum += self.agents.speed[i];
            }
        }
        for c in 0..self.density.level.len() {
            let ai = self.density.area_of[c];
            if (ai as usize) < self.areas.len() {
                match self.density.level[c] {
                    Level::Danger => {
                        self.areas[ai as usize].danger_cells += 1;
                        self.areas[ai as usize].heavy_cells += 1;
                    }
                    Level::Heavy => self.areas[ai as usize].heavy_cells += 1,
                    _ => {}
                }
                let d = self.density.density[c];
                if d > self.areas[ai as usize].peak_density {
                    self.areas[ai as usize].peak_density = d;
                }
            }
        }
        let mut any_heavy = false;
        let mut any_danger = false;
        let k = (dt / crate::metrics::SMOOTH_TAU).min(1.0);
        for ai in 0..self.areas.len() {
            let a = &mut self.areas[ai];
            let rho = a.occupancy as f32 / a.walk_area;
            a.density += (rho - a.density) * k;
            a.mean_speed = if a.occupancy > 0 {
                a.speed_sum / a.occupancy as f32
            } else {
                0.0
            };
            a.level = if a.danger_cells >= AREA_DANGER_CELLS {
                Level::Danger
            } else if a.heavy_cells >= AREA_HEAVY_CELLS {
                Level::Heavy
            } else if a.density >= crate::metrics::CROWDED_DENSITY || a.heavy_cells > 0 {
                Level::Crowded
            } else {
                Level::Comfortable
            };
            if a.level >= Level::Heavy {
                a.heavy_seconds += dt;
                any_heavy = true;
            }
            if a.level == Level::Danger {
                a.danger_seconds += dt;
                any_danger = true;
            }
            self.area_speed[ai] = weidmann_factor(a.density.max(a.occupancy as f32 / a.walk_area));
        }
        if any_heavy {
            self.heavy_seconds += dt;
        }
        if any_danger {
            self.danger_seconds += dt;
        }
        // warnings when an area gets worse
        for ai in 0..self.areas.len() {
            let lvl = self.areas[ai].level;
            if lvl > self.area_prev_level[ai]
                && lvl >= Level::Heavy
                && self.time - self.area_last_warn[ai] > 20.0
            {
                self.area_last_warn[ai] = self.time;
                let text = match lvl {
                    Level::Danger => format!("{}: dangerous crowding", self.area_names[ai]),
                    _ => format!("{}: heavy congestion", self.area_names[ai]),
                };
                self.log_event(
                    if lvl == Level::Danger {
                        "danger"
                    } else {
                        "warning"
                    },
                    text,
                    Some(ai),
                );
            }
            self.area_prev_level[ai] = lvl;
        }
        // staff cost while metering
        for g in &self.gates {
            if g.controllable && g.mode == GateMode::Metered {
                self.staff_spent += g.staff_cost_per_min * dt / 60.0;
            }
        }
        // once per simulated second: roll rate counters, refresh sensors and sign readouts
        self.second_acc += dt;
        if self.second_acc >= 1.0 - 1e-4 {
            self.second_acc -= 1.0;
            for a in self.areas.iter_mut() {
                a.inflow.roll();
                a.outflow.roll();
            }
            for g in self.gates.iter_mut() {
                g.passed.roll();
            }
            self.refresh_reports(false);
            self.refresh_sign_waits();
        }
    }

    /// Update what the operator sees. Delayed areas refresh only every `period` seconds.
    fn refresh_reports(&mut self, force: bool) {
        let t = self.time + self.dt;
        for ai in 0..self.areas.len() {
            let period = if self.perfect_info {
                0.0
            } else {
                self.delayed_period[ai]
            };
            let due = period <= 0.0 || force || (t - self.reported[ai].at) >= period - 1e-3;
            if !due {
                continue;
            }
            let a = &self.areas[ai];
            let delayed = period > 0.0;
            let mut render = Vec::new();
            let mut texels = Vec::new();
            if delayed {
                for i in 0..self.agents.len() {
                    if self.agents.area[i] as usize == ai {
                        self.push_render_record(i, &mut render, false);
                    }
                }
                for c in 0..self.density.area_of.len() {
                    if self.density.area_of[c] as usize == ai {
                        texels.push((c as u32, self.density_texel(c)));
                    }
                }
            }
            self.reported[ai] = Reported {
                occupancy: a.occupancy,
                density: a.density,
                level: a.level as u8,
                at: self.time,
                delayed,
                in_pm: a.inflow.per_minute(),
                out_pm: a.outflow.per_minute(),
                render,
                texels,
            };
            for gi in 0..self.gates.len() {
                if self.gates[gi].area as usize == ai {
                    let g = &self.gates[gi];
                    self.reported_node_wait[g.node as usize] = g.wait_estimate();
                    self.reported_gate_flow[gi] = g.passed.per_minute();
                }
            }
        }
        // gates outside any area report live
        for g in &self.gates {
            if g.area == u8::MAX {
                self.reported_node_wait[g.node as usize] = g.wait_estimate();
            }
        }
    }

    pub fn reported_wait(&self, node: u16) -> f32 {
        self.reported_node_wait[node as usize]
    }

    fn check_outcome(&mut self) {
        let fc = &self.sc.failure_conditions;
        let ob = &self.sc.objectives;
        if self.danger_seconds >= fc.max_danger_seconds {
            self.outcome = Outcome::FailedDanger;
        } else if (self.reservoir() == 0 && self.agents.is_empty()) || self.time >= ob.time_limit {
            let enough = self.completed as f32 >= ob.clear_fraction * self.total_population as f32;
            self.outcome = if enough {
                Outcome::Won
            } else {
                Outcome::FailedTimeout
            };
        }
        if self.outcome != Outcome::Running {
            self.ended_at = self.time;
            let text = match self.outcome {
                Outcome::Won => "Operation complete".to_string(),
                Outcome::FailedDanger => {
                    "Operation halted: dangerous crowding lasted too long".to_string()
                }
                _ => "Time is up with people still on site".to_string(),
            };
            self.log_event("end", text, None);
        }
    }

    /// Conservation: everyone is still inside, on site, or delivered.
    pub fn population_balance(&self) -> (u32, u32, u32, u32) {
        (
            self.reservoir(),
            self.active(),
            self.completed,
            self.total_population,
        )
    }

    /// FNV-1a over the state that matters for replay.
    pub fn checksum(&self) -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut mix = |v: u64| {
            for b in v.to_le_bytes() {
                h ^= b as u64;
                h = h.wrapping_mul(0x0000_0100_0000_01B3);
            }
        };
        mix(self.tick);
        mix(self.agents.len() as u64);
        for i in 0..self.agents.len() {
            mix(self.agents.id[i] as u64);
            mix(self.agents.pos[i].x.to_bits() as u64);
            mix(self.agents.pos[i].y.to_bits() as u64);
            mix(self.agents.next_node(i) as u64);
        }
        mix(self.completed as u64);
        mix(self.reservoir() as u64);
        for g in &self.gates {
            mix(g.total_passed as u64);
            for l in &g.lane_free {
                mix(l.to_bits() as u64);
            }
        }
        mix(self.spent.to_bits() as u64);
        mix(self.danger_seconds.to_bits() as u64);
        h
    }

    /// Step until the end (or `max_ticks`), applying `commands` at their ticks. Used by replay and
    /// headless experiments.
    pub fn run_with(
        &mut self,
        commands: &[TimedCommand],
        max_ticks: u64,
    ) -> Vec<Result<serde_json::Value, String>> {
        let mut results = Vec::new();
        let mut k = 0;
        while !self.is_over() && self.tick < max_ticks {
            while k < commands.len() && commands[k].tick <= self.tick {
                results.push(self.apply(commands[k].cmd.clone()));
                k += 1;
            }
            self.step();
        }
        results
    }
}
