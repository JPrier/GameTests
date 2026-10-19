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

/// A reasonable operator who heeds the briefing's warning of a likely train delay: wait-time signs,
/// both plaza gates held back from the start (North 25%, South 50%) so queues build in the open
/// plaza rather than packed into the station halls, and opened again once trains run normally.
fn operator(sim: &mut Sim, released: &mut bool) {
    let cmd = |sim: &mut Sim, c: Command| {
        sim.apply(c).unwrap();
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
        for (g, level) in [("gate_a", 0.25), ("gate_b", 0.5)] {
            cmd(
                sim,
                Command::Gate {
                    gate: g.into(),
                    mode: GateMode::Metered,
                    level: Some(level),
                },
            );
        }
    }
    let over = sim.incidents.iter().all(|e| !e.happens || e.done);
    if over && !*released {
        *released = true;
        for g in ["gate_a", "gate_b"] {
            cmd(
                sim,
                Command::Gate {
                    gate: g.into(),
                    mode: GateMode::Open,
                    level: None,
                },
            );
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
    // Not single file: people spread across the 7 m North Walkway.
    let mut s = sim(1);
    let north = area(&s, "north_corridor");
    let mut ys: Vec<f32> = Vec::new();
    while s.time < 120.0 {
        s.step();
        if s.tick.is_multiple_of(40) {
            for i in 0..s.agents.len() {
                let p = s.agents.pos[i];
                if s.agents.area[i] as usize == north && p.x > 90.0 && p.x < 110.0 {
                    ys.push(p.y);
                }
            }
        }
    }
    assert!(ys.len() > 200, "too few samples: {}", ys.len());
    let mean = ys.iter().sum::<f32>() / ys.len() as f32;
    let sd = (ys.iter().map(|y| (y - mean) * (y - mean)).sum::<f32>() / ys.len() as f32).sqrt();
    assert!(sd > 1.0, "lateral spread {sd:.2} m");
}

#[test]
fn queues_fill_the_station_halls() {
    // During the train delay the queue in front of the North Fare Gates spreads across the hall
    // instead of forming one line.
    let mut s = sim(2);
    let hall = area(&s, "station_north");
    let mut best_rows = 0;
    while !s.is_over() && s.time < 300.0 {
        s.step();
        if s.tick.is_multiple_of(100) {
            let mut rows = [false; 20];
            for i in 0..s.agents.len() {
                if s.agents.area[i] as usize == hall {
                    let r = ((s.agents.pos[i].y - 10.0) / 0.5) as usize;
                    if r < 20 {
                        rows[r] = true;
                    }
                }
            }
            best_rows = best_rows.max(rows.iter().filter(|r| **r).count());
        }
    }
    assert!(
        best_rows >= 14,
        "queue used only {best_rows} of 20 half-metre rows"
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
    let mut released = false;
    while !s.is_over() {
        if hold {
            operator(&mut s, &mut released);
        }
        s.step();
    }
    score::report(&s)
}

#[test]
fn doing_nothing_fails_and_holding_the_crowd_passes() {
    // The game plays the scenario's own seed: there, doing nothing must fail and a sensible hold
    // must pass.
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
    // Other seeds (different delay timing and crowd; outcomes vary a lot between seeds): doing
    // nothing fails on most of them and holding is clearly better on average.
    let (mut idle_sum, mut held_sum, mut idle_passes) = (0, 0, 0);
    for seed in 1..=6u64 {
        let i = play(Some(seed), false);
        let h = play(Some(seed), true);
        idle_sum += i.score;
        held_sum += h.score;
        if i.outcome == Outcome::Won {
            idle_passes += 1;
        }
    }
    assert!(
        idle_passes <= 3,
        "doing nothing passed on {idle_passes} of 6 seeds"
    );
    assert!(
        held_sum - idle_sum > 6 * 150,
        "holding {} vs nothing {} (sum of 6)",
        held_sum,
        idle_sum
    );
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
