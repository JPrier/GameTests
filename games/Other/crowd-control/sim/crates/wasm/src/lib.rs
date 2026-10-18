//! WebAssembly build for browsers. Plain C ABI (no wasm-bindgen): the JS glue in
//! `web/crowd_glue.js` writes UTF-8 inputs into buffers from `cc_alloc`, calls an export, and reads
//! the result from `cc_out_ptr`/`cc_out_len`. Godot reaches the glue through JavaScriptBridge.
//!
//! Single-threaded by construction (the web export runs without threads).

use crowd_core::Session;

struct State {
    session: Option<Session>,
    inputs: [Vec<u8>; 2],
    out: Vec<u8>,
}

static mut STATE: Option<State> = None;

#[allow(static_mut_refs)]
fn state() -> &'static mut State {
    // SAFETY: wasm32 web builds are single-threaded and calls never re-enter.
    unsafe {
        if STATE.is_none() {
            STATE = Some(State {
                session: None,
                inputs: [Vec::new(), Vec::new()],
                out: Vec::new(),
            });
        }
        STATE.as_mut().unwrap()
    }
}

fn input(slot: usize) -> String {
    String::from_utf8_lossy(&state().inputs[slot.min(1)]).into_owned()
}

fn set_out(bytes: &[u8]) {
    let st = state();
    st.out.clear();
    st.out.extend_from_slice(bytes);
}

/// Reserve `len` bytes in input `slot` (0 or 1) and return where to write them.
#[no_mangle]
pub extern "C" fn cc_alloc(slot: u32, len: u32) -> *mut u8 {
    let buf = &mut state().inputs[(slot as usize).min(1)];
    buf.clear();
    buf.resize(len as usize, 0);
    buf.as_mut_ptr()
}

#[no_mangle]
pub extern "C" fn cc_out_ptr() -> *const u8 {
    state().out.as_ptr()
}

#[no_mangle]
pub extern "C" fn cc_out_len() -> u32 {
    state().out.len() as u32
}

/// Load scenario (input 0) with options (input 1). Returns 0 on success; the error text is in out.
#[no_mangle]
pub extern "C" fn cc_load() -> i32 {
    let (sc, opts) = (input(0), input(1));
    match Session::load(&sc, &opts) {
        Ok(s) => {
            state().session = Some(s);
            set_out(b"");
            0
        }
        Err(e) => {
            state().session = None;
            set_out(e.as_bytes());
            1
        }
    }
}

fn with_session(f: impl FnOnce(&mut Session) -> Vec<u8>) {
    let bytes = match state().session.as_mut() {
        Some(s) => f(s),
        None => br#"{"ok":false,"error":"no scenario loaded"}"#.to_vec(),
    };
    set_out(&bytes);
}

/// Command JSON in input 0; result JSON in out.
#[no_mangle]
pub extern "C" fn cc_command() {
    let c = input(0);
    with_session(|s| s.command(&c).into_bytes());
}

#[no_mangle]
pub extern "C" fn cc_step(n: u32) -> u32 {
    state().session.as_mut().map(|s| s.step(n)).unwrap_or(0)
}

/// Render buffer as little-endian f32 bytes in out.
#[no_mangle]
pub extern "C" fn cc_render() {
    let st = state();
    st.out.clear();
    if let Some(s) = st.session.as_mut() {
        for f in s.render_buffer() {
            st.out.extend_from_slice(&f.to_le_bytes());
        }
    }
}

#[no_mangle]
pub extern "C" fn cc_density() {
    let st = state();
    st.out.clear();
    if let Some(s) = st.session.as_mut() {
        let img = s.density_image().to_vec();
        st.out.extend_from_slice(&img);
    }
}

#[no_mangle]
pub extern "C" fn cc_info() {
    with_session(|s| s.info().into_bytes());
}

#[no_mangle]
pub extern "C" fn cc_telemetry(since: u32) {
    with_session(|s| s.telemetry(since as usize).into_bytes());
}

/// Area id in input 0.
#[no_mangle]
pub extern "C" fn cc_explain() {
    let a = input(0);
    with_session(|s| s.explain(&a).into_bytes());
}

#[no_mangle]
pub extern "C" fn cc_inspect(x: f32, y: f32) {
    with_session(|s| s.inspect(x, y).into_bytes());
}

#[no_mangle]
pub extern "C" fn cc_report() {
    with_session(|s| s.report().into_bytes());
}

#[no_mangle]
pub extern "C" fn cc_replay() {
    with_session(|s| s.replay().into_bytes());
}

#[no_mangle]
pub extern "C" fn cc_check_barrier(ax: f32, ay: f32, bx: f32, by: f32) {
    with_session(|s| s.check_barrier(ax, ay, bx, by).into_bytes());
}

#[no_mangle]
pub extern "C" fn cc_tick() -> f64 {
    state()
        .session
        .as_ref()
        .map(|s| s.sim.tick as f64)
        .unwrap_or(0.0)
}

#[no_mangle]
pub extern "C" fn cc_is_over() -> u32 {
    state()
        .session
        .as_ref()
        .map(|s| s.sim.is_over() as u32)
        .unwrap_or(1)
}

/// Checksum as 16 hex characters in out.
#[no_mangle]
pub extern "C" fn cc_checksum() {
    with_session(|s| format!("{:016x}", s.sim.checksum()).into_bytes());
}
