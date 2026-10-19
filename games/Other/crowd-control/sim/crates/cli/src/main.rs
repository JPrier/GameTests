//! `crowd`: headless harness for the crowd simulation.
//!
//!   crowd validate <scenario.json>...
//!   crowd run <scenario.json> [--seed N] [--population N] [--commands cmds.json] [--out replay.json]
//!   crowd replay <scenario.json> <replay.json>
//!   crowd bench <scenario.json> [--populations 500,1000,5000] [--ticks N] [--out bench.json]
//!   crowd experiments <scenario.json> [--seeds N] [--out experiments.json]
//!   crowd trace <scenario.json> [--every SECONDS] [--strategy NAME]
//!   crowd research <scenario.json>       (timestep and route-reconsideration studies)
//!   crowd checksum <scenario.json> [--ticks N] [--commands cmds.json]   (compare with tools/wasm_check.mjs)

mod strategies;

use crowd_core::replay::Replay;
use crowd_core::sim::{LoadOptions, Sim, TimedCommand};
use crowd_core::{score, Scenario};
use serde_json::json;
use std::time::Instant;

fn arg(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1).cloned())
}

fn load(path: &str) -> Scenario {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| die(&format!("{path}: {e}")));
    Scenario::from_json(&text).unwrap_or_else(|e| die(&format!("{path}: {e}")))
}

fn die(msg: &str) -> ! {
    eprintln!("error: {msg}");
    std::process::exit(1)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let cmd = args.get(1).map(String::as_str).unwrap_or("help");
    match cmd {
        "validate" => {
            let mut bad = 0;
            for p in &args[2..] {
                let text = std::fs::read_to_string(p).unwrap_or_else(|e| die(&format!("{p}: {e}")));
                match Scenario::from_json(&text)
                    .and_then(|sc| Sim::new(sc, &LoadOptions::default()).map(|_| ()))
                {
                    Ok(()) => println!("ok      {p}"),
                    Err(e) => {
                        println!("INVALID {p}: {e}");
                        bad += 1;
                    }
                }
            }
            std::process::exit(if bad > 0 { 1 } else { 0 });
        }
        "run" => {
            let sc = load(
                args.get(2)
                    .map(String::as_str)
                    .unwrap_or_else(|| die("scenario path required")),
            );
            let opts = LoadOptions {
                seed: arg(&args, "--seed").map(|s| s.parse().unwrap()),
                population: arg(&args, "--population").map(|s| s.parse().unwrap()),
            };
            let commands: Vec<TimedCommand> = match arg(&args, "--commands") {
                Some(p) => serde_json::from_str(&std::fs::read_to_string(&p).unwrap())
                    .unwrap_or_else(|e| die(&format!("{p}: {e}"))),
                None => Vec::new(),
            };
            let mut sim = Sim::new(sc, &opts).unwrap_or_else(|e| die(&e.0));
            let max = (sim.sc.objectives.time_limit / sim.dt) as u64 + 10;
            let t0 = Instant::now();
            for (i, r) in sim.run_with(&commands, max).into_iter().enumerate() {
                if let Err(e) = r {
                    eprintln!("command {i} rejected: {e}");
                }
            }
            let wall = t0.elapsed().as_secs_f64();
            let rep = score::report(&sim);
            println!("{}", serde_json::to_string_pretty(&rep).unwrap());
            eprintln!(
                "simulated {:.0} s in {:.2} s wall ({} ticks)",
                sim.time, wall, sim.tick
            );
            if let Some(out) = arg(&args, "--out") {
                let replay = Replay::record(&sim, &opts);
                std::fs::write(&out, serde_json::to_string_pretty(&replay).unwrap()).unwrap();
                eprintln!("replay written to {out}");
            }
        }
        "replay" => {
            let sc = load(
                args.get(2)
                    .map(String::as_str)
                    .unwrap_or_else(|| die("scenario path required")),
            );
            let p = args.get(3).unwrap_or_else(|| die("replay path required"));
            let rep: Replay = serde_json::from_str(&std::fs::read_to_string(p).unwrap())
                .unwrap_or_else(|e| die(&format!("{p}: {e}")));
            match rep.verify(&sc) {
                Ok(sim) => println!(
                    "replay ok: {} checksums matched, final tick {}, checksum {:016x}",
                    rep.checksums.len(),
                    sim.tick,
                    sim.checksum()
                ),
                Err(e) => die(&format!("replay FAILED: {e}")),
            }
        }
        "bench" => bench(&args),
        "checksum" => {
            let sc = load(
                args.get(2)
                    .map(String::as_str)
                    .unwrap_or_else(|| die("scenario path required")),
            );
            let ticks: u64 = arg(&args, "--ticks")
                .map(|s| s.parse().unwrap())
                .unwrap_or(2000);
            let commands: Vec<TimedCommand> = match arg(&args, "--commands") {
                Some(p) => serde_json::from_str(&std::fs::read_to_string(&p).unwrap())
                    .unwrap_or_else(|e| die(&format!("{p}: {e}"))),
                None => Vec::new(),
            };
            let mut sim = Sim::new(sc, &LoadOptions::default()).unwrap_or_else(|e| die(&e.0));
            sim.run_with(&commands, ticks);
            println!("{:016x}", sim.checksum());
        }
        "experiments" => strategies::experiments(&args),
        "research" => research(&args),
        "trace" => strategies::trace(&args),
        _ => {
            eprintln!("usage: crowd <validate|run|replay|bench|experiments|trace> ... (see source header)");
            std::process::exit(2);
        }
    }
}

fn percentile(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let k = ((sorted.len() - 1) as f64 * p).round() as usize;
    sorted[k]
}

/// Steps the scenario at several population levels and records per-tick timing percentiles,
/// per-system averages, peak agent count and throughput.
fn bench(args: &[String]) {
    let path = args
        .get(2)
        .map(String::as_str)
        .unwrap_or_else(|| die("scenario path required"));
    let sc = load(path);
    let pops: Vec<u32> = arg(args, "--populations")
        .unwrap_or_else(|| "500,1000,5000".into())
        .split(',')
        .map(|s| s.trim().parse().unwrap())
        .collect();
    let max_ticks: u64 = arg(args, "--ticks")
        .map(|s| s.parse().unwrap())
        .unwrap_or(4000);
    let mut results = Vec::new();
    for &pop in &pops {
        let opts = LoadOptions {
            population: Some(pop),
            seed: None,
        };
        let t_load = Instant::now();
        let mut sim = Sim::new(sc.clone(), &opts).unwrap_or_else(|e| die(&e.0));
        let load_ms = t_load.elapsed().as_secs_f64() * 1000.0;
        let origin = Instant::now();
        let clock = move || origin.elapsed().as_secs_f64();
        let mut times = Vec::new();
        let mut peak_agents = 0usize;
        let mut agent_ticks = 0u64;
        let mut render = Vec::new();
        let mut render_ms = 0.0;
        let mut worst = (0.0f64, 0u64, json!({}));
        while !sim.is_over() && sim.tick < max_ticks {
            let before = sim.timings.clone();
            let t = Instant::now();
            sim.step_timed(Some(&clock));
            let ms = t.elapsed().as_secs_f64() * 1000.0;
            times.push(ms);
            if ms > worst.0 {
                let a = &sim.timings;
                let d = |x: f64, y: f64| (x - y) * 1000.0;
                worst = (
                    ms,
                    sim.tick,
                    json!({
                        "fields": d(a.fields, before.fields), "spawn": d(a.spawn, before.spawn),
                        "neighbor_index": d(a.neighbor_index, before.neighbor_index), "decisions": d(a.decisions, before.decisions),
                        "movement": d(a.movement, before.movement), "density": d(a.density, before.density),
                        "agents": sim.agents.len(),
                    }),
                );
            }
            peak_agents = peak_agents.max(sim.agents.len());
            agent_ticks += sim.agents.len() as u64;
            if sim.tick.is_multiple_of(3) {
                let t = Instant::now();
                sim.render_buffer(&mut render);
                render_ms += t.elapsed().as_secs_f64() * 1000.0;
            }
        }
        // barrier placement cost: full field rebuild, measured synchronously
        let t = Instant::now();
        for i in 0..sim.fields.len() {
            let n = &sim.graph.nodes[i];
            let _ = crowd_core::grid::build_field(&sim.grid, &sim.grid.walkable, n.pos, n.radius);
        }
        let rebuild_ms = t.elapsed().as_secs_f64() * 1000.0;
        let mut sorted = times.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let mean = times.iter().sum::<f64>() / times.len().max(1) as f64;
        let r = json!({
            "population": pop,
            "ticks": sim.tick,
            "sim_seconds": sim.time,
            "peak_microscopic_agents": peak_agents,
            "mean_agents": agent_ticks as f64 / sim.tick.max(1) as f64,
            "fidelity": "microscopic CFSM outside, aggregate reservoir inside the stadium",
            "step_ms": {"mean": mean, "p50": percentile(&sorted, 0.5), "p95": percentile(&sorted, 0.95), "p99": percentile(&sorted, 0.99), "max": sorted.last().copied().unwrap_or(0.0)},
            "systems_ms": sim.timing_report(),
            "render_buffer_ms": render_ms / (sim.tick / 3).max(1) as f64,
            "load_ms": load_ms,
            "worst_tick": {"ms": worst.0, "tick": worst.1, "systems_ms": worst.2},
            "full_field_rebuild_ms": rebuild_ms,
            "realtime_factor_20hz": if mean > 0.0 { 50.0 / mean } else { 0.0 },
            "outcome": sim.outcome,
            "completed": sim.completed,
        });
        eprintln!(
            "pop {:>6}: peak {:>5} agents, step p50 {:.2} ms p95 {:.2} ms p99 {:.2} ms max {:.2} ms, field rebuild {:.1} ms",
            pop,
            peak_agents,
            percentile(&sorted, 0.5),
            percentile(&sorted, 0.95),
            percentile(&sorted, 0.99),
            sorted.last().copied().unwrap_or(0.0),
            rebuild_ms
        );
        results.push(r);
    }
    let report = json!({
        "scenario": sc.scenario_id,
        "build": if cfg!(debug_assertions) { "debug" } else { "release" },
        "machine": machine(),
        "results": results,
    });
    let text = serde_json::to_string_pretty(&report).unwrap();
    match arg(args, "--out") {
        Some(p) => std::fs::write(&p, text).unwrap(),
        None => println!("{text}"),
    }
}

fn machine() -> serde_json::Value {
    let cpu = std::fs::read_to_string("/proc/cpuinfo")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("model name"))
                .map(|l| l.split(':').nth(1).unwrap_or("").trim().to_string())
        })
        .unwrap_or_else(|| "unknown".into());
    let cores = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1);
    json!({"cpu": cpu, "logical_cores": cores, "os": std::env::consts::OS, "arch": std::env::consts::ARCH, "threads_used": 1})
}

/// Empirical studies behind two design decisions: the fixed timestep and how often people
/// reconsider their route. Each variant runs the full scenario (no player action) over 3 seeds.
fn research(args: &[String]) {
    let path = args
        .get(2)
        .map(String::as_str)
        .unwrap_or_else(|| die("scenario path required"));
    let base = load(path);
    let seeds = [base.seed, base.seed + 7919, base.seed + 2 * 7919];
    let run = |sc: &crowd_core::Scenario| {
        let mut out = Vec::new();
        for &seed in &seeds {
            let mut sim = Sim::new(
                sc.clone(),
                &LoadOptions {
                    seed: Some(seed),
                    population: None,
                },
            )
            .unwrap();
            let t0 = Instant::now();
            let mut overlap_ticks = 0u64;
            let mut overlaps = 0u64;
            while !sim.is_over() && sim.time < sc.objectives.time_limit {
                sim.step();
                // body overlap: pairs closer than 60% of the summed radii
                if sim.tick.is_multiple_of(10) {
                    overlap_ticks += 1;
                    let a = &sim.agents;
                    // the sim's own index is from before this tick's arrivals left; build a fresh one
                    let mut grid = crowd_core::spatial::SpatialGrid::new(sc.map.size, 2.0);
                    grid.rebuild(&a.pos);
                    for i in 0..a.len() {
                        grid.for_each_near(a.pos[i], |j| {
                            if j > i
                                && (a.pos[i] - a.pos[j]).len() < 0.6 * (a.radius[i] + a.radius[j])
                            {
                                overlaps += 1;
                            }
                        });
                    }
                }
            }
            let r = score::report(&sim);
            out.push((
                r.avg_journey,
                sim.danger_seconds,
                sim.heavy_seconds,
                overlaps as f64 / overlap_ticks.max(1) as f64,
                t0.elapsed().as_secs_f64() / sim.time.max(1.0) as f64 * 1000.0,
                sim.completed,
            ));
        }
        let n = out.len() as f64;
        let m = |k: usize| {
            out.iter()
                .map(|o| [o.0 as f64, o.1 as f64, o.2 as f64, o.3, o.4, o.5 as f64][k])
                .sum::<f64>()
                / n
        };
        (m(0), m(1), m(2), m(3), m(4), m(5))
    };
    println!("## Timestep (no action, 3 seeds)");
    println!("| dt (s) | rate | avg journey s | danger s | heavy s | overlapping pairs/tick | ms per sim-second | delivered |");
    println!("|---:|---:|---:|---:|---:|---:|---:|---:|");
    for dt in [0.1f32, 0.05, 1.0 / 30.0] {
        let mut sc = base.clone();
        sc.tuning.dt = dt;
        let (j, d, h, o, ms, c) = run(&sc);
        println!(
            "| {dt:.3} | {:.0} Hz | {j:.1} | {d:.1} | {h:.1} | {o:.2} | {ms:.2} | {c:.0} |",
            1.0 / dt
        );
    }
    println!();
    println!("## Route reconsideration interval (dt 0.05, 3 seeds)");
    println!("| interval (s) | avg journey s | danger s | heavy s | ms per sim-second |");
    println!("|---:|---:|---:|---:|---:|");
    for iv in [1.0f32, 2.0, 4.0, 8.0, 16.0] {
        let mut sc = base.clone();
        sc.tuning.decision_interval = iv;
        let (j, d, h, _, ms, _) = run(&sc);
        println!("| {iv:.0} | {j:.1} | {d:.1} | {h:.1} | {ms:.2} |");
    }
}
