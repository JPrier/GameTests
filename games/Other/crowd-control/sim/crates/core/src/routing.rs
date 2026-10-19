//! Global route choice on the infrastructure graph.
//!
//! Edge lengths are geodesic (taken from the per-node distance fields), so closed gates and barriers
//! that cut a connection make it infinitely long. Each agent periodically picks the cheapest route
//! under its own weights: what it can see (queues and crowding within sight), what signs told it,
//! what nearby people are doing (herding) and how familiar it is with the venue.

use crate::math::Vec2;

pub const SIGHT: f32 = 35.0;
pub const MAX_NODES: usize = 64;
/// Route-cost bonus for following a sign recommendation (s, scaled by compliance).
pub const SIGN_BONUS: f32 = 45.0;
/// Route-cost bonus for the option most nearby people take (s, scaled by crowd_following * share).
pub const HERD_BONUS: f32 = 25.0;
/// Hysteresis: bonus for keeping the current next node (s), plus more for every change of mind
/// already made; after `MAX_SWITCHES` changes people stick with their choice.
pub const COMMIT_BONUS: f32 = 8.0;
pub const COMMIT_PER_SWITCH: f32 = 25.0;
pub const MAX_SWITCHES: u8 = 2;
/// Extra cost an impatient agent puts on the queue it is standing in (s).
pub const IMPATIENCE_PENALTY: f32 = 40.0;
/// Turning back against your own direction of travel (s); impatient people pay much less.
pub const BACKTRACK_PENALTY: f32 = 45.0;
pub const BACKTRACK_PENALTY_IMPATIENT: f32 = 8.0;
/// Unfamiliar people distrust long unseen legs (s per metre * (1 - familiarity)).
pub const UNCERTAINTY_PER_M: f32 = 0.25;

/// Weidmann (1993) speed-density relation as a fraction of free speed (gamma 1.913, rho_max 5.4).
pub fn weidmann_factor(density: f32) -> f32 {
    if density <= 0.05 {
        return 1.0;
    }
    let f = 1.0 - crate::math::exp(-1.913 * (1.0 / density - 1.0 / 5.4));
    crate::math::clamp(f, 0.05, 1.0)
}

#[derive(Clone, Debug)]
pub struct Node {
    pub id: String,
    pub pos: Vec2,
    pub radius: f32,
    /// What the node's distance field leads to (a disc, a portal line or a gate line).
    pub target: crate::grid::FieldTarget,
    pub gate: Option<u16>,
    pub dest: Option<u16>,
    pub door: bool,
}

#[derive(Clone, Debug)]
pub struct Edge {
    pub a: u16,
    pub b: u16,
    pub one_way: bool,
    pub stairs: bool,
    pub area: Option<u8>,
    /// Walking this edge happens in open space (a plaza) where people can still change their mind.
    /// On other edges (walkways, halls, ramps) they are committed and do not turn back unless the
    /// way ahead is cut.
    pub open_choice: bool,
    /// Geodesic length (m); infinite when the connection is cut.
    pub length: f32,
}

pub struct Graph {
    pub nodes: Vec<Node>,
    pub edges: Vec<Edge>,
    /// Outgoing (edge index, neighbour) per node.
    pub out: Vec<Vec<(u16, u16)>>,
    /// Incoming (edge index, predecessor) per node.
    pub inc: Vec<Vec<(u16, u16)>>,
}

impl Graph {
    pub fn build_adjacency(&mut self) {
        self.out = vec![Vec::new(); self.nodes.len()];
        self.inc = vec![Vec::new(); self.nodes.len()];
        for (ei, e) in self.edges.iter().enumerate() {
            self.out[e.a as usize].push((ei as u16, e.b));
            self.inc[e.b as usize].push((ei as u16, e.a));
            if !e.one_way {
                self.out[e.b as usize].push((ei as u16, e.a));
                self.inc[e.a as usize].push((ei as u16, e.b));
            }
        }
    }
}

/// Everything route choice reads about the current world for one agent.
pub struct ChoiceInput<'a> {
    pub graph: &'a Graph,
    pub pos: Vec2,
    pub speed: f32,
    pub dest_node: u16,
    pub last_node: u16,
    pub current_next: u16,
    pub familiarity: f32,
    pub sign_compliance: f32,
    pub crowd_following: f32,
    pub stairs_aversion: f32,
    pub sign_via: u16,
    pub impatient: bool,
    /// False once the agent is committed to its current next node (see `Edge::open_choice`).
    pub may_switch: bool,
    /// Route changes this agent has already made.
    pub switches: u8,
    /// Geodesic distance from the agent to each node (INF if unreachable).
    pub dist_to_node: &'a [f32],
    /// Measured queue wait at each node (s), 0 where there is no queue.
    pub node_wait: &'a [f32],
    /// Wait the agent believes (from a wait-time sign) per node; negative = no belief.
    pub believed_wait: &'a [f32],
    /// Speed factor per area from measured crowding (1 = free flow).
    pub area_speed: &'a [f32],
    /// Static speed factor per area (stairs), known to everyone.
    pub area_static: &'a [f32],
    pub area_center: &'a [Vec2],
    /// Share of nearby same-destination people heading to each node.
    pub herd_share: &'a [f32],
    /// Desired walking direction toward each node from the agent's position (field descent).
    pub dir_to_node: &'a [Vec2],
}

/// Cheapest route from the agent to its destination as node indices (first hop first). Returns false
/// when the destination is unreachable.
///
/// Cost-to-go is a Dijkstra from the destination over non-negative edge costs; the bonuses that can
/// make a cost negative (sign advice, herding, commitment) are applied once per candidate first hop,
/// so there are no negative cycles to worry about.
pub fn choose_route(inp: &ChoiceInput, out: &mut Vec<u16>) -> bool {
    let g = inp.graph;
    let n = g.nodes.len();
    assert!(n <= MAX_NODES, "graph too large");
    let v = inp.speed.max(0.3);
    let visible = |p: Vec2| (p - inp.pos).len() <= SIGHT;

    let wait_at = |u: usize| -> f32 {
        let b = inp.believed_wait[u];
        if b >= 0.0 {
            b
        } else if visible(g.nodes[u].pos) {
            inp.node_wait[u]
        } else {
            0.0
        }
    };
    let edge_time = |e: &Edge, len: f32| -> f32 {
        let mut f = 1.0;
        if let Some(a) = e.area {
            f = inp.area_static[a as usize];
            if visible(inp.area_center[a as usize]) {
                f *= inp.area_speed[a as usize];
            }
        }
        let t = len / (v * f.max(0.05));
        let mut c = t;
        if e.stairs {
            c += inp.stairs_aversion * t;
        }
        let near = visible(g.nodes[e.a as usize].pos) || visible(g.nodes[e.b as usize].pos);
        if !near {
            c += UNCERTAINTY_PER_M * len * (1.0 - inp.familiarity);
        }
        c
    };

    // Cost-to-go from every node to the destination (reverse Dijkstra; costs >= 0).
    let mut togo = [f32::INFINITY; MAX_NODES];
    let mut next = [u16::MAX; MAX_NODES];
    let mut done = [false; MAX_NODES];
    togo[inp.dest_node as usize] = 0.0;
    loop {
        let mut best = usize::MAX;
        let mut bc = f32::INFINITY;
        for i in 0..n {
            if !done[i] && togo[i] < bc {
                bc = togo[i];
                best = i;
            }
        }
        if best == usize::MAX {
            break;
        }
        done[best] = true;
        // relax edges u -> best
        for &(ei, u) in &g.inc[best] {
            let e = &g.edges[ei as usize];
            if !e.length.is_finite() || done[u as usize] {
                continue;
            }
            let c = bc + edge_time(e, e.length) + wait_at(best);
            if c < togo[u as usize] {
                togo[u as usize] = c;
                next[u as usize] = best as u16;
            }
        }
    }

    // Candidate first hops: the current next node and every neighbour of the last node passed.
    let mut best_total = f32::INFINITY;
    let mut best_first = u16::MAX;
    let cost_of = |u: u16, via_edge: Option<&Edge>| -> Option<f32> {
        let ui = u as usize;
        let d = inp.dist_to_node[ui];
        if !d.is_finite() || !togo[ui].is_finite() {
            return None;
        }
        let mut c = match via_edge {
            Some(e) => edge_time(e, d),
            None => d / v,
        };
        c += wait_at(ui) + togo[ui];
        if u == inp.current_next {
            c -= COMMIT_BONUS + COMMIT_PER_SWITCH * inp.switches as f32;
            if inp.impatient && inp.node_wait[ui] > 5.0 {
                c += IMPATIENCE_PENALTY;
            }
        }
        c -= HERD_BONUS * inp.crowd_following * inp.herd_share[ui];
        // switching to an option that means turning around (against people behind you)
        if u != inp.current_next && (inp.current_next as usize) < n {
            let a = inp.dir_to_node[inp.current_next as usize];
            let b = inp.dir_to_node[ui];
            if a.dot(b) < -0.3 {
                c += if inp.impatient {
                    BACKTRACK_PENALTY_IMPATIENT
                } else {
                    BACKTRACK_PENALTY
                };
            }
        }
        if (inp.sign_via as usize) < n {
            let mut k = ui;
            let mut hops = 0;
            loop {
                if k == inp.sign_via as usize {
                    c -= SIGN_BONUS * inp.sign_compliance;
                    break;
                }
                if next[k] == u16::MAX || hops > MAX_NODES {
                    break;
                }
                k = next[k] as usize;
                hops += 1;
            }
        }
        Some(c)
    };
    if (inp.current_next as usize) < n {
        let e = g
            .out
            .get(inp.last_node as usize)
            .and_then(|o| o.iter().find(|(_, b)| *b == inp.current_next))
            .map(|(ei, _)| &g.edges[*ei as usize]);
        if let Some(c) = cost_of(inp.current_next, e) {
            best_total = c;
            best_first = inp.current_next;
        }
    }
    // Committed people only reconsider when the way ahead is gone.
    let forced = best_first == u16::MAX;
    let may_switch = inp.may_switch && inp.switches < MAX_SWITCHES;
    if (may_switch || forced) && (inp.last_node as usize) < n {
        for &(ei, b) in &g.out[inp.last_node as usize] {
            if g.edges[ei as usize].length.is_finite() && b != inp.current_next {
                if let Some(c) = cost_of(b, Some(&g.edges[ei as usize])) {
                    if c < best_total {
                        best_total = c;
                        best_first = b;
                    }
                }
            }
        }
    }
    if best_first == u16::MAX {
        return false;
    }
    out.clear();
    let mut k = best_first as usize;
    out.push(k as u16);
    while next[k] != u16::MAX {
        k = next[k] as usize;
        out.push(k as u16);
        if out.len() > MAX_NODES {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn weidmann_is_monotone_and_bounded() {
        let mut last = 1.0;
        for i in 1..60 {
            let f = weidmann_factor(i as f32 * 0.1);
            assert!(f <= last + 1e-6 && f >= 0.05);
            last = f;
        }
        assert!(weidmann_factor(0.0) == 1.0);
        assert!(weidmann_factor(5.4) <= 0.06);
    }
}
