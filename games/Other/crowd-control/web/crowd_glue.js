// Crowd Control: browser glue between Godot (JavaScriptBridge) and the Rust simulation compiled to
// wasm32-unknown-unknown (sim/crates/wasm). Godot evaluates this file once, then calls
// window.CrowdSim.* through JavaScriptBridge.eval with string/number arguments only (JavaScriptBridge
// cannot pass PackedByteArrays to JS). Byte results are returned as fresh Uint8Arrays, which
// JavaScriptBridge.eval converts to PackedByteArray.
//
// The same file runs under Node in CI (tools/wasm_check.mjs) to compare checksums with native.
(function (root) {
  "use strict";
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const S = {
    inst: null,
    status: "idle",
    error: "",

    // Start instantiating from base64 (Godot reads the module out of its .pck).
    initBase64(b64) {
      const bin = typeof atob === "function" ? Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)) : Uint8Array.from(Buffer.from(b64, "base64"));
      return this.initBytes(bin);
    },
    initBytes(bin) {
      this.status = "loading";
      return WebAssembly.instantiate(bin, {})
        .then((r) => { this.inst = r.instance; this.status = "ready"; })
        .catch((e) => { this.status = "error"; this.error = String(e); });
    },
    get e() { return this.inst.exports; },
    _put(slot, str) {
      const b = enc.encode(str);
      const p = this.e.cc_alloc(slot, b.length);
      new Uint8Array(this.e.memory.buffer, p, b.length).set(b);
    },
    _bytes() { return new Uint8Array(this.e.memory.buffer, this.e.cc_out_ptr(), this.e.cc_out_len()).slice(); },
    _text() { return dec.decode(new Uint8Array(this.e.memory.buffer, this.e.cc_out_ptr(), this.e.cc_out_len())); },

    load(scenario, options) {
      this._put(0, scenario);
      this._put(1, options || "");
      return this.e.cc_load() === 0 ? "" : this._text();
    },
    command(json) { this._put(0, json); this.e.cc_command(); return this._text(); },
    step(n) { return this.e.cc_step(n >>> 0); },
    renderBuffer() { this.e.cc_render(); return this._bytes(); },
    densityImage() { this.e.cc_density(); return this._bytes(); },
    info() { this.e.cc_info(); return this._text(); },
    telemetry(since) { this.e.cc_telemetry(since >>> 0); return this._text(); },
    explain(area) { this._put(0, area); this.e.cc_explain(); return this._text(); },
    inspect(x, y) { this.e.cc_inspect(x, y); return this._text(); },
    report() { this.e.cc_report(); return this._text(); },
    replay() { this.e.cc_replay(); return this._text(); },
    checkCommand(json) { this._put(0, json); this.e.cc_check_command(); return this._text(); },
    checkBarrier(ax, ay, bx, by) { this.e.cc_check_barrier(ax, ay, bx, by); return this._text(); },
    tick() { return this.e.cc_tick(); },
    isOver() { return this.e.cc_is_over() === 1; },
    checksum() { this.e.cc_checksum(); return this._text(); },
  };
  root.CrowdSim = S;
})(typeof window !== "undefined" ? window : globalThis);
