extends Node2D
## Earthquake Test — a daily physics game.
## Everyone gets the same building site (anchors + budget) and the same earthquake each day.
## Build a truss from wood and steel beams, then run the quake. Score = height still standing
## (highest joint attached to an anchor) once the shaking stops. Three tries a day; best counts.

const Sim = preload("res://quake_sim.gd")
const Quake = preload("res://quake.gd")

const GW := 14                        # build grid width (m)
const GH := 18                        # build grid height (m)
const MAX_LEN := 3.2                  # longest single beam (m)
const U := 100                        # build coordinates are integer centimetres (grid dots every U)
const PIECE_LENS := [1, 2, 3]         # piece-length choices (m) for drawn lines
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
var piece_len := 2                     # target length (m) of each piece in a drawn line
var erasing := false                   # Erase tool: tap or swipe across beams to remove them
var erase_stroke := false              # an erase gesture is in progress (one undo step)
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
# camera: zoom 1 fits the whole site; cam_center is the world point at the board's centre
const ZOOM_MAX := 4.0
var zoom := 1.0
var cam_center := Vector2(-1e9, 0)
var fit_ppm := 30.0
var panning := false
var pan_last := Vector2()
var touches := {}                      # screen-touch index -> position (pinch zoom)
var gesture := false                   # two-finger gesture active: ignore the emulated mouse
var origin := Vector2()               # screen position of world (0, 0)
var drag_from := Vector2i(-1, -1)
var drag_to := Vector2i(-1, -1)
var drag_pointer := Vector2()          # where the finger/mouse actually is while dragging (screen)
var auto_lock := true                  # snap drag ends onto nearby joints (toggle, saved)
const LOCK_RADIUS := 0.9               # metres: how far the lock reaches for a joint...
const LOCK_PX := 44.0                  # ...or this many screen pixels, whichever is larger
const LOCK_BIAS := 0.45                # a joint wins over a closer grid dot by up to this much (m)
const PREFS := "user://quake_prefs.json"
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
	dev_open = String(url.get("dev", "")) == "1"
	# Links always open today's quake; past days are picked in-game. Only ?dev=1 honours ?d= / ?s=.
	if dev_open:
		if _valid_date(String(url.get("d", ""))):
			want = String(url.d)
		var s := String(url.get("s", ""))
		target_score = int(s) if s.is_valid_int() else 0
	elif String(url.get("d", "")) != "" or String(url.get("s", "")) != "":
		_clean_url()
	load_day(want)
	_load_prefs()
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
			if absi(a.x / U - x) < 2:
				ok = false
		if ok:
			anchors.append(Vector2i(x * U, 0))
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
	return wpos(b.a).distance_to(wpos(b.b))


## World position (metres) of a build point (centimetres).
static func wpos(p: Vector2i) -> Vector2:
	return Vector2(p) / U


## Build point (cm) for a grid dot (whole metres).
static func dot(x: int, y: int) -> Vector2i:
	return Vector2i(x * U, y * U)


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


## True when segment p-q lies along an existing beam (so building it would overlap).
func _covered(p: Vector2i, q: Vector2i) -> bool:
	for b in design:
		var a := Vector2(b.a)
		var c := Vector2(b.b)
		if Geometry2D.get_closest_point_to_segment(Vector2(p), a, c).distance_to(Vector2(p)) <= 1.5 \
				and Geometry2D.get_closest_point_to_segment(Vector2(q), a, c).distance_to(Vector2(q)) <= 1.5:
			return true
	return false


## Every anchor and joint in the design.
func _all_nodes() -> Array:
	var seen := {}
	for a in anchors:
		seen[a] = true
	for b in design:
		seen[b.a] = true
		seen[b.b] = true
	return seen.keys()


func beam_index(a: Vector2i, b: Vector2i) -> int:
	for i in design.size():
		var d: Dictionary = design[i]
		if (d.a == a and d.b == b) or (d.a == b and d.b == a):
			return i
	return -1


func in_grid(p: Vector2i) -> bool:
	return p.x >= 0 and p.x <= GW * U and p.y >= 0 and p.y <= GH * U


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
	if wpos(a).distance_to(wpos(b)) > MAX_LEN + 1e-6:
		return "Too long — max %.1f m" % MAX_LEN
	if beam_index(a, b) >= 0:
		return "Already built"
	var c := wpos(a).distance_to(wpos(b)) * float(Sim.MATS[mat].cost)
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


## Plan a straight line of beams from a to b, split into equal pieces no longer than `plen`
## metres (a 7 m line in 2 m pieces = 4 x 1.75 m). Joints between pieces can sit anywhere on
## the line, so any angle works. Returns {pieces: [[p, q], ...] still to build, why: "" or
## the reason it can't, cost: of those pieces, short: true when the budget ran out part-way}.
func plan_chain(a: Vector2i, b: Vector2i, plen: int = piece_len, mat: int = build_mat) -> Dictionary:
	var out := {"pieces": [], "why": "", "cost": 0.0, "short": false}
	if a == b:
		out.why = "same"
		return out
	if not in_grid(a) or not in_grid(b):
		out.why = "Off the site"
		return out
	if not is_node(a):
		if is_node(b):
			var t := a
			a = b
			b = t
		else:
			out.why = "Start from an anchor or a joint"
			return out
	# existing joints the line passes over become break points, so a line drawn over or
	# across earlier work connects to it instead of overlapping it
	var ab := Vector2(b - a)
	var ab_len2 := ab.length_squared()
	var stops := {0.0: a, 1.0: b}
	for p in _all_nodes():
		var t := Vector2(p - a).dot(ab) / ab_len2
		if t <= 1e-6 or t >= 1.0 - 1e-6:
			continue
		if (Vector2(a) + ab * t).distance_to(Vector2(p)) <= 1.5:
			stops[t] = p
	var ts: Array = stops.keys()
	ts.sort()
	var segs: Array = []      # [p, q, already_built]
	for i in ts.size() - 1:
		var p0: Vector2i = stops[ts[i]]
		var p1: Vector2i = stops[ts[i + 1]]
		if beam_index(p0, p1) >= 0:
			segs.append([p0, p1, true])
			continue
		var n := maxi(1, ceili(wpos(p0).distance_to(wpos(p1)) / float(plen) - 1e-6))
		var prev := p0
		for k in range(1, n + 1):
			var f := float(k) / n
			var q := p1 if k == n else Vector2i(roundi(p0.x + (p1.x - p0.x) * f), roundi(p0.y + (p1.y - p0.y) * f))
			segs.append([prev, q, false])
			prev = q
	for sg in segs:
		for p in [sg[0], sg[1]]:
			if p.y == 0 and not is_anchor(p):
				out.why = "Only anchors can touch the ground"
				return out
	var unit_cost := float(Sim.MATS[mat].cost)
	var left := money_left()
	var any_new := false
	for sg in segs:
		var p: Vector2i = sg[0]
		var q: Vector2i = sg[1]
		if sg[2] or beam_index(p, q) >= 0 or _covered(p, q):
			continue
		any_new = true
		var c := wpos(p).distance_to(wpos(q)) * unit_cost
		if out.cost + c > left + 1e-6:
			out.short = true
			break
		out.pieces.append([p, q])
		out.cost += c
	if not any_new:
		out.why = "Already built"
	elif out.pieces.is_empty():
		out.why = "Not enough budget"
	return out


## Build a planned line as one undo step. Returns how many pieces were added.
func add_chain(a: Vector2i, b: Vector2i, plen: int = piece_len, mat: int = build_mat) -> int:
	if phase == Phase.RESULT:
		back_to_build()
	if phase != Phase.BUILD:
		return 0
	var plan := plan_chain(a, b, plen, mat)
	if plan.why != "":
		if plan.why != "same":
			_toast(plan.why)
		return 0
	_push_history()
	for pq in plan.pieces:
		design.append({"a": pq[0], "b": pq[1], "m": mat})
	_save_state()
	if plan.short:
		_toast("Budget ran out — built %d piece%s" % [plan.pieces.size(), "" if plan.pieces.size() == 1 else "s"])
	return plan.pieces.size()


func set_erasing(on: bool) -> void:
	erasing = on
	selected = Vector2i(-1, -1)


## Erase the beam nearest world point w (Erase tool). One undo step per stroke.
func erase_at(w: Vector2) -> bool:
	if phase != Phase.BUILD:
		return false
	var i := beam_at(w, true)
	if i < 0:
		return false
	if not erase_stroke:
		_push_history()
		erase_stroke = true
	design.remove_at(i)
	_save_state()
	return true


func set_piece_len(l: int) -> void:
	if PIECE_LENS.has(l):
		piece_len = l


func remove_beam(i: int) -> void:
	if phase != Phase.BUILD or i < 0 or i >= design.size():
		return
	_push_history()
	design.remove_at(i)
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


## Grid points attached to an anchor through the design (pieces left floating aren't).
func attached_points(d: Array = design) -> Dictionary:
	var reach := {}
	for a in anchors:
		reach[a] = true
	var changed := true
	while changed:
		changed = false
		for b in d:
			if reach.has(b.a) != reach.has(b.b):
				reach[b.a] = true
				reach[b.b] = true
				changed = true
	return reach


func built_height(d: Array = design) -> float:
	var att := attached_points(d)
	var h := 0
	for b in d:
		if att.has(b.a):
			h = maxi(h, maxi(b.a.y, b.b.y))
	return h / float(U)


# ------------------------------------------------------------------ quake run

func run() -> void:
	if phase != Phase.BUILD or design.is_empty():
		return
	selected = Vector2i(-1, -1)
	sim = Sim.new()
	sim.setup(design, anchors, quake, 1.0 / U)
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
	if not tries.is_empty():
		_mark_played()


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
	return "user://quake2_%s.json" % date   # v2: build points in centimetres


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

## Always the plain game URL, so an old share still opens on today's quake.
func share_link() -> String:
	return base_url


## Remembers the day's best for the past-days picker and the GameTests home page.
func _mark_played() -> void:
	var label := fmt_m(best_score())
	_record_result(date, label)
	if OS.has_feature("web"):
		var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
			JSON.stringify("gametests:earthquake-test:" + date), JSON.stringify(JSON.stringify({"result": label}))]
		JavaScriptBridge.eval(js, true)


# ------------------------------------------------------------------ past days

const ARCHIVE_ROWS := 7
var archive_open := false
var archive_page := 0
var archive_results: Dictionary = {}
var cal_rect := Rect2()             # the past-days button in the header


## Drops ?d= (and anything else) from the address bar so a refresh stays on today.
func _clean_url() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{history.replaceState(null,'',location.pathname)}catch(e){}", true)


func _date_add(d: String, days: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00") + days * 86400)


func archive_count() -> int:
	return maxi(1, day_number(today))


func archive_pages() -> int:
	return ceili(float(archive_count()) / ARCHIVE_ROWS)


## The days on one page of the picker, newest first (page 0 starts with today).
func archive_page_days(page: int) -> Array:
	var out: Array = []
	for i in range(page * ARCHIVE_ROWS, mini((page + 1) * ARCHIVE_ROWS, archive_count())):
		out.append(_date_add(today, -i))
	return out


func open_archive() -> void:
	if phase == Phase.RUN:
		return
	archive_results = _picker_results()
	var idx := clampi(day_number(today) - day_number(date), 0, archive_count() - 1)
	archive_page = int(idx / ARCHIVE_ROWS)
	archive_open = true
	selected = Vector2i(-1, -1)
	_build_buttons()


func archive_shift(pages: int) -> void:
	archive_page = clampi(archive_page + pages, 0, archive_pages() - 1)
	_build_buttons()


## Opens a past (or today's) quake from the picker.
func pick_day(d: String) -> void:
	archive_open = false
	if d < EPOCH or d > today:
		_build_buttons()
		return
	if d != date:
		target_score = 0
		load_day(d)
	_layout()


func _results_path() -> String:
	return "user://quake_results.json"


func _load_results() -> Dictionary:
	var out: Dictionary = {}
	if FileAccess.file_exists(_results_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_results_path()))
		if data is Dictionary:
			out = data
	return out


## Recorded results, plus days with saved tries from before results were kept.
func _picker_results() -> Dictionary:
	var out := _load_results()
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	var re := RegEx.create_from_string("^quake2_(\\d{4}-\\d{2}-\\d{2})\\.json$")
	for f in dir.get_files():
		var m := re.search(f)
		if m == null or out.has(m.get_string(1)):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://" + f))
		if not data is Dictionary or (data.get("tries", []).is_empty() and data.get("design", []).is_empty()):
			continue
		var best := 0
		for t in data.get("tries", []):
			best = maxi(best, int(t.get("score", 0)))
		var done: bool = data.get("finished", false) or data.get("tries", []).size() >= MAX_TRIES
		out[m.get_string(1)] = fmt_m(best) if done else "In progress"
	return out


func _record_result(d: String, label: String) -> void:
	var all := _load_results()
	if String(all.get(d, "")) == label:
		return
	all[d] = label
	var f := FileAccess.open(_results_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
		f.close()


func _short_date(d: String) -> String:
	var t := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00"))
	var wd: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(t.weekday)]
	var mo: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(t.month) - 1]
	return "%s %s %d" % [wd, mo, int(t.day)]


func _archive_row_h() -> float:
	var vs := get_viewport_rect().size
	return clampf((vs.y - 40.0 - 210.0) / ARCHIVE_ROWS, 64.0, 92.0)


func _archive_card() -> Rect2:
	var vs := get_viewport_rect().size
	var w: float = min(vs.x - 40.0, 680.0)
	var h := 100.0 + ARCHIVE_ROWS * _archive_row_h() + 110.0
	return Rect2((vs.x - w) / 2.0, max(20.0, (vs.y - h) / 2.0), w, h)


func _archive_buttons() -> void:
	var c := _archive_card()
	var rh := _archive_row_h()
	var days := archive_page_days(archive_page)
	for i in days.size():
		buttons.append({"id": "day_" + String(days[i]), "label": "", "primary": false, "enabled": true, "kind": "row",
			"rect": Rect2(c.position.x + 20, c.position.y + 100 + i * rh, c.size.x - 40, rh - 10)})
	var bw := (c.size.x - 40 - 24) / 3.0
	var by := c.end.y - 90
	buttons.append({"id": "arch_newer", "label": "< Newer", "primary": false, "enabled": archive_page > 0,
		"rect": Rect2(c.position.x + 20, by, bw, 70)})
	buttons.append({"id": "arch_close", "label": "Close", "primary": true, "enabled": true,
		"rect": Rect2(c.position.x + 32 + bw, by, bw, 70)})
	buttons.append({"id": "arch_older", "label": "Older >", "primary": false, "enabled": archive_page < archive_pages() - 1,
		"rect": Rect2(c.position.x + 44 + bw * 2, by, bw, 70)})


func _draw_archive() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72))
	var c := _archive_card()
	_box(c, C_PANEL, 20, Color(C_INK, 0.15))
	draw_string(font, c.position + Vector2(30, 64), "Past quakes", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, C_INK)
	var pg := "Page %d of %d" % [archive_page + 1, archive_pages()]
	var pw := font.get_string_size(pg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, Vector2(c.end.x - 30 - pw, c.position.y + 62), pg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_MUTED)
	for b in buttons:
		if b.get("kind", "") != "row":
			continue
		var d := String(b.id).substr(4)
		var r: Rect2 = b.rect
		_box(r, C_BTN, 14, C_ACCENT if d == date else Color(0, 0, 0, 0))
		var mid := r.get_center().y + 10
		draw_string(font, Vector2(r.position.x + 22, mid), "#%d" % day_number(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_ACCENT)
		draw_string(font, Vector2(r.position.x + 120, mid), "Today" if d == today else _short_date(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_INK)
		var res := String(archive_results.get(d, ""))
		var txt := res if res != "" else "Not played"
		var sz := 26 if res != "" else 22
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(font, Vector2(r.end.x - 22 - tw, mid), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, C_ACCENT if res != "" else C_MUTED)


## Calendar glyph for the past-days button.
func _draw_calendar(c: Vector2, col_: Color) -> void:
	var r := Rect2(c.x - 12, c.y - 10, 24, 22)
	draw_rect(r, col_, false, 2.4)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 6.5), col_)
	draw_line(Vector2(c.x - 6, c.y - 15), Vector2(c.x - 6, c.y - 7), col_, 2.4)
	draw_line(Vector2(c.x + 6, c.y - 15), Vector2(c.x + 6, c.y - 7), col_, 2.4)
	for i in 3:
		draw_rect(Rect2(c.x - 9 + i * 6.5, c.y + 2, 4.5, 4.5), col_)


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
	pick_day(today)


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
	if _camera_input(ev):
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			if gesture:
				return
			if dev_open or tut_open or archive_open:
				_press_button(p)
				return
			if help_rect.grow(10).has_point(p):
				tut_open = true
				return
			if cal_rect.has_area() and cal_rect.grow(8).has_point(p):
				open_archive()
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
			press_pos = p
			pan_last = p
			drag_pointer = p
			dragging = false
			drag_to = Vector2i(-1, -1)
			drag_from = Vector2i(-1, -1)
			if phase != Phase.BUILD:
				panning = zoom > 1.01
				return
			if erasing:
				erase_stroke = false
				erase_at(screen_to_world(p))
				return
			var g := snap(p)
			if g.x >= 0 and is_node(g):
				drag_from = g
			elif zoom > 1.01:
				panning = true
		else:
			if gesture:
				if touches.is_empty():
					gesture = false
				_end_pointer()
				return
			var was_pan_drag := panning and dragging
			if phase == Phase.BUILD and not dev_open and not tut_open and not erasing and not was_pan_drag and board_rect.has_point(p):
				_release(p)
			_end_pointer()
	elif ev is InputEventMouseMotion and not gesture:
		if (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		var p: Vector2 = make_input_local(ev).position
		drag_pointer = p
		if p.distance_to(press_pos) > 12.0:
			dragging = true
		if erasing and phase == Phase.BUILD and board_rect.has_point(press_pos):
			# swipe: erase everything the pointer crosses
			var a := screen_to_world(pan_last)
			var b := screen_to_world(p)
			var steps := maxi(1, ceili(a.distance_to(b) / 0.15))
			for k in steps + 1:
				erase_at(a.lerp(b, float(k) / steps))
			pan_last = p
			return
		if panning:
			if dragging:
				_pan_by(p - pan_last)
			pan_last = p
			return
		if drag_from.x >= 0 and dragging:
			var g := snap(p, drag_from)
			drag_to = g if g.x >= 0 and g != drag_from else Vector2i(-1, -1)


func _end_pointer() -> void:
	drag_from = Vector2i(-1, -1)
	drag_to = Vector2i(-1, -1)
	dragging = false
	panning = false
	erase_stroke = false


## Zoom/pan input: mouse wheel, trackpad pinch/scroll, two-finger touch. True when consumed.
func _camera_input(ev: InputEvent) -> bool:
	if dev_open or tut_open:
		return false
	if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var p: Vector2 = make_input_local(ev).position
		if board_rect.has_point(p):
			zoom_at(p, 1.15 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			return true
		return false
	if ev is InputEventMagnifyGesture:
		var p: Vector2 = make_input_local(ev).position
		zoom_at(p if board_rect.has_point(p) else board_rect.get_center(), ev.factor)
		return true
	if ev is InputEventPanGesture:
		_pan_by(-ev.delta * 8.0)
		return true
	if ev is InputEventScreenTouch:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			touches[ev.index] = p
			if touches.size() >= 2 and not gesture:
				gesture = true
				_cancel_for_gesture()
		else:
			touches.erase(ev.index)
			if touches.is_empty() and gesture:
				gesture = false
				_end_pointer()
		return false   # the emulated mouse events still arrive; they're ignored while gesture
	if ev is InputEventScreenDrag:
		var p: Vector2 = make_input_local(ev).position
		if touches.size() >= 2 and touches.has(ev.index):
			var ids: Array = touches.keys()
			var other: Vector2 = touches[ids[1] if ids[0] == ev.index else ids[0]]
			var before: Vector2 = touches[ev.index]
			var d0 := before.distance_to(other)
			var d1 := p.distance_to(other)
			var mid0 := (before + other) * 0.5
			var mid1 := (p + other) * 0.5
			touches[ev.index] = p
			if d0 > 4.0:
				zoom_at(mid1, d1 / d0)
			_pan_by(mid1 - mid0)
			return true
		if touches.has(ev.index):
			touches[ev.index] = p
	return false


## A second finger landed: abandon what the first finger started (and undo a stray erase).
func _cancel_for_gesture() -> void:
	if erase_stroke:
		undo()
	_end_pointer()


func zoom_at(p: Vector2, factor: float) -> void:
	var w := screen_to_world(p)
	zoom = clampf(zoom * factor, 1.0, ZOOM_MAX)
	ppm = fit_ppm * zoom
	# keep world point w under the pointer
	var c := board_rect.get_center()
	cam_center = Vector2(w.x - (p.x - c.x) / ppm, w.y + (p.y - c.y) / ppm)
	_clamp_camera()
	_apply_camera()


func zoom_reset() -> void:
	zoom = 1.0
	cam_center = _fit_center()
	_apply_camera()


func _pan_by(screen_delta: Vector2) -> void:
	cam_center += Vector2(-screen_delta.x, screen_delta.y) / ppm
	_clamp_camera()
	_apply_camera()


func _fit_center() -> Vector2:
	return Vector2(GW / 2.0, (GH + VIEW_PAD - VIEW_GROUND) / 2.0)


func _clamp_camera() -> void:
	var hw := board_rect.size.x / (2.0 * ppm)
	var hh := board_rect.size.y / (2.0 * ppm)
	var x0 := -VIEW_PAD
	var x1 := GW + VIEW_PAD
	var y0 := -VIEW_GROUND
	var y1 := GH + VIEW_PAD
	cam_center.x = (x0 + x1) / 2.0 if hw * 2.0 >= x1 - x0 - 1e-6 else clampf(cam_center.x, x0 + hw, x1 - hw)
	cam_center.y = (y0 + y1) / 2.0 if hh * 2.0 >= y1 - y0 - 1e-6 else clampf(cam_center.y, y0 + hh, y1 - hh)


func _apply_camera() -> void:
	ppm = fit_ppm * zoom
	var c := board_rect.get_center()
	origin = Vector2(c.x - cam_center.x * ppm, c.y + cam_center.y * ppm)


## Pointer released on the board: finish a drag, or handle a tap.
func _release(p: Vector2) -> void:
	if dragging:
		if drag_from.x >= 0 and drag_to.x >= 0:
			add_chain(drag_from, drag_to)
			selected = Vector2i(-1, -1)
		return   # a drag that didn't start on a joint does nothing
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
			var why: String = plan_chain(selected, g).why
			if why == "":
				add_chain(selected, g)
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
	if beam_at(w) >= 0:
		_toast("To remove pieces, use Erase")
		return
	if g.x >= 0:
		_toast("Start at an anchor or a joint")


func beam_at(w: Vector2, whole := false) -> int:
	var best := -1
	var best_d := maxf(0.28, 14.0 / ppm) if not whole else maxf(0.35, 18.0 / ppm)
	for i in design.size():
		var b: Dictionary = design[i]
		var a := wpos(b.a)
		var c := wpos(b.b)
		var q := Geometry2D.get_closest_point_to_segment(w, a, c)
		var d := q.distance_to(w)
		if d < best_d and (whole or (q.distance_to(a) > 0.2 and q.distance_to(c) > 0.2)):
			best_d = d
			best = i
	return best


func screen_to_world(p: Vector2) -> Vector2:
	return Vector2((p.x - origin.x) / ppm, (origin.y - p.y) / ppm)


func world_to_screen(w: Vector2) -> Vector2:
	return Vector2(origin.x + w.x * ppm, origin.y - w.y * ppm)


## Nearest grid point to a screen position, or (-1, -1) when too far from any.
## Nearest build point to a screen position. With auto-lock on, existing joints (and anchors)
## pull the pointer in from up to LOCK_RADIUS / LOCK_PX away and beat a slightly closer grid
## dot; with it off, the nearest dot or joint under the pointer wins. `exclude` is skipped
## (the joint a drag started from). Returns (-1, -1) when nothing is near.
func snap(p: Vector2, exclude := Vector2i(-1, -1)) -> Vector2i:
	var w := screen_to_world(p)
	var node := Vector2i(-1, -1)
	var dn := INF
	for k in _all_nodes():
		if k == exclude:
			continue
		var d := wpos(k).distance_to(w)
		if d < dn:
			dn = d
			node = k
	var g := dot(roundi(w.x), roundi(w.y))
	var dd := wpos(g).distance_to(w)
	var dot_ok := in_grid(g) and g != exclude and dd <= 0.48
	if auto_lock:
		var reach := maxf(LOCK_RADIUS, LOCK_PX / ppm)
		if node.x >= 0 and dn <= reach and (not dot_ok or dn <= dd + LOCK_BIAS):
			return node
	elif node.x >= 0 and dn <= maxf(0.3, 16.0 / ppm) and (not dot_ok or dn <= dd):
		return node
	return g if dot_ok else Vector2i(-1, -1)


## True when the drag end is locked onto an existing joint rather than a free grid dot.
func is_locked_target(p: Vector2i) -> bool:
	return p.x >= 0 and is_node(p)


func set_auto_lock(on: bool) -> void:
	auto_lock = on
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"auto_lock": on}))
		f.close()
	_toast("Auto-lock " + ("on: lines snap to nearby joints" if on else "off: lines go to the nearest dot"))


func _load_prefs() -> void:
	if not FileAccess.file_exists(PREFS):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PREFS))
	if d is Dictionary:
		auto_lock = bool(d.get("auto_lock", true))


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
			if (f.begins_with("quake_") or f.begins_with("quake2_")) and f.ends_with(".json"):
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
					"erase": set_erasing(not erasing)
					"zoom_in": zoom_at(board_rect.get_center(), 1.5)
					"lock": set_auto_lock(not auto_lock)
					"zoom_out":
						if zoom / 1.5 <= 1.01:
							zoom_reset()
						else:
							zoom_at(board_rect.get_center(), 1.0 / 1.5)
					"len1": set_piece_len(1)
					"len2": set_piece_len(2)
					"len3": set_piece_len(3)
					"skip": skip()
					"again": back_to_build()
					"finish": finish()
					"share": share()
					"today": play_today()
					"dev_today": dev_reset_today()
					"dev_all": dev_reset_all()
					"dev_close": dev_open = false
					"tut_close": close_tutorial()
					"arch_newer": archive_shift(-1)
					"arch_older": archive_shift(1)
					"arch_close":
						archive_open = false
						_build_buttons()
					_:
						if String(b.id).begins_with("day_"):
							pick_day(String(b.id).substr(4))
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
	fit_ppm = ppm
	if cam_center.x < -1e8:
		cam_center = _fit_center()
	_clamp_camera()
	_apply_camera()
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
	if archive_open and not dev_open:
		_archive_buttons()
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
			var mats := [["wood", "Wood $1/m", build_mat == Sim.Mat.WOOD, true], ["steel", "Steel $3/m", build_mat == Sim.Mat.STEEL, true]]
			var lens: Array = []
			for l in PIECE_LENS:
				lens.append(["len%d" % l, "%d m" % l, piece_len == l, true])
			if panel_rect.size.x >= 560:
				rows.append(mats + lens)
			else:
				rows.append(mats)
				rows.append(lens)
			rows.append([["run", "Start quake", true, not design.is_empty()], ["undo", "Undo", false, not history.is_empty()], ["erase", "Erase", erasing, not design.is_empty() or erasing], ["clear", "Clear", false, not design.is_empty()]])
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
			if n == 4:
				w = free * (0.34 if i == 0 else 0.22)
			elif n == 5:
				w = free * (0.25 if i < 2 else 0.5 / 3.0)
			elif n == 3 and phase == Phase.BUILD and String(row[0][0]).begins_with("len"):
				w = free / 3.0
			elif n == 3:
				w = free * (0.46 if i == 0 else 0.27)
			elif n == 2 and phase != Phase.BUILD:
				w = free * (0.62 if i == 0 else 0.38)
			var kind := "toggle" if l[0] in ["wood", "steel", "erase"] or String(l[0]).begins_with("len") else "button"
			buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": l[3], "rect": Rect2(x, y, w, bh), "kind": kind})
			x += w + gap
		y += bh + gap
	# zoom controls in the board's top-right corner
	var zs := 46.0
	var zx := board_rect.end.x - zs - 8
	var zy := board_rect.position.y + 8
	buttons.append({"id": "zoom_in", "label": "+", "primary": false, "enabled": zoom < ZOOM_MAX - 0.01, "rect": Rect2(zx, zy, zs, zs), "kind": "zoom"})
	buttons.append({"id": "zoom_out", "label": "-", "primary": false, "enabled": zoom > 1.01, "rect": Rect2(zx, zy + zs + 6, zs, zs), "kind": "zoom"})
	if phase == Phase.BUILD:
		buttons.append({"id": "lock", "label": "LOCK", "primary": auto_lock, "enabled": true, "rect": Rect2(zx - 14, zy + (zs + 6) * 2, zs + 14, zs), "kind": "zoom"})


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if buttons.is_empty():
		_layout()
	_draw_board()
	_mask_outside_board()
	_draw_header()
	_draw_seismo()
	_draw_panel()
	_draw_help_button()
	if tut_open and not dev_open:
		_draw_tutorial()
	if archive_open and not dev_open:
		_draw_archive()
	if dev_open:
		var vs := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72))
		_text_c("Dev menu", Vector2(vs.x / 2.0, vs.y / 2.0 - 172), 32, C_ACCENT)
		_text_c("Reset saved progress for #%d (%s)" % [quake_no, date], Vector2(vs.x / 2.0, vs.y / 2.0 - 136), 20, C_MUTED)
	for b in buttons:
		if b.get("kind", "") != "row":
			_draw_button(b)
	if loupe_active():
		_draw_loupe()
	if toast_t > 0.0 and toast != "":
		var a := clampf(toast_t * 2.0, 0.0, 1.0)
		var vs := get_viewport_rect().size
		var tw := font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 40
		var ty := board_rect.position.y + 12
		var r := Rect2((vs.x - tw) / 2.0, ty, tw, 46)
		_box(r, Color(0.08, 0.07, 0.06, 0.94 * a), 23, Color(C_ACCENT, 0.6 * a))
		_text_c(toast, r.get_center() + Vector2(0, 8), 22, Color(C_INK, a))


## Cover anything drawn outside the board (the zoomed site) with the page background.
func _mask_outside_board() -> void:
	var vs := get_viewport_rect().size
	var r := board_rect
	draw_rect(Rect2(0, 0, vs.x, r.position.y), C_BG)
	draw_rect(Rect2(0, r.end.y, vs.x, vs.y - r.end.y), C_BG)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), C_BG)
	draw_rect(Rect2(r.end.x, r.position.y, vs.x - r.end.x, r.size.y), C_BG)
	_box(r.grow(2), Color(0, 0, 0, 0), 12, Color(C_INK, 0.08))


func _draw_header() -> void:
	var r := head_rect
	var title_sz := _title_size()
	draw_string(font, r.position + Vector2(0, 46), "Earthquake Test", HORIZONTAL_ALIGNMENT_LEFT, -1, title_sz, C_INK)
	draw_string(font, r.position + Vector2(0, 80), "#%d · %s" % [quake_no, date], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_MUTED if date == today else C_ACCENT)
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
	var ground := Rect2(r.position.x, gy0, r.size.x, maxf(0.0, r.end.y - gy0))
	if ground.size.y > 0.0:
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
				var p := dot(gx2, gy)
				var s := world_to_screen(wpos(p))
				if focus.x >= 0 and _reach(focus).has(p):
					draw_circle(s, maxf(2.0, ppm * 0.07), Color(C_DOT_REACH, 0.45))
				else:
					draw_circle(s, maxf(1.5, ppm * 0.05), C_DOT)
		# height ruler
		for hy in range(2, GH + 1, 2):
			var s := world_to_screen(Vector2(-0.45, hy))
			_text_r("%d" % hy, s + Vector2(0, 5), 13, Color(C_MUTED, 0.6))
	# ghost of the built design after a run
	if (phase == Phase.RESULT or phase == Phase.FINAL) and show_try >= 0:
		for b in _design_from_json(tries[show_try].design):
			draw_line(world_to_screen(wpos(b.a)), world_to_screen(wpos(b.b)), C_GHOST, maxf(2.0, ppm * 0.1))
	# anchors
	for a in anchors:
		var s := world_to_screen(wpos(a) + Vector2(g.x, g.y))
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


func _draw_beam(a: Vector2, b: Vector2, mat: int, tint := Color(0, 0, 0, 0), alpha := 1.0, width := -1.0) -> void:
	var w := _beam_width(mat) if width < 0.0 else width
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
	var att := attached_points()
	for b in design:
		if att.has(b.a):
			_draw_beam(world_to_screen(wpos(b.a)), world_to_screen(wpos(b.b)), int(b.m))
		else:   # floating piece: not attached to any anchor, it'll just fall
			_draw_beam(world_to_screen(wpos(b.a)), world_to_screen(wpos(b.b)), int(b.m), Color(C_DANGER, 0.5), 0.45)
		joints[b.a] = true
		joints[b.b] = true
	var plan_pts: Array = []
	loupe_caption = ""
	if drag_from.x >= 0 and drag_to.x >= 0:
		var plan := plan_chain(drag_from, drag_to)
		if plan.why == "":
			for pq in plan.pieces:
				_draw_beam(world_to_screen(wpos(pq[0])), world_to_screen(wpos(pq[1])), build_mat, Color(0, 0, 0, 0), 0.65)
				plan_pts.append(pq[1])
			var n_p: int = plan.pieces.size()
			_draw_drag_label("%d piece%s · $%d%s" % [n_p, "" if n_p == 1 else "s", ceili(plan.cost), " (budget!)" if plan.short else ""])
		elif plan.why != "same":
			_draw_beam(world_to_screen(wpos(drag_from)), world_to_screen(wpos(drag_to)), build_mat, Color(C_DANGER, 0.85), 0.5)
			_draw_drag_label(plan.why)
	for p in joints:
		_draw_joint(world_to_screen(wpos(p)), is_anchor(p))
	for a in anchors:
		_draw_joint(world_to_screen(wpos(a)), true)
	for p in plan_pts:
		_draw_joint(world_to_screen(wpos(p)), false)
	if selected.x >= 0:
		var s := world_to_screen(wpos(selected))
		draw_arc(s, ppm * 0.32 + 2.0 * sin(anim_t * 6.0), 0, TAU, 28, C_DOT_REACH, 3.0)
	if drag_to.x >= 0 and is_locked_target(drag_to):
		draw_arc(world_to_screen(wpos(drag_to)), maxf(10.0, ppm * 0.3), 0, TAU, 28, C_OK, 3.0)


## Small pill near the drag end saying what the line will build.
func _draw_drag_label(text: String) -> void:
	loupe_caption = text
	if loupe_active():
		return
	var s := world_to_screen(wpos(drag_to)) + Vector2(0, -ppm * 0.6 - 18)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 20
	var r := Rect2(s.x - tw / 2.0, s.y - 16, tw, 30)
	r.position.x = clampf(r.position.x, board_rect.position.x + 4, board_rect.end.x - tw - 4)
	r.position.y = maxf(r.position.y, board_rect.position.y + 4)
	_box(r, Color(0.08, 0.07, 0.06, 0.9), 15, Color(C_DOT_REACH, 0.5))
	_text_c(text, r.get_center() + Vector2(0, 6), 18, C_INK)


## Grid points a line can be drawn to from `focus` with the current settings (cached).
var _reach_key := ""
var _reach_set := {}


func _reach(focus: Vector2i) -> Dictionary:
	var key := "%s|%d|%d|%d|%d" % [focus, piece_len, build_mat, design.size(), floori(money_left() * 100)]
	if key == _reach_key:
		return _reach_set
	_reach_key = key
	_reach_set = {}
	for gy in range(0, GH + 1):
		for gx in range(0, GW + 1):
			var p := dot(gx, gy)
			if p != focus and plan_chain(focus, p).why == "":
				_reach_set[p] = true
	return _reach_set


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
		var ratio: float = sim.stress_ratio(i)
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
			var hint := "Drag a line from an anchor or joint to any dot — it's split into equal pieces up to the chosen length. Use Erase to remove pieces."
			if erasing:
				hint = "Erasing: tap or swipe across pieces to remove them. Tap Erase again to build."
			elif selected.x >= 0:
				hint = "Tap a lit dot to build a line to it from the selected joint. Tap the joint again to deselect."
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
	if b.id == "lock":
		var on: bool = b.primary
		_box(b.rect, Color(C_DOT_REACH, 0.9) if on else Color(0.1, 0.09, 0.08, 0.8), 12, Color(C_INK, 0.25))
		var ink := Color("1b1917") if on else C_MUTED
		_text_c("LOCK", b.rect.get_center() + Vector2(0, -2), 14, ink)
		_text_c("ON" if on else "OFF", b.rect.get_center() + Vector2(0, 15), 13, ink)
		return
	if b.get("kind", "") == "zoom":
		_box(b.rect, Color(0.1, 0.09, 0.08, 0.8 if b.enabled else 0.4), 12, Color(C_INK, 0.25))
		var c: Vector2 = b.rect.get_center()
		var col := C_INK if b.enabled else Color(C_INK, 0.3)
		draw_line(c - Vector2(9, 0), c + Vector2(9, 0), col, 3.0)
		if b.id == "zoom_in":
			draw_line(c - Vector2(0, 9), c + Vector2(0, 9), col, 3.0)
		return
	var toggle: bool = b.get("kind", "") == "toggle"
	var col: Color = C_BTN_PRIMARY if b.primary else C_BTN
	if toggle:
		var mc: Color = C_WOOD if b.id == "wood" else (C_STEEL if b.id == "steel" else (C_DANGER if b.id == "erase" else C_DOT_REACH))
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
	cal_rect = Rect2(help_rect.end.x + 12, help_rect.position.y, 38, 38)
	var a := 0.4 if phase == Phase.RUN else 1.0
	draw_circle(cal_rect.get_center(), 18, Color(C_BTN, a))
	draw_arc(cal_rect.get_center(), 18, 0, TAU, 32, Color(C_INK, 0.35 * a), 2.0)
	_draw_calendar(cal_rect.get_center() + Vector2(0, 1), Color(C_INK, a))


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
	var room := head_rect.size.x - stat_w - 16.0 - 56.0 - 52.0   # "?" and past-days buttons
	var sz := 44
	while sz > 24 and font.get_string_size("Earthquake Test", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > room:
		sz -= 2
	return sz


# ------------------------------------------------------------------ magnifier (loupe)

const LOUPE_SIZE := 230.0
const LOUPE_ZOOM := 2.6               # loupe magnification relative to the board
const LOUPE_LIFT := 110.0             # gap between the finger and the loupe
var loupe_caption := ""


## The loupe shows while a finger/mouse is held on a joint to draw a line.
func loupe_active() -> bool:
	return phase == Phase.BUILD and drag_from.x >= 0 and not erasing and not gesture


## Where the loupe sits: above the finger (the hand covers below it), or beside it near the top.
func loupe_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var L := minf(LOUPE_SIZE, minf(vs.x, vs.y) * 0.42)
	var f := drag_pointer
	var r := Rect2(f.x - L / 2.0, f.y - LOUPE_LIFT - L, L, L)
	if r.position.y < 8.0:
		r.position.y = clampf(f.y - L / 2.0, 8.0, vs.y - L - 8.0)
		r.position.x = f.x + LOUPE_LIFT * 0.8 if f.x < vs.x / 2.0 else f.x - LOUPE_LIFT * 0.8 - L
	r.position.x = clampf(r.position.x, 8.0, vs.x - L - 8.0)
	return r


func _draw_loupe() -> void:
	var R := loupe_rect()
	var lppm := maxf(ppm * LOUPE_ZOOM, 90.0)
	var wc := screen_to_world(drag_pointer)
	var c := R.get_center()
	var inner := R.grow(-3)
	var ls := func(w: Vector2) -> Vector2: return c + Vector2(w.x - wc.x, -(w.y - wc.y)) * lppm
	_box(R.grow(3), Color(0, 0, 0, 0.45), 18)
	_box(R, C_SKY, 16, Color(C_INK, 0.5))
	# ground
	var gy: float = ls.call(Vector2(0, 0)).y
	if gy < inner.end.y:
		var top := maxf(gy, inner.position.y)
		draw_rect(Rect2(inner.position.x, top, inner.size.x, inner.end.y - top), C_GROUND)
		if gy >= inner.position.y:
			draw_line(Vector2(inner.position.x, gy), Vector2(inner.end.x, gy), C_GROUND_HI, 3.0)
	# grid dots
	var half := R.size.x / 2.0 / lppm
	for gx in range(floori(wc.x - half), ceili(wc.x + half) + 1):
		for gyi in range(floori(wc.y - half), ceili(wc.y + half) + 1):
			var d := dot(gx, gyi)
			if not in_grid(d) or gyi == 0:
				continue
			var sp: Vector2 = ls.call(wpos(d))
			if inner.grow(-4).has_point(sp):
				draw_circle(sp, 3.0, Color(1, 1, 1, 0.22))
	# beams + preview
	var att := attached_points()
	for b in design:
		var seg := _clip_seg(ls.call(wpos(b.a)), ls.call(wpos(b.b)), inner)
		if not seg.is_empty():
			var w := lppm * (0.17 if int(b.m) == Sim.Mat.WOOD else 0.13)
			_draw_beam(seg[0], seg[1], int(b.m), Color(0, 0, 0, 0) if att.has(b.a) else Color(C_DANGER, 0.5), 1.0 if att.has(b.a) else 0.45, w)
	var plan_ok := false
	var pts: Array = []
	if drag_to.x >= 0:
		var plan := plan_chain(drag_from, drag_to)
		plan_ok = plan.why == ""
		if plan_ok:
			for pq in plan.pieces:
				var seg := _clip_seg(ls.call(wpos(pq[0])), ls.call(wpos(pq[1])), inner)
				if not seg.is_empty():
					_draw_beam(seg[0], seg[1], build_mat, Color(0, 0, 0, 0), 0.7, lppm * 0.15)
				pts.append(pq[1])
		elif plan.why != "same":
			var seg := _clip_seg(ls.call(wpos(drag_from)), ls.call(wpos(drag_to)), inner)
			if not seg.is_empty():
				_draw_beam(seg[0], seg[1], build_mat, Color(C_DANGER, 0.85), 0.55, lppm * 0.12)
	# joints + anchors
	var jr := maxf(5.0, lppm * 0.09)
	for k in _all_nodes() + pts:
		var sp: Vector2 = ls.call(wpos(k))
		if inner.grow(-jr).has_point(sp):
			draw_circle(sp, jr + 1.5, Color(0, 0, 0, 0.5))
			draw_circle(sp, jr, C_ANCHOR if is_anchor(k) else C_JOINT)
	# start joint and target
	var s0: Vector2 = ls.call(wpos(drag_from))
	if inner.has_point(s0):
		draw_arc(s0, jr + 6, 0, TAU, 24, C_DOT_REACH, 2.5)
	if drag_to.x >= 0:
		var st: Vector2 = ls.call(wpos(drag_to))
		if inner.grow(-6).has_point(st):
			var locked := is_locked_target(drag_to)
			draw_arc(st, jr + 8, 0, TAU, 28, C_OK if locked else (C_DOT_REACH if plan_ok else C_DANGER), 3.0)
	# crosshair where the finger actually is
	var cc := Color(C_INK, 0.75)
	draw_line(c + Vector2(-14, 0), c + Vector2(-5, 0), cc, 2.0)
	draw_line(c + Vector2(5, 0), c + Vector2(14, 0), cc, 2.0)
	draw_line(c + Vector2(0, -14), c + Vector2(0, -5), cc, 2.0)
	draw_line(c + Vector2(0, 5), c + Vector2(0, 14), cc, 2.0)
	# caption
	var cap := loupe_caption
	if drag_to.x >= 0 and is_locked_target(drag_to) and plan_ok:
		cap = "locked · " + cap
	if cap == "":
		cap = "drag to a dot or joint"
	var csz := 16
	while csz > 11 and font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x > R.size.x - 20:
		csz -= 1
	var cr := Rect2(R.position.x + 6, R.end.y - 30, R.size.x - 12, 24)
	_box(cr, Color(0.06, 0.05, 0.05, 0.85), 10)
	_text_c(cap, cr.get_center() + Vector2(0, csz * 0.36), csz, C_INK)


## Clip segment a-b to rect r (Liang-Barsky). Returns [a', b'] or [] when outside.
func _clip_seg(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		var pp: float = ps[i]
		var qq: float = qs[i]
		if absf(pp) < 1e-9:
			if qq < 0.0:
				return []
		else:
			var t := qq / pp
			if pp < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return []
	return [a + d * t0, a + d * t1]



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
		["beam", "Pick a max piece length (1, 2 or 3 m), then drag a line from an anchor or joint to any dot, at any angle. It's split into equal pieces no longer than that. Only the Erase tool removes pieces."],
		["steel", "Wood is cheap and light. Steel costs 3× but is ~5× stronger. Long pieces buckle more easily when squeezed."],
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
		_para("While you draw, a magnifier above your finger shows where the line will land, and LOCK (on by default) snaps it onto nearby joints. Pinch or use + and - to zoom.", x, y + 6, tw, 18, C_MUTED)


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
		"money_left": money_left(), "anchors": anchors.map(func(a): return a.x / U),
		"beams": design.size(), "built_height": built_height(), "build_mat": build_mat,
		"selected": [selected.x, selected.y],
		"quake": quake.describe() if quake else "",
		"sim_t": sim.t if sim != null else -1.0,
		"standing": sim.standing_height() if sim != null else -1.0,
		"broken": sim.broken_count() if sim != null else 0,
		"tries": tries.map(func(t): return t.score), "best": best_score(),
		"target": target_score, "tutorial": tut_open,
		"archive_open": archive_open, "archive_page": archive_page, "today": today,
		"share": share_text() if not tries.is_empty() else "",
	}
