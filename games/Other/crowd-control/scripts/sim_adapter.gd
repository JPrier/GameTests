class_name SimAdapter
extends RefCounted
## One API over the two builds of the same Rust simulation:
##   * desktop / headless tests: the `CrowdSim` GDExtension class (native/crowd.gdextension)
##   * browsers: web/crowd_sim.wasm, driven through web/crowd_glue.js with JavaScriptBridge
## Every query returns JSON text from Rust, parsed here. Commands are typed dictionaries
## (see sim/crates/core/src/sim.rs `Command`). Gameplay rules never live in this file.

const GLUE := "res://web/crowd_glue.js"
const WASM := "res://web/crowd_sim.wasm"

var backend := ""      # "native", "web" or "" (unavailable)
var error := ""
var _native: Object


## Begin loading the simulation backend. On the web this is asynchronous: poll is_ready().
func start() -> void:
	error = ""
	if OS.has_feature("web"):
		backend = "web"
		if not FileAccess.file_exists(WASM):
			error = "This build is missing its simulation module (web/crowd_sim.wasm)."
			backend = ""
			return
		JavaScriptBridge.eval(FileAccess.get_file_as_string(GLUE), true)
		var wasm := FileAccess.get_file_as_bytes(WASM)
		JavaScriptBridge.eval("CrowdSim.initBase64(%s)" % JSON.stringify(Marshalls.raw_to_base64(wasm)), true)
	elif ClassDB.class_exists("CrowdSim"):
		backend = "native"
		_native = ClassDB.instantiate("CrowdSim")
	else:
		error = "The simulation library is not built. Run tools/build_native.sh."


func is_ready() -> bool:
	match backend:
		"native":
			return true
		"web":
			var st = JavaScriptBridge.eval("CrowdSim.status", true)
			if st == "error":
				error = "The simulation failed to start: %s" % str(JavaScriptBridge.eval("CrowdSim.error", true))
				backend = ""
			return st == "ready"
	return false


func _js(call: String):
	return JavaScriptBridge.eval("CrowdSim." + call, true)


func _q(s: String) -> String:
	return JSON.stringify(s)


func _parse(text) -> Variant:
	if typeof(text) != TYPE_STRING or text == "":
		return {}
	var v = JSON.parse_string(text)
	return v if v != null else {}


## Load a scenario (JSON text). Returns "" or an error message.
func load_scenario(scenario_text: String, options: Dictionary = {}) -> String:
	var opts := JSON.stringify(options) if not options.is_empty() else ""
	if backend == "native":
		return _native.load(scenario_text, opts)
	if backend == "web":
		return str(_js("load(%s, %s)" % [_q(scenario_text), _q(opts)]))
	return error


func command(cmd: Dictionary) -> Dictionary:
	var text := JSON.stringify(cmd)
	var out = _native.command(text) if backend == "native" else _js("command(%s)" % _q(text))
	var d = _parse(out)
	return d if d is Dictionary else {"ok": false, "error": "bad reply"}


func step(n: int) -> int:
	if backend == "native":
		return _native.step(n)
	if backend == "web":
		return int(_js("step(%d)" % n))
	return 0


func render_buffer() -> PackedFloat32Array:
	if backend == "native":
		return _native.render_buffer()
	if backend == "web":
		var b = _js("renderBuffer()")
		return (b as PackedByteArray).to_float32_array() if b is PackedByteArray else PackedFloat32Array()
	return PackedFloat32Array()


func density_image() -> PackedByteArray:
	if backend == "native":
		return _native.density_image()
	if backend == "web":
		var b = _js("densityImage()")
		return b if b is PackedByteArray else PackedByteArray()
	return PackedByteArray()


func _text_call(native_method: String, args: Array, js_call: String) -> Variant:
	if backend == "native":
		return _parse(_native.callv(native_method, args))
	if backend == "web":
		return _parse(_js(js_call))
	return {}


func info() -> Dictionary:
	return _text_call("info", [], "info()")


func telemetry(since_log: int) -> Dictionary:
	return _text_call("telemetry", [since_log], "telemetry(%d)" % since_log)


func explain(area_id: String) -> Dictionary:
	return _text_call("explain", [area_id], "explain(%s)" % _q(area_id))


func inspect(p: Vector2) -> Variant:
	return _text_call("inspect", [p.x, p.y], "inspect(%f, %f)" % [p.x, p.y])


func report() -> Dictionary:
	return _text_call("report", [], "report()")


func replay_text() -> String:
	if backend == "native":
		return _native.replay()
	if backend == "web":
		return str(_js("replay()"))
	return ""


func check_barrier(a: Vector2, b: Vector2) -> Dictionary:
	return _text_call("check_barrier", [a.x, a.y, b.x, b.y], "checkBarrier(%f, %f, %f, %f)" % [a.x, a.y, b.x, b.y])


func tick() -> int:
	if backend == "native":
		return _native.tick()
	if backend == "web":
		return int(_js("tick()"))
	return 0


func checksum() -> String:
	if backend == "native":
		return _native.checksum()
	if backend == "web":
		return str(_js("checksum()"))
	return ""
