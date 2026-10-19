//! Structure-of-arrays pedestrian storage.
//!
//! Index positions change when agents leave (swap-remove); `id` is the stable identity. `slot_of`
//! maps id -> current index for group lookups and the debug inspector.

use crate::math::Vec2;

pub const NONE16: u16 = u16::MAX;
pub const NONE32: u32 = u32::MAX;
pub const MAX_ROUTE: usize = 10;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum State {
    Walking = 0,
    /// Stopped at a gate line waiting to be served.
    Holding = 1,
    /// Moving slower than the waiting threshold (queue or jam).
    Slowed = 2,
    /// No reachable destination right now (e.g. every route closed).
    Stuck = 3,
}

#[derive(Default)]
pub struct Agents {
    pub id: Vec<u32>,
    pub pos: Vec<Vec2>,
    pub prev: Vec<Vec2>,
    pub heading: Vec<Vec2>,
    pub speed: Vec<f32>,
    pub desired_speed: Vec<f32>,
    pub radius: Vec<f32>,
    pub dest: Vec<u16>,
    pub profile: Vec<u8>,
    /// Stable id of the group leader (own id for solo agents and leaders).
    pub leader: Vec<u32>,
    pub familiarity: Vec<f32>,
    pub sign_compliance: Vec<f32>,
    pub crowd_following: Vec<f32>,
    pub patience: Vec<f32>,
    pub stairs_aversion: Vec<f32>,
    /// Route as graph node indices; `route_pos` points at the next node.
    pub route: Vec<[u16; MAX_ROUTE]>,
    pub route_len: Vec<u8>,
    pub route_pos: Vec<u8>,
    /// Last graph node passed (decision origin).
    pub last_node: Vec<u16>,
    pub next_decision: Vec<f32>,
    /// Gate index this agent has been served at (may cross that gate line), or NONE16.
    pub gate_pass: Vec<u16>,
    /// Node recommended by a sign this agent read (NONE16 = none) and the sign it came from.
    pub sign_via: Vec<u16>,
    pub signs_read: Vec<u8>,
    pub area: Vec<u8>,
    pub state: Vec<State>,
    pub spawn_time: Vec<f32>,
    /// Total time spent waiting/slowed (s) and current continuous wait (s).
    pub wait_total: Vec<f32>,
    pub wait_now: Vec<f32>,
    pub satisfaction: Vec<f32>,
    /// Free-flow geodesic travel time estimated at spawn (s).
    pub ideal_time: Vec<f32>,
    /// Group leader should slow down this tick (members fell behind).
    pub leader_slow: Vec<bool>,
}

pub struct NewAgent {
    pub id: u32,
    pub pos: Vec2,
    pub desired_speed: f32,
    pub radius: f32,
    pub dest: u16,
    pub profile: u8,
    pub leader: u32,
    pub familiarity: f32,
    pub sign_compliance: f32,
    pub crowd_following: f32,
    pub patience: f32,
    pub stairs_aversion: f32,
    pub last_node: u16,
    pub spawn_time: f32,
    pub next_decision: f32,
}

impl Agents {
    pub fn len(&self) -> usize {
        self.id.len()
    }
    pub fn is_empty(&self) -> bool {
        self.id.is_empty()
    }

    pub fn push(&mut self, a: NewAgent) {
        self.id.push(a.id);
        self.pos.push(a.pos);
        self.prev.push(a.pos);
        self.heading.push(Vec2::new(1.0, 0.0));
        self.speed.push(0.0);
        self.desired_speed.push(a.desired_speed);
        self.radius.push(a.radius);
        self.dest.push(a.dest);
        self.profile.push(a.profile);
        self.leader.push(a.leader);
        self.familiarity.push(a.familiarity);
        self.sign_compliance.push(a.sign_compliance);
        self.crowd_following.push(a.crowd_following);
        self.patience.push(a.patience);
        self.stairs_aversion.push(a.stairs_aversion);
        self.route.push([NONE16; MAX_ROUTE]);
        self.route_len.push(0);
        self.route_pos.push(0);
        self.last_node.push(a.last_node);
        self.next_decision.push(a.next_decision);
        self.gate_pass.push(NONE16);
        self.sign_via.push(NONE16);
        self.signs_read.push(0);
        self.area.push(u8::MAX);
        self.state.push(State::Walking);
        self.spawn_time.push(a.spawn_time);
        self.wait_total.push(0.0);
        self.wait_now.push(0.0);
        self.satisfaction.push(100.0);
        self.ideal_time.push(0.0);
        self.leader_slow.push(false);
    }

    pub fn swap_remove(&mut self, i: usize) {
        self.id.swap_remove(i);
        self.pos.swap_remove(i);
        self.prev.swap_remove(i);
        self.heading.swap_remove(i);
        self.speed.swap_remove(i);
        self.desired_speed.swap_remove(i);
        self.radius.swap_remove(i);
        self.dest.swap_remove(i);
        self.profile.swap_remove(i);
        self.leader.swap_remove(i);
        self.familiarity.swap_remove(i);
        self.sign_compliance.swap_remove(i);
        self.crowd_following.swap_remove(i);
        self.patience.swap_remove(i);
        self.stairs_aversion.swap_remove(i);
        self.route.swap_remove(i);
        self.route_len.swap_remove(i);
        self.route_pos.swap_remove(i);
        self.last_node.swap_remove(i);
        self.next_decision.swap_remove(i);
        self.gate_pass.swap_remove(i);
        self.sign_via.swap_remove(i);
        self.signs_read.swap_remove(i);
        self.area.swap_remove(i);
        self.state.swap_remove(i);
        self.spawn_time.swap_remove(i);
        self.wait_total.swap_remove(i);
        self.wait_now.swap_remove(i);
        self.satisfaction.swap_remove(i);
        self.ideal_time.swap_remove(i);
        self.leader_slow.swap_remove(i);
    }

    #[inline]
    pub fn next_node(&self, i: usize) -> u16 {
        let p = self.route_pos[i] as usize;
        if p < self.route_len[i] as usize {
            self.route[i][p]
        } else {
            NONE16
        }
    }

    pub fn set_route(&mut self, i: usize, nodes: &[u16]) {
        let n = nodes.len().min(MAX_ROUTE);
        self.route[i] = [NONE16; MAX_ROUTE];
        self.route[i][..n].copy_from_slice(&nodes[..n]);
        self.route_len[i] = n as u8;
        self.route_pos[i] = 0;
    }
}
