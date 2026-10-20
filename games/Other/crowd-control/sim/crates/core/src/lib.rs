//! Crowd simulation core for the Crowd Control game.
//!
//! Engine-independent: Godot talks to it through `Session` (via the GDExtension on desktop and the
//! WebAssembly module in browsers), and the `crowd` CLI runs it headless for tests, replays and
//! benchmarks.

pub mod agents;
pub mod grid;
pub mod math;
pub mod metrics;
pub mod output;
pub mod replay;
pub mod rng;
pub mod routing;
pub mod scenario;
pub mod score;
pub mod sim;
pub mod spatial;

pub use scenario::Scenario;
pub use sim::{Command, LoadOptions, Sim, TimedCommand};

use serde_json::json;

/// String/bytes API shared by both engine bindings, so the GDExtension and the wasm module behave
/// identically.
pub struct Session {
    pub sim: Sim,
    pub opts: LoadOptions,
    render: Vec<f32>,
    image: Vec<u8>,
}

impl Session {
    pub fn load(scenario_json: &str, options_json: &str) -> Result<Session, String> {
        let sc = Scenario::from_json(scenario_json).map_err(|e| e.0)?;
        let opts: LoadOptions = if options_json.trim().is_empty() {
            LoadOptions::default()
        } else {
            serde_json::from_str(options_json).map_err(|e| format!("options: {e}"))?
        };
        let sim = Sim::new(sc, &opts).map_err(|e| e.0)?;
        Ok(Session {
            sim,
            opts,
            render: Vec::new(),
            image: Vec::new(),
        })
    }

    /// Apply a JSON command; returns {"ok": true, ...} or {"ok": false, "error": "..."}.
    pub fn command(&mut self, json_text: &str) -> String {
        let cmd: Command = match serde_json::from_str(json_text) {
            Ok(c) => c,
            Err(e) => {
                return json!({"ok": false, "error": format!("bad command: {e}")}).to_string()
            }
        };
        match self.sim.apply(cmd) {
            Ok(mut v) => {
                if let Some(o) = v.as_object_mut() {
                    o.insert("ok".into(), json!(true));
                }
                v.to_string()
            }
            Err(e) => json!({"ok": false, "error": e}).to_string(),
        }
    }

    /// Advance up to `n` ticks; returns ticks actually run.
    pub fn step(&mut self, n: u32) -> u32 {
        let mut k = 0;
        while k < n && !self.sim.is_over() {
            self.sim.step();
            k += 1;
        }
        k
    }

    pub fn render_buffer(&mut self) -> &[f32] {
        self.sim.render_buffer(&mut self.render);
        &self.render
    }

    pub fn density_image(&mut self) -> &[u8] {
        self.sim.density_image(&mut self.image);
        &self.image
    }

    pub fn info(&self) -> String {
        let (c, r, cell) = self.sim.density_dims();
        json!({
            "density_cols": c, "density_rows": r, "density_cell": cell, "dt": self.sim.dt,
            "sim_version": sim::SIM_VERSION, "seed": self.sim.seed, "population": self.sim.total_population,
            "floats_per_agent": output::FLOATS_PER_AGENT,
        })
        .to_string()
    }

    pub fn telemetry(&self, since_log: usize) -> String {
        self.sim.telemetry(since_log).to_string()
    }
    pub fn explain(&self, area: &str) -> String {
        self.sim.explain(area).to_string()
    }
    pub fn inspect(&self, x: f32, y: f32) -> String {
        self.sim.inspect(math::Vec2::new(x, y)).to_string()
    }
    pub fn report(&self) -> String {
        serde_json::to_string(&score::report(&self.sim)).unwrap_or_default()
    }
    pub fn replay(&self) -> String {
        serde_json::to_string(&replay::Replay::record(&self.sim, &self.opts)).unwrap_or_default()
    }
    /// Dry run of a command (placement preview): {"ok", "cost"} or {"ok": false, "error"}.
    pub fn check_command(&self, json_text: &str) -> String {
        let cmd: Command = match serde_json::from_str(json_text) {
            Ok(c) => c,
            Err(e) => {
                return json!({"ok": false, "error": format!("bad command: {e}")}).to_string()
            }
        };
        match self.sim.check_command(&cmd) {
            Ok(cost) => json!({"ok": true, "cost": cost}).to_string(),
            Err(e) => json!({"ok": false, "error": e}).to_string(),
        }
    }

    pub fn check_barrier(&self, ax: f32, ay: f32, bx: f32, by: f32) -> String {
        match self
            .sim
            .check_barrier(math::Vec2::new(ax, ay), math::Vec2::new(bx, by))
        {
            Ok(()) => json!({"ok": true}).to_string(),
            Err(e) => json!({"ok": false, "error": e}).to_string(),
        }
    }
}
