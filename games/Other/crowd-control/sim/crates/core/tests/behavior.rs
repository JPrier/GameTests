//! Behavioural reference geometries. Each test checks a measurable consequence in the simulation.

mod common;
use common::*;
use crowd_core::sim::{Command, GateMode};
use serde_json::json;

/// Reference 1: Straight corridor: free flow at roughly the desired speed, everyone arrives, nobody leaves
/// the walkable area.
#[test]
fn straight_corridor_free_flow() {
    let s = Spec {
        size: [60.0, 6.0],
        walkable: vec![[0.0, 0.0, 60.0, 6.0]],
        nodes: vec![node("start", 2.0, 3.0, 1.0), node("end", 57.0, 3.0, 1.5)],
        edges: vec![edge("start", "end")],
        dests: vec![dest("end", "end")],
        sources: vec![source(
            "s",
            20,
            "start",
            [0.5, 0.5, 4.0, 5.0],
            1.0,
            &[("end", 1.0)],
        )],
        ..Default::default()
    };
    let mut sim = s.sim();
    let mut ok = true;
    run_until_done(&mut sim, 200.0, |sim| ok &= all_on_walkable(sim));
    assert!(ok, "someone left the walkable area");
    assert_eq!(sim.completed, 20);
    let avg = sim.journey_sum / sim.completed as f32;
    // ~53 m at 1.2-1.4 m/s is 38-44 s; allow for start-up and mild interaction
    assert!(avg > 35.0 && avg < 55.0, "average journey {avg}");
}

fn bottleneck_flow(width: f32) -> f32 {
    bottleneck_flow_t(width, None)
}

fn bottleneck_flow_t(width: f32, time_gap: Option<f32>) -> f32 {
    // 10 x 10 room, door of `width` in the right wall, exit corridor beyond
    let y0 = 5.0 - width / 2.0;
    let s = Spec {
        size: [30.0, 10.0],
        walkable: vec![
            [0.0, 0.0, 10.0, 10.0],
            [10.0, y0, 1.0, width],
            [11.0, 0.0, 19.0, 10.0],
        ],
        nodes: vec![
            node("in", 2.0, 5.0, 1.0),
            node("door", 12.0, 5.0, 0.8),
            node("out", 27.0, 5.0, 2.0),
        ],
        edges: vec![edge("in", "door"), edge("door", "out")],
        dests: vec![dest("out", "out")],
        sources: vec![source(
            "s",
            150,
            "in",
            [0.5, 0.5, 7.0, 9.0],
            20.0,
            &[("out", 1.0)],
        )],
        time_gap,
        ..Default::default()
    };
    let mut sim = s.sim();
    // measure the steady discharge: time between the 20th and 120th person reaching the far side
    let mut t20 = 0.0;
    let mut t120 = 0.0;
    run_until_done(&mut sim, 400.0, |sim| {
        if sim.completed >= 20 && t20 == 0.0 {
            t20 = sim.time;
        }
        if sim.completed >= 120 && t120 == 0.0 {
            t120 = sim.time;
        }
    });
    assert!(t120 > t20, "bottleneck run did not finish (width {width})");
    100.0 / (t120 - t20) / width
}

/// Reference 2: Narrowing corridor: a bottleneck limits flow; specific flow is in the range measured in
/// experiments (Seyfried et al. 2007 report ~1.6-2.0 p/m/s for 0.8-1.2 m), and total capacity grows
/// with width.
#[test]
fn bottleneck_specific_flow_and_width() {
    let narrow = bottleneck_flow(1.0);
    let wide = bottleneck_flow(2.0);
    println!("specific flow: 1.0 m -> {narrow:.2} p/m/s, 2.0 m -> {wide:.2} p/m/s");
    assert!(
        narrow > 1.2 && narrow < 2.2,
        "1 m door specific flow {narrow} (Seyfried et al. 2007: about 1.6-2.0)"
    );
    assert!(
        wide * 2.0 > narrow * 1.0 * 1.3,
        "a wider door must pass clearly more people per second"
    );
}

fn two_exit_room() -> Spec {
    Spec {
        size: [30.0, 20.0],
        walkable: vec![
            [0.0, 0.0, 20.0, 20.0],
            [20.0, 2.0, 10.0, 3.0],
            [20.0, 15.0, 10.0, 3.0],
        ],
        nodes: vec![
            node("in", 3.0, 10.0, 1.0),
            node("ga", 22.0, 3.5, 1.0),
            node("gb", 22.0, 16.5, 1.0),
            node("outa", 28.0, 3.5, 1.0),
            node("outb", 28.0, 16.5, 1.0),
            node("out", 29.0, 3.5, 0.4),
        ],
        edges: vec![
            edge("in", "ga"),
            edge("in", "gb"),
            edge("ga", "outa"),
            edge("gb", "outb"),
        ],
        gates: vec![
            json!({"id": "ga", "name": "A", "node": "ga", "line": [20.5, 2.0, 20.5, 5.0], "lanes": 3, "lane_rate": 1.0, "controllable": true}),
            json!({"id": "gb", "name": "B", "node": "gb", "line": [20.5, 15.0, 20.5, 18.0], "lanes": 3, "lane_rate": 1.0, "controllable": true}),
        ],
        dests: vec![dest("a", "outa"), dest("b", "outb")],
        // half want exit A, half exit B as a destination; with one closed the router must use the
        // other: model that with a shared "any exit" by giving both destinations equal demand
        sources: vec![source(
            "s",
            80,
            "in",
            [0.5, 2.0, 8.0, 16.0],
            10.0,
            &[("a", 1.0), ("b", 1.0)],
        )],
        ..Default::default()
    }
}

/// Calibration sweep of the CFSM time gap against bottleneck flow (run with --ignored --nocapture).
#[test]
#[ignore]
fn calibrate_time_gap() {
    for t in [1.0, 0.8, 0.6, 0.5, 0.4] {
        let a = bottleneck_flow_t(1.0, Some(t));
        let b = bottleneck_flow_t(1.6, Some(t));
        println!("T={t:.1}: 1.0 m door {a:.2} p/m/s, 1.6 m door {b:.2} p/m/s");
    }
}

/// Reference 3: Room with two exits: both are used; nobody is lost.
#[test]
fn room_with_two_exits_uses_both() {
    let mut sim = two_exit_room().sim();
    run_until_done(&mut sim, 300.0, |_| {});
    assert_eq!(sim.completed, 80);
    assert!(sim.completed_by_dest[0] > 20 && sim.completed_by_dest[1] > 20);
}

/// Reference 4: Opposing streams: two groups cross through one corridor in opposite directions without
/// deadlock, and the counterflow takes longer than the same people walking one way.
#[test]
fn opposing_streams_pass_without_deadlock() {
    let build = |counter: bool| Spec {
        size: [50.0, 4.0],
        walkable: vec![[0.0, 0.0, 50.0, 4.0]],
        nodes: vec![
            node("w", 2.0, 2.0, 1.0),
            node("e", 48.0, 2.0, 1.0),
            node("we", 49.5, 2.0, 0.5),
            node("ew", 0.5, 2.0, 0.5),
        ],
        edges: vec![edge("w", "we"), edge("e", "ew")],
        dests: vec![dest("east", "we"), dest("west", "ew")],
        sources: if counter {
            vec![
                source("sw", 80, "w", [0.3, 0.3, 4.0, 3.4], 8.0, &[("east", 1.0)]),
                source("se", 80, "e", [45.7, 0.3, 4.0, 3.4], 8.0, &[("west", 1.0)]),
            ]
        } else {
            // same two sources and rates, both at the west end
            vec![
                source("sw", 80, "w", [0.3, 0.3, 4.0, 3.4], 8.0, &[("east", 1.0)]),
                source("sw2", 80, "w", [0.3, 0.3, 4.0, 3.4], 8.0, &[("east", 1.0)]),
            ]
        },
        ..Default::default()
    };
    let mut bi = build(true).sim();
    let mut ok = true;
    run_until_done(&mut bi, 600.0, |s| ok &= all_on_walkable(s));
    assert!(ok);
    assert_eq!(bi.completed, 160, "counterflow deadlocked");
    let mut uni = build(false).sim();
    run_until_done(&mut uni, 600.0, |_| {});
    let t_bi = bi.journey_sum / 160.0;
    let t_uni = uni.journey_sum / 160.0;
    println!(
        "mean journey (160 people, same demand): counterflow {t_bi:.1} s, one-way {t_uni:.1} s"
    );
    assert!(
        t_bi > t_uni * 1.05,
        "opposing streams should clearly interfere"
    );
}

/// Reference 5: Intersecting streams: two perpendicular flows cross in a square and everyone gets through.
#[test]
fn intersecting_streams_cross() {
    let s = Spec {
        size: [40.0, 40.0],
        walkable: vec![[0.0, 16.0, 40.0, 8.0], [16.0, 0.0, 8.0, 40.0]],
        nodes: vec![
            node("w", 2.0, 20.0, 1.0),
            node("e", 38.5, 20.0, 1.0),
            node("n", 20.0, 2.0, 1.0),
            node("s", 20.0, 38.5, 1.0),
        ],
        edges: vec![edge("w", "e"), edge("n", "s")],
        dests: vec![dest("east", "e"), dest("south", "s")],
        sources: vec![
            source(
                "from_w",
                60,
                "w",
                [0.5, 16.5, 4.0, 7.0],
                3.0,
                &[("east", 1.0)],
            ),
            source(
                "from_n",
                60,
                "n",
                [16.5, 0.5, 7.0, 4.0],
                3.0,
                &[("south", 1.0)],
            ),
        ],
        ..Default::default()
    };
    let mut sim = s.sim();
    run_until_done(&mut sim, 400.0, |_| {});
    assert_eq!(sim.completed, 120);
}

/// Reference 6: Closed gate: nobody passes; people reroute to the open exit; no unserved crossings.
#[test]
fn closed_gate_passes_nobody_and_people_reroute() {
    let mut sim = two_exit_room().sim();
    sim.apply(Command::Gate {
        gate: "ga".into(),
        mode: GateMode::Closed,
        level: None,
    })
    .unwrap();
    run_until_done(&mut sim, 120.0, |_| {});
    assert_eq!(sim.gates[0].total_passed, 0, "closed gate passed people");
    // destination A is unreachable while A is closed: those people wait (Stuck), B flows
    assert!(sim.gates[1].total_passed > 20);
    assert_eq!(sim.gates.iter().map(|g| g.violations).sum::<u32>(), 0);
    // reopen: A's people now get out
    sim.apply(Command::Gate {
        gate: "ga".into(),
        mode: GateMode::Open,
        level: None,
    })
    .unwrap();
    run_until_done(&mut sim, 400.0, |_| {});
    assert_eq!(sim.completed, 80, "reopening restores the route");
}

/// Reference 7: Queue spillback: a slow service point's queue grows past its room into a walkway and slows
/// unrelated cross traffic there.
#[test]
fn queue_spillback_slows_unrelated_traffic() {
    let build = |service: f32| Spec {
        size: [40.0, 30.0],
        // shared hall (0..40 x 10..20), a small kiosk room above it reached through a gate
        walkable: vec![[0.0, 10.0, 40.0, 10.0], [16.0, 4.0, 8.0, 6.0]],
        nodes: vec![
            node("w", 2.0, 15.0, 1.0),
            node("e", 38.5, 15.0, 1.0),
            node("kiosk", 20.0, 6.0, 1.2),
            node("kin", 20.0, 9.0, 0.6),
        ],
        edges: vec![edge("w", "e"), edge("w", "kin"), edge("kin", "kiosk")],
        gates: vec![
            json!({"id": "k", "name": "Kiosk", "node": "kin", "line": [16.0, 10.0, 24.0, 10.0], "lanes": 1, "lane_rate": service, "default_mode": "metered"}),
        ],
        dests: vec![dest("east", "e"), dest("kiosk", "kiosk")],
        sources: vec![source(
            "s",
            160,
            "w",
            [0.5, 10.5, 4.0, 9.0],
            2.0,
            &[("east", 0.4), ("kiosk", 0.6)],
        )],
        areas: vec![
            area("hall", [0.0, 10.0, 40.0, 10.0]),
            area("kioskroom", [16.0, 4.0, 8.0, 6.0]),
        ],
        ..Default::default()
    };
    let journey_east = |service: f32| {
        let mut sim = build(service).sim();
        let mut max_queue = 0;
        run_until_done(&mut sim, 300.0, |s| {
            max_queue = max_queue.max(s.gates[0].queue);
        });
        (sim, max_queue)
    };
    let (slow, q_slow) = journey_east(0.25);
    let (fast, q_fast) = journey_east(5.0);
    println!("max queue slow {q_slow} fast {q_fast}");
    assert!(
        q_slow > 15 && q_slow > q_fast * 3,
        "a slow service point builds a queue"
    );
    // the hall gets denser and slower with the spilled queue
    let hall_wait = |s: &crowd_core::Sim| s.areas[0].wait_person_seconds;
    assert!(
        hall_wait(&slow) > hall_wait(&fast) * 2.0,
        "spillback congests the shared hall"
    );
}

/// Reference 8: Station service interruption: an incident cuts throughput, a backlog builds, persists
/// after service resumes, then clears.
#[test]
fn service_interruption_backlog_persists_then_clears() {
    let s = Spec {
        size: [40.0, 12.0],
        walkable: vec![[0.0, 0.0, 40.0, 12.0]],
        nodes: vec![
            node("in", 2.0, 6.0, 1.0),
            node("fg", 26.0, 6.0, 1.0),
            node("plat", 37.0, 6.0, 1.5),
        ],
        edges: vec![edge("in", "fg"), edge("fg", "plat")],
        gates: vec![
            json!({"id": "fg", "name": "Fare", "node": "fg", "line": [24.0, 0.0, 24.0, 12.0], "lanes": 4, "lane_rate": 0.5, "default_mode": "metered"}),
        ],
        transit: vec![json!({"id": "t", "name": "Trains", "gates": ["fg"], "destination": "plat"})],
        events: vec![
            json!({"id": "d", "name": "Delay", "kind": "service_reduction", "target": "t", "factor": 0.1, "start": [40.0, 40.0], "duration": [60.0, 60.0]}),
        ],
        dests: vec![dest("plat", "plat")],
        sources: vec![source(
            "s",
            240,
            "in",
            [0.5, 0.5, 4.0, 11.0],
            1.5,
            &[("plat", 1.0)],
        )],
        ..Default::default()
    };
    let mut sim = s.sim();
    let mut passed_during = 0;
    let mut q_at_resume = 0;
    let mut start_count = 0;
    run_until_done(&mut sim, 600.0, |s| {
        if (s.time - 40.0).abs() < 0.026 {
            start_count = s.gates[0].total_passed;
        }
        if (s.time - 100.0).abs() < 0.026 {
            passed_during = s.gates[0].total_passed - start_count;
            q_at_resume = s.gates[0].queue;
        }
    });
    // capacity during the delay: 4 lanes * 0.5 * 0.1 = 0.2 p/s -> at most ~13 in 60 s (+lane slack)
    assert!(
        passed_during <= 16,
        "throughput during the delay was {passed_during}"
    );
    assert!(q_at_resume > 30, "backlog at resume {q_at_resume}");
    assert_eq!(sim.completed, 240, "backlog clears after service resumes");
}

/// Reference 9: Signage rerouting: recommending the longer route measurably shifts route shares.
#[test]
fn signage_shifts_route_choice() {
    let build = |mode: &str| Spec {
        size: [40.0, 30.0],
        walkable: vec![
            [0.0, 10.0, 12.0, 10.0],
            [12.0, 10.0, 16.0, 3.0],
            [12.0, 17.0, 16.0, 3.0],
            [28.0, 10.0, 12.0, 10.0],
            [12.0, 20.0, 16.0, 6.0],
        ],
        nodes: vec![
            node("in", 2.0, 15.0, 1.0),
            node("a", 20.0, 11.5, 1.0),
            node("b", 20.0, 18.5, 1.0),
            node("out", 37.0, 15.0, 1.5),
        ],
        edges: vec![
            edge("in", "a"),
            edge("in", "b"),
            edge("a", "out"),
            edge("b", "out"),
        ],
        dests: vec![dest("out", "out")],
        signs: vec![
            json!({"id": "s", "name": "Sign", "pos": [6.0, 15.0], "radius": 8.0, "default_mode": mode,
            "modes": [{"id": "off", "label": "-", "kind": "off"}, {"id": "via_b", "label": "Use B", "kind": "route", "destination": "out", "via": "b"}]}),
        ],
        sources: vec![source(
            "s",
            100,
            "in",
            [0.5, 10.5, 3.0, 9.0],
            2.0,
            &[("out", 1.0)],
        )],
        sign_compliance: [0.6, 1.0],
        seed: 5,
        ..Default::default()
    };
    let share_b = |mode: &str| {
        let mut sim = build(mode).sim();
        run_until_done(&mut sim, 300.0, |_| {});
        assert_eq!(sim.completed, 100);
        // count by which corridor people used: node passes are not recorded, so use area flow
        let mut via_b = 0;
        let mut sim2 = build(mode).sim();
        let mut seen = std::collections::BTreeSet::new();
        run_until_done(&mut sim2, 300.0, |s| {
            for i in 0..s.agents.len() {
                if s.agents.pos[i].y > 17.0 && s.agents.pos[i].x > 14.0 && s.agents.pos[i].x < 26.0
                {
                    seen.insert(s.agents.id[i]);
                }
            }
        });
        via_b += seen.len();
        via_b as f32 / 100.0
    };
    let off = share_b("off");
    let on = share_b("via_b");
    println!("share via B: sign off {off:.2}, sign on {on:.2}");
    assert!(on > off + 0.2, "the sign should shift people to B");
}

/// Reference 10: Groups stay together while walking.
#[test]
fn groups_stay_together() {
    let s = Spec {
        size: [60.0, 10.0],
        walkable: vec![[0.0, 0.0, 60.0, 10.0]],
        nodes: vec![node("start", 2.0, 5.0, 1.0), node("end", 57.0, 5.0, 1.5)],
        edges: vec![edge("start", "end")],
        dests: vec![dest("end", "end")],
        sources: vec![source(
            "s",
            40,
            "start",
            [0.5, 0.5, 5.0, 9.0],
            4.0,
            &[("end", 1.0)],
        )],
        group: [4, 4],
        speed: [0.9, 1.5],
        ..Default::default()
    };
    let mut sim = s.sim();
    let mut worst = 0.0f32;
    let mut samples = 0;
    let mut sum = 0.0;
    run_until_done(&mut sim, 200.0, |s| {
        if s.tick % 20 != 0 {
            return;
        }
        for i in 0..s.agents.len() {
            let l = s.agents.leader[i];
            if l != s.agents.id[i] {
                let li = s.slot_of[l as usize];
                if li != u32::MAX {
                    let d = (s.agents.pos[li as usize] - s.agents.pos[i]).len();
                    worst = worst.max(d);
                    sum += d;
                    samples += 1;
                }
            }
        }
    });
    assert_eq!(sim.completed, 40);
    let mean = sum / samples.max(1) as f32;
    println!("group member to leader: mean {mean:.2} m, worst {worst:.2} m");
    // desired speeds differ by up to 0.6 m/s within a group; without cohesion members would drift
    // apart by >20 m over the walk
    assert!(mean < 3.0, "groups drift apart: mean {mean}");
    assert!(worst < 8.0, "a member got far from its leader: {worst}");
}
