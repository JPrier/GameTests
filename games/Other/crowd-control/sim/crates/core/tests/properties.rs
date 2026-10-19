//! Invariants over randomised maps, populations and seeds, plus replay determinism and scenario
//! validation. (Hand-rolled property loops with the crate's own seeded RNG: no extra dependencies.)

mod common;
use common::*;
use crowd_core::replay::Replay;
use crowd_core::rng::Rng;
use crowd_core::sim::{Command, GateMode, LoadOptions, Sim, TimedCommand};
use crowd_core::Scenario;
use serde_json::json;

fn stadium() -> Scenario {
    let text = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../scenarios/stadium_departure.json"
    ))
    .unwrap();
    Scenario::from_json(&text).unwrap()
}

/// A random map: a big room split by a wall with 1-3 random openings, a metered gate in one of
/// them, random population and seed.
fn random_world(seed: u64) -> (Spec, u32) {
    let mut r = Rng::new(seed);
    let pop = r.int(20, 200) as u32;
    let wall_x = r.range(18.0, 26.0).round();
    let n_open = r.int(1, 3) as usize;
    let mut walls = Vec::new();
    let mut ys: Vec<f32> = (0..n_open)
        .map(|k| 3.0 + k as f32 * 9.0 + r.range(0.0, 3.0))
        .collect();
    ys.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mut y = 0.0f32;
    for (k, oy) in ys.iter().enumerate() {
        let w = r.range(1.5, 3.0);
        walls.push([wall_x, y, wall_x, *oy]);
        y = oy + w;
        if k == n_open - 1 {
            walls.push([wall_x, y, wall_x, 30.0]);
        }
    }
    let first_open = (ys[0], walls[1][1]);
    let mid = (first_open.0 + first_open.1) * 0.5;
    let spec = Spec {
        size: [50.0, 30.0],
        walkable: vec![[0.0, 0.0, 50.0, 30.0]],
        walls,
        nodes: vec![
            node("in", 3.0, 15.0, 1.0),
            node("g", wall_x + 1.5, mid, 0.8),
            node("out", 46.0, 15.0, 2.0),
        ],
        edges: vec![edge("in", "g"), edge("g", "out")],
        gates: vec![
            json!({"id": "g", "name": "G", "node": "g", "line": [wall_x, first_open.0 + 0.05, wall_x, first_open.1 - 0.05],
            "lanes": 2, "lane_rate": r.range(0.5, 2.0), "controllable": true, "default_mode": "metered", "meter_levels": [1.0, 0.5]}),
        ],
        dests: vec![dest("out", "out")],
        sources: vec![source(
            "s",
            pop,
            "in",
            [0.5, 2.0, 6.0, 26.0],
            r.range(1.0, 8.0),
            &[("out", 1.0)],
        )],
        group: [1, r.int(1, 4) as u32],
        seed,
        ..Default::default()
    };
    (spec, pop)
}

#[test]
fn invariants_hold_on_random_worlds() {
    for seed in 0..12u64 {
        let (spec, pop) = random_world(seed);
        let mut sim = spec.sim();
        let mut ok_walk = true;
        let mut ok_pop = true;
        let mut ok_rate = true;
        let mut window: Vec<(f32, u32)> = Vec::new();
        run_until_done(&mut sim, 900.0, |s| {
            if ok_walk && !all_on_walkable(s) {
                for i in 0..s.agents.len() {
                    if !s.grid.is_base_walkable(s.agents.pos[i]) {
                        println!(
                            "seed {seed} t={:.2} agent {} at {:?} prev {:?}",
                            s.time, s.agents.id[i], s.agents.pos[i], s.agents.prev[i]
                        );
                    }
                }
            }
            ok_walk &= all_on_walkable(s);
            let (res, act, done, total) = s.population_balance();
            ok_pop &= res + act + done == total && total == pop;
            // service tokens never exceed lanes * rate over any 10 s window (+ one per lane), and nobody
            // crosses without a token (violations), so throughput is bounded by the service rate
            let g = &s.gates[0];
            window.push((s.time, g.served));
            while window.len() > 1 && s.time - window[0].0 > 10.0 {
                window.remove(0);
            }
            if g.mode == GateMode::Metered && window.len() > 1 {
                let passed = g.served - window[0].1;
                let cap = g.lanes as f32 * g.lane_rate * g.level * (s.time - window[0].0)
                    + g.lanes as f32
                    + 0.5;
                ok_rate &= passed as f32 <= cap;
            }
        });
        assert!(ok_walk, "seed {seed}: someone left walkable ground");
        assert!(ok_pop, "seed {seed}: population not conserved");
        assert!(
            ok_rate,
            "seed {seed}: metered gate exceeded its service rate"
        );
        assert_eq!(sim.gates[0].violations, 0, "seed {seed}: unserved crossing");
        assert_eq!(
            sim.completed, pop,
            "seed {seed}: not everyone arrived ({} of {pop})",
            sim.completed
        );
    }
}

#[test]
fn closed_gate_passes_nobody_on_random_worlds() {
    for seed in 20..26u64 {
        let (spec, _) = random_world(seed);
        let mut sim = spec.sim();
        sim.apply(Command::Gate {
            gate: "g".into(),
            mode: GateMode::Closed,
            level: None,
        })
        .unwrap();
        let mut before = 0;
        run_until_done(&mut sim, 120.0, |s| before = s.gates[0].total_passed);
        assert_eq!(before, 0, "seed {seed}: closed gate passed people");
    }
}

#[test]
fn stadium_population_is_conserved_every_tick() {
    let mut sim = Sim::new(stadium(), &LoadOptions::default()).unwrap();
    while !sim.is_over() {
        sim.step();
        let (res, act, done, total) = sim.population_balance();
        assert_eq!(res + act + done, total, "tick {}", sim.tick);
        assert!(all_on_walkable(&sim), "tick {}", sim.tick);
    }
    assert!(sim.gates.iter().all(|g| g.violations == 0));
}

#[test]
fn same_seed_same_state_and_different_seed_differs() {
    let run = |seed: u64| {
        let mut sim = Sim::new(
            stadium(),
            &LoadOptions {
                seed: Some(seed),
                population: None,
            },
        )
        .unwrap();
        for _ in 0..1200 {
            sim.step();
        }
        sim.checksum()
    };
    assert_eq!(run(7), run(7));
    assert_ne!(run(7), run(8));
}

#[test]
fn replay_reproduces_and_detects_tampering() {
    let sc = stadium();
    let opts = LoadOptions::default();
    let cmds = vec![
        TimedCommand {
            tick: 300,
            cmd: Command::Sign {
                sign: "sign_n".into(),
                mode: "waits".into(),
            },
        },
        TimedCommand {
            tick: 2400,
            cmd: Command::Gate {
                gate: "gate_a".into(),
                mode: GateMode::Metered,
                level: Some(0.25),
            },
        },
        TimedCommand {
            tick: 2500,
            cmd: Command::BarrierAdd {
                a: [294.0, 193.5],
                b: [294.0, 210.0],
            },
        },
        TimedCommand {
            tick: 3600,
            cmd: Command::Gate {
                gate: "gate_a".into(),
                mode: GateMode::Open,
                level: None,
            },
        },
    ];
    let mut sim = Sim::new(sc.clone(), &opts).unwrap();
    let res = sim.run_with(&cmds, 4000);
    assert!(res.iter().all(|r| r.is_ok()), "{res:?}");
    let rec = Replay::record(&sim, &opts);
    assert!(rec.checksums.len() >= 30);
    // round trip through JSON
    let text = serde_json::to_string(&rec).unwrap();
    let back: Replay = serde_json::from_str(&text).unwrap();
    back.verify(&sc).expect("replay verifies");
    // a changed command must be detected
    let mut bad = back.clone();
    // (closing the gate instead of metering it changes who gets through)
    bad.commands[1].cmd = Command::Gate {
        gate: "gate_a".into(),
        mode: GateMode::Closed,
        level: None,
    };
    assert!(bad.verify(&sc).is_err(), "tampered replay must fail");
}

#[test]
fn barrier_placement_rules() {
    let mut sim = Sim::new(stadium(), &LoadOptions::default()).unwrap();
    for _ in 0..200 {
        sim.step();
    }
    let add = |sim: &mut Sim, a: [f32; 2], b: [f32; 2]| sim.apply(Command::BarrierAdd { a, b });
    assert!(
        add(&mut sim, [5.0, 5.0], [10.0, 5.0]).is_err(),
        "outside zones"
    );
    assert!(
        add(&mut sim, [130.0, 60.0], [170.0, 60.0]).is_err(),
        "too long"
    );
    assert!(
        add(&mut sim, [290.0, 200.0], [290.1, 200.0]).is_err(),
        "too short"
    );
    // a barrier across the whole north walkway would cut the north route but not trap anyone
    // (they can still go south), so it is allowed, and the route graph sees the cut
    let ok = add(&mut sim, [280.0, 39.1], [280.0, 59.9]);
    assert!(ok.is_ok(), "{ok:?}");
    for _ in 0..20 {
        sim.step();
    }
    assert_eq!(sim.fields_pending(), 0);
    // the walkway is cut, so the geodesic from the North Gate to the north entrance now runs the
    // long way round through the station (platforms -> south hall -> ramp -> south walkway)
    let cut = sim
        .graph
        .edges
        .iter()
        .find(|e| {
            sim.graph.nodes[e.a as usize].id == "gate_a"
                && sim.graph.nodes[e.b as usize].id == "north_end"
        })
        .unwrap();
    assert!(
        cut.length > 120.0,
        "the route graph must see the cut walkway (length {})",
        cut.length
    );
    // everyone heading north re-routes; nobody crosses the barrier
    for _ in 0..1200 {
        sim.step();
        for i in 0..sim.agents.len() {
            let p = sim.agents.pos[i];
            let q = sim.agents.prev[i];
            assert!(
                !((q.x < 280.0 && p.x >= 280.0 || q.x > 280.0 && p.x <= 280.0)
                    && p.y > 39.0
                    && p.y < 60.0),
                "crossed the barrier"
            );
        }
    }
    // a barrier that would trap the people behind the first one is refused
    assert!(
        add(&mut sim, [274.0, 39.1], [274.0, 59.9]).is_err()
            || sim
                .agents
                .pos
                .iter()
                .all(|p| !(p.x > 274.0 && p.x < 280.0 && p.y < 60.0))
    );
}

#[test]
fn invalid_scenarios_are_rejected() {
    let base: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../scenarios/stadium_departure.json"
        ))
        .unwrap(),
    )
    .unwrap();
    let check = |f: &dyn Fn(&mut serde_json::Value), expect: &str| {
        let mut v = base.clone();
        f(&mut v);
        let err = Scenario::from_json(&v.to_string())
            .and_then(|sc| Sim::new(sc, &LoadOptions::default()).map(|_| ()));
        let msg = err.expect_err(&format!("should reject: {expect}")).0;
        assert!(msg.contains(expect), "expected '{expect}' in '{msg}'");
    };
    check(&|v| v["schema_version"] = json!(2), "schema_version");
    check(&|v| v["edges"][0]["b"] = json!("nowhere"), "unknown node");
    check(&|v| v["gates"][0]["lane_rate"] = json!(-1.0), "lane_rate");
    check(
        &|v| v["nodes"][0]["pos"] = json!([10.0, 2.0]),
        "not on walkable ground",
    );
    check(
        &|v| v["map"]["walkable"][0] = json!([0, 0, 500, 10]),
        "outside the map",
    );
    check(
        &|v| v["spawn_schedules"][0]["destination_mix"][0][0] = json!("moon"),
        "unknown destination",
    );
    check(
        &|v| v["event_schedule"][0]["target"] = json!("bus"),
        "unknown transit",
    );
    check(
        &|v| v["population_profiles"][0]["speed"] = json!([2.0, 1.0]),
        "speed range",
    );
    check(
        &|v| v["signs"][0]["default_mode"] = json!("shout"),
        "default_mode",
    );
    check(&|v| v["nodes"][1]["id"] = json!("door1"), "duplicate node");
    check(&|v| v["unexpected"] = json!(1), "unknown field");
}

#[test]
fn overlays_and_queries_do_not_change_state() {
    let mut a = Sim::new(stadium(), &LoadOptions::default()).unwrap();
    let mut b = Sim::new(stadium(), &LoadOptions::default()).unwrap();
    let mut buf = Vec::new();
    let mut img = Vec::new();
    for t in 0..1500 {
        a.step();
        b.step();
        if t % 7 == 0 {
            b.render_buffer(&mut buf);
            b.density_image(&mut img);
            let _ = b.telemetry(0);
            let _ = b.explain("plaza");
            let _ = b.inspect(crowd_core::math::Vec2::new(60.0, 40.0));
            let _ = b.check_barrier(
                crowd_core::math::Vec2::new(50.0, 30.0),
                crowd_core::math::Vec2::new(58.0, 30.0),
            );
        }
    }
    assert_eq!(a.checksum(), b.checksum());
}

/// Independent geometric audit of every gate line (not the simulation's own counters): nobody walks
/// back through a one-way fare line, and downstream crossings of metered lines never exceed the
/// service tokens issued there.
#[test]
fn nobody_bypasses_fare_or_metered_gates() {
    for seed in [1u64, 2, 3] {
        let mut sim = Sim::new(
            stadium(),
            &LoadOptions {
                seed: Some(seed),
                population: None,
            },
        )
        .unwrap();
        // hold the north side mid-run so metered plaza gates are exercised too
        let mut forward = vec![0u32; sim.gates.len()];
        let mut backward = vec![0u32; sim.gates.len()];
        while !sim.is_over() {
            if sim.tick == 1500 {
                sim.apply(Command::Gate {
                    gate: "gate_a".into(),
                    mode: GateMode::Metered,
                    level: Some(0.25),
                })
                .unwrap();
            }
            sim.step();
            for i in 0..sim.agents.len() {
                let (a, b) = (sim.agents.prev[i], sim.agents.pos[i]);
                for (gi, g) in sim.gates.iter().enumerate() {
                    if crowd_core::math::segments_intersect(a, b, g.a, g.b) {
                        if (b - a).dot(g.normal) > 0.0 {
                            forward[gi] += 1;
                        } else {
                            backward[gi] += 1;
                        }
                    }
                }
            }
        }
        for (gi, g) in sim.gates.iter().enumerate() {
            if g.one_way {
                assert_eq!(backward[gi], 0, "seed {seed}: walked back through {}", g.id);
            }
            if !g.controllable {
                // fare gates are always metered: every downstream crossing needed a token
                assert!(
                    forward[gi] <= g.served,
                    "seed {seed}: {} crossed {} times with {} tokens",
                    g.id,
                    forward[gi],
                    g.served
                );
            }
        }
    }
}
