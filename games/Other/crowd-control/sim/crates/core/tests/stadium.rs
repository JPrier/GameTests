//! Behaviour of the full Stadium Departure scenario: the things a player sees. These are the
//! regressions behind "people move stupidly", "danger makes no sense" and "doing nothing wins".

use crowd_core::score;
use crowd_core::sim::{Command, GateMode, LoadOptions, Outcome, Sim};
use crowd_core::Scenario;

fn stadium() -> Scenario {
    let text = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../scenarios/stadium_departure.json"
    ))
    .unwrap();
    Scenario::from_json(&text).unwrap()
}

fn sim(seed: u64) -> Sim {
    Sim::new(
        stadium(),
        &LoadOptions {
            seed: Some(seed),
            population: None,
        },
    )
    .unwrap()
}

fn area(sim: &Sim, id: &str) -> usize {
    sim.area_ids.iter().position(|a| a == id).unwrap()
}

/// A reasonable operator: wait-time signs; when the trains stop, close both station entrances (so
/// the halls do not overfill) and hold both plaza gates at half rate (so the walkways do not
/// either); open everything again when service returns.
fn operator(sim: &mut Sim, held: &mut bool, released: &mut bool) {
    let cmd = |sim: &mut Sim, c: Command| {
        sim.apply(c).unwrap();
    };
    let gate = |sim: &mut Sim, g: &str, mode: GateMode, level: Option<f32>| {
        cmd(
            sim,
            Command::Gate {
                gate: g.into(),
                mode,
                level,
            },
        );
    };
    if sim.tick == 0 {
        for sg in ["sign_n", "sign_s"] {
            cmd(
                sim,
                Command::Sign {
                    sign: sg.into(),
                    mode: "waits".into(),
                },
            );
        }
    }
    let active = sim.incidents.iter().any(|e| e.active);
    let over = sim.incidents.iter().all(|e| !e.happens || e.done);
    if active && !*held {
        *held = true;
        gate(sim, "station_n", GateMode::Closed, None);
        gate(sim, "station_r", GateMode::Closed, None);
        gate(sim, "gate_a", GateMode::Metered, Some(0.5));
        gate(sim, "gate_b", GateMode::Metered, Some(0.5));
    }
    if over && *held && !*released {
        *released = true;
        for g in ["station_n", "station_r", "gate_a", "gate_b"] {
            gate(sim, g, GateMode::Open, None);
        }
    }
}

#[test]
fn people_do_not_turn_back_inside_walkways() {
    // Once in a walkway people are committed: almost nobody walks back against the flow.
    let mut s = sim(1);
    let walkways = [area(&s, "north_corridor"), area(&s, "south_corridor")];
    let (mut inside, mut backwards) = (0u64, 0u64);
    while !s.is_over() {
        s.step();
        if !s.tick.is_multiple_of(20) {
            continue;
        }
        for i in 0..s.agents.len() {
            if walkways.contains(&(s.agents.area[i] as usize)) && s.agents.speed[i] > 0.3 {
                inside += 1;
                if s.agents.heading[i].x < -0.7 {
                    backwards += 1;
                }
            }
        }
    }
    let share = backwards as f64 / inside.max(1) as f64;
    assert!(inside > 1000, "too few samples: {inside}");
    assert!(share < 0.01, "{:.1}% walking back", share * 100.0);
}

#[test]
fn people_use_the_width_of_the_walkways() {
    // Not single file: people spread across the 21 m North Walkway.
    let mut s = sim(1);
    let north = area(&s, "north_corridor");
    let mut ys: Vec<f32> = Vec::new();
    while s.time < 240.0 {
        s.step();
        if s.tick.is_multiple_of(40) {
            for i in 0..s.agents.len() {
                let p = s.agents.pos[i];
                if s.agents.area[i] as usize == north && p.x > 255.0 && p.x < 285.0 {
                    ys.push(p.y);
                }
            }
        }
    }
    assert!(ys.len() > 200, "too few samples: {}", ys.len());
    let mean = ys.iter().sum::<f32>() / ys.len() as f32;
    let sd = (ys.iter().map(|y| (y - mean) * (y - mean)).sum::<f32>() / ys.len() as f32).sqrt();
    assert!(sd > 3.0, "lateral spread {sd:.2} m");
}

#[test]
fn queues_fill_the_station_halls() {
    // During the train delay the queue in front of the North Fare Gates spreads across the hall
    // instead of forming one line.
    let mut s = sim(2);
    let hall = area(&s, "station_north");
    let r = s.areas[hall].rect;
    let mut best_rows = 0;
    while !s.is_over() && s.time < 700.0 {
        s.step();
        if s.tick.is_multiple_of(100) {
            let mut rows = [false; 30];
            for i in 0..s.agents.len() {
                if s.agents.area[i] as usize == hall {
                    let k = (s.agents.pos[i].y - r.y) as usize;
                    if k < 30 {
                        rows[k] = true;
                    }
                }
            }
            best_rows = best_rows.max(rows.iter().filter(|r| **r).count());
        }
    }
    assert!(
        best_rows >= 20,
        "queue used only {best_rows} of 30 one-metre rows"
    );
}

fn play(seed: Option<u64>, hold: bool) -> score::Report {
    let mut s = Sim::new(
        stadium(),
        &LoadOptions {
            seed,
            population: None,
        },
    )
    .unwrap();
    let (mut held, mut released) = (false, false);
    while !s.is_over() {
        if hold {
            operator(&mut s, &mut held, &mut released);
        }
        s.step();
    }
    score::report(&s)
}

#[test]
fn doing_nothing_fails_and_managing_the_delay_passes() {
    // The game plays the scenario's own seed: there, doing nothing must fail and a sensible
    // operator must pass.
    let idle = play(None, false);
    assert_ne!(
        idle.outcome,
        Outcome::Won,
        "doing nothing passed with {}",
        idle.score
    );
    assert!(
        idle.danger_seconds > 10.0,
        "no real crush: {}",
        idle.danger_seconds
    );
    let held = play(None, true);
    assert_eq!(
        held.outcome,
        Outcome::Won,
        "holding failed with {}",
        held.score
    );
    // Other seeds (different delay timing and crowd): doing nothing fails and the same operator
    // passes.
    for seed in 1..=2u64 {
        let i = play(Some(seed), false);
        assert_ne!(
            i.outcome,
            Outcome::Won,
            "seed {seed}: nothing passed with {}",
            i.score
        );
        let h = play(Some(seed), true);
        assert_eq!(
            h.outcome,
            Outcome::Won,
            "seed {seed}: holding failed with {}",
            h.score
        );
    }
}

#[test]
fn danger_happens_where_the_crowd_is_packed() {
    // Every area that accumulated dangerous crowding really was packed at some point.
    let mut s = sim(2);
    while !s.is_over() {
        s.step();
    }
    for (i, a) in s.areas.iter().enumerate() {
        if a.danger_seconds > 1.0 {
            assert!(
                a.peak_density >= 3.0,
                "{} flagged dangerous at a peak of only {:.1} p/m²",
                s.area_ids[i],
                a.peak_density
            );
        }
    }
}
