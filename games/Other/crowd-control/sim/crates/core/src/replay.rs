//! Deterministic replay: scenario + seed + simulation version + ordered, tick-stamped commands.
//!
//! Guarantee (tested): the same build replays a recording to identical checksums at every recorded
//! tick. Native x86_64 and wasm32 builds are designed to match too (IEEE basic ops only, `libm` for
//! transcendentals, no fused multiply-add); CI compares their checksums.

use crate::scenario::Scenario;
use crate::sim::{LoadOptions, Sim, TimedCommand, SIM_VERSION};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Replay {
    pub format: String,
    pub sim_version: u32,
    pub schema_version: u32,
    pub scenario_id: String,
    pub seed: u64,
    pub options: LoadOptions,
    pub commands: Vec<TimedCommand>,
    pub checksums: Vec<(u64, u64)>,
    pub final_tick: u64,
    pub final_checksum: u64,
    #[serde(default)]
    pub events: serde_json::Value,
    #[serde(default)]
    pub report: serde_json::Value,
}

impl Replay {
    pub fn record(sim: &Sim, opts: &LoadOptions) -> Replay {
        let mut opts = opts.clone();
        opts.seed = Some(sim.seed);
        Replay {
            format: "crowd-replay".into(),
            sim_version: SIM_VERSION,
            schema_version: sim.sc.schema_version,
            scenario_id: sim.sc.scenario_id.clone(),
            seed: sim.seed,
            options: opts,
            commands: sim.commands.clone(),
            checksums: sim.checksums.clone(),
            final_tick: sim.tick,
            final_checksum: sim.checksum(),
            events: serde_json::to_value(&sim.log).unwrap_or_default(),
            report: serde_json::to_value(crate::score::report(sim)).unwrap_or_default(),
        }
    }

    /// Re-run the recording and compare every checksum. Returns the re-simulated state on success.
    pub fn verify(&self, scenario: &Scenario) -> Result<Sim, String> {
        if self.format != "crowd-replay" {
            return Err("not a crowd replay".into());
        }
        if self.sim_version != SIM_VERSION {
            return Err(format!(
                "replay is from simulation version {}, this build is {}",
                self.sim_version, SIM_VERSION
            ));
        }
        if self.scenario_id != scenario.scenario_id
            || self.schema_version != scenario.schema_version
        {
            return Err("replay belongs to a different scenario or schema version".into());
        }
        let mut sim = Sim::new(scenario.clone(), &self.options).map_err(|e| e.0)?;
        let results = sim.run_with(&self.commands, self.final_tick);
        if let Some(e) = results.iter().find_map(|r| r.as_ref().err()) {
            return Err(format!("a recorded command was rejected on replay: {e}"));
        }
        if sim.checksums.len() != self.checksums.len() {
            return Err(format!(
                "checksum count differs: {} vs {}",
                sim.checksums.len(),
                self.checksums.len()
            ));
        }
        for (a, b) in sim.checksums.iter().zip(&self.checksums) {
            if a != b {
                return Err(format!(
                    "diverged at tick {} (checksum {:x} vs {:x})",
                    b.0, a.1, b.1
                ));
            }
        }
        if sim.tick != self.final_tick || sim.checksum() != self.final_checksum {
            return Err("final state differs".into());
        }
        Ok(sim)
    }
}
