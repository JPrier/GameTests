extends Node2D
## Operations UI (product UI on the shared GameTests GTUI system) plus crisp world labels.
## Immediate mode: everything is redrawn each frame from main.gd's state. Fixed layout: the bars and
## panels never move existing controls, so a tap always lands where the player aimed.

const PAL := {
	"bg": Color("14181c"), "surface": Color("1b2127"), "surface_high": Color("26303a"),
	"text": Color("eef2f4"), "text_muted": Color("9eabb5"), "border": Color(1, 1, 1, 0.12),
	"accent": Color("ffc145"), "on_accent": Color("1d1606"), "success": Color("5ccf8a"),
	"danger": Color("ff6b5e"), "focus": Color("ffd479"),
}
const LEVEL_COL := {"comfortable": Color("5ccf8a"), "crowded": Color("ffd43b"), "heavy": Color("ff922b"), "danger": Color("ff5d52")}
const LEVEL_TEXT := {"comfortable": "Comfortable", "crowded": "Crowded", "heavy": "Heavily congested", "danger": "Dangerous"}
const GATE_MODES := ["Open", "50%", "25%", "10%", "Close"]
const GATE_LEVELS := [0.5, 0.25, 0.1]
const OVERLAYS := [["density", "Density"], ["risk", "Risk"], ["flow", "Flow"], ["queues", "Queues"], ["routes", "Routes"], ["mood", "Mood"]]
const TUTORIAL := [
	"Fans pour out of the stadium on the left. Teal people want the trains, orange people the car park.",
	"Tap a gate to change it. Metering the North Gate holds people in the roomy plaza instead of the narrow walkway.",
	"Tap a sign in the plaza to point train passengers to a gate, or to show the wait at each station entrance.",
	"Barrier tool: drag inside a yellow zone to place a temporary barrier. People route around it.",
	"A train delay is likely. Tap any area to see why it is congested. Keep everyone out of the red.",
]

const OBJECTIVE_W := 232.0

var main: Node
var _labels: Array = []
var _reserved: Array = []
var _pressed_id := ""
var _blockers: Array = []
var _modal := false
var big_crowd := false


func _ready() -> void:
	GTUI.setup(self, PAL)


func _short() -> bool:
	return GTUI.view_size(self).y < GTUI.dp(480)


## Bar height including its outer margin: TARGET plus inner padding (smaller on short screens).
func _bar_pad() -> float:
	return GTUI.SP_XS if _short() else GTUI.SP_S


func top_bar_h() -> float:
	return GTUI.dp(GTUI.TARGET + _bar_pad() * 2 + GTUI.SP_S * 2)


func bottom_bar_h() -> float:
	var one := GTUI.TARGET + _bar_pad() * 2
	return GTUI.dp((one * 2 - _bar_pad() if _narrow() else one) + GTUI.SP_S * 2)


func objective_h() -> float:
	return GTUI.dp(74 if _short() else 96)


func _narrow() -> bool:
	return GTUI.view_size(self).x < GTUI.dp(780)


func _vs() -> Vector2:
	return GTUI.view_size(self)


# ------------------------------------------------------------------ input

## Returns true when the UI consumed the event (it never reaches the map).
func handle(ev: InputEvent) -> bool:
	var local := make_input_local(ev)
	var r := GTUI.handle_input(local)
	if r.has("activate"):
		_activate(r.activate)
		return true
	if r.get("cancel", false):
		return _cancel()
	if r.get("consumed", false):
		return true
	var pos := Vector2(-1, -1)
	var pressed := false
	var is_press := false
	if local is InputEventMouseButton and local.button_index == MOUSE_BUTTON_LEFT:
		pos = local.position
		pressed = local.pressed
		is_press = true
	elif local is InputEventScreenTouch and local.index == 0:
		pos = local.position
		pressed = local.pressed
		is_press = true
	if is_press:
		if pressed:
			var id := _hit(pos)
			if id != "":
				_pressed_id = id
				return true
			_pressed_id = ""
			return _modal or _blocked(pos)
		else:
			if _pressed_id != "":
				var id := _hit(pos)
				if id == _pressed_id:
					_activate(id)
				_pressed_id = ""
				return true
			return _modal
	if local is InputEventMouseButton or local is InputEventScreenDrag or local is InputEventMagnifyGesture or local is InputEventPanGesture:
		if _modal:
			return true
		if local is InputEventMouseButton and (local.button_index == MOUSE_BUTTON_WHEEL_UP or local.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			return _blocked(local.position)
	return false


func _hit(pos: Vector2) -> String:
	var best := ""
	for t in GTUI._active_targets():
		if t.ci == self and (t.rect as Rect2).has_point(pos):
			best = t.id
	return best


func _blocked(pos: Vector2) -> bool:
	for r in _blockers:
		if (r as Rect2).has_point(pos):
			return true
	return false


func _cancel() -> bool:
	if main.help_open:
		main.help_open = false
	elif main.tool == "barrier":
		main.set_tool("select")
	elif not main.selection.is_empty():
		main.selection = {}
	else:
		return false
	return true


func _activate(id: String) -> void:
	var parts := id.split(":")
	match parts[0]:
		"title_start":
			main.population_override = 5000 if big_crowd else 0
			main.start_scenario(true)
		"title_big":
			big_crowd = not big_crowd
		"help":
			main.help_open = not main.help_open
		"help_close":
			main.help_open = false
		"brief_start":
			main.begin_play()
		"pause":
			if main.tutorial_step < 0:
				main.paused = not main.paused
		"speed":
			main.speed_idx = int(parts[1])
		"tool":
			main.set_tool("barrier" if int(parts[1]) == 1 else "select")
		"ov":
			if parts[1] == "mood":
				main.color_mode = 0 if main.color_mode == 1 else 1
			else:
				main.toggle_overlay(parts[1])
		"panel_close":
			main.selection = {}
		"gate_mode":
			var g: String = main.selection.id
			var k := int(parts[1])
			if k == 0:
				main.set_gate(g, "open")
			elif k == GATE_MODES.size() - 1:
				main.set_gate(g, "closed")
			else:
				main.set_gate(g, "metered", GATE_LEVELS[k - 1])
		"sign_mode":
			main.set_sign(main.selection.id, parts[1])
		"barrier_remove":
			main.remove_barrier(int(main.selection.id))
		"tut_next":
			main.tutorial_next()
		"tut_skip":
			main.tutorial_step = 4
			main.tutorial_next()
		"res_retry":
			main.start_scenario(false)
		"res_menu":
			main.phase = main.Phase.TITLE
		"dbg_perfect":
			main.set_perfect_info(not main.perfect_info)
		"dbg_step":
			main.step_ticks(1)
		"dbg_export":
			_export_telemetry()
		"dbg_close":
			main.debug = false
		"err_retry":
			get_tree().reload_current_scene()


func _export_telemetry() -> void:
	var f := FileAccess.open("user://telemetry.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"telemetry": main.telemetry, "log": main.log_entries, "replay": JSON.parse_string(main.adapter.replay_text())}, "  "))
		main.toast("Saved telemetry to user://telemetry.json")


# ------------------------------------------------------------------ draw

func _draw() -> void:
	GTUI.begin()
	_blockers.clear()
	_modal = false
	if main == null:
		return
	var ph: int = main.phase
	match ph:
		main.Phase.LOADING:
			_draw_center_note("Starting the simulation…")
		main.Phase.ERROR:
			_draw_error()
		main.Phase.TITLE:
			_draw_title()
		_:
			_draw_world_labels()
			_draw_hud()
			if ph == main.Phase.BRIEFING:
				_draw_briefing()
			elif ph == main.Phase.ENDED:
				_draw_results()
			else:
				if main.tutorial_step >= 0:
					_draw_tutorial()
				if main.help_open:
					_draw_help()
	_draw_toasts()


## Screen rects the HUD will occupy this frame (map labels avoid them).
func _ui_rects() -> Array:
	var vs := _vs()
	var m := GTUI.dp(GTUI.SP_S)
	var out := [Rect2(0, 0, vs.x, top_bar_h()), Rect2(0, vs.y - bottom_bar_h(), vs.x, bottom_bar_h()), Rect2(m, top_bar_h(), GTUI.dp(OBJECTIVE_W), objective_h())]
	if not main.selection.is_empty():
		out.append(_panel_rect(vs.y) if not _narrow() else Rect2(0, vs.y * 0.5, vs.x, vs.y * 0.5))
	if main.debug:
		out.append(Rect2(m, vs.y - bottom_bar_h() - GTUI.dp(250), GTUI.dp(300), GTUI.dp(250)))
	for tl in _toast_layout():
		out.append(tl.rect)
	return out


func _draw_center_note(msg: String) -> void:
	var vs := _vs()
	GTUI.text_in(self, Rect2(0, vs.y * 0.5 - GTUI.dp(20), vs.x, GTUI.dp(40)), msg, GTUI.FS_BODY, GTUI.c("text_muted"))


# --- world labels (screen space, so they stay crisp at any zoom)

func _draw_world_labels() -> void:
	_labels.clear()
	_reserved = _ui_rects()
	var sc: Dictionary = main.sc
	var zoom: float = main.camera.zoom.x
	for l in sc.map.get("decor", {}).get("labels", []):
		var p: Vector2 = main.m_to_screen(Vector2(l.pos[0], l.pos[1]))
		var tw := GTUI.text_width(l.text, GTUI.FS_LABEL, true)
		var lr := Rect2(p.x - tw / 2, p.y - GTUI.dp(12), tw, GTUI.dp(24))
		if _reserved.any(func(o): return (o as Rect2).intersects(lr)):
			continue  # never half-hidden behind the HUD or a toast
		GTUI.text_in(self, Rect2(p.x - GTUI.dp(80), p.y - GTUI.dp(12), GTUI.dp(160), GTUI.dp(24)), l.text, GTUI.FS_LABEL, Color(1, 1, 1, 0.55), 0, true)  # gt:art
	# dangerous crowding first, so it always gets its label
	for at in main.telemetry.get("areas", []):
		if at.get("alarm", false):
			for d in sc.map.areas:
				if d.id == at.id:
					var top_mid: Vector2 = main.m_to_screen(Vector2(d.rect[0] + d.rect[2] * 0.5, d.rect[1]))
					_pill_label(top_mid + Vector2(0, GTUI.dp(14)), "Dangerous crowding", Color("ff3b3b"))
	if zoom < 0.4:
		return
	var tg := {}
	for g in main.telemetry.get("gates", []):
		tg[g.id] = g
	for g in sc.gates:
		var a := Vector2(g.line[0], g.line[1])
		var b := Vector2(g.line[2], g.line[3])
		var top := a if a.y < b.y else b
		var p: Vector2 = main.m_to_screen(top) + Vector2(0, -GTUI.dp(16))
		var label: String = g.name
		var t: Dictionary = tg.get(g.id, {})
		if t.get("mode", "") == "metered" and g.get("controllable", false):
			label += " · %d/min" % int(t.get("rate_pm", 0))
		elif t.get("mode", "") == "closed":
			label += " · closed"
		_pill_label(p, label)
		if main.overlays.queues and int(t.get("queue", 0)) > 0:
			var bp: Vector2 = main.m_to_screen(Vector2(maxf(a.x, b.x), maxf(a.y, b.y))) + Vector2(0, GTUI.dp(14))
			_pill_label(bp, "%d waiting" % int(t.queue), Color("f59f00"))
		elif main.overlays.queues and int(t.get("queue", 0)) < 0:
			var bp: Vector2 = main.m_to_screen(Vector2(maxf(a.x, b.x), maxf(a.y, b.y))) + Vector2(0, GTUI.dp(14))
			_pill_label(bp, "camera: ~%s wait" % _wait_text(t.get("wait", 0)), Color("f59f00"))
	for s in sc.get("signs", []):
		for st in main.telemetry.get("signs", []):
			if st.id == s.id and st.mode != "off":
				var txt: String = st.label
				if st.mode == "waits" and st.shown.size() >= 2:
					txt = "N %s · S %s" % [_wait_text(st.shown[0]), _wait_text(st.shown[1])]
				_pill_label(main.m_to_screen(Vector2(s.pos[0], s.pos[1])) + Vector2(0, -GTUI.dp(24)), txt, Color("ffb627"))
	if main.overlays.density or main.overlays.risk:
		for a in main.telemetry.get("areas", []):
			if int(a.occupancy) <= 0:
				continue
			for d in sc.map.areas:
				if d.id == a.id:
					var c: Vector2 = main.m_to_screen(Vector2(d.rect[0] + d.rect[2] * 0.5, d.rect[1] + d.rect[3] * 0.5))
					_pill_label(c, "%d · %.1f/m²" % [int(a.occupancy), float(a.density)], LEVEL_COL.get(a.level, Color.WHITE))


func _wait_text(w) -> String:
	var s := int(round(float(w)))
	if s >= 600:
		return "10+ min"
	return "%d s" % s if s < 90 else "%d min" % int(round(s / 60.0))


## A small map label. Labels never overlap each other or the UI: one that would is skipped.
func _pill_label(center: Vector2, text: String, dot := Color(0, 0, 0, 0)) -> void:
	var w := GTUI.text_width(text, GTUI.FS_CAPTION, true) + GTUI.dp(GTUI.SP_M) * 2 + (GTUI.dp(10) if dot.a > 0 else 0.0)
	var h := GTUI.dp(20)
	var r := Rect2(center.x - w / 2, center.y - h / 2, w, h)
	for o in _labels:
		if (o as Rect2).grow(GTUI.dp(2)).intersects(r):
			return
	for o in _reserved:
		if (o as Rect2).intersects(r):
			return
	_labels.append(r)
	GTUI.box(self, r, Color(0.08, 0.1, 0.12, 0.82), GTUI.R_CONTROL)
	var tr := r.grow_individual(-GTUI.dp(GTUI.SP_M), 0, -GTUI.dp(GTUI.SP_M), 0)
	if dot.a > 0:
		draw_circle(Vector2(tr.position.x + GTUI.dp(3), r.get_center().y), GTUI.dp(3), dot)
		tr.position.x += GTUI.dp(10)
		tr.size.x -= GTUI.dp(10)
	GTUI.text_in(self, tr, text, GTUI.FS_CAPTION, Color.WHITE, -1, true)


# --- HUD

func _draw_hud() -> void:
	var vs := _vs()
	var m := GTUI.dp(GTUI.SP_S)
	var t: Dictionary = main.telemetry
	var pop: Dictionary = t.get("population", {})
	# top bar
	var bar := Rect2(m, m, vs.x - m * 2, top_bar_h() - m * 2)
	GTUI.panel(self, bar)
	_blockers.append(bar)
	var inner := bar.grow(-GTUI.dp(_bar_pad()))
	var tsec := float(t.get("time", 0.0))
	var limit := float(t.get("time_limit", 900.0))
	var meta := "%s · %s / %s" % [main.sc.get("title", ""), _mmss(tsec), "99:99"]
	var title_w := maxf(GTUI.text_width("Crowd Control", GTUI.FS_TITLE, true), GTUI.text_width(meta, GTUI.FS_CAPTION)) + GTUI.dp(GTUI.SP_S)
	meta = "%s · %s / %s" % [main.sc.get("title", ""), _mmss(tsec), _mmss(limit)]
	GTUI.text_in(self, Rect2(inner.position.x + GTUI.dp(4), inner.position.y, title_w, inner.size.y * 0.58), "Crowd Control", GTUI.FS_TITLE, GTUI.c("accent"), -1, true)
	GTUI.text_in(self, Rect2(inner.position.x + GTUI.dp(4), inner.position.y + inner.size.y * 0.56, title_w, inner.size.y * 0.42), meta, GTUI.FS_CAPTION, GTUI.c("text_muted"), -1)
	# controls on the right: pause, speeds, help
	var ih := GTUI.target()
	var x := inner.end.x
	var help_r := Rect2(x - ih, inner.position.y + (inner.size.y - ih) / 2, ih, ih)
	GTUI.icon_button(self, "help", help_r, "help")
	x = help_r.position.x - GTUI.dp(GTUI.SP_S)
	var seg_w := GTUI.dp(176)
	var seg_r := Rect2(x - seg_w, help_r.position.y, seg_w, ih)
	GTUI.segmented(self, "speed", seg_r, ["1×", "2×", "4×", "8×"], main.speed_idx, main.phase == main.Phase.PLAYING)
	x = seg_r.position.x - GTUI.dp(GTUI.SP_S)
	var pr := Rect2(x - ih, help_r.position.y, ih, ih)
	var playing: bool = main.phase == main.Phase.PLAYING and not main.paused
	GTUI.icon_button(self, "pause", pr, "", main.phase == main.Phase.PLAYING, not playing)
	_play_pause_glyph(pr, playing)
	# stats between title and controls
	var sx := inner.position.x + title_w + GTUI.dp(GTUI.SP_L)
	var room := pr.position.x - GTUI.dp(GTUI.SP_L) - sx
	var stats := [
		["Home", "%d/%d" % [int(pop.get("completed", 0)), int(pop.get("total", 0))]],
		["On site", str(int(pop.get("active", 0)))],
		["In stadium", str(int(pop.get("inside", 0)))],
		["Budget", "$%d" % int(float(t.get("budget", 0)) - float(t.get("spent", 0)))],
	]
	# each stat reserves room for its widest plausible value so nothing shifts or overlaps as numbers grow
	var widest := ["0000/0000", "0000", "0000", "$0000"]
	var cx := sx
	for i in stats.size():
		var w := maxf(GTUI.text_width(String(stats[i][0]).to_upper(), GTUI.FS_CAPTION, true), GTUI.text_width(widest[i], GTUI.FS_HEADING, true)) + GTUI.dp(GTUI.SP_L)
		if cx + w > sx + room:
			break
		GTUI.stat(self, Vector2(cx, inner.position.y - GTUI.dp(2)), stats[i][0], stats[i][1])
		cx += w
	_draw_objective()
	_draw_bottom_bar()
	if not main.selection.is_empty():
		_draw_side_panel()
	if main.debug:
		_draw_debug()


func _play_pause_glyph(r: Rect2, playing: bool) -> void:
	var c := r.get_center()
	var u := r.size.x * 0.16
	var ink: Color = GTUI.c("text") if playing else GTUI.c("on_accent")
	if playing:
		draw_rect(Rect2(c.x - u * 1.1, c.y - u * 1.3, u * 0.8, u * 2.6), ink)
		draw_rect(Rect2(c.x + u * 0.3, c.y - u * 1.3, u * 0.8, u * 2.6), ink)
	else:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-u, -u * 1.3), c + Vector2(u * 1.3, 0), c + Vector2(-u, u * 1.3)]), ink)


func _draw_objective() -> void:
	var t: Dictionary = main.telemetry
	var pop: Dictionary = t.get("population", {})
	var m := GTUI.dp(GTUI.SP_S)
	var w := GTUI.dp(OBJECTIVE_W)
	var r := Rect2(m, top_bar_h(), w, objective_h())
	GTUI.panel(self, r)
	_blockers.append(r)
	var x := r.position.x + GTUI.dp(GTUI.SP_M)
	var iw := r.size.x - GTUI.dp(GTUI.SP_M) * 2
	var y := r.position.y + GTUI.dp(GTUI.SP_S)
	var total := maxf(1.0, float(pop.get("total", 1)))
	var done := float(pop.get("completed", 0))
	var need := float(main.sc.objectives.clear_fraction)
	var ds := float(t.get("danger_seconds", 0.0))
	var dl := float(t.get("danger_limit", 90.0))
	var compact := _short()
	var label_h := GTUI.dp(16 if compact else 18)
	GTUI.text_in(self, Rect2(x, y, iw, label_h), ("Home %d%% of %d%%" % [int(done / total * 100), int(need * 100)]) if compact else ("Get %d%% home safely" % int(need * 100)), GTUI.FS_CAPTION if compact else GTUI.FS_LABEL, GTUI.c("text"), -1, true)
	y += label_h + GTUI.dp(2)
	_bar(Rect2(x, y, iw, GTUI.dp(6 if compact else 8)), done / total, GTUI.c("success"), need)
	y += GTUI.dp(10 if compact else 14)
	GTUI.text_in(self, Rect2(x, y, iw, label_h), "Dangerous crowding %d / %d s" % [int(ds), int(dl)], GTUI.FS_CAPTION if compact else GTUI.FS_LABEL, GTUI.c("danger") if ds > 0 else GTUI.c("text_muted"), -1, ds > 0)
	y += label_h + GTUI.dp(2)
	_bar(Rect2(x, y, iw, GTUI.dp(6 if compact else 8)), ds / dl, GTUI.c("danger"), -1.0)


func _bar(r: Rect2, frac: float, col: Color, marker: float) -> void:
	GTUI.box(self, r, GTUI.c("surface_high"), GTUI.R_CONTROL)
	if frac > 0.0:
		GTUI.box(self, Rect2(r.position, Vector2(maxf(r.size.y, r.size.x * clampf(frac, 0.0, 1.0)), r.size.y)), col, GTUI.R_CONTROL)
	if marker > 0.0:
		var mx := r.position.x + r.size.x * marker
		draw_line(Vector2(mx, r.position.y - GTUI.dp(3)), Vector2(mx, r.end.y + GTUI.dp(3)), GTUI.c("text"), GTUI.dp(2))


func _draw_bottom_bar() -> void:
	var vs := _vs()
	var m := GTUI.dp(GTUI.SP_S)
	var h := bottom_bar_h() - m * 2
	var bar := Rect2(m, vs.y - m - h, vs.x - m * 2, h)
	GTUI.panel(self, bar)
	_blockers.append(bar)
	var inner := bar.grow(-GTUI.dp(_bar_pad()))
	var ih := GTUI.target()
	var playing: bool = main.phase == main.Phase.PLAYING
	var tool_w := GTUI.dp(196)
	var row1 := Rect2(inner.position.x, inner.position.y, inner.size.x, ih)
	GTUI.segmented(self, "tool", Rect2(row1.position, Vector2(tool_w, ih)), ["Select", "Barrier"], 1 if main.tool == "barrier" else 0, playing)
	var chips_r: Rect2
	if _narrow():
		chips_r = Rect2(inner.position.x, inner.end.y - ih, inner.size.x, ih)
	else:
		chips_r = Rect2(row1.position.x + tool_w + GTUI.dp(GTUI.SP_L), row1.position.y, row1.size.x - tool_w - GTUI.dp(GTUI.SP_L), ih)
	var rects := GTUI.row(chips_r, OVERLAYS.size())
	for i in OVERLAYS.size():
		var key: String = OVERLAYS[i][0]
		var on: bool = main.color_mode == 1 if key == "mood" else bool(main.overlays.get(key, false))
		GTUI.chip(self, "ov:" + key, rects[i], OVERLAYS[i][1], on, playing)
	# barrier hint (inside the bar, so nothing moves)
	if main.tool == "barrier" and not _narrow():
		pass


# --- inspector panel

func _panel_rect(content_h: float) -> Rect2:
	var vs := _vs()
	var m := GTUI.dp(GTUI.SP_S)
	if _narrow():
		var h := minf(content_h, vs.y * 0.5)
		return Rect2(m, vs.y - bottom_bar_h() - h, vs.x - m * 2, h)
	var w := GTUI.dp(300)
	var top := top_bar_h()
	return Rect2(vs.x - m - w, top, w, minf(content_h, vs.y - top - bottom_bar_h()))


func _draw_side_panel() -> void:
	var sel: Dictionary = main.selection
	match sel.kind:
		"gate":
			_gate_panel(sel.id)
		"sign":
			_sign_panel(sel.id)
		"barrier":
			_barrier_panel(int(sel.id))
		"area":
			_area_panel()
		"person":
			_person_panel()


func _panel_head(r: Rect2, title: String) -> float:
	GTUI.panel(self, r, 1)
	_blockers.append(r)
	var p := GTUI.dp(GTUI.SP_M)
	var th := GTUI.target()
	var close := Rect2(r.end.x - p - th, r.position.y + GTUI.dp(GTUI.SP_S), th, th)
	GTUI.icon_button(self, "panel_close", close, "close")
	GTUI.text_in(self, Rect2(r.position.x + p, close.position.y, close.position.x - r.position.x - p * 2, th), title, GTUI.FS_TITLE, GTUI.c("text"), -1, true)
	return close.end.y + GTUI.dp(GTUI.SP_S)


func _line(r: Rect2, y: float, s: String, size := GTUI.FS_BODY, col := Color(0, 0, 0, 0), bold := false) -> float:
	var p := GTUI.dp(GTUI.SP_M)
	return GTUI.paragraph(self, r.position.x + p, y, r.size.x - p * 2, s, size, col if col.a > 0 else GTUI.c("text"), bold)


func _gate_panel(id: String) -> void:
	var def: Dictionary = {}
	for g in main.sc.gates:
		if g.id == id:
			def = g
	var t: Dictionary = {}
	for g in main.telemetry.get("gates", []):
		if g.id == id:
			t = g
	if def.is_empty():
		return
	var controllable: bool = def.get("controllable", false)
	var r := _panel_rect(GTUI.dp(268) if controllable else GTUI.dp(210))
	var y := _panel_head(r, def.name)
	var mode: String = t.get("mode", "open")
	var status := "Open, no limit"
	if mode == "metered":
		status = "Letting %d people/min through" % int(t.get("rate_pm", 0))
	elif mode == "closed":
		status = "Closed"
	y = _line(r, y, status, GTUI.FS_BODY, Color(0, 0, 0, 0), true)
	y = _line(r, y, "%d passed in the last minute" % int(t.get("flow_pm", 0)), GTUI.FS_LABEL, GTUI.c("text_muted"))
	if int(t.get("queue", 0)) > 0:
		y = _line(r, y, "%d waiting, about %s" % [int(t.queue), _wait_text(t.get("wait", 0))], GTUI.FS_LABEL, GTUI.c("text_muted"))
	elif bool(t.get("delayed", false)):
		y = _line(r, y, "Camera feed (updates every 30 s): about %s wait" % _wait_text(t.get("wait", 0)), GTUI.FS_LABEL, GTUI.c("text_muted"))
	y += GTUI.dp(GTUI.SP_S)
	if controllable:
		var sel := 0
		if mode == "metered":
			var lvl := float(t.get("level", 1.0))
			sel = 1
			for k in GATE_LEVELS.size():
				if absf(GATE_LEVELS[k] - lvl) < 0.01:
					sel = k + 1
		elif mode == "closed":
			sel = GATE_MODES.size() - 1
		var p := GTUI.dp(GTUI.SP_M)
		GTUI.segmented(self, "gate_mode", Rect2(r.position.x + p, y, r.size.x - p * 2, GTUI.target()), GATE_MODES, sel)
		y += GTUI.target() + GTUI.dp(GTUI.SP_S)
		_line(r, y, "Metering lets a share of the gate's capacity through and holds the rest in an orderly queue. Staff cost $%d/min while metering." % int(def.get("staff_cost_per_min", 0)), GTUI.FS_CAPTION, GTUI.c("text_muted"))
	else:
		if float(t.get("service_factor", 1.0)) < 1.0:
			y = _line(r, y, "Train delay: boarding at %d%%" % int(float(t.service_factor) * 100), GTUI.FS_LABEL, GTUI.c("danger"), true)
		_line(r, y, "Station staff run the fare gates. You control what reaches them.", GTUI.FS_CAPTION, GTUI.c("text_muted"))


func _sign_panel(id: String) -> void:
	var t: Dictionary = {}
	for s in main.telemetry.get("signs", []):
		if s.id == id:
			t = s
	if t.is_empty():
		return
	var modes: Array = t.get("modes", [])
	var r := _panel_rect(GTUI.dp(120) + modes.size() * GTUI.dp(GTUI.TARGET + GTUI.SP_S))
	var y := _panel_head(r, t.name)
	var p := GTUI.dp(GTUI.SP_M)
	for mo in modes:
		var current: bool = mo.id == t.mode
		GTUI.button(self, "sign_mode:" + mo.id, Rect2(r.position.x + p, y, r.size.x - p * 2, GTUI.target()), mo.label, "primary" if current else "secondary")
		y += GTUI.target() + GTUI.dp(GTUI.SP_S)
	_line(r, y, "Changing the message costs $%d. Read %d times." % [int(t.get("cost", 0)), int(t.get("reads", 0))], GTUI.FS_CAPTION, GTUI.c("text_muted"))


func _barrier_panel(id: int) -> void:
	var b: Dictionary = {}
	for x in main.telemetry.get("barriers", []):
		if int(x.id) == id:
			b = x
	if b.is_empty():
		return
	var r := _panel_rect(GTUI.dp(176))
	var y := _panel_head(r, "Temporary barrier")
	var len := Vector2(b.a.x, b.a.y).distance_to(Vector2(b.b.x, b.b.y))
	y = _line(r, y, "%d m of crowd barrier" % int(round(len)), GTUI.FS_BODY)
	y += GTUI.dp(GTUI.SP_S)
	var p := GTUI.dp(GTUI.SP_M)
	GTUI.button(self, "barrier_remove", Rect2(r.position.x + p, y, r.size.x - p * 2, GTUI.target()), "Remove barrier", "danger")
	y += GTUI.target() + GTUI.dp(GTUI.SP_S)
	var age := float(main.telemetry.get("time", 0.0)) - float(b.placed_at)
	var undo := float(main.sc.player_resources.get("undo_window", 10))
	_line(r, y, "Full refund if removed within %d s." % int(undo) if age <= undo else "Placed %s ago; removing it gives no refund." % _mmss(age), GTUI.FS_CAPTION, GTUI.c("text_muted"))


func _area_panel() -> void:
	var e: Dictionary = main.explain
	if e.is_empty() or e.has("error"):
		return
	var r := _panel_rect(GTUI.dp(320))
	var y := _panel_head(r, e.name)
	var lvl: String = e.get("level", "comfortable")
	var p := GTUI.dp(GTUI.SP_M)
	draw_circle(Vector2(r.position.x + p + GTUI.dp(5), y + GTUI.dp(11)), GTUI.dp(5), LEVEL_COL.get(lvl, Color.WHITE))
	GTUI.text_in(self, Rect2(r.position.x + p + GTUI.dp(16), y, r.size.x - p * 2 - GTUI.dp(16), GTUI.dp(22)), LEVEL_TEXT.get(lvl, lvl), GTUI.FS_BODY, GTUI.c("text"), -1, true)
	y += GTUI.dp(26)
	var speed_txt := "" if float(e.mean_speed) < 0.0 else " · moving %.1f m/s" % float(e.mean_speed)
	y = _line(r, y, "%d people · %.1f per m²%s" % [int(e.occupancy), float(e.density), speed_txt], GTUI.FS_LABEL, GTUI.c("text_muted"))
	y = _line(r, y, "Arriving %d/min · leaving %d/min" % [int(e.arrivals_pm), int(e.departures_pm)], GTUI.FS_LABEL, GTUI.c("text_muted"))
	for n in e.get("notes", []):
		y = _line(r, y, str(n), GTUI.FS_LABEL, GTUI.c("text"))
	if e.get("limiting") != null:
		y += GTUI.dp(GTUI.SP_XS)
		y = _line(r, y, "LIMITED BY", GTUI.FS_CAPTION, GTUI.c("text_muted"), true)
		y = _line(r, y, str(e.limiting), GTUI.FS_LABEL, GTUI.c("accent"))
	var recent: Array = e.get("recent", [])
	if not recent.is_empty():
		y += GTUI.dp(GTUI.SP_XS)
		y = _line(r, y, "RECENT", GTUI.FS_CAPTION, GTUI.c("text_muted"), true)
		for k in mini(recent.size(), 3):
			if y > r.end.y - GTUI.dp(24):
				break
			y = _line(r, y, "%s  %s" % [_mmss(float(recent[k].t)), recent[k].text], GTUI.FS_CAPTION, GTUI.c("text"))


func _person_panel() -> void:
	var w = main.inspected
	if not (w is Dictionary) or w.is_empty():
		return
	var r := _panel_rect(GTUI.dp(300))
	var y := _panel_head(r, "Person #%d" % int(w.id))
	for k in ["profile", "destination", "state", "group"]:
		y = _line(r, y, "%s: %s" % [k.capitalize(), str(w.get(k, ""))], GTUI.FS_LABEL)
	y = _line(r, y, "Route: " + " → ".join(PackedStringArray(w.get("route", []))), GTUI.FS_LABEL)
	y = _line(r, y, "Speed %.2f / %.2f m/s · waited %d s (patience %d)" % [float(w.speed), float(w.desired_speed), int(w.wait), int(w.patience)], GTUI.FS_CAPTION, GTUI.c("text_muted"))
	y = _line(r, y, "Familiarity %.2f · sign %.2f · herding %.2f · mood %d" % [float(w.familiarity), float(w.sign_compliance), float(w.crowd_following), int(w.satisfaction)], GTUI.FS_CAPTION, GTUI.c("text_muted"))
	_line(r, y, "Sign advice: %s" % str(w.get("sign_advice")), GTUI.FS_CAPTION, GTUI.c("text_muted"))


# --- debug

func _draw_debug() -> void:
	var t: Dictionary = main.telemetry
	var vs := _vs()
	var w := GTUI.dp(300)
	var h := GTUI.dp(250)
	var r := Rect2(GTUI.dp(GTUI.SP_S), vs.y - bottom_bar_h() - h, w, h)
	GTUI.panel(self, r, 1)
	_blockers.append(r)
	var y := r.position.y + GTUI.dp(GTUI.SP_S)
	var lines := [
		"Diagnostics (F3) · backend %s" % main.adapter.backend,
		"FPS %d · step %.2f ms/tick · render %.2f ms" % [Engine.get_frames_per_second(), main._step_ms, main._render_ms],
		"Tick %d · seed %s · checksum %s" % [int(t.get("tick", 0)), str(main.info.get("seed", "")), main.adapter.checksum().substr(0, 8)],
		"Rendered %d people · fields pending %d" % [main.world.count, int(t.get("fields_pending", 0))],
	]
	for f in t.get("fidelity", []):
		lines.append("%s: %d (%s)" % [f.region, int(f.count), f.model])
	for l in lines:
		y = _line(r, y, l, GTUI.FS_CAPTION, GTUI.c("text"))
	y += GTUI.dp(GTUI.SP_XS)
	var p := GTUI.dp(GTUI.SP_M)
	var row := GTUI.row(Rect2(r.position.x + p, r.end.y - GTUI.target() - p, r.size.x - p * 2, GTUI.target()), 3)
	GTUI.chip(self, "dbg_perfect", row[0], "True data", main.perfect_info)
	GTUI.button(self, "dbg_step", row[1], "Step", "secondary", main.paused)
	GTUI.button(self, "dbg_export", row[2], "Export")


# --- dialogs

func _draw_title() -> void:
	var vs := _vs()
	GTUI.scrim(self, 0.6)
	_modal = true
	var card := GTUI.modal_rect(self, 560, GTUI.dp(330))
	GTUI.box(self, card, GTUI.c("surface"), GTUI.R_OVERLAY, GTUI.c("border"))
	var p := GTUI.dp(GTUI.SP_XL)
	var x := card.position.x + p
	var w := card.size.x - p * 2
	var y := card.position.y + p
	GTUI.text_in(self, Rect2(x, y, w, GTUI.dp(44)), "Crowd Control", GTUI.FS_DISPLAY, GTUI.c("accent"), -1, true)
	y += GTUI.dp(48)
	y = GTUI.paragraph(self, x, y, w, "You don't control people. You control the system they move through.", GTUI.FS_BODY, GTUI.c("text"))
	y += GTUI.dp(GTUI.SP_M)
	var sc_r := Rect2(x, y, w, GTUI.dp(84))
	GTUI.panel(self, sc_r, 1)
	GTUI.text_in(self, Rect2(x + GTUI.dp(GTUI.SP_M), y + GTUI.dp(GTUI.SP_S), w - GTUI.dp(GTUI.SP_M) * 2, GTUI.dp(24)), main.sc.get("title", ""), GTUI.FS_TITLE, GTUI.c("text"), -1, true)
	GTUI.paragraph(self, x + GTUI.dp(GTUI.SP_M), y + GTUI.dp(34), w - GTUI.dp(GTUI.SP_M) * 2, "1,000 fans after the match · 2 gates, 2 signs, barriers · a train delay is likely", GTUI.FS_LABEL, GTUI.c("text_muted"))
	var btn := Rect2(x, card.end.y - p - GTUI.target(), w, GTUI.target())
	var cols := GTUI.row(btn, 3, [1.3, 1, 1])
	GTUI.chip(self, "title_big", cols[0], "Stress test: 5,000", big_crowd)
	if big_crowd:
		GTUI.paragraph(self, x, btn.position.y - GTUI.dp(GTUI.SP_L + 18), w, "Stress test: performance only, not balanced for a fair score.", GTUI.FS_CAPTION, GTUI.c("text_muted"))
	GTUI.button(self, "help", cols[1], "How to play")
	GTUI.button(self, "title_start", cols[2], "Start", "primary")
	if main.help_open:
		_draw_help()


func _draw_briefing() -> void:
	_modal = true
	var sc: Dictionary = main.sc
	var w_dp := 520.0
	var content_w := minf(GTUI.dp(w_dp), _vs().x - GTUI.dp(GTUI.SP_L) * 2) - GTUI.dp(GTUI.SP_XL) * 2
	var items := [
		"Get %d%% of people to the trains or the car park by %s." % [int(sc.objectives.clear_fraction * 100), _mmss(sc.objectives.time_limit)],
		"%d seconds of dangerous crowding ends the operation." % int(sc.failure_conditions.max_danger_seconds),
		"Your score counts journey times, the longest wait, congestion, money spent and how fans feel. You need %d points (one star) to pass." % int(sc.scoring_rules.stars[0]),
	]
	var h := GTUI.paragraph(null, 0, 0, content_w, sc.get("briefing", ""), GTUI.FS_BODY, Color.WHITE, false, false) + GTUI.dp(GTUI.SP_M)
	for it in items:
		h += GTUI.paragraph(null, 0, 0, content_w - GTUI.dp(16), it, GTUI.FS_LABEL, Color.WHITE, false, false) + GTUI.dp(GTUI.SP_XS)
	var card := GTUI.modal_rect(self, w_dp, GTUI.modal_height(h))
	var c := GTUI.modal(self, card, sc.get("title", ""))
	var y := GTUI.paragraph(self, c.position.x, c.position.y, c.size.x, sc.get("briefing", ""), GTUI.FS_BODY, GTUI.c("text"))
	y += GTUI.dp(GTUI.SP_M)
	for it in items:
		draw_circle(Vector2(c.position.x + GTUI.dp(4), y + GTUI.dp(10)), GTUI.dp(3), GTUI.c("accent"))
		y = GTUI.paragraph(self, c.position.x + GTUI.dp(16), y, c.size.x - GTUI.dp(16), it, GTUI.FS_LABEL, GTUI.c("text_muted")) + GTUI.dp(GTUI.SP_XS)
	var br := GTUI.modal_buttons_rect(c)
	var cols := GTUI.row(br, 2)
	GTUI.button(self, "help", cols[0], "How to play")
	GTUI.button(self, "brief_start", cols[1], "Start operation", "primary")
	if main.help_open:
		_draw_help()


func _draw_help() -> void:
	_modal = true
	var lines := [
		"People choose their own routes. You change gates, barriers and signs, and they react.",
		"Gates: tap one, then Open, Meter (hold people back) or Close.",
		"Signs: point train passengers to a gate, or show live waits. Not everyone reads them.",
		"Barriers: pick the Barrier tool and drag inside a yellow zone (pan with two fingers meanwhile).",
		"Station halls are watched by cameras that refresh every 30 s: what you see there may be out of date.",
		"Tap an area to see what is limiting it. Overlays show density, risk, flow and routes.",
		"Drag or use WASD to pan; scroll, pinch or +/- to zoom; Space pauses; 1–4 set the speed.",
	]
	var cw := minf(GTUI.dp(520), _vs().x - GTUI.dp(GTUI.SP_L) * 2) - GTUI.dp(GTUI.SP_XL) * 2
	var h := 0.0
	for l in lines:
		h += GTUI.paragraph(null, 0, 0, cw - GTUI.dp(16), l, GTUI.FS_LABEL, Color.WHITE, false, false) + GTUI.dp(GTUI.SP_XS)
	var card := GTUI.modal_rect(self, 520, GTUI.modal_height(h))
	var c := GTUI.modal(self, card, "How to play", "help_close")
	var y := c.position.y
	for l in lines:
		draw_circle(Vector2(c.position.x + GTUI.dp(4), y + GTUI.dp(10)), GTUI.dp(3), GTUI.c("accent"))
		y = GTUI.paragraph(self, c.position.x + GTUI.dp(16), y, c.size.x - GTUI.dp(16), l, GTUI.FS_LABEL, GTUI.c("text")) + GTUI.dp(GTUI.SP_XS)
	GTUI.button(self, "help_close", GTUI.modal_buttons_rect(c), "Got it", "primary")


func _draw_tutorial() -> void:
	var vs := _vs()
	var w := minf(GTUI.dp(460), vs.x - GTUI.dp(GTUI.SP_L) * 2)
	var p := GTUI.dp(GTUI.SP_M)
	var text: String = TUTORIAL[clampi(main.tutorial_step, 0, TUTORIAL.size() - 1)]
	var th := GTUI.paragraph(null, 0, 0, w - p * 2, text, GTUI.FS_BODY, Color.WHITE, false, false)
	var h := th + GTUI.target() + p * 3 + GTUI.dp(18)
	var r := Rect2((vs.x - w) / 2, vs.y - bottom_bar_h() - h - GTUI.dp(GTUI.SP_S), w, h)
	GTUI.panel(self, r, 1)
	_blockers.append(r)
	GTUI.text_in(self, Rect2(r.position.x + p, r.position.y + p, w - p * 2, GTUI.dp(16)), "TIP %d OF %d" % [main.tutorial_step + 1, TUTORIAL.size()], GTUI.FS_CAPTION, GTUI.c("accent"), -1, true)
	GTUI.paragraph(self, r.position.x + p, r.position.y + p + GTUI.dp(18), w - p * 2, text, GTUI.FS_BODY, GTUI.c("text"))
	var cols := GTUI.row(Rect2(r.position.x + p, r.end.y - p - GTUI.target(), w - p * 2, GTUI.target()), 2)
	GTUI.button(self, "tut_skip", cols[0], "Skip tips", "quiet")
	GTUI.button(self, "tut_next", cols[1], "Next" if main.tutorial_step < TUTORIAL.size() - 1 else "Start", "primary")


func _draw_results() -> void:
	_modal = true
	var rep: Dictionary = main.report
	var vs := _vs()
	var narrow := _narrow()
	var outcome: String = rep.get("outcome", "won")
	var title: String = {"won": "Operation complete", "failed_score": "Not good enough", "failed_danger": "Operation halted"}.get(outcome, "Time ran out")
	var card := GTUI.modal_rect(self, 720 if not narrow else 420, vs.y - GTUI.dp(GTUI.SP_L) * 2)
	var c := GTUI.modal(self, card, title)
	var left := Rect2(c.position, Vector2(c.size.x if narrow else c.size.x * 0.46, c.size.y - GTUI.target() - GTUI.dp(GTUI.SP_M)))
	var y := left.position.y
	var stars := int(rep.get("stars", 0))
	GTUI.text_in(self, Rect2(left.position.x, y, left.size.x, GTUI.dp(44)), str(int(rep.get("score", 0))), GTUI.FS_DISPLAY, GTUI.c("text"), -1, true)
	_stars(Vector2(left.position.x + GTUI.text_width(str(int(rep.get("score", 0))), GTUI.FS_DISPLAY, true) + GTUI.dp(GTUI.SP_L), y + GTUI.dp(22)), stars)
	y += GTUI.dp(48)
	var summary := "%d of %d home · average journey %s · longest wait %s" % [int(rep.get("completed", 0)), int(rep.get("total", 0)), _mmss(float(rep.get("avg_journey", 0))), _mmss(float(rep.get("max_wait", 0)))]
	y = GTUI.paragraph(self, left.position.x, y, left.size.x, summary, GTUI.FS_LABEL, GTUI.c("text_muted")) + GTUI.dp(GTUI.SP_S)
	var verdict := _verdict(rep)
	if verdict != "":
		y = GTUI.paragraph(self, left.position.x, y, left.size.x, verdict, GTUI.FS_LABEL, GTUI.c("success") if outcome == "won" else GTUI.c("danger")) + GTUI.dp(GTUI.SP_M)
	var losses: Array = rep.get("top_losses", [])
	if not losses.is_empty():
		y = GTUI.paragraph(self, left.position.x, y, left.size.x, "BIGGEST LOSSES", GTUI.FS_CAPTION, GTUI.c("text_muted"), true)
		for l in losses:
			if y > left.end.y - GTUI.dp(20):
				break
			y = GTUI.paragraph(self, left.position.x, y, left.size.x, str(l), GTUI.FS_LABEL, GTUI.c("text")) + GTUI.dp(GTUI.SP_XS)
	if not narrow:
		var right := Rect2(c.position.x + c.size.x * 0.52, c.position.y, c.size.x * 0.48, left.size.y)
		var ry := right.position.y
		var rh := GTUI.dp(24)
		for comp in rep.get("components", []):
			if ry > right.end.y - rh:
				break
			var pts := float(comp.points)
			GTUI.text_in(self, Rect2(right.position.x, ry, right.size.x * 0.5, rh), comp.label, GTUI.FS_LABEL, GTUI.c("text"), -1)
			GTUI.text_in(self, Rect2(right.position.x + right.size.x * 0.5, ry, right.size.x * 0.25, rh), str(comp.value), GTUI.FS_LABEL, GTUI.c("text_muted"), 1)
			GTUI.text_in(self, Rect2(right.position.x + right.size.x * 0.75, ry, right.size.x * 0.25, rh), ("%+d" % int(round(pts))) if absf(pts) >= 0.5 else "0", GTUI.FS_LABEL, GTUI.c("success") if pts > 0.5 else (GTUI.c("danger") if pts < -0.5 else GTUI.c("text_muted")), 1, true)
			ry += rh
	var cols := GTUI.row(GTUI.modal_buttons_rect(c), 2)
	GTUI.button(self, "res_menu", cols[0], "Menu")
	GTUI.button(self, "res_retry", cols[1], "Try again", "primary")


## One sentence on whether the run passed and what was needed.
func _verdict(rep: Dictionary) -> String:
	var th: Array = rep.get("star_thresholds", [600, 800, 950])
	var one := int(th[0]) if th.size() > 0 else 600
	match str(rep.get("outcome", "won")):
		"failed_score":
			return "Everyone got out, but too slowly or unsafely to earn a star. You need %d points to pass." % one
		"failed_danger":
			return "Stopped: people were crushed in dangerous crowding for too long."
		"failed_timeout":
			return "Time ran out with people still on site."
		"won":
			var stars := int(rep.get("stars", 0))
			if stars >= 3:
				return "Passed with full marks."
			if stars < th.size():
				return "Passed. %d points for the next star." % int(th[stars])
	return ""


func _stars(pos: Vector2, n: int) -> void:
	for i in 3:
		var c := pos + Vector2(i * GTUI.dp(26), 0)
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2 + k * PI / 5
			var rad := GTUI.dp(10) if k % 2 == 0 else GTUI.dp(4.2)
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
		draw_colored_polygon(pts, GTUI.c("accent") if i < n else GTUI.c("surface_high"))  # gt:art


func _draw_error() -> void:
	_modal = true
	var cw := minf(GTUI.dp(460), _vs().x - GTUI.dp(GTUI.SP_L) * 2) - GTUI.dp(GTUI.SP_XL) * 2
	var h := GTUI.paragraph(null, 0, 0, cw, main.error_text, GTUI.FS_BODY, Color.WHITE, false, false)
	var card := GTUI.modal_rect(self, 460, GTUI.modal_height(h))
	var c := GTUI.modal(self, card, "Something went wrong")
	GTUI.paragraph(self, c.position.x, c.position.y, c.size.x, main.error_text, GTUI.FS_BODY, GTUI.c("text"))
	GTUI.button(self, "err_retry", GTUI.modal_buttons_rect(c), "Reload", "primary")


func _draw_toasts() -> void:
	if _modal:
		return
	var lh := GTUI.line_height(GTUI.FS_LABEL)
	var pad := GTUI.dp(GTUI.SP_M + 12)
	for tl in _toast_layout():
		var r: Rect2 = tl.rect
		var lines: Array = tl.lines
		var col: Color = tl.col
		var h := r.size.y
		GTUI.box(self, r, GTUI.c("text"), GTUI.R_CONTROL)
		draw_rect(Rect2(r.position.x + GTUI.dp(GTUI.SP_M), r.position.y + GTUI.dp(GTUI.SP_M), GTUI.dp(6), h - GTUI.dp(GTUI.SP_M) * 2), col)
		var ty: float = r.position.y + (h - lines.size() * lh) / 2
		for l in lines:
			GTUI.text_in(self, Rect2(r.position.x + pad, ty, r.size.x - pad - GTUI.dp(GTUI.SP_M), lh), l, GTUI.FS_LABEL, GTUI.c("bg"), -1, true)
			ty += lh


## Where this frame's toasts go (map labels avoid these rects too).
func _toast_layout() -> Array:
	var out := []
	if main == null or main.phase != main.Phase.PLAYING:
		return out
	var vs := _vs()
	var m := GTUI.dp(GTUI.SP_S)
	# Wide screens: stacked under the objective panel, over the stadium (the one part of the map
	# that never needs watching). Narrow screens: full width under the objective panel.
	var left := m
	var right := m + GTUI.dp(OBJECTIVE_W)
	if _narrow():
		right = vs.x - m
	var y := top_bar_h() + objective_h() + m
	var pad := GTUI.dp(GTUI.SP_M + 12)
	for tst in main.toasts:
		var msg: String = tst.text
		var max_w := right - left
		var w := minf(GTUI.text_width(msg, GTUI.FS_LABEL, true) + pad + GTUI.dp(GTUI.SP_M), max_w)
		var lines := GTUI.wrap_lines(msg, GTUI.FS_LABEL, w - pad - GTUI.dp(GTUI.SP_M), true)
		var lh := GTUI.line_height(GTUI.FS_LABEL)
		var h := maxf(GTUI.target(), lines.size() * lh + GTUI.dp(GTUI.SP_S) * 2)
		var r := Rect2(left + (max_w - w) / 2, y, w, h)
		var col := GTUI.c("danger") if tst.kind in ["danger", "error"] else (Color("ff922b") if tst.kind in ["warning", "incident"] else GTUI.c("success") if tst.kind == "incident_end" else GTUI.c("surface_high"))
		out.append({"rect": r, "lines": lines, "col": col})
		y += h + GTUI.dp(GTUI.SP_XS)
	return out


static func _mmss(s: float) -> String:
	var t := int(maxf(s, 0.0))
	return "%d:%02d" % [t / 60, t % 60]
