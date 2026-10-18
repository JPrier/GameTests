extends Node2D
## Crowd Control: game flow, the fixed-step simulation clock, camera and world input.
##
## The Rust simulation is authoritative. This script only advances it, sends typed player commands,
## and hands its read-only outputs to world_view.gd (rendering) and ui.gd (product UI).

enum Phase { LOADING, TITLE, BRIEFING, PLAYING, ENDED, ERROR }

const SCENARIO_PATH := "res://scenarios/stadium_departure.json"
const SPEEDS := [1, 2, 4, 8]
const TELEMETRY_EVERY := 0.25
const MAX_STEPS_PER_FRAME := 20
const TAP_SLOP := 8.0
const TUTORIAL_FLAG := "user://tutorial_done"
const GAME_SLUG := "crowd-control"

var phase: int = Phase.LOADING
var adapter := SimAdapter.new()
var sc: Dictionary = {}
var sc_text := ""
var info: Dictionary = {}
var telemetry: Dictionary = {}
var report: Dictionary = {}
var explain: Dictionary = {}
var inspected = null
var log_entries: Array = []
var toasts: Array = []             # {text, kind, until}
var speed_idx := 1
var paused := true
var acc := 0.0
var dt := 0.05
var tool := "select"               # "select" | "barrier"
var selection: Dictionary = {}     # {kind: gate|sign|barrier|area|person, id}
var overlays := {"density": false, "risk": false, "flow": false, "queues": true, "routes": false}
var color_mode := 0                # 0 destination, 1 stress, 2 profile
var debug := false
var perfect_info := false
var population_override := 0
var seed_override := -1
var tutorial_step := -1
var help_open := false
var error_text := ""

# barrier drawing
var drag_active := false
var drag_from := Vector2.ZERO
var drag_to := Vector2.ZERO
var preview_ok := false
var preview_error := ""
var _preview_t := 0.0

# pointer / camera
var world: Node2D
var camera: Camera2D
var ui: Node2D
var _press_pos := Vector2.ZERO
var _pressing := false
var _panning := false
var _touches := {}
var _pinch_dist := 0.0
var _telemetry_t := 0.0
var _last_render_tick := -1
var _step_ms := 0.0
var _render_ms := 0.0
var _keys_pan := Vector2.ZERO


func _ready() -> void:
	world = Node2D.new()
	world.name = "World"
	world.set_script(load("res://scripts/world_view.gd"))
	add_child(world)
	camera = Camera2D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)
	ui = Node2D.new()
	ui.name = "UI"
	ui.set_script(load("res://scripts/ui.gd"))
	layer.add_child(ui)
	ui.main = self
	sc_text = FileAccess.get_file_as_string(SCENARIO_PATH)
	var parsed = JSON.parse_string(sc_text)
	sc = parsed if parsed is Dictionary else {}
	world.setup(self, sc)
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	adapter.start()
	if adapter.error != "":
		_fail(adapter.error)
	var capture: Script = load("res://scripts/capture.gd")
	if capture.requested():
		var c := Node.new()
		c.set_script(capture)
		add_child(c)


func _fail(msg: String) -> void:
	error_text = msg
	phase = Phase.ERROR
	ui.queue_redraw()


# ------------------------------------------------------------------ flow

func _process(delta: float) -> void:
	_update_toasts()
	match phase:
		Phase.LOADING:
			if adapter.is_ready():
				phase = Phase.TITLE
			elif adapter.error != "":
				_fail(adapter.error)
		Phase.PLAYING:
			_advance(delta)
	_apply_keys_pan(delta)
	var alpha := 1.0 if paused or phase != Phase.PLAYING else clampf(acc / dt, 0.0, 1.0)
	var heat := -1
	if overlays.risk:
		heat = 1
	elif overlays.density or camera.zoom.x < 0.55:
		heat = 0
	world.set_frame(alpha, camera.zoom.x, color_mode, heat)
	world.top.queue_redraw()
	ui.queue_redraw()


## Start (or restart) the scenario. Seeds and population can be overridden from the debug panel.
func start_scenario(show_briefing := true) -> void:
	var opts := {}
	if population_override > 0:
		opts["population"] = population_override
	if seed_override >= 0:
		opts["seed"] = seed_override
	var err := adapter.load_scenario(sc_text, opts)
	if err != "":
		_fail("Scenario failed to load: " + err)
		return
	info = adapter.info()
	dt = float(info.get("dt", 0.05))
	world.set_density_dims(int(info.density_cols), int(info.density_rows), float(info.density_cell))
	telemetry = {}
	log_entries = []
	report = {}
	explain = {}
	inspected = null
	selection = {}
	tool = "select"
	drag_active = false
	acc = 0.0
	_last_render_tick = -1
	_refresh(true)
	paused = true
	phase = Phase.BRIEFING if show_briefing else Phase.PLAYING
	if phase == Phase.PLAYING:
		paused = false
	_fit_camera()


func begin_play() -> void:
	phase = Phase.PLAYING
	paused = false
	if not FileAccess.file_exists(TUTORIAL_FLAG):
		tutorial_step = 0
		paused = true


func tutorial_next() -> void:
	tutorial_step += 1
	if tutorial_step >= 5:
		tutorial_step = -1
		paused = false
		var f := FileAccess.open(TUTORIAL_FLAG, FileAccess.WRITE)
		if f:
			f.store_string("1")


func _advance(delta: float) -> void:
	if paused:
		return
	acc += delta * SPEEDS[speed_idx]
	var n := int(acc / dt)
	if n > MAX_STEPS_PER_FRAME:
		n = MAX_STEPS_PER_FRAME
		acc = n * dt   # drop time we cannot keep up with rather than spiral
	if n > 0:
		var t0 := Time.get_ticks_usec()
		adapter.step(n)
		_step_ms = lerpf(_step_ms, (Time.get_ticks_usec() - t0) / 1000.0 / n, 0.1)
		acc -= n * dt
		_render()
	_telemetry_t += delta
	if _telemetry_t >= TELEMETRY_EVERY:
		_telemetry_t = 0.0
		_refresh(false)


## Advance the simulation by whole ticks immediately (tests and the debug single-step).
func step_ticks(n: int) -> void:
	adapter.step(n)
	_render()
	_refresh(false)


func _render() -> void:
	var t0 := Time.get_ticks_usec()
	world.set_crowd(adapter.render_buffer())
	_render_ms = lerpf(_render_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _refresh(force_density: bool) -> void:
	var t := adapter.telemetry(log_entries.size())
	if t.is_empty():
		return
	telemetry = t
	for e in t.get("log", []):
		log_entries.append(e)
		_on_log(e)
	if force_density or overlays.density or overlays.risk or overlays.flow or camera.zoom.x < 0.55:
		world.set_density(adapter.density_image())
	if selection.get("kind", "") == "area":
		explain = adapter.explain(selection.id)
	if selection.get("kind", "") == "person" and inspected is Dictionary and inspected.has("pos"):
		inspected = adapter.inspect(Vector2(inspected.pos[0], inspected.pos[1]))
	if _last_render_tick < 0:
		_render()
		_last_render_tick = 0
	if phase == Phase.PLAYING and str(t.get("outcome", "running")) != "running":
		_end()


func _on_log(e: Dictionary) -> void:
	var kind: String = e.get("kind", "")
	if kind in ["incident", "incident_end", "danger", "warning"]:
		toasts.append({"text": e.text, "kind": kind, "until": Time.get_ticks_msec() + 4500})
		if toasts.size() > 3:
			toasts.pop_front()


func toast(text: String, kind := "info") -> void:
	toasts.append({"text": text, "kind": kind, "until": Time.get_ticks_msec() + 3000})
	if toasts.size() > 3:
		toasts.pop_front()


func _update_toasts() -> void:
	var now := Time.get_ticks_msec()
	toasts = toasts.filter(func(t): return t.until > now)


func _end() -> void:
	phase = Phase.ENDED
	paused = true
	report = adapter.report()
	var replay := adapter.replay_text()
	var f := FileAccess.open("user://last_replay.json", FileAccess.WRITE)
	if f:
		f.store_string(replay)
	if OS.has_feature("web"):
		var stars := int(report.get("stars", 0))
		var result := "%s %d" % ["★".repeat(stars) if stars > 0 else "–", int(report.get("score", 0))]
		var key := "gametests:%s:%s" % [GAME_SLUG, Time.get_date_string_from_system()]
		JavaScriptBridge.eval("try{localStorage.setItem(%s, %s)}catch(e){}" % [JSON.stringify(key), JSON.stringify(JSON.stringify({"result": result}))], true)


# ------------------------------------------------------------------ commands from the UI

func set_gate(id: String, mode: String, level := 1.0) -> void:
	var cmd := {"type": "gate", "gate": id, "mode": mode}
	if mode == "metered":
		cmd["level"] = level
	_command(cmd)


func set_sign(id: String, mode: String) -> void:
	_command({"type": "sign", "sign": id, "mode": mode})


func remove_barrier(id: int) -> void:
	var r := _command({"type": "barrier_remove", "id": id})
	if r.get("ok", false):
		selection = {}
		if float(r.get("refund", 0.0)) > 0.0:
			toast("Barrier undone, refunded")


func set_perfect_info(on: bool) -> void:
	_command({"type": "perfect_info", "on": on})
	perfect_info = on


func _command(cmd: Dictionary) -> Dictionary:
	var r := adapter.command(cmd)
	if not r.get("ok", false):
		toast(str(r.get("error", "Not possible")), "error")
	_refresh(true)
	return r


func set_tool(t: String) -> void:
	tool = t
	drag_active = false
	if t == "barrier":
		selection = {}


func toggle_overlay(key: String) -> void:
	overlays[key] = not overlays[key]
	if key == "density" and overlays.density:
		overlays.risk = false
	if key == "risk" and overlays.risk:
		overlays.density = false
	_refresh(true)


func select(kind: String, id) -> void:
	selection = {"kind": kind, "id": id}
	explain = adapter.explain(id) if kind == "area" else {}


# ------------------------------------------------------------------ camera

func map_size_px() -> Vector2:
	return Vector2(sc.map.size[0], sc.map.size[1]) * world.PPM if not sc.is_empty() else Vector2(1200, 720)


func fit_zoom() -> float:
	var vp := get_viewport().get_visible_rect().size
	var m := map_size_px()
	return minf(vp.x / m.x, (vp.y - ui.top_bar_h() - ui.bottom_bar_h()) / m.y) * 0.98


func _fit_camera() -> void:
	if camera == null or ui == null:
		return
	var z := fit_zoom()
	camera.zoom = Vector2(z, z)
	var m := map_size_px()
	var shift: float = (ui.bottom_bar_h() - ui.top_bar_h()) * 0.5 / z
	camera.position = m * 0.5 + Vector2(0, shift)


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world_px(screen_pos)
	var z := clampf(camera.zoom.x * factor, fit_zoom() * 0.85, 5.0)
	camera.zoom = Vector2(z, z)
	var after := screen_to_world_px(screen_pos)
	camera.position += before - after
	_clamp_camera()


func _clamp_camera() -> void:
	var m := map_size_px()
	camera.position = camera.position.clamp(Vector2(-80, -80), m + Vector2(80, 80))


func screen_to_world_px(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func screen_to_m(p: Vector2) -> Vector2:
	return screen_to_world_px(p) / world.PPM


func m_to_screen(m: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * (m * world.PPM)


func _apply_keys_pan(delta: float) -> void:
	if _keys_pan != Vector2.ZERO:
		camera.position += _keys_pan * 600.0 * delta / camera.zoom.x
		_clamp_camera()


# ------------------------------------------------------------------ input

func _input(ev: InputEvent) -> void:
	if ui.handle(ev):
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey:
		_key(ev)
		return
	if phase != Phase.PLAYING or help_open:
		return
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		_touch(ev)
	elif ev is InputEventMouseButton:
		_mouse_button(ev)
	elif ev is InputEventMouseMotion:
		_mouse_motion(ev)
	elif ev is InputEventMagnifyGesture:
		zoom_at(ev.position, ev.factor)
	elif ev is InputEventPanGesture:
		camera.position += ev.delta * 12.0 / camera.zoom.x
		_clamp_camera()


func _key(ev: InputEventKey) -> void:
	var dir := {KEY_W: Vector2.UP, KEY_UP: Vector2.UP, KEY_S: Vector2.DOWN, KEY_DOWN: Vector2.DOWN, KEY_A: Vector2.LEFT, KEY_LEFT: Vector2.LEFT, KEY_D: Vector2.RIGHT, KEY_RIGHT: Vector2.RIGHT}
	if dir.has(ev.keycode) and phase == Phase.PLAYING:
		if ev.pressed and not ev.echo:
			_keys_pan += dir[ev.keycode]
		elif not ev.pressed:
			_keys_pan -= dir[ev.keycode]
		_keys_pan = _keys_pan.clamp(Vector2(-1, -1), Vector2(1, 1))
		return
	if not ev.pressed or ev.echo:
		return
	match ev.keycode:
		KEY_SPACE:
			if phase == Phase.PLAYING and tutorial_step < 0:
				paused = not paused
		KEY_1, KEY_2, KEY_3, KEY_4:
			speed_idx = ev.keycode - KEY_1
		KEY_B:
			if phase == Phase.PLAYING:
				set_tool("select" if tool == "barrier" else "barrier")
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.25)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_at(get_viewport().get_visible_rect().size * 0.5, 0.8)
		KEY_F3:
			debug = not debug
		KEY_PERIOD:
			if debug and paused and phase == Phase.PLAYING:
				step_ticks(1)


func _mouse_button(ev: InputEventMouseButton) -> void:
	if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
		zoom_at(ev.position, 1.12)
	elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
		zoom_at(ev.position, 1.0 / 1.12)
	elif ev.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if ev.pressed and drag_active:
			drag_active = false   # right click cancels a barrier in progress
			return
		_panning = ev.pressed
	elif ev.button_index == MOUSE_BUTTON_LEFT:
		_pointer(ev.position, ev.pressed)


func _mouse_motion(ev: InputEventMouseMotion) -> void:
	if _panning:
		camera.position -= ev.relative / camera.zoom.x
		_clamp_camera()
	elif _pressing:
		_pointer_move(ev.position, ev.relative)


func _touch(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		if _touches.size() == 2:
			drag_active = false
			_pressing = false
			var p: Array = _touches.values()
			_pinch_dist = (p[0] as Vector2).distance_to(p[1])
			return
		if _touches.size() <= 1 and ev.index == 0:
			_pointer(ev.position, ev.pressed)
	elif ev is InputEventScreenDrag:
		var prev: Vector2 = _touches.get(ev.index, ev.position)
		_touches[ev.index] = ev.position
		if _touches.size() >= 2:
			var p: Array = _touches.values()
			var d := (p[0] as Vector2).distance_to(p[1])
			var mid := ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5
			if _pinch_dist > 0.0:
				zoom_at(mid, d / _pinch_dist)
			_pinch_dist = d
			camera.position -= (ev.position - prev) * 0.5 / camera.zoom.x
			_clamp_camera()
		elif _pressing:
			_pointer_move(ev.position, ev.position - prev)


func _pointer(pos: Vector2, pressed: bool) -> void:
	if pressed:
		_pressing = true
		_press_pos = pos
		if tool == "barrier":
			drag_active = true
			drag_from = _snap(screen_to_m(pos))
			drag_to = drag_from
			preview_ok = false
			preview_error = ""
		return
	if not _pressing:
		return
	_pressing = false
	if tool == "barrier":
		if drag_active:
			drag_active = false
			_update_preview(true)
			if preview_ok:
				var r := _command({"type": "barrier_add", "a": [drag_from.x, drag_from.y], "b": [drag_to.x, drag_to.y]})
				if r.get("ok", false):
					selection = {"kind": "barrier", "id": int(r.id)}
					tool = "select"
			elif preview_error != "" and drag_from.distance_to(drag_to) > 0.5:
				toast(preview_error, "error")
		return
	if _panning_touch_moved(pos):
		return
	_tap(screen_to_m(pos))


var _moved := false


func _panning_touch_moved(_pos: Vector2) -> bool:
	var m := _moved
	_moved = false
	return m


func _pointer_move(pos: Vector2, rel: Vector2) -> void:
	if tool == "barrier" and drag_active:
		var p := _snap(screen_to_m(pos))
		var max_len := float(sc.player_resources.barrier_max_len)
		if p.distance_to(drag_from) > max_len:
			p = drag_from + (p - drag_from).normalized() * max_len
		drag_to = p
		_preview_t -= 1.0
		_update_preview(false)
		return
	if pos.distance_to(_press_pos) > TAP_SLOP or _moved:
		_moved = true
		camera.position -= rel / camera.zoom.x
		_clamp_camera()


func _snap(p: Vector2) -> Vector2:
	return (p * 2.0).round() / 2.0


func _update_preview(force: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - _preview_t < 0.08:
		return
	_preview_t = now
	if drag_from.distance_to(drag_to) < 1.0:
		preview_ok = false
		preview_error = "Drag to draw a barrier"
		return
	var r := adapter.check_barrier(drag_from, drag_to)
	preview_ok = r.get("ok", false)
	preview_error = str(r.get("error", ""))


## Select whatever is under a world point (metres): gate, sign, barrier, person (debug) or area.
func _tap(p: Vector2) -> void:
	var best := {}
	var best_d := 3.0
	for g in sc.gates:
		var d := _seg_dist(p, Vector2(g.line[0], g.line[1]), Vector2(g.line[2], g.line[3]))
		if d < best_d:
			best_d = d
			best = {"kind": "gate", "id": g.id}
	for s in sc.get("signs", []):
		var d := p.distance_to(Vector2(s.pos[0], s.pos[1]))
		if d < best_d:
			best_d = d
			best = {"kind": "sign", "id": s.id}
	for b in telemetry.get("barriers", []):
		var d := _seg_dist(p, Vector2(b.a.x, b.a.y), Vector2(b.b.x, b.b.y))
		if d < minf(best_d, 1.8):
			best_d = d
			best = {"kind": "barrier", "id": int(b.id)}
	if best.is_empty() and debug:
		var who = adapter.inspect(p)
		if who is Dictionary and not who.is_empty():
			inspected = who
			best = {"kind": "person", "id": who.id}
	if best.is_empty():
		for a in sc.map.areas:
			var r := Rect2(a.rect[0], a.rect[1], a.rect[2], a.rect[3])
			if r.has_point(p):
				best = {"kind": "area", "id": a.id}
				break
	if best.is_empty():
		selection = {}
		explain = {}
	else:
		select(best.kind, best.id)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


# ------------------------------------------------------------------ agent-facing state

func get_agent_state() -> Dictionary:
	var pop: Dictionary = telemetry.get("population", {})
	return {
		"phase": Phase.keys()[phase], "backend": adapter.backend, "tick": adapter.tick(),
		"paused": paused, "speed": SPEEDS[speed_idx], "tool": tool, "selection": selection,
		"inside": pop.get("inside", 0), "active": pop.get("active", 0), "completed": pop.get("completed", 0),
		"danger_seconds": telemetry.get("danger_seconds", 0.0), "outcome": telemetry.get("outcome", ""),
		"rendered": world.count, "score": report.get("score", -1), "zoom": camera.zoom.x,
	}
