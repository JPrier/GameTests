//! GDExtension binding: exposes `CrowdSim` (RefCounted) to GDScript on desktop builds and in
//! headless native tests. Mirrors the wasm module's API one-to-one (see sim_adapter.gd).

use crowd_core::Session;
use godot::prelude::*;

struct CrowdExtension;

#[gdextension]
unsafe impl ExtensionLibrary for CrowdExtension {}

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct CrowdSim {
    session: Option<Session>,
}

#[godot_api]
impl CrowdSim {
    /// Load a scenario (JSON text) with options (JSON text, may be empty). Returns "" or an error.
    #[func]
    fn load(&mut self, scenario: GString, options: GString) -> GString {
        match Session::load(&scenario.to_string(), &options.to_string()) {
            Ok(s) => {
                self.session = Some(s);
                GString::new()
            }
            Err(e) => {
                self.session = None;
                GString::from(e.as_str())
            }
        }
    }

    #[func]
    fn command(&mut self, json: GString) -> GString {
        match self.session.as_mut() {
            Some(s) => GString::from(s.command(&json.to_string()).as_str()),
            None => GString::from(r#"{"ok":false,"error":"no scenario loaded"}"#),
        }
    }

    #[func]
    fn step(&mut self, n: i64) -> i64 {
        self.session
            .as_mut()
            .map(|s| s.step(n.max(0) as u32) as i64)
            .unwrap_or(0)
    }

    #[func]
    fn render_buffer(&mut self) -> PackedFloat32Array {
        match self.session.as_mut() {
            Some(s) => PackedFloat32Array::from(s.render_buffer()),
            None => PackedFloat32Array::new(),
        }
    }

    #[func]
    fn density_image(&mut self) -> PackedByteArray {
        match self.session.as_mut() {
            Some(s) => PackedByteArray::from(s.density_image()),
            None => PackedByteArray::new(),
        }
    }

    #[func]
    fn info(&self) -> GString {
        self.text(|s| s.info())
    }
    #[func]
    fn telemetry(&self, since_log: i64) -> GString {
        self.text(|s| s.telemetry(since_log.max(0) as usize))
    }
    #[func]
    fn explain(&self, area: GString) -> GString {
        let a = area.to_string();
        self.text(|s| s.explain(&a))
    }
    #[func]
    fn inspect(&self, x: f64, y: f64) -> GString {
        self.text(|s| s.inspect(x as f32, y as f32))
    }
    #[func]
    fn report(&self) -> GString {
        self.text(|s| s.report())
    }
    #[func]
    fn replay(&self) -> GString {
        self.text(|s| s.replay())
    }
    #[func]
    fn check_command(&self, json: GString) -> GString {
        self.text(|s| s.check_command(&json.to_string()))
    }
    #[func]
    fn check_barrier(&self, ax: f64, ay: f64, bx: f64, by: f64) -> GString {
        self.text(|s| s.check_barrier(ax as f32, ay as f32, bx as f32, by as f32))
    }
    #[func]
    fn tick(&self) -> i64 {
        self.session
            .as_ref()
            .map(|s| s.sim.tick as i64)
            .unwrap_or(0)
    }
    #[func]
    fn is_over(&self) -> bool {
        self.session
            .as_ref()
            .map(|s| s.sim.is_over())
            .unwrap_or(true)
    }
    #[func]
    fn checksum(&self) -> GString {
        self.text(|s| format!("{:016x}", s.sim.checksum()))
    }
}

impl CrowdSim {
    fn text(&self, f: impl FnOnce(&Session) -> String) -> GString {
        match self.session.as_ref() {
            Some(s) => GString::from(f(s).as_str()),
            None => GString::new(),
        }
    }
}
