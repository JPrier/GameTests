//! The player's tools change where people actually walk: fences build routes, arrows pull people
//! into lanes (one-way lanes keep them out), steward lines hold a crowd and let it go.

mod common;
use common::*;
use crowd_core::sim::{Command, Sim};

/// A 60 x 40 m open room: people enter on the left and leave on the right. With `block`, a 10 m
/// square kiosk in the middle splits the room into a top and a bottom way round.
fn room(block: bool, pop: u32) -> Spec {
    room_at(block, pop, 2.0)
}

fn room_at(block: bool, pop: u32, rate: f32) -> Spec {
    let walls = if block {
        vec![
            [25.0, 15.0, 35.0, 15.0],
            [35.0, 15.0, 35.0, 25.0],
            [35.0, 25.0, 25.0, 25.0],
            [25.0, 25.0, 25.0, 15.0],
        ]
    } else {
        vec![]
    };
    Spec {
        size: [60.0, 40.0],
        walkable: vec![[0.0, 0.0, 60.0, 40.0]],
        walls,
        nodes: vec![node("in", 3.0, 20.0, 1.0), node("out", 57.0, 20.0, 1.5)],
        edges: vec![edge("in", "out")],
        dests: vec![dest("out", "out")],
        sources: vec![source(
            "s",
            pop,
            "in",
            [1.0, 16.0, 3.0, 8.0],
            rate,
            &[("out", 1.0)],
        )],
        ..Default::default()
    }
}

/// Run to the end; returns the y of every crossing of the line x = `x`.
fn crossings(sim: &mut Sim, x: f32, max_s: f32) -> Vec<f32> {
    let mut ys = Vec::new();
    run_until_done(sim, max_s, |s| {
        for i in 0..s.agents.len() {
            let (p, q) = (s.agents.pos[i], s.agents.prev[i]);
            if q.x < x && p.x >= x {
                ys.push(p.y);
            }
        }
    });
    ys
}

fn share(ys: &[f32], f: impl Fn(f32) -> bool) -> f32 {
    ys.iter().filter(|y| f(**y)).count() as f32 / ys.len().max(1) as f32
}

#[test]
fn a_fence_builds_a_route() {
    // A bent fence closes the room across the middle except a 6 m opening at the top: everyone
    // walks the route it makes, and still gets out.
    let mut sim = room(false, 120).sim();
    sim.apply(Command::FenceAdd {
        points: vec![[22.0, 0.0], [30.0, 8.0], [30.0, 34.0]],
    })
    .unwrap();
    let ys = crossings(&mut sim, 30.0, 400.0);
    assert_eq!(sim.completed, 120, "everyone arrives");
    assert!(ys.len() >= 120);
    assert!(
        share(&ys, |y| y > 34.0) > 0.99,
        "{:.0}% used the opening",
        share(&ys, |y| y > 34.0) * 100.0
    );
}

#[test]
fn arrows_pull_people_into_a_lane() {
    // Round the kiosk people split between top and bottom; an arrow along the bottom pulls most of
    // them that way, and a one-way lane against them along the top empties it.
    let bottom = |y: f32| y < 15.0;
    let base = {
        let mut sim = room(true, 150).sim();
        share(&crossings(&mut sim, 30.0, 400.0), bottom)
    };
    assert!(base > 0.25 && base < 0.75, "split without arrows {base:.2}");
    let guided = {
        let mut sim = room(true, 150).sim();
        sim.apply(Command::ArrowAdd {
            points: vec![[12.0, 9.0], [30.0, 7.0], [48.0, 9.0]],
            one_way: false,
        })
        .unwrap();
        let ys = crossings(&mut sim, 30.0, 400.0);
        assert_eq!(sim.completed, 150);
        share(&ys, bottom)
    };
    assert!(
        guided > 0.85,
        "only {:.0}% followed the arrow",
        guided * 100.0
    );
    let one_way = {
        // two lanes side by side cover the whole 15 m passage above the kiosk
        let mut sim = room(true, 150).sim();
        for y in [29.0, 36.0] {
            sim.apply(Command::ArrowAdd {
                points: vec![[48.0, y], [12.0, y]],
                one_way: true,
            })
            .unwrap();
        }
        let ys = crossings(&mut sim, 30.0, 400.0);
        assert_eq!(sim.completed, 150);
        share(&ys, bottom)
    };
    assert!(
        one_way > 0.95,
        "{:.0}% walked against the one-way lane",
        (1.0 - one_way) * 100.0
    );
}

#[test]
fn stewards_hold_the_crowd_and_let_it_go() {
    // Stewards across the whole room: nobody passes while they hold, people wait at the line,
    // and after the release everyone gets out.
    let mut sim = room(false, 150).sim();
    let r = sim
        .apply(Command::StewardsAdd {
            a: [30.0, 0.2],
            b: [30.0, 39.8],
        })
        .unwrap();
    let id = r["id"].as_u64().unwrap() as u32;
    let mut passed = 0;
    while sim.time < 90.0 {
        sim.step();
        for i in 0..sim.agents.len() {
            if sim.agents.prev[i].x < 30.0 && sim.agents.pos[i].x >= 30.0 {
                passed += 1;
            }
        }
    }
    assert_eq!(passed, 0, "people got through a holding steward line");
    let waiting = (0..sim.agents.len())
        .filter(|&i| sim.agents.pos[i].x > 24.0 && sim.agents.pos[i].x < 30.0)
        .count();
    assert!(waiting > 60, "only {waiting} waiting at the line");
    sim.apply(Command::StewardsHold { id, hold: false })
        .unwrap();
    run_until_done(&mut sim, 500.0, |_| {});
    assert_eq!(sim.completed, 150, "everyone out after the release");
}

#[test]
fn people_walk_round_a_short_steward_line() {
    // A short line is a detour, not a dead end: people go round its end.
    let mut sim = room(false, 100).sim();
    sim.apply(Command::StewardsAdd {
        a: [30.0, 12.0],
        b: [30.0, 28.0],
    })
    .unwrap();
    let ys = crossings(&mut sim, 30.0, 400.0);
    assert_eq!(sim.completed, 100);
    assert!(
        share(&ys, |y| !(12.5..27.5).contains(&y)) > 0.99,
        "people crossed the line"
    );
}

#[test]
fn placement_rules() {
    let mut sim = room(false, 50).sim();
    // a fence that seals the exit off is refused
    let r = sim.apply(Command::FenceAdd {
        points: vec![[45.0, 0.0], [45.0, 40.0]],
    });
    assert!(r.is_err(), "trapping fence accepted");
    // a steward line may close the room (it opens again)
    assert!(sim
        .apply(Command::StewardsAdd {
            a: [45.0, 0.2],
            b: [45.0, 39.8]
        })
        .is_ok());
    // and does not stop fences elsewhere passing the trap check
    assert!(sim
        .apply(Command::FenceAdd {
            points: vec![[20.0, 5.0], [20.0, 15.0]]
        })
        .is_ok());
    // stewards cannot form a line through a dense crowd
    let mut sim = room_at(false, 2000, 10.0).sim();
    // a 2.5 m gap passes fewer people than arrive, so a dense queue builds in front of it
    sim.apply(Command::FenceAdd {
        points: vec![[10.0, 0.0], [10.0, 18.75]],
    })
    .unwrap();
    sim.apply(Command::FenceAdd {
        points: vec![[10.0, 21.25], [10.0, 40.0]],
    })
    .unwrap();
    let packed = |sim: &Sim| {
        (17..=23).any(|y| {
            sim.density.density[sim
                .density
                .index(crowd_core::math::Vec2::new(8.5, y as f32))]
                > 2.5
        })
    };
    while sim.time < 200.0 && !packed(&sim) {
        sim.step();
    }
    assert!(packed(&sim), "no crowd formed in front of the gap");
    let r = sim.apply(Command::StewardsAdd {
        a: [8.5, 17.0],
        b: [8.5, 23.0],
    });
    assert!(r.is_err(), "stewards formed a line in a crush: {r:?}");
}
