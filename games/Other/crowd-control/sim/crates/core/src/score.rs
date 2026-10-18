//! Final scoring and deterministic explanations of where points were lost.

use crate::sim::{Outcome, Sim};
use serde::Serialize;

#[derive(Clone, Debug, Serialize)]
pub struct Component {
    pub key: &'static str,
    pub label: String,
    /// Human-readable measured value.
    pub value: String,
    /// Points gained (+) or lost (-).
    pub points: f32,
    /// Why, built from recorded telemetry (empty when nothing notable).
    pub why: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct Report {
    pub outcome: Outcome,
    pub score: i32,
    pub stars: u8,
    pub completed: u32,
    pub total: u32,
    pub avg_journey: f32,
    pub max_wait: f32,
    pub peak_density: f32,
    pub heavy_seconds: f32,
    pub danger_seconds: f32,
    pub cost: f32,
    pub satisfaction: f32,
    pub components: Vec<Component>,
    /// The three biggest losses, worst first.
    pub top_losses: Vec<String>,
    pub ended_at: f32,
}

fn mmss(s: f32) -> String {
    let s = s.max(0.0) as u32;
    format!("{}:{:02}", s / 60, s % 60)
}

pub fn report(sim: &Sim) -> Report {
    let rules = &sim.sc.scoring_rules;
    let ob = &sim.sc.objectives;
    let completed = sim.completed;
    let total = sim.total_population;
    let avg_journey = if completed > 0 {
        sim.journey_sum / completed as f32
    } else {
        0.0
    };
    // people still on site count with their current wait
    let mut max_wait = sim.wait_max;
    for w in &sim.agents.wait_total {
        if *w > max_wait {
            max_wait = *w;
        }
    }
    let active_sat: f32 = sim.agents.satisfaction.iter().sum();
    let n_sat = completed as f32 + sim.agents.len() as f32;
    let satisfaction = if n_sat > 0.0 {
        (sim.satisfaction_sum + active_sat) / n_sat
    } else {
        100.0
    };
    let cost = sim.spent + sim.staff_spent;
    let stranded = total - completed;

    let worst_area = |f: &dyn Fn(usize) -> f32| -> Option<(usize, f32)> {
        let mut best: Option<(usize, f32)> = None;
        for i in 0..sim.areas.len() {
            let v = f(i);
            if v > 0.0 && best.map(|b| v > b.1).unwrap_or(true) {
                best = Some((i, v));
            }
        }
        best
    };
    let first_log = |kind: &str, area: Option<&str>| {
        sim.log
            .iter()
            .find(|e| e.kind == kind && area.map(|a| e.area.as_deref() == Some(a)).unwrap_or(true))
    };
    let incident = sim.log.iter().find(|e| e.kind == "incident");

    let mut comps = Vec::new();
    comps.push(Component {
        key: "base",
        label: "Base".into(),
        value: String::new(),
        points: rules.base,
        why: String::new(),
    });

    let over_j = (avg_journey - ob.target_journey).max(0.0);
    comps.push(Component {
        key: "journey",
        label: "Average journey".into(),
        value: mmss(avg_journey),
        points: -over_j * rules.per_journey_second,
        why: if over_j > 0.0 {
            format!(
                "{} over the {} target",
                mmss(over_j),
                mmss(ob.target_journey)
            )
        } else {
            String::new()
        },
    });

    let over_w = (max_wait - ob.target_max_wait).max(0.0);
    let wait_where =
        worst_area(&|i| sim.areas[i].wait_person_seconds).map(|(i, _)| sim.area_names[i].clone());
    comps.push(Component {
        key: "wait",
        label: "Longest wait".into(),
        value: mmss(max_wait),
        points: -over_w * rules.per_wait_second,
        why: if over_w > 0.0 {
            match &wait_where {
                Some(a) => format!("most waiting happened in {a}"),
                None => String::new(),
            }
        } else {
            String::new()
        },
    });

    let heavy_where = worst_area(&|i| sim.areas[i].heavy_seconds);
    comps.push(Component {
        key: "heavy",
        label: "Heavy congestion".into(),
        value: mmss(sim.heavy_seconds),
        points: -sim.heavy_seconds * rules.per_heavy_second,
        why: heavy_where
            .map(|(i, s)| format!("{} for {}", sim.area_names[i], mmss(s)))
            .unwrap_or_default(),
    });

    let danger_where = worst_area(&|i| sim.areas[i].danger_seconds);
    let danger_why = match danger_where {
        Some((i, s)) => {
            let mut w = format!("{} for {}", sim.area_names[i], mmss(s));
            if let Some(first) = first_log("danger", Some(&sim.area_ids[i])) {
                w.push_str(&format!(", first at {}", mmss(first.t)));
                if let Some(inc) = incident {
                    if inc.t <= first.t {
                        w.push_str(&format!(" after the incident at {}", mmss(inc.t)));
                    }
                }
            }
            w
        }
        None => String::new(),
    };
    comps.push(Component {
        key: "danger",
        label: "Dangerous crowding".into(),
        value: mmss(sim.danger_seconds),
        points: -sim.danger_seconds * rules.per_danger_second,
        why: danger_why,
    });

    let mut cost_parts = Vec::new();
    if !sim.barriers.is_empty() {
        cost_parts.push(format!(
            "{} barrier{}",
            sim.barriers.len(),
            if sim.barriers.len() == 1 { "" } else { "s" }
        ));
    }
    if sim.staff_spent > 0.5 {
        cost_parts.push(format!("gate staff ${:.0}", sim.staff_spent));
    }
    comps.push(Component {
        key: "cost",
        label: "Operating cost".into(),
        value: format!("${:.0}", cost),
        points: -cost * rules.per_cost,
        why: cost_parts.join(", "),
    });

    comps.push(Component {
        key: "stranded",
        label: "Still on site".into(),
        value: format!("{stranded}"),
        points: -(stranded as f32) * rules.per_stranded,
        why: if stranded > 0 {
            format!("{} people had not left when the run ended", stranded)
        } else {
            String::new()
        },
    });
    comps.push(Component {
        key: "satisfaction",
        label: "Satisfaction".into(),
        value: format!("{:.0}%", satisfaction),
        points: satisfaction * rules.per_satisfaction,
        why: String::new(),
    });

    let mut score: f32 = comps.iter().map(|c| c.points).sum();
    if sim.outcome == Outcome::FailedDanger || sim.outcome == Outcome::FailedTimeout {
        score = score.min(rules.stars[0] - 1.0);
    }
    let score = score.max(0.0);
    let stars = rules.stars.iter().filter(|t| score >= **t).count() as u8;
    let mut losses: Vec<&Component> = comps.iter().filter(|c| c.points < -0.5).collect();
    losses.sort_by(|a, b| {
        a.points
            .partial_cmp(&b.points)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let top_losses = losses
        .iter()
        .take(3)
        .map(|c| {
            if c.why.is_empty() {
                format!("{}: {:.0} pts", c.label, c.points)
            } else {
                format!("{}: {:.0} pts ({})", c.label, c.points, c.why)
            }
        })
        .collect();
    Report {
        outcome: sim.outcome,
        score: score.round() as i32,
        stars,
        completed,
        total,
        avg_journey,
        max_wait,
        peak_density: sim.peak_density,
        heavy_seconds: sim.heavy_seconds,
        danger_seconds: sim.danger_seconds,
        cost,
        satisfaction,
        components: comps,
        top_losses,
        ended_at: sim.ended_at,
    }
}
