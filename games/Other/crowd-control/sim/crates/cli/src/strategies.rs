//! Scripted operator strategies for gameplay validation: each runs over several seeds and is
//! compared with doing nothing, so dominant or pointless strategies show up as numbers.

use crowd_core::score;
use crowd_core::sim::{Command, GateMode, LoadOptions, Outcome, Sim};
use serde_json::json;

type Policy = fn(&mut Sim, &mut PolicyState);

#[derive(Default)]
pub struct PolicyState {
    step: u32,
    done: Vec<&'static str>,
}

impl PolicyState {
    fn once(&mut self, key: &'static str) -> bool {
        if self.done.contains(&key) {
            false
        } else {
            self.done.push(key);
            true
        }
    }
}

fn incident_active(sim: &Sim) -> bool {
    sim.incidents.iter().any(|e| e.active)
}
fn incident_over(sim: &Sim) -> bool {
    sim.incidents.iter().all(|e| !e.happens || e.done)
}

fn cmd(sim: &mut Sim, c: Command) {
    if let Err(e) = sim.apply(c.clone()) {
        eprintln!("  (strategy command {c:?} rejected: {e})");
    }
}

fn sign(sim: &mut Sim, s: &str, m: &str) {
    cmd(
        sim,
        Command::Sign {
            sign: s.into(),
            mode: m.into(),
        },
    );
}
fn gate(sim: &mut Sim, g: &str, mode: GateMode, level: Option<f32>) {
    cmd(
        sim,
        Command::Gate {
            gate: g.into(),
            mode,
            level,
        },
    );
}

fn none(_: &mut Sim, _: &mut PolicyState) {}

/// Show live wait times at both plaza signs from the start.
fn wait_signs(sim: &mut Sim, st: &mut PolicyState) {
    if st.once("signs") {
        sign(sim, "sign_n", "waits");
        sign(sim, "sign_s", "waits");
    }
}

/// Send train passengers south on both signs for the whole event.
fn divert_south(sim: &mut Sim, st: &mut PolicyState) {
    if st.once("signs") {
        sign(sim, "sign_n", "trains_south");
        sign(sim, "sign_s", "trains_south");
    }
}

/// Meter the North Gate to a quarter while the train is delayed; keep the crowd in the plaza.
fn meter_north(sim: &mut Sim, st: &mut PolicyState) {
    if incident_active(sim) && st.once("meter") {
        gate(sim, "gate_a", GateMode::Metered, Some(0.25));
    }
    if incident_over(sim) && st.done.contains(&"meter") && st.once("reopen") {
        gate(sim, "gate_a", GateMode::Open, None);
    }
}

/// Close the North Gate during the delay (everyone south), reopen afterwards.
fn close_north(sim: &mut Sim, st: &mut PolicyState) {
    if incident_active(sim) && st.once("close") {
        gate(sim, "gate_a", GateMode::Closed, None);
    }
    if incident_over(sim) && st.done.contains(&"close") && st.once("reopen") {
        gate(sim, "gate_a", GateMode::Open, None);
    }
}

/// Trains via the North Gate on both signs (keeps the South Walkway for car park traffic), and
/// meter the North Gate at half rate during the delay so the overflow waits in the open plaza.
fn north_and_meter(sim: &mut Sim, st: &mut PolicyState) {
    if st.once("signs") {
        sign(sim, "sign_n", "trains_north");
        sign(sim, "sign_s", "trains_north");
    }
    if incident_active(sim) && st.once("meter") {
        gate(sim, "gate_a", GateMode::Metered, Some(0.1));
    }
    if incident_over(sim) && st.done.contains(&"meter") && st.once("reopen") {
        gate(sim, "gate_a", GateMode::Open, None);
    }
}

/// Trickle the North Gate (10%) during the delay, nothing else.
fn trickle_north(sim: &mut Sim, st: &mut PolicyState) {
    if incident_active(sim) && st.once("meter") {
        gate(sim, "gate_a", GateMode::Metered, Some(0.1));
    }
    if incident_over(sim) && st.done.contains(&"meter") && st.once("reopen") {
        gate(sim, "gate_a", GateMode::Open, None);
    }
}

/// Hold the crowd in the open plaza during the delay: meter both gates (the South Gate less,
/// since car park traffic uses it too), with wait-time signs to balance the two station halls.
fn hold_in_plaza(sim: &mut Sim, st: &mut PolicyState) {
    wait_signs(sim, st);
    if incident_active(sim) && st.once("meter") {
        gate(sim, "gate_a", GateMode::Metered, Some(0.1));
        gate(sim, "gate_b", GateMode::Metered, Some(0.25));
    }
    if incident_over(sim) && st.done.contains(&"meter") && st.once("reopen") {
        gate(sim, "gate_a", GateMode::Open, None);
        gate(sim, "gate_b", GateMode::Open, None);
    }
}

/// React to what the operator sees: meter whichever gate feeds a heavily congested walkway or hall,
/// reopen it once that area recovers. Uses only operator-visible (possibly delayed) information.
fn reactive(sim: &mut Sim, st: &mut PolicyState) {
    wait_signs(sim, st);
    if !st.step.is_multiple_of(20) {
        return;
    }
    let level = |sim: &Sim, ids: &[&str]| -> u8 {
        ids.iter()
            .filter_map(|id| sim.area_ids.iter().position(|a| a == id))
            .map(|i| {
                if sim.reported[i].delayed && !sim.perfect_info {
                    sim.reported[i].level
                } else {
                    sim.areas[i].level as u8
                }
            })
            .max()
            .unwrap_or(0)
    };
    for (g, watched) in [
        ("gate_a", &["north_corridor", "station_north"][..]),
        (
            "gate_b",
            &["south_corridor", "station_south", "connector"][..],
        ),
    ] {
        let lv = level(sim, watched);
        let gi = sim.gates.iter().position(|x| x.id == g).unwrap();
        let mode = sim.gates[gi].mode;
        if lv >= 2 && mode == GateMode::Open {
            gate(sim, g, GateMode::Metered, Some(0.25));
        } else if lv == 0 && mode == GateMode::Metered {
            gate(sim, g, GateMode::Open, None);
        }
    }
}

/// Wait-time signs plus metering the North Gate during the delay.
fn signs_and_meter(sim: &mut Sim, st: &mut PolicyState) {
    wait_signs(sim, st);
    meter_north(sim, st);
}

/// A barrier pen that gives the station-ramp queue its own space in the South Junction, so it no
/// longer spills into the car park stream.
fn ramp_pen(sim: &mut Sim, st: &mut PolicyState) {
    if st.once("barriers") {
        for (a, b) in [
            ([117.0, 64.5], [117.0, 70.0]),
            ([117.0, 70.0], [124.0, 70.0]),
        ] {
            cmd(sim, Command::BarrierAdd { a, b });
        }
    }
}

/// Ramp pen plus a light hold on the North Gate during the delay.
fn pen_and_meter(sim: &mut Sim, st: &mut PolicyState) {
    ramp_pen(sim, st);
    if incident_active(sim) && st.once("meter") {
        gate(sim, "gate_a", GateMode::Metered, Some(0.25));
    }
    if incident_over(sim) && st.done.contains(&"meter") && st.once("reopen") {
        gate(sim, "gate_a", GateMode::Open, None);
    }
}

/// Ramp pen plus holding both gates lightly during the delay.
fn expert(sim: &mut Sim, st: &mut PolicyState) {
    ramp_pen(sim, st);
    if incident_active(sim) && st.once("meter") {
        gate(sim, "gate_a", GateMode::Metered, Some(0.25));
        gate(sim, "gate_b", GateMode::Metered, Some(0.5));
    }
    if incident_over(sim) && st.done.contains(&"meter") && st.once("reopen") {
        gate(sim, "gate_a", GateMode::Open, None);
        gate(sim, "gate_b", GateMode::Open, None);
    }
}

pub fn policies() -> Vec<(&'static str, &'static str, Policy)> {
    vec![
        ("none", "Do nothing", none as Policy),
        ("wait_signs", "Wait-time signs", wait_signs),
        ("divert_south", "Signs: trains via South Gate", divert_south),
        (
            "meter_north",
            "Meter North Gate during the delay",
            meter_north,
        ),
        (
            "close_north",
            "Close North Gate during the delay",
            close_north,
        ),
        ("signs_and_meter", "Wait signs + metering", signs_and_meter),
        (
            "north_and_meter",
            "Trains north + meter during delay",
            north_and_meter,
        ),
        (
            "trickle_north",
            "Trickle North Gate (10%) in the delay",
            trickle_north,
        ),
        (
            "hold_in_plaza",
            "Hold crowd in plaza (meter both)",
            hold_in_plaza,
        ),
        ("reactive", "Meter whichever side is congested", reactive),
        ("ramp_pen", "Barrier pen for the ramp queue", ramp_pen),
        (
            "pen_and_meter",
            "Ramp pen + meter North in the delay",
            pen_and_meter,
        ),
        ("expert", "Ramp pen + hold both gates lightly", expert),
    ]
}

pub fn run_policy(sc: &crowd_core::Scenario, seed: u64, pop: Option<u32>, policy: Policy) -> Sim {
    let mut sim = Sim::new(
        sc.clone(),
        &LoadOptions {
            seed: Some(seed),
            population: pop,
        },
    )
    .expect("scenario");
    let mut st = PolicyState::default();
    let max = (sim.sc.objectives.time_limit / sim.dt) as u64 + 10;
    while !sim.is_over() && sim.tick < max {
        policy(&mut sim, &mut st);
        st.step += 1;
        sim.step();
    }
    sim
}

pub fn experiments(args: &[String]) {
    let path = args
        .get(2)
        .map(String::as_str)
        .unwrap_or_else(|| crate::die("scenario path required"));
    let sc = crate::load(path);
    let seeds: u64 = crate::arg(args, "--seeds")
        .map(|s| s.parse().unwrap())
        .unwrap_or(5);
    let pop = crate::arg(args, "--population").map(|s| s.parse().unwrap());
    let only = crate::arg(args, "--only");
    let mut rows = Vec::new();
    let mut table: Vec<(String, Vec<i32>)> = Vec::new();
    println!(
        "{:<34} {:>6} {:>5} {:>8} {:>8} {:>8} {:>8} {:>7} {:>5} {:>6}",
        "strategy",
        "score",
        "stars",
        "journey",
        "maxwait",
        "heavy_s",
        "danger_s",
        "cost",
        "sat",
        "fails"
    );
    for (key, label, p) in policies() {
        if let Some(o) = &only {
            if !o.split(',').any(|x| x == key) {
                continue;
            }
        }
        let mut scores = Vec::new();
        let mut agg = [0.0f64; 7];
        let mut fails = 0;
        for k in 0..seeds {
            let seed = sc.seed.wrapping_add(k * 7919);
            let sim = run_policy(&sc, seed, pop, p);
            let r = score::report(&sim);
            if r.outcome != Outcome::Won {
                fails += 1;
            }
            scores.push(r.score);
            for (i, v) in [
                r.score as f32,
                r.stars as f32,
                r.avg_journey,
                r.max_wait,
                r.heavy_seconds,
                r.danger_seconds,
                r.cost,
            ]
            .iter()
            .enumerate()
            {
                agg[i] += *v as f64;
            }
            rows.push(
                json!({"strategy": key, "seed": seed, "report": r, "satisfaction": r.satisfaction}),
            );
        }
        let n = seeds as f64;
        let sat: f64 = rows
            .iter()
            .filter(|r| r["strategy"] == key)
            .map(|r| r["satisfaction"].as_f64().unwrap())
            .sum::<f64>()
            / n;
        println!(
            "{:<34} {:>6.0} {:>5.1} {:>8.0} {:>8.0} {:>8.0} {:>8.1} {:>7.0} {:>5.0} {:>6}",
            label,
            agg[0] / n,
            agg[1] / n,
            agg[2] / n,
            agg[3] / n,
            agg[4] / n,
            agg[5] / n,
            agg[6] / n,
            sat,
            fails
        );
        table.push((key.to_string(), scores));
    }
    // Dominance check: a strategy that wins on every seed by a wide margin is a balancing problem.
    let mut findings = Vec::new();
    for k in 0..seeds as usize {
        let mut best = (String::new(), i32::MIN, i32::MIN);
        for (name, s) in &table {
            if s[k] > best.1 {
                best = (name.clone(), s[k], best.1);
            } else if s[k] > best.2 {
                best.2 = s[k];
            }
        }
        findings.push(json!({"seed_index": k, "best": best.0, "margin": best.1 - best.2}));
    }
    let winners: std::collections::BTreeSet<String> = findings
        .iter()
        .map(|f| f["best"].as_str().unwrap().to_string())
        .collect();
    if winners.len() == 1 {
        println!(
            "\nNOTE: '{}' was best on every seed: check for a dominant strategy.",
            winners.iter().next().unwrap()
        );
    } else {
        println!("\nBest strategy varied across seeds: {:?}", winners);
    }
    if let Some(out) = crate::arg(args, "--out") {
        std::fs::write(
            out,
            serde_json::to_string_pretty(&json!({"runs": rows, "best_by_seed": findings})).unwrap(),
        )
        .unwrap();
    }
}

pub fn trace(args: &[String]) {
    let path = args
        .get(2)
        .map(String::as_str)
        .unwrap_or_else(|| crate::die("scenario path required"));
    let sc = crate::load(path);
    let every: f32 = crate::arg(args, "--every")
        .map(|s| s.parse().unwrap())
        .unwrap_or(20.0);
    let name = crate::arg(args, "--strategy").unwrap_or_else(|| "none".into());
    let seed = crate::arg(args, "--seed")
        .map(|s| s.parse().unwrap())
        .unwrap_or(sc.seed);
    let pop = crate::arg(args, "--population").map(|s| s.parse().unwrap());
    let policy = policies()
        .into_iter()
        .find(|p| p.0 == name)
        .map(|p| p.2)
        .unwrap_or_else(|| crate::die("unknown strategy"));
    let mut sim = Sim::new(
        sc,
        &LoadOptions {
            seed: Some(seed),
            population: pop,
        },
    )
    .unwrap();
    let mut st = PolicyState::default();
    let mut next = 0.0;
    let mut log_seen = 0;
    if let Some(spec) = crate::arg(args, "--barriers") {
        for b in spec.split(';') {
            let v: Vec<f32> = b.split(',').map(|x| x.trim().parse().unwrap()).collect();
            match sim.apply(Command::BarrierAdd {
                a: [v[0], v[1]],
                b: [v[2], v[3]],
            }) {
                Ok(_) => {}
                Err(e) => println!("barrier {b} rejected: {e}"),
            }
        }
    }
    while !sim.is_over() && sim.time < sim.sc.objectives.time_limit + 1.0 {
        policy(&mut sim, &mut st);
        sim.step();
        for e in &sim.log[log_seen..] {
            println!("        [{:>5.0}s] {}: {}", e.t, e.kind, e.text);
        }
        log_seen = sim.log.len();
        if crate::arg(args, "--long").is_some() && sim.tick.is_multiple_of(200) {
            for i in 0..sim.agents.len() {
                if sim.agents.wait_total[i] > 250.0 && sim.agents.wait_total[i] < 251.0 {
                    println!(
                        "t={:.0} long wait: {}",
                        sim.time,
                        sim.inspect(sim.agents.pos[i])
                    );
                }
            }
        }
        if let Some(spec) = crate::arg(args, "--dump") {
            // --dump AREA@SECONDS: list everyone in an area at that time
            let (area, at) = spec.split_once('@').unwrap();
            let at: f32 = at.parse().unwrap();
            if (sim.time - at).abs() < sim.dt * 0.5 {
                for i in 0..sim.agents.len() {
                    if sim.agents.area[i] as usize
                        == sim.area_ids.iter().position(|a| a == area).unwrap()
                    {
                        let nn = sim.agents.next_node(i);
                        println!("  #{} pos ({:.1},{:.1}) next {} state {:?} speed {:.2} heading ({:.2},{:.2}) dest {} pass {}", sim.agents.id[i], sim.agents.pos[i].x, sim.agents.pos[i].y, if (nn as usize) < sim.graph.nodes.len() { sim.graph.nodes[nn as usize].id.as_str() } else { "-" }, sim.agents.state[i], sim.agents.speed[i], sim.agents.heading[i].x, sim.agents.heading[i].y, sim.agents.dest[i], sim.agents.gate_pass[i]);
                    }
                }
            }
        }
        if sim.time >= next {
            next += every;
            let (res, act, done, _) = sim.population_balance();
            let gates: Vec<String> = sim
                .gates
                .iter()
                .map(|g| format!("{}:q{} {}/m", g.id, g.queue, g.passed.per_minute()))
                .collect();
            let areas: Vec<String> = sim
                .areas
                .iter()
                .enumerate()
                .filter(|(_, a)| a.occupancy > 0)
                .map(|(i, a)| {
                    format!(
                        "{}:{} d{:.1} L{}",
                        sim.area_ids[i], a.occupancy, a.density, a.level as u8
                    )
                })
                .collect();
            let signs: Vec<String> = sim
                .signs
                .iter()
                .map(|s| format!("{}:{}r", s.id, s.reads))
                .collect();
            let advised = sim
                .agents
                .sign_via
                .iter()
                .filter(|v| **v != u16::MAX)
                .count();
            println!("t={:>5.0} in={:>4} act={:>4} done={:>4} danger={:>4.0}s heavy={:>4.0}s | {} | {} | {} adv={}", sim.time, res, act, done, sim.danger_seconds, sim.heavy_seconds, gates.join(" "), areas.join(" "), signs.join(" "), advised);
        }
    }
    let r = score::report(&sim);
    if crate::arg(args, "--json").is_some() {
        println!("{}", serde_json::to_string_pretty(&r).unwrap());
    }
    println!("score {} stars {} outcome {:?} journey {:.0} maxwait {:.0} heavy {:.0} danger {:.1} cost {:.0} sat {:.0}", r.score, r.stars, r.outcome, r.avg_journey, r.max_wait, r.heavy_seconds, r.danger_seconds, r.cost, r.satisfaction);
    for (i, a) in sim.areas.iter().enumerate() {
        if a.heavy_seconds > 0.0 || a.danger_seconds > 0.0 {
            println!(
                "  {:<16} heavy {:>5.0}s danger {:>5.1}s peak {:.1} wait_ps {:.0}",
                sim.area_ids[i],
                a.heavy_seconds,
                a.danger_seconds,
                a.peak_density,
                a.wait_person_seconds
            );
        }
    }
    for i in 0..sim.agents.len() {
        if sim.agents.wait_total[i] > 200.0 {
            println!("long wait: {}", sim.inspect(sim.agents.pos[i]));
        }
    }
}
