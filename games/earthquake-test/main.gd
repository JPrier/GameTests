extends Node2D
## Earthquake Test — a daily physics game.
## Everyone gets the same building site (anchors + budget) and the same earthquake each day.
## Build a truss from wood and steel beams, then run the quake. Score = height still standing
## (highest joint attached to an anchor) once the shaking stops. Three tries a day; best counts.

const Sim = preload("res://quake_sim.gd")
const Quake = preload("res://quake.gd")

const GW := 14                        # build grid width (m)
const GH := 18                        # build grid height (m)
const MAX_LEN := 2.3                  # longest beam (m)
const MAX_TRIES := 3
const EPOCH := "2026-10-02"           # quake #1
const DEFAULT_URL := "https://jprier.github.io/GameTests/earthquake-test/"
const FAST := 8.0                     # skip = fast-forward multiplier
const VIEW_PAD := 0.7                 # metres of margin around the grid
const VIEW_GROUND := 1.4              # metres of ground shown below y = 0
const VIS_EXAGGERATE := 3.0           # drawn motion multiplier at peak shaking (visual only)
const VIS_MAX_EXTRA := 0.6            # cap on the extra drawn sway (m)

enum Phase { BUILD, RUN, RESULT, FINAL }

const C_BG := Color("1b1917")
const C_PANEL := Color("25221f")
const C_SKY := Color("221f1c")
const C_GROUND := Color("5b4a3a")
const C_GROUND_HI := Color("7a6450")
const C_DOT := Color(1, 1, 1, 0.09)
const C_DOT_REACH := Color("ffd27a")
const C_ANCHOR := Color("9aa3ad")
const C_WOOD := Color("d79b5a")
const C_WOOD_DK := Color("8f5f30")
const C_STEEL := Color("8fb3d9")
const C_STEEL_DK := Color("4b6a8c")
const C_JOINT := Color("f1e6d6")
const C_INK := Color("f4ece2")
const C_MUTED := Color("ab9f92")
const C_ACCENT := Color("ffb347")
const C_DANGER := Color("ff5e4d")
const C_OK := Color("7fd68a")
const C_BTN := Color("3a3530")
const C_BTN_PRIMARY := Color("d9652b")
const C_GHOST := Color(1, 1, 1, 0.10)

# site + quake
var date := ""
var today := ""
var quake_no := 1
var budget := 50
var anchors: Array = []               # Vector2i on y = 0
var quake = null

# player
var design: Array = []                # [{a: Vector2i, b: Vector2i, m: int}]
var history: Array = []               # undo stack of design copies
var build_mat := 0                     # Sim.Mat
var selected := Vector2i(-1, -1)      # tapped joint waiting for a second tap
var tries: Array = []                 # [{score, built, broken, beams, design, end_x, end_y, end_ok}]
var finished := false
var phase: int = Phase.BUILD
var target_score := 0                 # cm, from a shared link (?s=)
var base_url := DEFAULT_URL

# simulation
var sim = null
var sim_acc := 0.0
var fast := false
var show_try := -1                    # which try's end state to draw in RESULT/FINAL
var flashes: Array = []               # [{pos: Vector2, t: float}] beam snap sparks

# ui
var buttons: Array = []
var head_rect := Rect2()
var seis_rect := Rect2()
var board_rect := Rect2()
var panel_rect := Rect2()
var text_rect := Rect2()
var ppm := 30.0                       # pixels per metre
var vis_k := 1.0                      # current visual exaggeration
var origin := Vector2()               # screen position of world (0, 0)
var drag_from := Vector2i(-1, -1)
var drag_to := Vector2i(-1, -1)
var press_pos := Vector2()
var dragging := false
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""
var anim_t := 0.0
var dev_open := false
var dev_taps := 0
var dev_last_tap := -10.0
var tut_open := false
var help_rect := Rect2()
var title_rect := Rect2()             # tap 5x quickly to open the dev menu
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(C_BG)
	_add_key_action("run", [KEY_ENTER, KEY_SPACE])
	_add_key_action("undo", [KEY_BACKSPACE, KEY_Z])
	_add_key_action("build_mat", [KEY_TAB, KEY_M])
	today = Time.get_date_string_from_system(false)
	var want := today
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	if _valid_date(String(url.get("d", ""))):
		want = String(url.d)
	dev_open = String(url.get("dev", "")) == "1"
	var s := String(url.get("s", ""))
	target_score = int(s) if s.is_valid_int() else 0
	load_day(want)
	if not dev_open and not tutorial_seen():
		tut_open = true


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------------ daily site

func _valid_date(d: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return false
	return d >= EPOCH and d <= today


func day_number(d: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(EPOCH + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return int(round((b - a) / 86400.0)) + 1


## Build the site and quake for a date. Deterministic: same date -> same day everywhere.
func generate(d: String) -> void:
	date = d
	quake_no = day_number(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("site:" + d).hash()
	budget = rng.randi_range(8, 13) * 5
	anchors.clear()
	var count := rng.randi_range(2, 3)
	var tries_left := 200
	while anchors.size() < count and tries_left > 0:
		tries_left -= 1
		var x := rng.randi_range(2, GW - 2)
		var ok := true
		for a in anchors:
			if absi(a.x - x) < 2:
				ok = false
		if ok:
			anchors.append(Vector2i(x, 0))
	anchors.sort_custom(func(a, b): return a.x < b.x)
	quake = Quake.new()
	quake.make(d)


func load_day(d: String) -> void:
	generate(d)
	design.clear()
	history.clear()
	tries.clear()
	finished = false
	selected = Vector2i(-1, -1)
	sim = null
	_load_state()
	if finished or tries.size() >= MAX_TRIES:
		_enter_final()
	else:
		phase = Phase.BUILD


# ------------------------------------------------------------------ building

func design_cost(d: Array = design) -> float:
	var c := 0.0
	for b in d:
		c += beam_len(b) * float(Sim.MATS[int(b.m)].cost)
	return c


func beam_len(b: Dictionary) -> float:
	return Vector2(b.a).distance_to(Vector2(b.b))


func money_left() -> float:
	return budget - design_cost()


func is_anchor(p: Vector2i) -> bool:
	return anchors.has(p)


## A point you can build from: an anchor or an existing joint.
func is_node(p: Vector2i) -> bool:
	if is_anchor(p):
		return true
	for b in design:
		if b.a == p or b.b == p:
			return true
	return false


func beam_index(a: Vector2i, b: Vector2i) -> int:
	for i in design.size():
		var d: Dictionary = design[i]
		if (d.a == a and d.b == b) or (d.a == b and d.b == a):
			return i
	return -1


func in_grid(p: Vector2i) -> bool:
	return p.x >= 0 and p.x <= GW and p.y >= 0 and p.y <= GH


## "" when the beam can be built, otherwise the reason it can't.
func check_beam(a: Vector2i, b: Vector2i, mat: int = build_mat) -> String:
	if a == b:
		return "same"
	if not in_grid(a) or not in_grid(b):
		return "Off the site"
	if not is_node(a) and not is_node(b):
		return "Start from an anchor or a joint"
	for p in [a, b]:
		if p.y == 0 and not is_anchor(p):
			return "Only anchors can touch the ground"
	if Vector2(a).distance_to(Vector2(b)) > MAX_LEN + 1e-6:
		return "Too long — max %.1f m" % MAX_LEN
	if beam_index(a, b) >= 0:
		return "Already built"
	var c := Vector2(a).distance_to(Vector2(b)) * float(Sim.MATS[mat].cost)
	if c > money_left() + 1e-6:
		return "Not enough budget ($%d needed)" % ceili(c)
	return ""


func add_beam(a: Vector2i, b: Vector2i, mat: int = build_mat) -> bool:
	if phase == Phase.RESULT:
		back_to_build()
	if phase != Phase.BUILD:
		return false
	var why := check_beam(a, b, mat)
	if why != "":
		if why != "same":
			_toast(why)
		return false
	_push_history()
	design.append({"a": a, "b": b, "m": mat})
	_save_state()
	return true


func remove_beam(i: int) -> void:
	if phase != Phase.BUILD or i < 0 or i >= design.size():
		return
	_push_history()
	design.remove_at(i)
	_prune()
	_save_state()


## Drop beams no longer connected to an anchor.
func _prune() -> void:
	var reach := {}
	for a in anchors:
		reach[a] = true
	var changed := true
	while changed:
		changed = false
		for b in design:
			if reach.has(b.a) != reach.has(b.b):
				reach[b.a] = true
				reach[b.b] = true
				changed = true
	var kept: Array = []
	for b in design:
		if reach.has(b.a):
			kept.append(b)
	design = kept


func _push_history() -> void:
	history.append(design.duplicate(true))
	if history.size() > 200:
		history.pop_front()


func undo() -> void:
	if phase == Phase.BUILD and not history.is_empty():
		design = history.pop_back()
		selected = Vector2i(-1, -1)
		_save_state()


func clear_design() -> void:
	if phase == Phase.BUILD and not design.is_empty():
		_push_history()
		design.clear()
		selected = Vector2i(-1, -1)
		_save_state()


func set_mat(m: int) -> void:
	build_mat = clampi(m, 0, Sim.MATS.size() - 1)


func built_height(d: Array = design) -> float:
	var h := 0
	for b in d:
		h = maxi(h, maxi(b.a.y, b.b.y))
	return h


# ------------------------------------------------------------------ quake run

func run() -> void:
	if phase != Phase.BUILD or design.is_empty():
		return
	selected = Vector2i(-1, -1)
	sim = Sim.new()
	sim.setup(design, anchors, quake)
	sim_acc = 0.0
	fast = false
	flashes.clear()
	phase = Phase.RUN


func skip() -> void:
	if phase == Phase.RUN:
		fast = true


## Run the whole quake now (tests / agents).
func run_instant() -> Dictionary:
	run()
	if phase != Phase.RUN:
		return {}
	sim.run_to_end()
	_finish_try()
	return tries[-1]


func _advance(delta: float) -> void:
	var before: int = sim.broken_count()
	if fast:
		var t0 := Time.get_ticks_usec()
		while not sim.done() and Time.get_ticks_usec() - t0 < 14000:
			sim.step()
	else:
		sim_acc += delta
		var n := 0
		while sim_acc >= Sim.STEP and not sim.done() and n < 8:
			sim_acc -= Sim.STEP
			sim.step()
			n += 1
		sim_acc = minf(sim_acc, Sim.STEP * 2)
	if sim.broken_count() > before:
		for i in sim.m:
			if sim.b_ok[i] == 0 and sim.broken_at[i] > sim.t - Sim.STEP * 8 and sim.broken_at[i] <= sim.t:
				var mid := (_vis(sim.ba[i]) + _vis(sim.bb[i])) * 0.5
				flashes.append({"pos": mid, "t": 0.5})
	if sim.done():
		_finish_try()


func _finish_try() -> void:
	var r := {
		"score": int(round(sim.standing_height() * 100.0)),
		"built": int(round(built_height() * 100.0)),
		"broken": sim.broken_count(),
		"beams": sim.m,
		"design": _design_to_json(design),
		"end_x": Array(sim.px), "end_y": Array(sim.py), "end_ok": Array(sim.b_ok),
		"end_gx": sim.gx, "end_gy": sim.gy,
	}
	tries.append(r)
	show_try = tries.size() - 1
	_save_state()
	if tries.size() >= MAX_TRIES:
		_enter_final()
	else:
		phase = Phase.RESULT


func back_to_build() -> void:
	if phase == Phase.RESULT:
		sim = null
		phase = Phase.BUILD


func finish() -> void:
	if not tries.is_empty():
		finished = true
		_save_state()
		_enter_final()


func _enter_final() -> void:
	phase = Phase.FINAL
	sim = null
	show_try = best_index()


func best_index() -> int:
	var bi := -1
	for i in tries.size():
		if bi < 0 or int(tries[i].score) > int(tries[bi].score):
			bi = i
	return bi


func best_score() -> int:
	var i := best_index()
	return int(tries[i].score) if i >= 0 else 0


static func fmt_m(cm: int) -> String:
	return "%.2f m" % (cm / 100.0)


# ------------------------------------------------------------------ saving (user:// is IndexedDB on the web)

func _design_to_json(d: Array) -> Array:
	var out: Array = []
	for b in d:
		out.append([b.a.x, b.a.y, b.b.x, b.b.y, b.m])
	return out


func _design_from_json(arr) -> Array:
	var out: Array = []
	if not arr is Array:
		return out
	for e in arr:
		if e is Array and e.size() == 5:
			out.append({"a": Vector2i(int(e[0]), int(e[1])), "b": Vector2i(int(e[2]), int(e[3])), "m": int(e[4])})
	return out


func _save_path() -> String:
	return "user://quake_%s.json" % date


func _save_state() -> void:
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"tries": tries, "design": _design_to_json(design), "finished": finished}))


func _load_state() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if not data is Dictionary:
		return
	for t in data.get("tries", []):
		if not t is Dictionary:
			continue
		tries.append({
			"score": int(t.get("score", 0)), "built": int(t.get("built", 0)),
			"broken": int(t.get("broken", 0)), "beams": int(t.get("beams", 0)),
			"design": t.get("design", []),
			"end_x": t.get("end_x", []), "end_y": t.get("end_y", []), "end_ok": t.get("end_ok", []),
			"end_gx": float(t.get("end_gx", 0.0)), "end_gy": float(t.get("end_gy", 0.0)),
		})
	design = _design_from_json(data.get("design", []))
	finished = bool(data.get("finished", false))


func wipe_save() -> void:
	_wipe_file(_save_path())
	_flush_storage()


func _wipe_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("{}")
		f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _flush_storage() -> void:
	var f := FileAccess.open("user://.sync", FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


# ------------------------------------------------------------------ sharing

func share_link() -> String:
	return "%s?d=%s&s=%d" % [base_url, date, best_score()]


func share_text() -> String:
	var parts := PackedStringArray()
	for t in tries:
		parts.append("%.1f" % (int(t.score) / 100.0))
	var bi := best_index()
	var lines := PackedStringArray()
	lines.append("Earthquake Test #%d 🏗️ %s" % [quake_no, quake.describe() if quake else ""])
	if bi >= 0:
		var b: Dictionary = tries[bi]
		var bar := ""
		var built := maxi(int(b.built), 1)
		var filled := clampi(int(round(10.0 * int(b.score) / built)), 0, 10)
		for k in 10:
			bar += "🟧" if k < filled else "⬛"
		lines.append("Still standing: %s of %s" % [fmt_m(int(b.score)), fmt_m(int(b.built))])
		lines.append(bar)
	lines.append("Tries (m): " + " → ".join(parts))
	if target_score > 0:
		if best_score() > target_score:
			lines.append("Beat the %s I was sent 💥" % fmt_m(target_score))
		else:
			lines.append("Couldn't beat %s — can you?" % fmt_m(target_score))
	lines.append("Same quake, your build: " + share_link())
	return "\n".join(lines)


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__eqShare='pending';
			var done=function(r){if(window.__eqShare==='pending'){window.__eqShare=r;}};
			var ask=function(){try{window.prompt('Copy your result:',t);done('prompted');}catch(e){done('failed');}};
			var legacy=function(){
				var ok=false;
				try{
					var ta=document.createElement('textarea');
					ta.value=t;ta.setAttribute('readonly','');
					ta.style.cssText='position:fixed;top:0;left:0;opacity:0;';
					document.body.appendChild(ta);ta.select();
					ok=document.execCommand('copy');
					document.body.removeChild(ta);
					var c=document.querySelector('canvas');if(c){c.focus();}
				}catch(e){ok=false;}
				return ok;
			};
			var copy=function(){
				if(legacy()){done('copied');return;}
				if(navigator.clipboard&&navigator.clipboard.writeText){
					setTimeout(function(){if(window.__eqShare==='pending'){ask();}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},ask);
				}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__eqCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__eqCopyNext=true;done('share_failed');}
				});
			}else{window.__eqCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Result copied — paste it anywhere")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__eqShare||''", true)
	if typeof(r) != TYPE_STRING or r == "pending" or r == "":
		return
	share_pending = false
	match r:
		"copied": _toast("Result + link copied — paste it anywhere")
		"shared": _toast("Shared!")
		"prompted", "cancelled": pass
		"share_failed": _toast("Couldn't share — tap again to copy")
		_: _toast("Couldn't share — try again")


func play_today() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.href=%s" % JSON.stringify(base_url), true)
	else:
		target_score = 0
		load_day(today)


func _read_url() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var r = JavaScriptBridge.eval("""(function(){var p=new URLSearchParams(location.search);
		return JSON.stringify({d:p.get('d')||'',s:p.get('s')||'',dev:p.get('dev')||'',base:location.origin+location.pathname});})()""", true)
	if typeof(r) != TYPE_STRING:
		return {}
	var d = JSON.parse_string(r)
	return d if d is Dictionary else {}


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 2.6


# ------------------------------------------------------------------ frame + input

func _process(delta: float) -> void:
	anim_t += delta
	if toast_t > 0.0:
		toast_t -= delta
	if share_pending:
		_poll_share()
	if phase == Phase.RUN and sim != null:
		_advance(delta)
	for f in flashes:
		f.t -= delta
	flashes = flashes.filter(func(f): return f.t > 0.0)
	if tut_open:
		if Input.is_action_just_pressed("run"):
			close_tutorial()
	elif not dev_open:
		if Input.is_action_just_pressed("run"):
			match phase:
				Phase.BUILD: run()
				Phase.RUN: skip()
				Phase.RESULT: back_to_build()
		if Input.is_action_just_pressed("undo"):
			undo()
		if Input.is_action_just_pressed("build_mat"):
			set_mat(1 - build_mat)
	_layout()
	queue_redraw()


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			if dev_open or tut_open:
				_press_button(p)
				return
			if help_rect.grow(10).has_point(p):
				tut_open = true
				return
			if title_rect.grow(8).has_point(p):
				_dev_tap()
				return
			if _press_button(p):
				return
			if not board_rect.has_point(p):
				return
			if phase == Phase.RESULT:
				back_to_build()
				return
			if phase != Phase.BUILD:
				return
			press_pos = p
			dragging = false
			var g := snap(p)
			drag_to = Vector2i(-1, -1)
			if g.x >= 0 and is_node(g):
				drag_from = g
			else:
				drag_from = Vector2i(-1, -1)
		else:
			if phase == Phase.BUILD and not dev_open and not tut_open and board_rect.has_point(p):
				_release(p)
			drag_from = Vector2i(-1, -1)
			drag_to = Vector2i(-1, -1)
			dragging = false
	elif ev is InputEventMouseMotion and drag_from.x >= 0:
		var p: Vector2 = make_input_local(ev).position
		if p.distance_to(press_pos) > ppm * 0.45:
			dragging = true
		if dragging:
			var g := snap(p)
			drag_to = g if g.x >= 0 and g != drag_from else Vector2i(-1, -1)


## Pointer released on the board: finish a drag, or handle a tap.
func _release(p: Vector2) -> void:
	if dragging and drag_from.x >= 0:
		if drag_to.x >= 0:
			add_beam(drag_from, drag_to)
		selected = Vector2i(-1, -1)
		return
	tap_world(snap(p), screen_to_world(p))


## Tap logic (also used by tests): g is the snapped grid point (or -1,-1), w the exact world point.
func tap_world(g: Vector2i, w: Vector2) -> void:
	if phase == Phase.RESULT:
		back_to_build()
	if phase != Phase.BUILD:
		return
	if selected.x >= 0:
		if g == selected:
			selected = Vector2i(-1, -1)
			return
		if g.x >= 0:
			var why := check_beam(selected, g)
			if why == "":
				add_beam(selected, g)
				selected = g
				return
			if is_node(g):
				selected = g
				return
			_toast(why)
			return
	if g.x >= 0 and is_node(g):
		selected = g
		return
	var bi := beam_at(w)
	if bi >= 0:
		remove_beam(bi)
		return
	if g.x >= 0:
		_toast("Start at an anchor or a joint")


func beam_at(w: Vector2) -> int:
	var best := -1
	var best_d := 0.28
	for i in design.size():
		var b: Dictionary = design[i]
		var a := Vector2(b.a)
		var c := Vector2(b.b)
		var q := Geometry2D.get_closest_point_to_segment(w, a, c)
		var d := q.distance_to(w)
		if d < best_d and q.distance_to(a) > 0.2 and q.distance_to(c) > 0.2:
			best_d = d
			best = i
	return best


func screen_to_world(p: Vector2) -> Vector2:
	return Vector2((p.x - origin.x) / ppm, (origin.y - p.y) / ppm)


func world_to_screen(w: Vector2) -> Vector2:
	return Vector2(origin.x + w.x * ppm, origin.y - w.y * ppm)


## Nearest grid point to a screen position, or (-1, -1) when too far from any.
func snap(p: Vector2) -> Vector2i:
	var w := screen_to_world(p)
	var g := Vector2i(roundi(w.x), roundi(w.y))
	if not in_grid(g) or Vector2(g).distance_to(w) > 0.48:
		return Vector2i(-1, -1)
	return g


## One tap on the title; five within 0.6 s of each other opens the dev menu.
func _dev_tap() -> void:
	dev_taps = dev_taps + 1 if anim_t - dev_last_tap < 0.6 else 1
	dev_last_tap = anim_t
	if dev_taps >= 5:
		dev_taps = 0
		dev_open = true
		selected = Vector2i(-1, -1)


func dev_reset_today() -> void:
	wipe_save()
	load_day(date)
	dev_open = false
	_toast("Dev: today's progress reset")


func dev_reset_all() -> void:
	var n := 0
	var dir := DirAccess.open("user://")
	if dir:
		for f in dir.get_files():
			if f.begins_with("quake_") and f.ends_with(".json"):
				_wipe_file("user://" + f)
				n += 1
	_wipe_file(TUT_FLAG)
	_flush_storage()
	load_day(date)
	dev_open = false
	_toast("Dev: cleared %d saved day(s) + tutorial" % n)


func _press_button(p: Vector2) -> bool:
	for b in buttons:
		if b.rect.has_point(p):
			if b.enabled:
				match b.id:
					"run": run()
					"undo": undo()
					"clear": clear_design()
					"wood": set_mat(Sim.Mat.WOOD)
					"steel": set_mat(Sim.Mat.STEEL)
					"skip": skip()
					"again": back_to_build()
					"finish": finish()
					"share": share()
					"today": play_today()
					"dev_today": dev_reset_today()
					"dev_all": dev_reset_all()
					"dev_close": dev_open = false
					"tut_close": close_tutorial()
			return true
	return false


# ------------------------------------------------------------------ tutorial

const TUT_FLAG := "user://quake_tutorial_seen"


func close_tutorial() -> void:
	tut_open = false
	var f := FileAccess.open(TUT_FLAG, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()


func tutorial_seen() -> bool:
	return FileAccess.file_exists(TUT_FLAG)


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	var m := 16.0
	var portrait := vs.y >= vs.x * 1.05
	var view_w := GW + VIEW_PAD * 2
	var view_h := GH + VIEW_PAD + VIEW_GROUND
	if portrait:
		head_rect = Rect2(m, m, vs.x - m * 2, 92)
		seis_rect = Rect2(m, head_rect.end.y + 4, vs.x - m * 2, 64)
		var panel_h := 236.0 if phase == Phase.BUILD else 200.0
		var avail := Rect2(m, seis_rect.end.y + 10, vs.x - m * 2, vs.y - seis_rect.end.y - 10 - panel_h - m)
		ppm = minf(avail.size.x / view_w, avail.size.y / view_h)
		var bs := Vector2(view_w, view_h) * ppm
		board_rect = Rect2(avail.position + Vector2((avail.size.x - bs.x) / 2.0, 0), bs)
		panel_rect = Rect2(m, board_rect.end.y + 12, vs.x - m * 2, vs.y - board_rect.end.y - 12 - m)
	else:
		var avail_h := vs.y - m * 2
		ppm = minf(avail_h / view_h, (vs.x * 0.56) / view_w)
		var bs := Vector2(view_w, view_h) * ppm
		board_rect = Rect2(m, (vs.y - bs.y) / 2.0, bs.x, bs.y)
		var px := board_rect.end.x + 24
		var pw := vs.x - px - m
		head_rect = Rect2(px, m, pw, 92)
		seis_rect = Rect2(px, head_rect.end.y + 4, pw, 72)
		panel_rect = Rect2(px, seis_rect.end.y + 16, pw, vs.y - seis_rect.end.y - 16 - m)
	origin = board_rect.position + Vector2(VIEW_PAD * ppm, (GH + VIEW_PAD) * ppm)
	_build_buttons()


func _build_buttons() -> void:
	buttons.clear()
	var vs := get_viewport_rect().size
	if tut_open and not dev_open:
		var w := minf(vs.x - 32, 640.0)
		var h := minf(vs.y - 32, 860.0)
		var r := Rect2((vs.x - w) / 2.0, (vs.y - h) / 2.0, w, h)
		buttons.append({"id": "tut_close", "label": "Let's build", "primary": true, "enabled": true,
			"rect": Rect2(r.position.x + 24, r.end.y - 24 - 64, r.size.x - 48, 64)})
		return
	if dev_open:
		var w := minf(vs.x - 80, 420.0)
		var x := (vs.x - w) / 2.0
		var y := vs.y / 2.0 - 110
		for l in [["dev_today", "Reset today", true], ["dev_all", "Reset all days", true], ["dev_close", "Close", false]]:
			buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": true, "rect": Rect2(x, y, w, 64)})
			y += 78
		return
	var bh := 62.0
	var gap := 10.0
	var rows: Array = []
	match phase:
		Phase.BUILD:
			rows.append([["wood", "Wood $1/m", build_mat == Sim.Mat.WOOD, true], ["steel", "Steel $3/m", build_mat == Sim.Mat.STEEL, true]])
			rows.append([["run", "Start quake", true, not design.is_empty()], ["undo", "Undo", false, not history.is_empty()], ["clear", "Clear", false, not design.is_empty()]])
		Phase.RUN:
			rows.append([["skip", "Fast-forward" if not fast else "Fast-forwarding…", false, not fast]])
		Phase.RESULT:
			rows.append([["again", "Rebuild (%d left)" % (MAX_TRIES - tries.size()), true, true], ["finish", "Finish", false, true]])
		Phase.FINAL:
			var row := [["share", "Share result", true, true]]
			if date != today:
				row.append(["today", "Play today's", false, true])
			rows.append(row)
	var y := panel_rect.end.y - bh * rows.size() - gap * (rows.size() - 1)
	text_rect = Rect2(panel_rect.position, Vector2(panel_rect.size.x, y - panel_rect.position.y - 8))
	for row in rows:
		var n: int = row.size()
		var free := panel_rect.size.x - gap * (n - 1)
		var x := panel_rect.position.x
		for i in n:
			var l: Array = row[i]
			var w := free / n
			if n == 3:
				w = free * (0.46 if i == 0 else 0.27)
			elif n == 2 and phase != Phase.BUILD:
				w = free * (0.62 if i == 0 else 0.38)
			var kind := "toggle" if l[0] in ["wood", "steel"] else "button"
			buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": l[3], "rect": Rect2(x, y, w, bh), "kind": kind})
			x += w + gap
		y += bh + gap


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if buttons.is_empty():
		_layout()
	_draw_header()
	_draw_seismo()
	_draw_board()
	_draw_panel()
	_draw_help_button()
	if tut_open and not dev_open:
		_draw_tutorial()
	if dev_open:
		var vs := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72))
		_text_c("Dev menu", Vector2(vs.x / 2.0, vs.y / 2.0 - 172), 32, C_ACCENT)
		_text_c("Reset saved progress for #%d (%s)" % [quake_no, date], Vector2(vs.x / 2.0, vs.y / 2.0 - 136), 20, C_MUTED)
	for b in buttons:
		_draw_button(b)
	if toast_t > 0.0 and toast != "":
		var a := clampf(toast_t * 2.0, 0.0, 1.0)
		var vs := get_viewport_rect().size
		var tw := font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 40
		var ty := board_rect.position.y + 12
		var r := Rect2((vs.x - tw) / 2.0, ty, tw, 46)
		_box(r, Color(0.08, 0.07, 0.06, 0.94 * a), 23, Color(C_ACCENT, 0.6 * a))
		_text_c(toast, r.get_center() + Vector2(0, 8), 22, Color(C_INK, a))


func _draw_header() -> void:
	var r := head_rect
	var title_sz := _title_size()
	draw_string(font, r.position + Vector2(0, 46), "Earthquake Test", HORIZONTAL_ALIGNMENT_LEFT, -1, title_sz, C_INK)
	draw_string(font, r.position + Vector2(0, 80), "#%d · %s" % [quake_no, date], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_MUTED)
	var st := _stat()
	var label: String = st[0]
	var big: String = st[1]
	var col := C_ACCENT
	label = label.to_upper()
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(font, Vector2(r.end.x - lw, r.position.y + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_MUTED)
	var bw := font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	draw_string(font, Vector2(r.end.x - bw, r.position.y + 56), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, col)
	if phase == Phase.BUILD:
		var sub := "of $%d" % budget
		var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(font, Vector2(r.end.x - sw, r.position.y + 82), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_MUTED)


## Today's seismogram, with a playhead while the quake runs.
func _draw_seismo() -> void:
	var r := seis_rect
	_box(r, C_PANEL, 10)
	var label: String = "TODAY'S QUAKE  " + quake.describe()
	draw_string(font, r.position + Vector2(12, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_MUTED)
	var tr := Rect2(r.position + Vector2(10, 26), r.size - Vector2(20, 32))
	var mid := tr.get_center().y
	draw_line(Vector2(tr.position.x, mid), Vector2(tr.end.x, mid), Color(1, 1, 1, 0.08), 1.0)
	var tr_data: PackedFloat32Array = quake.trace
	var n := tr_data.size()
	if n < 2:
		return
	var cols := int(tr.size.x / 2.0)
	var head_frac := -1.0
	if phase == Phase.RUN and sim != null:
		head_frac = clampf(sim.quake_time() / quake.duration, 0.0, 1.0)
	elif phase == Phase.RESULT or phase == Phase.FINAL:
		head_frac = 1.0
	for c in cols:
		var i0 := int(float(c) / cols * n)
		var i1 := maxi(i0 + 1, int(float(c + 1) / cols * n))
		var lo := 0.0
		var hi := 0.0
		for i in range(i0, mini(i1, n)):
			lo = minf(lo, tr_data[i])
			hi = maxf(hi, tr_data[i])
		var x := tr.position.x + c * 2.0 + 1.0
		var frac := float(c) / cols
		var col := Color(C_ACCENT, 0.9) if head_frac >= 0.0 and frac <= head_frac else Color(C_MUTED, 0.55)
		draw_line(Vector2(x, mid - hi * tr.size.y * 0.5), Vector2(x, mid - lo * tr.size.y * 0.5 + 1), col, 1.6)
	if phase == Phase.RUN and sim != null:
		var qt: float = sim.quake_time()
		var hx := tr.position.x + head_frac * tr.size.x
		draw_line(Vector2(hx, tr.position.y), Vector2(hx, tr.end.y), C_INK, 2.0)
		var status := "settling…" if qt < 0.0 else ("%.1fs" % minf(qt, quake.duration) if qt < quake.duration else "aftershock check…")
		var sw := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, Vector2(r.end.x - sw - 12, r.position.y + 20), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_INK)


func _draw_board() -> void:
	var r := board_rect
	_box(r, C_SKY, 12)
	# ground (moves with the quake)
	var g := Vector2.ZERO
	vis_k = 1.0
	if phase == Phase.RUN and sim != null:
		vis_k = 1.0 + (VIS_EXAGGERATE - 1.0) * quake.intensity(sim.quake_time())
		g = Vector2(sim.gx, sim.gy) * vis_k
	elif (phase == Phase.RESULT or phase == Phase.FINAL) and show_try >= 0:
		g = Vector2(float(tries[show_try].end_gx), float(tries[show_try].end_gy))
	var gy0 := world_to_screen(Vector2(0, g.y)).y
	var ground := Rect2(r.position.x, gy0, r.size.x, r.end.y - gy0)
	_box(ground, C_GROUND, 0)
	draw_line(Vector2(r.position.x, gy0), Vector2(r.end.x, gy0), C_GROUND_HI, 3.0)
	# soil texture ticks that slide with the ground
	var off := fposmod(g.x * ppm, ppm)
	var k := 0
	var x := r.position.x - ppm + off
	while x < r.end.x:
		var yy := gy0 + 10.0 + float(k % 3) * 9.0
		if yy < r.end.y - 4:
			draw_line(Vector2(x, yy), Vector2(x + ppm * 0.3, yy), Color(0, 0, 0, 0.18), 2.0)
		x += ppm * 0.5
		k += 1
	# grid dots + reach preview while building
	if phase == Phase.BUILD:
		var focus := selected if selected.x >= 0 else drag_from
		for gy in range(1, GH + 1):
			for gx2 in range(0, GW + 1):
				var p := Vector2i(gx2, gy)
				var s := world_to_screen(Vector2(p))
				if focus.x >= 0 and Vector2(p).distance_to(Vector2(focus)) <= MAX_LEN + 1e-6 and p != focus:
					var ok := check_beam(focus, p) == ""
					draw_circle(s, maxf(2.5, ppm * 0.09), Color(C_DOT_REACH, 0.9 if ok else 0.25))
				else:
					draw_circle(s, maxf(1.5, ppm * 0.05), C_DOT)
		# height ruler
		for hy in range(2, GH + 1, 2):
			var s := world_to_screen(Vector2(-0.45, hy))
			_text_r("%d" % hy, s + Vector2(0, 5), 13, Color(C_MUTED, 0.6))
	# ghost of the built design after a run
	if (phase == Phase.RESULT or phase == Phase.FINAL) and show_try >= 0:
		for b in _design_from_json(tries[show_try].design):
			draw_line(world_to_screen(Vector2(b.a)), world_to_screen(Vector2(b.b)), C_GHOST, maxf(2.0, ppm * 0.1))
	# anchors
	for a in anchors:
		var s := world_to_screen(Vector2(a) + Vector2(g.x, g.y))
		var w := maxf(10.0, ppm * 0.42)
		draw_rect(Rect2(s.x - w, s.y, w * 2, maxf(8.0, ppm * 0.3)), Color("6f747a"))
		draw_colored_polygon(PackedVector2Array([s + Vector2(-w * 0.75, 2), s + Vector2(w * 0.75, 2), s + Vector2(0, -w * 0.9)]), C_ANCHOR)
	# structure
	match phase:
		Phase.BUILD:
			_draw_design()
		Phase.RUN:
			_draw_sim()
		Phase.RESULT, Phase.FINAL:
			_draw_end_state()
	# height marker
	if phase != Phase.BUILD:
		var h := 0.0
		if phase == Phase.RUN and sim != null:
			h = sim.standing_height()
		elif show_try >= 0:
			h = int(tries[show_try].score) / 100.0
		if h > 0.05:
			var y := world_to_screen(Vector2(0, h + g.y)).y
			_dashed(Vector2(r.position.x + 6, y), Vector2(r.end.x - 6, y), Color(C_OK, 0.8))
			_text_r("%.2f m" % h, Vector2(r.end.x - 10, y - 8), 18, C_OK)
	if target_score > 0:
		var y := world_to_screen(Vector2(0, target_score / 100.0)).y
		_dashed(Vector2(r.position.x + 6, y), Vector2(r.end.x - 6, y), Color(C_ACCENT, 0.55))
		draw_string(font, Vector2(r.position.x + 12, y - 8), "to beat %s" % fmt_m(target_score), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(C_ACCENT, 0.85))
	for f in flashes:
		var s := world_to_screen(f.pos)
		var a: float = f.t / 0.5
		draw_circle(s, ppm * (0.5 - f.t * 0.6) + 4.0, Color(C_DANGER, 0.5 * a))
		draw_circle(s, 4.0, Color(1, 1, 0.8, a))


func _beam_width(mat: int) -> float:
	return maxf(3.0, ppm * (0.17 if mat == Sim.Mat.WOOD else 0.13))


func _draw_beam(a: Vector2, b: Vector2, mat: int, tint := Color(0, 0, 0, 0), alpha := 1.0) -> void:
	var w := _beam_width(mat)
	var base: Color = C_WOOD if mat == Sim.Mat.WOOD else C_STEEL
	var edge: Color = C_WOOD_DK if mat == Sim.Mat.WOOD else C_STEEL_DK
	if tint.a > 0.0:
		base = base.lerp(Color(tint, 1.0), tint.a)
	draw_line(a, b, Color(edge, alpha), w + 3.0)
	draw_line(a, b, Color(base, alpha), w)


func _draw_joint(s: Vector2, anchor := false) -> void:
	var r := maxf(3.5, ppm * 0.12)
	draw_circle(s, r + 1.5, Color(0, 0, 0, 0.5))
	draw_circle(s, r, C_ANCHOR if anchor else C_JOINT)


func _draw_design() -> void:
	var joints := {}
	for b in design:
		_draw_beam(world_to_screen(Vector2(b.a)), world_to_screen(Vector2(b.b)), int(b.m))
		joints[b.a] = true
		joints[b.b] = true
	if drag_from.x >= 0 and drag_to.x >= 0:
		var ok := check_beam(drag_from, drag_to) == ""
		_draw_beam(world_to_screen(Vector2(drag_from)), world_to_screen(Vector2(drag_to)), build_mat, Color(C_DANGER, 0.0 if ok else 0.8), 0.6)
	for p in joints:
		_draw_joint(world_to_screen(Vector2(p)), is_anchor(p))
	for a in anchors:
		_draw_joint(world_to_screen(Vector2(a)), true)
	if selected.x >= 0:
		var s := world_to_screen(Vector2(selected))
		draw_arc(s, ppm * 0.32 + 2.0 * sin(anim_t * 6.0), 0, TAU, 28, C_DOT_REACH, 3.0)


func _stress_tint(ratio: float) -> Color:
	if ratio < 0.35:
		return Color(0, 0, 0, 0)
	var u := clampf((ratio - 0.35) / 0.65, 0.0, 1.0)
	return Color(Color("ffd84a").lerp(C_DANGER, u), 0.35 + 0.6 * u)


## Where to draw joint j while the quake runs. Ground motion and the structure's sway are
## exaggerated (up to VIS_EXAGGERATE x, easing back to 1x as the shaking dies) so a few
## centimetres of real movement read on a phone screen. Physics and scoring are untouched.
func _vis(j: int) -> Vector2:
	var rest := Vector2(sim.rest_x[j], sim.rest_y[j])
	var g := Vector2(sim.gx, sim.gy)
	var d := Vector2(sim.px[j], sim.py[j]) - rest - g
	var extra := minf(d.length() * (vis_k - 1.0), VIS_MAX_EXTRA)
	var v := rest + g * vis_k + d + d.normalized() * extra
	v.y = maxf(v.y, g.y * vis_k)
	return v


func _draw_sim() -> void:
	for i in sim.m:
		if sim.b_ok[i] == 0:
			continue
		var a := world_to_screen(_vis(sim.ba[i]))
		var b := world_to_screen(_vis(sim.bb[i]))
		var ratio: float = absf(sim.b_force[i]) / sim.b_strength[i]
		_draw_beam(a, b, sim.b_mat[i], _stress_tint(ratio))
	for j in sim.n:
		_draw_joint(world_to_screen(_vis(j)), sim.anchor[j] == 1)


func _draw_end_state() -> void:
	if show_try < 0:
		return
	var t: Dictionary = tries[show_try]
	var d := _design_from_json(t.design)
	var ex: Array = t.end_x
	var ey: Array = t.end_y
	var ok: Array = t.end_ok
	# joint order matches Sim.setup: first appearance in the design
	var index := {}
	var pts: Array = []
	for b in d:
		for key in [b.a, b.b]:
			if not index.has(key):
				index[key] = pts.size()
				pts.append(key)
	if ex.size() != pts.size() or ok.size() != d.size():
		return
	for i in d.size():
		if int(ok[i]) == 0:
			continue
		var a := world_to_screen(Vector2(float(ex[index[d[i].a]]), float(ey[index[d[i].a]])))
		var b := world_to_screen(Vector2(float(ex[index[d[i].b]]), float(ey[index[d[i].b]])))
		_draw_beam(a, b, int(d[i].m))
	# broken beams: show their stubs lying where their joints ended up, faded
	for i in d.size():
		if int(ok[i]) == 1:
			continue
		var a := world_to_screen(Vector2(float(ex[index[d[i].a]]), float(ey[index[d[i].a]])))
		var b := world_to_screen(Vector2(float(ex[index[d[i].b]]), float(ey[index[d[i].b]])))
		var mid := (a + b) * 0.5
		draw_line(a, a.lerp(mid, 0.8), Color(C_DANGER, 0.45), 2.0)
		draw_line(b, b.lerp(mid, 0.8), Color(C_DANGER, 0.45), 2.0)
	for p in pts:
		var j: int = index[p]
		_draw_joint(world_to_screen(Vector2(float(ex[j]), float(ey[j]))), is_anchor(p))


func _draw_panel() -> void:
	var r := text_rect
	var lines: Array = []
	match phase:
		Phase.BUILD:
			var hint := "Drag from an anchor or a joint to build a beam. Tap a beam to remove it."
			if selected.x >= 0:
				hint = "Tap a lit dot to build from the selected joint. Tap it again to deselect."
			lines.append([hint, 21, C_INK])
			lines.append(["Built %d m · %d beams · try %d of %d%s" % [int(built_height()), design.size(), tries.size() + 1, MAX_TRIES,
				("  ·  " + _tries_line()) if not tries.is_empty() else ""], 19, C_MUTED])
		Phase.RUN:
			var qt: float = sim.quake_time()
			var msg := "Settling under its own weight…"
			if qt >= 0.0 and qt < quake.duration:
				msg = "SHAKING — %d%% intensity" % int(round(quake.intensity(qt) * 100))
			elif qt >= quake.duration:
				msg = "The ground is still. Checking what's left…"
			lines.append([msg, 26, C_INK if qt < 0.0 else C_ACCENT])
			lines.append(["%d of %d beams snapped" % [sim.broken_count(), sim.m], 21, C_MUTED])
		Phase.RESULT:
			var t: Dictionary = tries[-1]
			lines.append(["Still standing: %s" % fmt_m(int(t.score)), 30, C_OK if int(t.score) > 0 else C_DANGER])
			lines.append(["Built %s · %d of %d beams snapped" % [fmt_m(int(t.built)), int(t.broken), int(t.beams)], 20, C_MUTED])
			lines.append([_tries_line() + "  ·  tap the site to rebuild", 19, C_MUTED])
		Phase.FINAL:
			var bi := best_index()
			if bi >= 0:
				var b: Dictionary = tries[bi]
				lines.append(["Best: %s still standing" % fmt_m(int(b.score)), 30, C_OK])
				lines.append(["%s  ·  built %s, %d/%d beams snapped" % [_tries_line(), fmt_m(int(b.built)), int(b.broken), int(b.beams)], 19, C_MUTED])
			if date == today:
				lines.append(["Next quake in " + _countdown(), 19, C_MUTED])
			else:
				lines.append(["Today's quake is waiting.", 19, C_MUTED])
	if target_score > 0 and phase != Phase.RUN:
		var beat := best_score() > target_score
		lines.append([("You beat %s!" if beat else "Height to beat: %s") % fmt_m(target_score), 21, C_ACCENT])
	var y := r.position.y + 2
	for l in lines:
		var sz: int = l[1]
		var h := font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x, sz).y
		if y + h > r.end.y + 4:
			break
		draw_multiline_string(font, Vector2(r.position.x, y + font.get_ascent(sz)), l[0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x, sz, -1, l[2])
		y += h + 6.0


func _tries_line() -> String:
	var parts := PackedStringArray()
	for t in tries:
		parts.append("%.1f" % (int(t.score) / 100.0))
	return "Tries (m): " + ", ".join(parts)


func _countdown() -> String:
	var t := Time.get_time_dict_from_system()
	var left := 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	return "%dh %02dm" % [left / 3600, (left % 3600) / 60]


func _draw_button(b: Dictionary) -> void:
	var toggle: bool = b.get("kind", "") == "toggle"
	var col: Color = C_BTN_PRIMARY if b.primary else C_BTN
	if toggle:
		var mc: Color = C_WOOD if b.id == "wood" else C_STEEL
		col = Color(mc, 0.95) if b.primary else C_BTN
	if not b.enabled:
		col = Color(col, 0.35)
	_box(b.rect, col, 14, Color(C_INK, 0.7) if toggle and b.primary else Color(0, 0, 0, 0))
	var sz := 26
	while sz > 15 and font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > b.rect.size.x - 20:
		sz -= 2
	var ink := C_INK if b.enabled else Color(C_INK, 0.4)
	if toggle and b.primary:
		ink = Color("1b1917")
	_text_c(b.label, b.rect.get_center() + Vector2(0, sz * 0.36), sz, ink)


func _draw_help_button() -> void:
	var title_sz := _title_size()
	var tw := font.get_string_size("Earthquake Test", HORIZONTAL_ALIGNMENT_LEFT, -1, title_sz).x
	title_rect = Rect2(head_rect.position, Vector2(tw, 56))
	help_rect = Rect2(head_rect.position + Vector2(tw + 14, 14), Vector2(38, 38))
	draw_circle(help_rect.get_center(), 18, C_BTN)
	draw_arc(help_rect.get_center(), 18, 0, TAU, 32, Color(C_INK, 0.35), 2.0)
	_text_c("?", help_rect.get_center() + Vector2(0, 9), 24, C_INK)


## [label, big value] for the header's right-hand stat.
func _stat() -> Array:
	match phase:
		Phase.RUN:
			return ["standing", "%.1f m" % sim.standing_height()]
		Phase.RESULT:
			return ["standing", "%.2f m" % (int(tries[-1].score) / 100.0)]
		Phase.FINAL:
			return ["best", "%.2f m" % (best_score() / 100.0)]
	return ["budget left", "$%d" % floori(money_left() + 1e-6)]


## Title font size that leaves room for the "?" button and the big stat on the right.
func _title_size() -> int:
	var stat_w := font.get_string_size("18.00 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	var room := head_rect.size.x - stat_w - 16.0 - 56.0
	var sz := 44
	while sz > 24 and font.get_string_size("Earthquake Test", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > room:
		sz -= 2
	return sz


func _draw_tutorial() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.02, 0.02, 0.84))
	var w := minf(vs.x - 32, 640.0)
	var h := minf(vs.y - 32, 860.0)
	var r := Rect2((vs.x - w) / 2.0, (vs.y - h) / 2.0, w, h)
	_box(r, Color("2a2622"), 18, Color(C_ACCENT, 0.4))
	var x := r.position.x + 28
	var tw := r.size.x - 56
	var y := r.position.y + 26
	var bottom := r.end.y - 24 - 64 - 16
	y = _para("How Earthquake Test works", x, y, tw, 32, C_INK) + 14
	var rows := [
		["anchor", "Everyone gets the same site: the same grey anchors and the same budget."],
		["beam", "Drag from an anchor or joint to a nearby dot to build a beam (max %.1f m). Or tap a joint, then tap dots." % MAX_LEN],
		["steel", "Wood is cheap and light. Steel costs 3× but is ~5× stronger."],
		["quake", "Start the quake: today's exact seismogram hits your build. Overloaded beams snap."],
		["height", "Score = height still standing (attached to an anchor) when the shaking stops."],
		["tries", "%d tries a day — best counts. Share your result; the link opens the same quake." % MAX_TRIES],
	]
	var icon := 30.0
	for row in rows:
		var ir := Rect2(x, y + 2, icon, icon)
		match row[0]:
			"anchor":
				draw_colored_polygon(PackedVector2Array([ir.position + Vector2(3, 26), ir.position + Vector2(27, 26), ir.position + Vector2(15, 4)]), C_ANCHOR)
			"beam":
				_draw_beam(ir.position + Vector2(3, 26), ir.position + Vector2(27, 4), Sim.Mat.WOOD)
			"steel":
				_draw_beam(ir.position + Vector2(3, 26), ir.position + Vector2(27, 4), Sim.Mat.STEEL)
			"quake":
				var pts := PackedVector2Array()
				for k in 9:
					pts.append(ir.position + Vector2(k * 3.4, 15 + (12 if k % 2 == 0 else -12) * (1.0 - absf(k - 4) / 5.0)))
				draw_polyline(pts, C_ACCENT, 2.5)
			"height":
				_dashed(ir.position + Vector2(0, 8), ir.position + Vector2(30, 8), C_OK)
				draw_line(ir.position + Vector2(15, 28), ir.position + Vector2(15, 10), C_OK, 3.0)
			"tries":
				_text_c(str(MAX_TRIES), ir.get_center() + Vector2(0, 9), 26, C_ACCENT)
		var ny := _para(row[1], x + icon + 16, y, tw - icon - 16, 21, C_INK)
		y = maxf(ny, y + icon + 4) + 14
		if y > bottom:
			break
	if y + 60 < bottom:
		_para("Watch the seismograph: bigger, faster shaking finds tall, floppy towers. Triangles are your friend.", x, y + 6, tw, 18, C_MUTED)


func _para(text: String, x: float, y: float, w: float, size: int, col: Color) -> float:
	draw_multiline_string(font, Vector2(x, y + font.get_ascent(size)), text, HORIZONTAL_ALIGNMENT_LEFT, w, size, -1, col)
	return y + font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, size).y


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 0.001)
	var s := 0.0
	while s < len:
		draw_line(a + dir * s, a + dir * minf(s + 8.0, len), col, 2.0)
		s += 14.0


func _box(r: Rect2, col: Color, radius: float, border := Color(0, 0, 0, 0)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	draw_style_box(sb, r)


func _text_c(s: String, center: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w / 2.0, center.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_r(s: String, right: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(right.x - w, right.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ------------------------------------------------------------------ agent hooks

func get_agent_state() -> Dictionary:
	return {
		"phase": Phase.keys()[phase], "date": date, "quake_no": quake_no, "budget": budget,
		"money_left": money_left(), "anchors": anchors.map(func(a): return a.x),
		"beams": design.size(), "built_height": built_height(), "build_mat": build_mat,
		"selected": [selected.x, selected.y],
		"quake": quake.describe() if quake else "",
		"sim_t": sim.t if sim != null else -1.0,
		"standing": sim.standing_height() if sim != null else -1.0,
		"broken": sim.broken_count() if sim != null else 0,
		"tries": tries.map(func(t): return t.score), "best": best_score(),
		"target": target_score, "tutorial": tut_open,
		"share": share_text() if not tries.is_empty() else "",
	}
