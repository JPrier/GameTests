extends Node2D
## Daily Bridge — a daily bridge-building physics puzzle.
## Everyone gets the same canyon (gap, bank heights, anchors, ledges or pillars) and the same
## vehicle each day. Drag lines from joints (road for the vehicle to drive on, wood to brace
## it), then press Go: one vehicle tries to cross. The physics is deterministic (bridge_sim.gd),
## so the same bridge always plays out the same way. Three attempts a day.
## Score = 100 x ideal / material used, where the ideal is the cheapest reference bridge that
## crosses today's level (found in-game by running the candidates through the physics).

const EPOCH := "2026-10-02"           # puzzle #1
const DEFAULT_URL := "https://jprier.github.io/GameTests/daily-bridge/"
const MAX_TRIES := 3
const MAX_HISTORY := 60
const ZOOM_MAX := 3.5
const U := BridgeSim.U
const PIECE_LENGTHS := [1, 2, 3, 4]
const TUT_FLAG := "user://daily_bridge_tutorial_seen"
const PREFS := "user://daily_bridge_prefs.json"
const LOCK_RADIUS := 0.9              # metres: how far auto-lock reaches for a joint...
const LOCK_PX := 44.0                 # ...or this many screen pixels, whichever is larger
const LOCK_BIAS := 0.45               # a joint wins over a closer grid dot by up to this much (m)
const LOUPE_SIZE := 230.0
const LOUPE_ZOOM := 2.6               # loupe magnification relative to the view
const LOUPE_LIFT := 110.0             # gap between the finger and the loupe
const SAVE_PREFIX := "bridge2_"       # v2 saves: centimetre build points
const IDEAL_VERSION := "v2"           # bump when the physics or candidates change
const NONE := Vector2i(1 << 30, 1 << 30)

enum Phase { BUILD, RUN, RESULT, FINAL }
enum Tool { ROAD, WOOD, ERASE }

const C_SKY_TOP := Color("7db7e0")
const C_SKY_LOW := Color("d9ecf5")
const C_HILL := Color("a9cbb8")
const C_ROCK := Color("8a6a52")
const C_ROCK_DARK := Color("6b503d")
const C_GRASS := Color("6fb35a")
const C_WATER := Color("3c7fb8")
const C_WATER_HI := Color(1, 1, 1, 0.25)
const C_ROAD := Color("3d3f46")
const C_ROAD_LINE := Color("f4d35e")
const C_WOOD := Color("c8945a")
const C_WOOD_DARK := Color("8f6337")
const C_STRESS := Color("e8412f")
const C_JOINT := Color("f7f3ea")
const C_ANCHOR := Color("d6453a")
const C_INK := Color("1f2a36")
const C_MUTED := Color("5b6b7c")
const C_PANEL := Color(1, 1, 1, 0.88)
const C_BTN := Color("e4ebf1")
const C_BTN_ON := Color("2f6fa8")
const C_BTN_PRIMARY := Color("2e9b5f")
const C_BAD := Color("d6453a")
const C_GOOD := Color("2e9b5f")
const C_DOT := Color(1, 1, 1, 0.55)
const C_IDEAL := Color("7a4fd1")

# puzzle
var date := ""
var today := ""
var puzzle_no := 1
var lv: Dictionary = {}               # BridgeSim.make_level()
var gap := 10
var dy := 0
var vehicle_i := 0
var anchors: Array = []               # Vector2i, centimetres
var ideal := -1                       # material of the ideal bridge (scores 100); -1 while searching
var ideal_design: Array = []
var ideal_search: BridgeSim.IdealSearch

# player
var design: Array = []                # [{p:Vector2i cm, q:Vector2i cm, m:int}]
var history: Array = []
var tool: int = Tool.ROAD
var piece_len := 2
var tries: Array = []                 # [{crossed, outcome, cost, snapped, design}]
var finished := false
var phase: int = Phase.BUILD
var target_score := -1                # score of whoever sent the link (?s=)
var base_url := DEFAULT_URL
var last_loads := {}                  # beam key -> {load, broken} from the previous attempt
var show_ideal := false               # final screen: show the ideal bridge instead of yours

# run
var sim: BridgeSim
var sim_design: Array = []
var sim_acc := 0.0
var fast := false
var splash_t := -1.0
var splash_at := Vector2.ZERO
var _is_replay := false

# camera: zoom 1 fits the whole canyon; cam_center is the world point at the view's centre
var zoom := 1.0
var fit_ppm := 30.0
var ppm := 30.0
var cam_center := Vector2.ZERO
var origin := Vector2.ZERO
var touches := {}                     # screen-touch index -> position (pinch zoom)
var gesture := false

# pointer
var drag_from := NONE                 # joint a line is being dragged from
var dragging := false                 # pointer moved far enough to count as a drag
var pressed := false
var press_empty := false              # press started on empty space (tap-to-build or pan)
var panning := false
var erase_stroke := false
var pan_last := Vector2.ZERO
var drag_pos := Vector2.ZERO
var press_pos := Vector2.ZERO
var selected := NONE                  # tap-tap building: where the next line starts
var auto_lock := true                 # line ends snap onto nearby joints (toggle, saved)
var loupe_caption := ""

# ui
var buttons: Array = []
var view_rect := Rect2()
var head_rect := Rect2()
var panel_rect := Rect2()
var help_rect := Rect2()
var dev_rect := Rect2()
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""
var anim_t := 0.0
var tut_open := false
var dev_mode := false                 # ?dev=1 or a debug build: shows the DEV button
var dev_open := false
var dev_sandbox := false              # after dev day-jumps / instant results: don't save
var dev_taps := 0
var dev_last_tap := -10.0
var font: Font
var ui := 1.0                         # UI scale: bigger on narrow (phone) screens


func _ready() -> void:
	font = ThemeDB.fallback_font
	_add_key_action("go", [KEY_ENTER, KEY_SPACE])
	_add_key_action("undo", [KEY_Z, KEY_BACKSPACE])
	_add_key_action("tool_road", [KEY_1])
	_add_key_action("tool_wood", [KEY_2])
	_add_key_action("tool_erase", [KEY_3])
	_add_key_action("zoom_in", [KEY_EQUAL, KEY_KP_ADD])
	_add_key_action("zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT])
	_add_key_action("dev", [KEY_QUOTELEFT])
	today = Time.get_date_string_from_system(false)
	var want := today
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	var d := String(url.get("day", ""))
	if d == "":
		d = String(url.get("d", ""))
	dev_mode = String(url.get("dev", "")) == "1" or (OS.is_debug_build() and not OS.has_feature("web"))
	# Links always open today's bridge; past days are picked in-game. Only ?dev=1 honours ?day= / ?s=.
	if String(url.get("dev", "")) == "1":
		if _valid_date(d):
			want = d
		var s := String(url.get("s", ""))
		target_score = int(s) if s.is_valid_int() else -1
	elif d != "" or String(url.get("s", "")) != "":
		_clean_url()
	load_puzzle(want)
	_load_prefs()
	if not tutorial_seen() and String(url.get("dev", "")) != "1":
		open_tutorial()


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------------ puzzle

func _valid_date(d: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(d) == null:
		return false
	return d >= EPOCH and d <= today


func day_number(d: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(EPOCH + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(d + "T00:00:00")
	return int(round((b - a) / 86400.0)) + 1


func load_puzzle(d: String) -> void:
	date = d
	puzzle_no = day_number(d)
	generate(d)
	design = []
	history = []
	tries = []
	finished = false
	last_loads = {}
	selected = NONE
	drag_from = NONE
	dragging = false
	show_ideal = false
	sim = null
	_is_replay = false
	zoom = 1.0
	cam_center = _fit_center()
	_load_state()
	_start_ideal_search()
	phase = Phase.FINAL if finished else Phase.BUILD
	if finished:
		_show_best()


func generate(d: String) -> void:
	lv = BridgeSim.make_level(d)
	gap = int(lv.gap)
	dy = int(lv.dy)
	vehicle_i = int(lv.vehicle)
	anchors = lv.anchors


func level() -> Dictionary:
	return lv


func vehicle() -> Dictionary:
	return BridgeSim.VEHICLES[vehicle_i]


# ------------------------------------------------------------------ ideal bridge

func _ideal_cache_path() -> String:
	return "user://bridge_ideal_%s_%s.json" % [IDEAL_VERSION, date]


func _start_ideal_search() -> void:
	ideal = -1
	ideal_design = []
	ideal_search = null
	var idx := ideal_index_for(date)
	if idx >= 0:
		var cands := BridgeSim.candidates(lv)
		if idx < cands.size():
			ideal_design = cands[idx]
			ideal = BridgeSim.design_cost(ideal_design)
			return
	if FileAccess.file_exists(_ideal_cache_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_ideal_cache_path()))
		if data is Dictionary and int(data.get("cost", -1)) > 0:
			ideal = int(data.cost)
			ideal_design = _unpack(data.get("design", []))
			return
	ideal_search = BridgeSim.IdealSearch.new(lv)


static var _ideals := {}


## Precomputed ideal for a day (index into BridgeSim.candidates), or -1 when not in the table.
## tools/precompute_ideals.gd writes ideals.json; days past it are searched in-game.
static func ideal_index_for(d: String) -> int:
	if _ideals.is_empty() and FileAccess.file_exists("res://ideals.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://ideals.json"))
		if data is Dictionary:
			_ideals = data
	return int(_ideals.get(d, -1))


## Work on the ideal search for about `usec` microseconds (it runs in the background).
func _advance_ideal(usec: int) -> void:
	if ideal_search == null:
		return
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < usec:
		if ideal_search.step(3):
			_ideal_found()
			return


func _ideal_found() -> void:
	ideal = ideal_search.cost
	ideal_design = ideal_search.design
	ideal_search = null
	if ideal > 0:
		var f := FileAccess.open(_ideal_cache_path(), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"cost": ideal, "design": _pack(ideal_design)}))


## Finish the ideal search right now (tests, sharing).
func ensure_ideal() -> void:
	if ideal_search != null:
		ideal_search.run()
		_ideal_found()


# ------------------------------------------------------------------ building

func cost() -> int:
	return BridgeSim.design_cost(design)


func joints() -> Array:
	var seen := {}
	var out: Array = []
	for a in anchors:
		seen[a] = true
		out.append(a)
	for b in design:
		for g: Vector2i in [b.p, b.q]:
			if not seen.has(g):
				seen[g] = true
				out.append(g)
	return out


func is_joint(g: Vector2i) -> bool:
	if anchors.has(g):
		return true
	for b in design:
		if b.p == g or b.q == g:
			return true
	return false


static func _key(p: Vector2i, q: Vector2i) -> String:
	if p.x > q.x or (p.x == q.x and p.y > q.y):
		var t := p
		p = q
		q = t
	return "%d,%d,%d,%d" % [p.x, p.y, q.x, q.y]


func beam_index(p: Vector2i, q: Vector2i) -> int:
	var k := _key(p, q)
	for i in design.size():
		if _key(design[i].p, design[i].q) == k:
			return i
	return -1


## True when segment p-q lies along an existing beam (building it would overlap).
func _covered(p: Vector2i, q: Vector2i) -> bool:
	for b in design:
		var a := Vector2(b.p)
		var c := Vector2(b.q)
		if Geometry2D.get_closest_point_to_segment(Vector2(p), a, c).distance_to(Vector2(p)) <= 1.5 \
				and Geometry2D.get_closest_point_to_segment(Vector2(q), a, c).distance_to(Vector2(q)) <= 1.5:
			return true
	return false


## Why a joint can't go at g ("" when it can).
func point_problem(g: Vector2i) -> String:
	if anchors.has(g):
		return ""
	var w := BridgeSim.wpos(g)
	if w.x < -2.0 or w.x > gap + 2.0 or w.y < -6.0 or w.y > BridgeSim.WATER_Y - 0.5:
		return "Out of the build area"
	if BridgeSim.in_rock(lv, w):
		return "That's solid rock"
	return ""


## Why a single beam p→q can't be built ("" when it can).
func beam_problem(p: Vector2i, q: Vector2i) -> String:
	if p == q:
		return "Pick a different point"
	if BridgeSim.wpos(p).distance_to(BridgeSim.wpos(q)) > BridgeSim.MAX_LEN + 0.001:
		return "Too long — pieces reach %d m at most" % int(BridgeSim.MAX_LEN)
	var pp := point_problem(p)
	if pp == "":
		pp = point_problem(q)
	if pp != "":
		return pp
	if beam_index(p, q) >= 0:
		return "There's already a beam there"
	return ""


## Plan a straight line from a to b, split into equal pieces no longer than `plen` metres
## (a 7 m line in 2 m pieces = 4 x 1.75 m), so any angle works and the joints between pieces
## can sit between grid dots. Existing joints the line passes over become break points, and
## stretches already built are skipped. Returns {pieces: [[p, q], ...], why: ""}.
func plan_line(a: Vector2i, b: Vector2i, plen: int = -1) -> Dictionary:
	if plen < 0:
		plen = piece_len
	var out := {"pieces": [], "why": ""}
	if a == b:
		out.why = "Pick a different point"
		return out
	if not is_joint(a) and is_joint(b):
		var t := a
		a = b
		b = t
	var ab := Vector2(b - a)
	var ab_len2 := ab.length_squared()
	var stops := {0.0: a, 1.0: b}
	for p in joints():
		var t := Vector2(p - a).dot(ab) / ab_len2
		if t <= 1e-6 or t >= 1.0 - 1e-6:
			continue
		if (Vector2(a) + ab * t).distance_to(Vector2(p)) <= 1.5:
			stops[t] = p
	var ts: Array = stops.keys()
	ts.sort()
	var any_new := false
	for i in ts.size() - 1:
		var p0: Vector2i = stops[ts[i]]
		var p1: Vector2i = stops[ts[i + 1]]
		if beam_index(p0, p1) >= 0:
			continue
		var n := maxi(1, ceili(BridgeSim.wpos(p0).distance_to(BridgeSim.wpos(p1)) / float(plen) - 1e-6))
		var prev := p0
		for k in range(1, n + 1):
			var f := float(k) / n
			var q := p1 if k == n else Vector2i(roundi(p0.x + (p1.x - p0.x) * f), roundi(p0.y + (p1.y - p0.y) * f))
			if not _covered(prev, q):
				for g: Vector2i in [prev, q]:
					var why := point_problem(g)
					if why != "":
						out.why = why
						out.pieces = []
						return out
				out.pieces.append([prev, q])
				any_new = true
			prev = q
	if not any_new:
		out.why = "There's already a beam there"
	return out


func path_problem(a: Vector2i, b: Vector2i) -> String:
	return plan_line(a, b).why


## Build a line as pieces of up to piece_len metres (one undo step).
func add_path(a: Vector2i, b: Vector2i, m: int) -> bool:
	if phase != Phase.BUILD:
		return false
	var plan := plan_line(a, b)
	if plan.why != "":
		_toast(plan.why)
		return false
	_push_history()
	for pq in plan.pieces:
		design.append(BridgeSim.beam(pq[0], pq[1], m))
	_design_changed()
	return true


## Build a single beam (tests, dev tools).
func add_beam(p: Vector2i, q: Vector2i, m: int) -> bool:
	if phase != Phase.BUILD:
		return false
	var why := beam_problem(p, q)
	if why != "":
		_toast(why)
		return false
	_push_history()
	design.append(BridgeSim.beam(p, q, m))
	_design_changed()
	return true


## Grid dot (whole metres) as a build point.
static func dot(x: int, y: int) -> Vector2i:
	return Vector2i(x * U, y * U)


func set_piece_len(n: int) -> void:
	if PIECE_LENGTHS.has(n):
		piece_len = n


func remove_beam(i: int) -> void:
	if i < 0 or i >= design.size() or phase != Phase.BUILD:
		return
	_push_history()
	design.remove_at(i)
	if not is_joint(selected):
		selected = NONE
	_design_changed()


## Erase tool: remove the beam under screen point p. One undo step per stroke.
func erase_at(p: Vector2) -> bool:
	if phase != Phase.BUILD:
		return false
	var i := _beam_at(p)
	if i < 0:
		return false
	if not erase_stroke:
		_push_history()
		erase_stroke = true
	design.remove_at(i)
	if not is_joint(selected):
		selected = NONE
	_design_changed()
	return true


func undo() -> void:
	if phase != Phase.BUILD or history.is_empty():
		return
	design = history.pop_back()
	if not is_joint(selected):
		selected = NONE
	_design_changed()


func clear_design() -> void:
	if phase != Phase.BUILD or design.is_empty():
		return
	_push_history()
	design = []
	selected = NONE
	_design_changed()


func set_design(d: Array) -> void:
	design = []
	for b in d:
		design.append(BridgeSim.beam(b.p, b.q, int(b.m)))
	_design_changed()


func _push_history() -> void:
	history.append(design.duplicate(true))
	if history.size() > MAX_HISTORY:
		history.pop_front()


func _design_changed() -> void:
	_save_state()


func set_tool(t: int) -> void:
	tool = t
	if t == Tool.ERASE:
		selected = NONE


# ------------------------------------------------------------------ attempts + score

func tries_left() -> int:
	return MAX_TRIES - tries.size()


func can_go() -> bool:
	return phase == Phase.BUILD and tries_left() > 0 and not design.is_empty()


func go() -> void:
	if phase != Phase.BUILD:
		return
	if design.is_empty():
		_toast("Build something first")
		return
	if tries_left() <= 0:
		return
	_start_sim(design)
	selected = NONE


func _start_sim(d: Array) -> void:
	sim_design = d.duplicate(true)
	sim = BridgeSim.new()
	sim.setup(lv, sim_design)
	sim_acc = 0.0
	splash_t = -1.0
	phase = Phase.RUN


## Run a design to the end without touching game state (tests, previews).
func simulate(d: Array) -> Dictionary:
	var s := BridgeSim.new()
	s.setup(lv, d)
	return s.run_to_end()


func _sim_frame() -> void:
	sim.step_frame()
	if sim.outcome == "splash" and splash_t < 0.0:
		splash_t = 0.0
		var w := sim.w0 if sim.py[sim.w0] > sim.py[sim.w1] else sim.w1
		splash_at = Vector2(sim.px[w], BridgeSim.WATER_Y)
	if sim.done:
		_finish_try()


## Fast-forward the current run to its end.
func skip() -> void:
	if phase != Phase.RUN:
		return
	while phase == Phase.RUN:
		_sim_frame()


func _finish_try() -> void:
	if _is_replay:
		_is_replay = false
		phase = Phase.FINAL if finished else Phase.RESULT
		return
	var r := sim.summary()
	tries.append({"crossed": bool(r.crossed), "outcome": String(r.outcome),
		"cost": BridgeSim.design_cost(sim_design), "snapped": int(r.snapped), "design": _pack(sim_design)})
	last_loads = {}
	for b in sim.ba.size():
		var d: Dictionary = sim_design[b]
		last_loads[_key(d.p, d.q)] = {"load": sim.peak[b], "broken": sim.broken[b] == 1}
	if tries.size() >= MAX_TRIES:
		finished = true
	phase = Phase.RESULT
	_save_state()


## Watch a run again without using an attempt: the last attempt, or on the final screen
## your best bridge or (when shown) the ideal one.
func replay() -> void:
	if phase != Phase.RESULT and phase != Phase.FINAL:
		return
	var d: Array = []
	if phase == Phase.FINAL:
		if show_ideal:
			d = ideal_design
		elif not best_try().is_empty():
			d = _unpack(best_try().design)
		elif not tries.is_empty():
			d = _unpack(tries.back().design)
	elif not tries.is_empty():
		d = _unpack(tries.back().design)
	if d.is_empty():
		return
	_is_replay = true
	_start_sim(d)


## Back to the drawing board after an attempt (the bridge is kept).
func repair() -> void:
	if phase != Phase.RESULT or tries_left() <= 0:
		return
	phase = Phase.BUILD
	sim = null


func finish() -> void:
	finished = true
	_save_state()
	phase = Phase.FINAL
	ensure_ideal()
	_show_best()
	_mark_played()


func _show_best() -> void:
	var t := best_try()
	if t.is_empty() and not tries.is_empty():
		t = tries.back()
	sim = null
	if not t.is_empty():
		design = _unpack(t.design)


## Final screen: flip between your best bridge and the ideal one.
func toggle_ideal() -> void:
	if phase != Phase.FINAL:
		return
	ensure_ideal()
	show_ideal = not show_ideal and not ideal_design.is_empty()
	sim = null


func shown_design() -> Array:
	return ideal_design if phase == Phase.FINAL and show_ideal else design


## The crossing that used the least material.
func best_try() -> Dictionary:
	var best := {}
	for t in tries:
		if t.crossed and (best.is_empty() or int(t.cost) < int(best.cost)):
			best = t
	return best


## 100 at the ideal bridge, toward 0 the more material you use, over 100 if you beat it.
func score_for(material: int) -> int:
	if ideal <= 0:
		return -1
	return roundi(100.0 * ideal / maxf(1.0, material))


func try_score(t: Dictionary) -> int:
	return score_for(int(t.cost)) if t.crossed else 0


func best_score() -> int:
	var b := best_try()
	return try_score(b) if not b.is_empty() else 0


func _pack(d: Array) -> Array:
	var out: Array = []
	for b in d:
		var p: Vector2i = b.p
		var q: Vector2i = b.q
		out.append([p.x, p.y, q.x, q.y, int(b.m)])
	return out


func _unpack(a: Array) -> Array:
	var out: Array = []
	for e in a:
		if e is Array and e.size() == 5:
			out.append(BridgeSim.beam(Vector2i(int(e[0]), int(e[1])), Vector2i(int(e[2]), int(e[3])), int(e[4])))
	return out


# ------------------------------------------------------------------ saving (user:// is IndexedDB on the web)

func _save_path() -> String:
	return "user://%s%s.json" % [SAVE_PREFIX, date]


func _save_state() -> void:
	if dev_sandbox:
		return
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"design": _pack(design), "tries": tries, "finished": finished}))


func _load_state() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if not data is Dictionary:
		return
	design = _unpack(data.get("design", []))
	for t in data.get("tries", []):
		if t is Dictionary:
			tries.append({"crossed": bool(t.get("crossed", false)), "outcome": String(t.get("outcome", "")),
				"cost": int(t.get("cost", 0)), "snapped": int(t.get("snapped", 0)), "design": t.get("design", [])})
	finished = bool(data.get("finished", false)) or tries.size() >= MAX_TRIES


## Forget this day's progress (used by tests and dev).
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

## Always the plain game URL, so an old share still opens on today's bridge.
func share_link() -> String:
	return base_url


## Remembers the day's score for the past-days picker and the GameTests home page.
func _mark_played() -> void:
	if dev_sandbox:
		return
	var label := "Score %d" % maxi(0, best_score())
	_record_result(date, label)
	if OS.has_feature("web"):
		var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
			JSON.stringify("gametests:daily-bridge:" + date), JSON.stringify(JSON.stringify({"result": label}))]
		JavaScriptBridge.eval(js, true)


# ------------------------------------------------------------------ past days

const ARCHIVE_ROWS := 7
var archive_open := false
var archive_page := 0
var archive_results: Dictionary = {}
var cal_rect := Rect2()


## Drops ?day= (and anything else) from the address bar so a refresh stays on today.
func _clean_url() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{history.replaceState(null,'',location.pathname)}catch(e){}", true)


func archive_count() -> int:
	return maxi(1, day_number(today))


func archive_pages() -> int:
	return ceili(float(archive_count()) / ARCHIVE_ROWS)


## The days on one page of the picker, newest first (page 0 starts with today).
func archive_page_days(page: int) -> Array:
	var out: Array = []
	for i in range(page * ARCHIVE_ROWS, mini((page + 1) * ARCHIVE_ROWS, archive_count())):
		out.append(shift_date(today, -i))
	return out


func open_archive() -> void:
	if phase == Phase.RUN:
		return
	archive_results = _picker_results()
	var idx := clampi(day_number(today) - day_number(date), 0, archive_count() - 1)
	archive_page = int(idx / ARCHIVE_ROWS)
	archive_open = true
	_build_buttons()


func archive_shift(pages: int) -> void:
	archive_page = clampi(archive_page + pages, 0, archive_pages() - 1)
	_build_buttons()


## Opens a past (or today's) bridge from the picker. Always real play, never the dev sandbox.
func pick_day(d: String) -> void:
	archive_open = false
	if d < EPOCH or d > today:
		_build_buttons()
		return
	if d != date or dev_sandbox:
		dev_sandbox = false
		target_score = -1
		load_puzzle(d)
	_build_buttons()


func _results_path() -> String:
	return "user://bridge_results.json"


func _load_results() -> Dictionary:
	var out: Dictionary = {}
	if FileAccess.file_exists(_results_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_results_path()))
		if data is Dictionary:
			out = data
	return out


## Recorded results, plus days with a save from before results were kept.
func _picker_results() -> Dictionary:
	var out := _load_results()
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	var re := RegEx.create_from_string("^" + SAVE_PREFIX + "(\\d{4}-\\d{2}-\\d{2})\\.json$")
	for f in dir.get_files():
		var m := re.search(f)
		if m == null or out.has(m.get_string(1)):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://" + f))
		if not data is Dictionary or (data.get("tries", []).is_empty() and data.get("design", []).is_empty()):
			continue
		var done: bool = data.get("finished", false) or data.get("tries", []).size() >= MAX_TRIES
		out[m.get_string(1)] = "Played" if done else "In progress"
	return out


func _record_result(d: String, label: String) -> void:
	var all := _load_results()
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
	return clampf((vs.y - 40.0 - 170.0 * ui) / ARCHIVE_ROWS, 44.0 * ui, 60.0 * ui)


func _archive_card() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 24.0, 560.0 * ui)
	var h := 70.0 * ui + ARCHIVE_ROWS * _archive_row_h() + 80.0 * ui
	return Rect2((vs.x - w) * 0.5, maxf(12.0, (vs.y - h) * 0.5), w, h)


func _archive_buttons() -> void:
	var c := _archive_card()
	var rh := _archive_row_h()
	var days := archive_page_days(archive_page)
	for i in days.size():
		_btn("day_" + String(days[i]), Rect2(c.position.x + 16, c.position.y + 70 * ui + i * rh, c.size.x - 32, rh - 8), "", false, true, false, "row")
	var bw := (c.size.x - 32 - 20) / 3.0
	var by := c.end.y - 66 * ui
	_btn("arch_newer", Rect2(c.position.x + 16, by, bw, 50 * ui), "< Newer", false, archive_page > 0)
	_btn("arch_close", Rect2(c.position.x + 26 + bw, by, bw, 50 * ui), "Close", true)
	_btn("arch_older", Rect2(c.position.x + 36 + bw * 2, by, bw, 50 * ui), "Older >", false, archive_page < archive_pages() - 1)


func _draw_archive() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var c := _archive_card()
	_box(c, Color(0.96, 0.97, 0.98), 16)
	_text("Past bridges", c.position + Vector2(20, 44 * ui), 24, C_INK)
	_text("Page %d of %d" % [archive_page + 1, archive_pages()], Vector2(c.position.x, c.position.y + 42 * ui), 14, C_MUTED,
		HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 20)
	for b in buttons:
		if b.kind == "row":
			var d := String(b.id).substr(4)
			var r: Rect2 = b.rect
			_box(r, C_BTN, 10, C_BTN_PRIMARY if d == date and not dev_sandbox else Color(0, 0, 0, 0))
			var mid := r.get_center().y + 6 * ui
			_text("#%d" % day_number(d), Vector2(r.position.x + 14, mid), 17, C_BTN_PRIMARY)
			_text("Today" if d == today else _short_date(d), Vector2(r.position.x + 14 + 62 * ui, mid), 17, C_INK)
			var res := String(archive_results.get(d, ""))
			_text(res if res != "" else "Not played", Vector2(r.position.x, mid), 16 if res != "" else 14,
				C_GOOD if res != "" else C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14)
		else:
			_draw_button(b)


## Calendar glyph for the past-days button.
func _draw_calendar(c: Vector2, col_: Color) -> void:
	var k := ui
	var r := Rect2(c.x - 9 * k, c.y - 8 * k, 18 * k, 17 * k)
	draw_rect(r, col_, false, 1.8 * k)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5 * k), col_)
	draw_line(Vector2(c.x - 4.5 * k, c.y - 11 * k), Vector2(c.x - 4.5 * k, c.y - 6 * k), col_, 1.8 * k)
	draw_line(Vector2(c.x + 4.5 * k, c.y - 11 * k), Vector2(c.x + 4.5 * k, c.y - 6 * k), col_, 1.8 * k)
	for i in 3:
		draw_rect(Rect2(c.x + (-6.5 + i * 4.5) * k, c.y + 1.5 * k, 3 * k, 3 * k), col_)


func share_text() -> String:
	ensure_ideal()
	var lines := PackedStringArray()
	lines.append("Daily Bridge #%d 🌉 %s" % [puzzle_no, date])
	lines.append("%s across %d m" % [String(vehicle().name), gap])
	var marks := PackedStringArray()
	for t in tries:
		marks.append("✅" if t.crossed else "💥")
	var best := best_score()
	if not best_try().is_empty():
		lines.append("Score %d" % best)
	else:
		lines.append("Score 0 — didn't make it across")
	lines.append("Attempts: " + " ".join(marks))
	if target_score > 0:
		if best > target_score:
			lines.append("Beat the %d I was sent 🏆" % target_score)
		else:
			lines.append("Couldn't beat %d — can you?" % target_score)
	lines.append("Can you beat it? " + share_link())
	return "\n".join(lines)


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__bridgeShare='pending';
			var done=function(r){if(window.__bridgeShare==='pending'){window.__bridgeShare=r;}};
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
					setTimeout(function(){if(window.__bridgeShare==='pending'){ask();}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},ask);
				}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__bridgeCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__bridgeCopyNext=true;done('share_failed');}
				});
			}else{window.__bridgeCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied! Paste it anywhere")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__bridgeShare||''", true)
	if typeof(r) != TYPE_STRING or r == "pending" or r == "":
		return
	share_pending = false
	match r:
		"copied": _toast("Copied! Result + link ready to paste")
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
		return JSON.stringify({day:p.get('day')||'',d:p.get('d')||'',s:p.get('s')||'',dev:p.get('dev')||'',base:location.origin+location.pathname});})()""", true)
	if typeof(r) != TYPE_STRING:
		return {}
	var d = JSON.parse_string(r)
	return d if d is Dictionary else {}


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 2.6


# ------------------------------------------------------------------ tutorial + dev

func open_tutorial() -> void:
	tut_open = true


func close_tutorial() -> void:
	tut_open = false
	var f := FileAccess.open(TUT_FLAG, FileAccess.WRITE)
	if f:
		f.store_string("1")


func tutorial_seen() -> bool:
	return FileAccess.file_exists(TUT_FLAG)


func _dev_tap() -> void:
	dev_taps = dev_taps + 1 if anim_t - dev_last_tap < 0.6 else 1
	dev_last_tap = anim_t
	if dev_taps >= 5:
		dev_taps = 0
		dev_mode = true
		dev_open = true


static func shift_date(d: String, days: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(d + "T00:00:00") + days * 86400)


## Dev: jump to any day (past or future). Results from here on aren't saved.
func dev_set_day(d: String) -> void:
	dev_sandbox = true
	load_puzzle(d)
	dev_open = false
	_toast("Dev: %s (results not saved)" % d)


func dev_random_day() -> void:
	dev_set_day(shift_date(EPOCH, randi_range(0, 730)))


func dev_reset_today() -> void:
	var sb := dev_sandbox
	dev_sandbox = false
	wipe_save()
	dev_sandbox = sb
	load_puzzle(date)
	dev_open = false
	_toast("Dev: this day's progress reset")


func dev_reset_all() -> void:
	var n := 0
	var dir := DirAccess.open("user://")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json") and (f.begins_with(SAVE_PREFIX) or f.begins_with("bridge_")):
				_wipe_file("user://" + f)
				n += 1
	_wipe_file(TUT_FLAG)
	_flush_storage()
	load_puzzle(date)
	dev_open = false
	_toast("Dev: cleared %d saved file(s) + tutorial" % n)


func dev_load_reference() -> void:
	dev_open = false
	ensure_ideal()
	if phase != Phase.BUILD or ideal_design.is_empty():
		return
	_push_history()
	set_design(ideal_design)
	_toast("Dev: loaded the ideal bridge")


## Dev: jump straight to the end screen with a crossing at the ideal (score 100). Not saved.
func dev_win() -> void:
	ensure_ideal()
	dev_sandbox = true
	dev_open = false
	sim = null
	tries = [{"crossed": true, "outcome": "crossed", "cost": ideal, "snapped": 0, "design": _pack(ideal_design)}]
	finish()


## Dev: jump to the end screen with three failed attempts. Not saved.
func dev_lose() -> void:
	dev_sandbox = true
	dev_open = false
	sim = null
	tries = []
	for i in MAX_TRIES:
		tries.append({"crossed": false, "outcome": "splash", "cost": 0, "snapped": 0, "design": []})
	finish()


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	anim_t += delta
	if toast_t > 0.0:
		toast_t -= delta
	if share_pending:
		_poll_share()
	if splash_t >= 0.0:
		splash_t += delta
	if phase == Phase.RUN and sim != null:
		sim_acc += delta * (4.0 if fast else 1.0)
		var n := 0
		while sim_acc >= BridgeSim.FRAME_DT and phase == Phase.RUN and n < 16:
			sim_acc -= BridgeSim.FRAME_DT
			_sim_frame()
			n += 1
		if n >= 16:
			sim_acc = 0.0
	else:
		_advance_ideal(8000)
	if Input.is_action_just_pressed("dev") and dev_mode:
		dev_open = not dev_open
	if not tut_open and not dev_open:
		if Input.is_action_just_pressed("go"):
			match phase:
				Phase.BUILD: go()
				Phase.RUN: fast = not fast
				Phase.RESULT:
					if tries_left() > 0 and not (tries.back().crossed):
						repair()
		if Input.is_action_just_pressed("zoom_in"):
			zoom_at(view_rect.get_center(), 1.4)
		if Input.is_action_just_pressed("zoom_out"):
			zoom_at(view_rect.get_center(), 1.0 / 1.4)
		if phase == Phase.BUILD:
			if Input.is_action_just_pressed("undo"):
				undo()
			if Input.is_action_just_pressed("tool_road"):
				set_tool(Tool.ROAD)
			if Input.is_action_just_pressed("tool_wood"):
				set_tool(Tool.WOOD)
			if Input.is_action_just_pressed("tool_erase"):
				set_tool(Tool.ERASE)
	elif tut_open and Input.is_action_just_pressed("go"):
		close_tutorial()
	_layout()
	queue_redraw()


# ------------------------------------------------------------------ camera

func w2s(v: Vector2) -> Vector2:
	return origin + v * ppm


func s2w(p: Vector2) -> Vector2:
	return (p - origin) / ppm


func gpos(g: Vector2i) -> Vector2:
	return w2s(BridgeSim.wpos(g))


func _world_min() -> Vector2:
	return Vector2(-4.5, -6.2)


func _world_max() -> Vector2:
	return Vector2(gap + 4.5, BridgeSim.WATER_Y + 1.0)


func _fit_center() -> Vector2:
	return (_world_min() + _world_max()) * 0.5


func zoom_at(p: Vector2, factor: float) -> void:
	var w := s2w(p)
	zoom = clampf(zoom * factor, 1.0, ZOOM_MAX)
	ppm = fit_ppm * zoom
	var c := view_rect.get_center()
	cam_center = w - (p - c) / ppm          # keep world point w under the pointer
	_clamp_camera()
	_apply_camera()


func zoom_reset() -> void:
	zoom = 1.0
	cam_center = _fit_center()
	_apply_camera()


func _pan_by(screen_delta: Vector2) -> void:
	cam_center -= screen_delta / ppm
	_clamp_camera()
	_apply_camera()


func _clamp_camera() -> void:
	var hw := view_rect.size.x / (2.0 * ppm)
	var hh := view_rect.size.y / (2.0 * ppm)
	var a := _world_min()
	var b := _world_max()
	cam_center.x = (a.x + b.x) / 2.0 if hw * 2.0 >= b.x - a.x - 1e-6 else clampf(cam_center.x, a.x + hw, b.x - hw)
	cam_center.y = (a.y + b.y) / 2.0 if hh * 2.0 >= b.y - a.y - 1e-6 else clampf(cam_center.y, a.y + hh, b.y - hh)


func _apply_camera() -> void:
	ppm = fit_ppm * zoom
	origin = view_rect.get_center() - cam_center * ppm


# ------------------------------------------------------------------ input

## Where a line ends for a pointer at p. With auto-lock on, existing joints (and anchors) pull
## the pointer in from up to LOCK_RADIUS / LOCK_PX away and beat a slightly closer grid dot;
## with it off, the nearest dot or joint under the pointer wins. `exclude` is skipped (the
## joint a line starts from).
func _snap(p: Vector2, exclude := NONE) -> Vector2i:
	var w := s2w(p)
	var node := NONE
	var dn := INF
	for g in joints():
		if g == exclude:
			continue
		var d := BridgeSim.wpos(g).distance_to(w)
		if d < dn:
			dn = d
			node = g
	var g := dot(roundi(w.x), roundi(w.y))
	var dd := BridgeSim.wpos(g).distance_to(w)
	var dot_ok := g != exclude
	if auto_lock:
		var reach := maxf(LOCK_RADIUS, LOCK_PX / ppm)
		if node != NONE and dn <= reach and (not dot_ok or dn <= dd + LOCK_BIAS):
			return node
	elif node != NONE and dn <= maxf(0.3, 16.0 / ppm) and (not dot_ok or dn <= dd):
		return node
	return g


## True when a line end is locked onto an existing joint rather than a free grid dot.
func is_locked_target(g: Vector2i) -> bool:
	return g != NONE and is_joint(g)


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


## Nearest joint to a screen point, within a finger's reach (a little further with auto-lock).
func _joint_at(p: Vector2) -> Vector2i:
	var best := NONE
	var bd := maxf(24.0 * ui, ppm * 0.35)
	if auto_lock:
		bd = maxf(32.0 * ui, ppm * 0.45)
	for g in joints():
		var d := gpos(g).distance_to(p)
		if d < bd:
			bd = d
			best = g
	return best


func _beam_at(p: Vector2) -> int:
	var best := -1
	var bd := maxf(16.0 * ui, ppm * 0.25)
	for i in design.size():
		var b: Dictionary = design[i]
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, gpos(b.p), gpos(b.q)))
		if d < bd:
			bd = d
			best = i
	return best


func _input(ev: InputEvent) -> void:
	if _camera_input(ev):
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			if not gesture:
				_on_press(p)
		else:
			if gesture:
				if touches.is_empty():
					gesture = false
				_end_pointer()
				return
			_on_release(p)
	elif ev is InputEventMouseMotion and not gesture:
		var p: Vector2 = make_input_local(ev).position
		drag_pos = p
		if not pressed or (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		if p.distance_to(press_pos) > 12.0:
			dragging = true
		if erase_stroke or (tool == Tool.ERASE and phase == Phase.BUILD and view_rect.has_point(press_pos)):
			# swipe: erase everything the pointer crosses
			var a := pan_last
			var steps := maxi(1, ceili(a.distance_to(p) / 6.0))
			for k in steps + 1:
				erase_at(a.lerp(p, float(k) / steps))
			pan_last = p
			return
		if press_empty and dragging and zoom > 1.01:
			panning = true
		if panning:
			_pan_by(p - pan_last)
		pan_last = p


## Zoom/pan input: mouse wheel, trackpad pinch/scroll, two-finger touch. True when consumed.
func _camera_input(ev: InputEvent) -> bool:
	if dev_open or tut_open:
		return false
	if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var p: Vector2 = make_input_local(ev).position
		if view_rect.has_point(p):
			zoom_at(p, 1.15 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
			return true
		return false
	if ev is InputEventMagnifyGesture:
		var p: Vector2 = make_input_local(ev).position
		zoom_at(p if view_rect.has_point(p) else view_rect.get_center(), ev.factor)
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
				if erase_stroke:
					undo()
				_end_pointer()
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


func _end_pointer() -> void:
	pressed = false
	drag_from = NONE
	dragging = false
	press_empty = false
	panning = false
	erase_stroke = false


func _on_press(p: Vector2) -> void:
	drag_pos = p
	press_pos = p
	pan_last = p
	if dev_open or tut_open or archive_open:
		_press_button(p)
		return
	if help_rect.grow(10).has_point(p):
		open_tutorial()
		return
	if cal_rect.grow(6).has_point(p):
		open_archive()
		return
	if dev_mode and dev_rect.has_point(p):
		dev_open = true
		return
	if Rect2(head_rect.position, Vector2(220 * ui, head_rect.size.y)).has_point(p):
		_dev_tap()
		return
	if _press_button(p):
		return
	if not view_rect.has_point(p):
		return
	pressed = true
	dragging = false
	if phase != Phase.BUILD:
		press_empty = true
		return
	if tool == Tool.ERASE:
		erase_stroke = false
		erase_at(p)
		return
	var j := _joint_at(p)
	if j != NONE:
		drag_from = j
	else:
		press_empty = true


func _on_release(p: Vector2) -> void:
	var was_drag := dragging
	var from := drag_from
	var empty := press_empty and not panning
	_end_pointer()
	if phase != Phase.BUILD or tool == Tool.ERASE:
		return
	if from != NONE:
		var q := _snap(p, from)
		if not was_drag or q == from:
			# a tap on a joint: build from the selection to it, or select it
			if selected != NONE and selected != from:
				if add_path(selected, from, tool):
					selected = from
			else:
				selected = NONE if selected == from else from
			return
		if add_path(from, q, tool):
			selected = q
		return
	if empty and not was_drag:
		if selected != NONE:
			var q := _snap(p, selected)
			if add_path(selected, q, tool):
				selected = q
		else:
			_toast("Start a line from a joint — drag from a dot")


# ------------------------------------------------------------------ buttons

func _press_button(p: Vector2) -> bool:
	for b in buttons:
		if b.rect.has_point(p):
			if b.enabled:
				_do(String(b.id))
			return true
	return false


func _do(id: String) -> void:
	if id.begins_with("day_"):
		pick_day(id.substr(4))
		return
	match id:
		"road": set_tool(Tool.ROAD)
		"wood": set_tool(Tool.WOOD)
		"erase": set_tool(Tool.ERASE)
		"undo": undo()
		"len1": set_piece_len(1)
		"len2": set_piece_len(2)
		"len3": set_piece_len(3)
		"len4": set_piece_len(4)
		"clear": clear_design()
		"go": go()
		"fast": fast = not fast
		"skip": skip()
		"repair": repair()
		"finish": finish()
		"replay": replay()
		"ideal": toggle_ideal()
		"share": share()
		"today": play_today()
		"arch_newer": archive_shift(-1)
		"arch_older": archive_shift(1)
		"arch_close":
			archive_open = false
			_build_buttons()
		"zoom_in": zoom_at(view_rect.get_center(), 1.5)
		"lock": set_auto_lock(not auto_lock)
		"zoom_out":
			if zoom / 1.5 <= 1.01:
				zoom_reset()
			else:
				zoom_at(view_rect.get_center(), 1.0 / 1.5)
		"tut_close": close_tutorial()
		"dev_prev": dev_set_day(shift_date(date, -1))
		"dev_next": dev_set_day(shift_date(date, 1))
		"dev_rand": dev_random_day()
		"dev_today": dev_set_day(today)
		"dev_reset": dev_reset_today()
		"dev_all": dev_reset_all()
		"dev_ref": dev_load_reference()
		"dev_win": dev_win()
		"dev_lose": dev_lose()
		"dev_close": dev_open = false


func _btn(id: String, r: Rect2, label: String, primary := false, enabled := true, on := false, kind := "") -> void:
	buttons.append({"id": id, "rect": r, "label": label, "primary": primary, "enabled": enabled, "on": on, "kind": kind})


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	ui = clampf(1.0 + (860.0 - vs.x) / 300.0, 1.0, 1.5)
	var m := 12.0
	var head_h := 64.0 * ui
	head_rect = Rect2(m, m, vs.x - m * 2, head_h)
	help_rect = Rect2(head_rect.end.x - 46 * ui, head_rect.position.y + (head_h - 40 * ui) * 0.5, 40 * ui, 40 * ui)
	cal_rect = Rect2(help_rect.position.x - 48 * ui, help_rect.position.y, 40 * ui, 40 * ui)
	var panel_h := 128.0 * ui
	panel_rect = Rect2(m, vs.y - panel_h - m, vs.x - m * 2, panel_h)
	view_rect = Rect2(0, head_rect.end.y + 4, vs.x, panel_rect.position.y - head_rect.end.y - 50 * ui)
	var wsize := _world_max() - _world_min()
	fit_ppm = minf(view_rect.size.x / wsize.x, view_rect.size.y / wsize.y)
	if zoom <= 1.0001:
		cam_center = _fit_center()
	ppm = fit_ppm * zoom
	_clamp_camera()
	_apply_camera()
	var ds := 34.0 * ui
	dev_rect = Rect2(view_rect.position.x + 8, view_rect.end.y - ds - 8, ds * 1.6, ds)
	_build_buttons()


func _build_buttons() -> void:
	buttons.clear()
	if tut_open:
		var card := _tut_card()
		_btn("tut_close", Rect2(card.position.x + 24, card.end.y - 70 * ui, card.size.x - 48, 50 * ui), "Start building", true)
		return
	if archive_open and not dev_open:
		_archive_buttons()
		return
	if dev_open:
		var card := _dev_card()
		var y := card.position.y + 92 * ui
		var bw := (card.size.x - 50) / 2.0
		var rows := [["dev_prev", "< Prev day", "dev_next", "Next day >"], ["dev_today", "Today", "dev_rand", "Random day"],
			["dev_win", "Instant win", "dev_lose", "Instant lose"], ["dev_ref", "Load ideal bridge", "dev_reset", "Reset this day"],
			["dev_all", "Reset everything", "dev_close", "Close"]]
		for row in rows:
			_btn(row[0], Rect2(card.position.x + 20, y, bw, 42 * ui), row[1])
			_btn(row[2], Rect2(card.position.x + 30 + bw, y, bw, 42 * ui), row[3], row[2] == "dev_close")
			y += 50 * ui
		return
	# zoom controls in the view's top-right corner
	var zs := 40.0 * ui
	var zx := view_rect.end.x - zs - 10
	var zy := view_rect.position.y + 8
	_btn("zoom_in", Rect2(zx, zy, zs, zs), "+", false, zoom < ZOOM_MAX - 0.01, false, "zoom")
	_btn("zoom_out", Rect2(zx, zy + zs + 6, zs, zs), "−", false, zoom > 1.01, false, "zoom")
	if phase == Phase.BUILD:
		_btn("lock", Rect2(zx - 14 * ui, zy + (zs + 6) * 2, zs + 14 * ui, zs), "LOCK", false, true, auto_lock, "zoom")
	var r := panel_rect
	var pad := 10.0
	var row_h := (r.size.y - pad * 3) / 2.0
	var y1 := r.position.y + pad
	var y2 := y1 + row_h + pad
	var x0 := r.position.x + pad
	var w := r.size.x - pad * 2
	match phase:
		Phase.BUILD:
			var bw := (w - pad * 3) / 4.0
			_btn("road", Rect2(x0, y1, bw, row_h), "Road", false, true, tool == Tool.ROAD)
			_btn("wood", Rect2(x0 + (bw + pad), y1, bw, row_h), "Wood", false, true, tool == Tool.WOOD)
			_btn("erase", Rect2(x0 + (bw + pad) * 2, y1, bw, row_h), "Erase", false, true, tool == Tool.ERASE)
			_btn("undo", Rect2(x0 + (bw + pad) * 3, y1, bw, row_h), "Undo", false, not history.is_empty())
			var cw := w * 0.17
			_btn("clear", Rect2(x0, y2, cw, row_h), "Clear", false, not design.is_empty())
			var sx := x0 + cw + pad
			var sw := w * 0.46
			var gap_px := 4.0
			var pw := (sw - gap_px * (PIECE_LENGTHS.size() - 1)) / PIECE_LENGTHS.size()
			for i in PIECE_LENGTHS.size():
				var n: int = PIECE_LENGTHS[i]
				_btn("len%d" % n, Rect2(sx + i * (pw + gap_px), y2, pw, row_h), "%d m" % n, false, tool != Tool.ERASE, piece_len == n)
			var gx := sx + sw + pad
			_btn("go", Rect2(gx, y2, x0 + w - gx, row_h), "Go!", true, can_go())
		Phase.RUN:
			var hw := (w - pad) / 2.0
			_btn("fast", Rect2(x0, y2, hw, row_h), "Speed: %s" % ("4x" if fast else "1x"), false, true, fast)
			_btn("skip", Rect2(x0 + hw + pad, y2, hw, row_h), "Skip to end")
		Phase.RESULT:
			var t: Dictionary = tries.back()
			var hw := (w - pad) / 2.0
			if tries_left() > 0:
				if t.crossed:
					_btn("repair", Rect2(x0, y2, hw, row_h), "Build cheaper", false)
					_btn("finish", Rect2(x0 + hw + pad, y2, hw, row_h), "Finish for today", true)
				else:
					_btn("replay", Rect2(x0, y2, hw * 0.7, row_h), "Replay")
					_btn("repair", Rect2(x0 + hw * 0.7 + pad, y2, w - hw * 0.7 - pad, row_h), "Repair the bridge", true)
			else:
				_btn("replay", Rect2(x0, y2, hw * 0.7, row_h), "Replay")
				_btn("finish", Rect2(x0 + hw * 0.7 + pad, y2, w - hw * 0.7 - pad, row_h), "See today's result", true)
		Phase.FINAL:
			var tw := (w - pad * 2) / 3.0
			if date != today and not dev_sandbox:
				_btn("today", Rect2(x0, y2, tw, row_h), "Today's bridge")
			else:
				_btn("replay", Rect2(x0, y2, tw, row_h), "Replay", false, not tries.is_empty() or show_ideal)
			_btn("ideal", Rect2(x0 + tw + pad, y2, tw, row_h), "Your bridge" if show_ideal else "Ideal bridge", false, true, show_ideal)
			_btn("share", Rect2(x0 + (tw + pad) * 2, y2, tw, row_h), "Share", true)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var vs := get_viewport_rect().size
	_draw_backdrop(vs)
	_draw_terrain()
	if phase == Phase.BUILD:
		_draw_build_grid()
	if sim != null:
		_draw_sim()
	else:
		_draw_design()
		_draw_vehicle_parked()
	_draw_water_front()
	_draw_header()
	_draw_panel()
	for b in buttons:
		if b.kind == "zoom":
			_draw_button(b)
	if loupe_active():
		_draw_loupe()
	if dev_mode and not dev_open and not tut_open:
		_box(dev_rect, Color(0.12, 0.16, 0.2, 0.7), 8)
		_text_c("DEV", dev_rect.get_center(), 13, Color.WHITE)
	if toast_t > 0.0 and toast != "":
		_draw_toast()
	if tut_open:
		_draw_tutorial()
	if archive_open and not dev_open:
		_draw_archive()
	if dev_open:
		_draw_dev()


func _draw_backdrop(vs: Vector2) -> void:
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)])
	draw_polygon(pts, PackedColorArray([C_SKY_TOP, C_SKY_TOP, C_SKY_LOW, C_SKY_LOW]))
	# far hills (slight parallax with the camera)
	var hills := PackedVector2Array()
	var base_y := w2s(Vector2(0, 1.5)).y
	var shift := (origin.x - view_rect.get_center().x) * 0.15
	hills.append(Vector2(0, vs.y))
	for i in 25:
		var x := vs.x * i / 24.0
		hills.append(Vector2(x, base_y - 40.0 - 26.0 * sin(i * 0.9 + 1.3 + shift * 0.01) - 14.0 * sin(i * 2.1)))
	hills.append(Vector2(vs.x, vs.y))
	draw_colored_polygon(hills, C_HILL)
	for c in [[0.18, 0.12, 1.0], [0.62, 0.08, 0.8], [0.86, 0.2, 0.6]]:
		var cx := fmod(vs.x * float(c[0]) + anim_t * 6.0 * float(c[2]), vs.x + 160.0) - 80.0
		var cy := head_rect.end.y + 20.0 + vs.y * float(c[1]) * 0.4
		var s := 22.0 * float(c[2]) + 10.0
		for k in [[-1.0, 0.2, 0.8], [0.0, 0.0, 1.0], [1.0, 0.25, 0.75]]:
			draw_circle(Vector2(cx + float(k[0]) * s, cy + float(k[1]) * s), s * float(k[2]), Color(1, 1, 1, 0.75))


func _draw_terrain() -> void:
	var vs := get_viewport_rect().size
	var g := float(gap)
	var d := float(dy)
	var deep := BridgeSim.WATER_Y + 4.0
	var wy := w2s(Vector2(0, BridgeSim.WATER_Y)).y
	draw_rect(Rect2(-10, wy, vs.x + 20, vs.y - wy + 20), C_WATER)
	var far_l := s2w(Vector2(-20, 0)).x - 1.0
	var far_r := s2w(Vector2(vs.x + 20, 0)).x + 1.0
	var left := PackedVector2Array([w2s(Vector2(far_l, 0)), w2s(Vector2(0, 0)), w2s(Vector2(0.15, 2.0)),
		w2s(Vector2(-0.1, 4.0)), w2s(Vector2(0.25, deep)), w2s(Vector2(far_l, deep))])
	var right := PackedVector2Array([w2s(Vector2(g, d)), w2s(Vector2(far_r, d)), w2s(Vector2(far_r, deep)),
		w2s(Vector2(g - 0.25, deep)), w2s(Vector2(g + 0.1, d + 4.0)), w2s(Vector2(g - 0.15, d + 2.0))])
	draw_colored_polygon(left, C_ROCK)
	draw_colored_polygon(right, C_ROCK)
	for strata in [1.2, 2.6, 4.2]:
		draw_line(w2s(Vector2(far_l, strata)), w2s(Vector2(-0.12, strata)), C_ROCK_DARK, 2.0)
		draw_line(w2s(Vector2(g + 0.12, d + strata)), w2s(Vector2(far_r, d + strata)), C_ROCK_DARK, 2.0)
	var gh := ppm * 0.22
	draw_rect(Rect2(w2s(Vector2(far_l, 0)) - Vector2(0, 2), Vector2(w2s(Vector2(0, 0)).x - w2s(Vector2(far_l, 0)).x, gh)), C_GRASS)
	draw_rect(Rect2(w2s(Vector2(g, d)) - Vector2(0, 2), Vector2(w2s(Vector2(far_r, d)).x - w2s(Vector2(g, d)).x, gh)), C_GRASS)
	for r: Rect2 in lv.get("rocks", []):
		var bot := minf(r.end.y, deep)
		var pts := PackedVector2Array([w2s(r.position), w2s(Vector2(r.end.x, r.position.y)),
			w2s(Vector2(r.end.x + (0.25 if r.size.y > 3 else 0.0), bot)), w2s(Vector2(r.position.x - (0.25 if r.size.y > 3 else 0.0), bot))])
		draw_colored_polygon(pts, C_ROCK)
		draw_line(w2s(r.position), w2s(Vector2(r.end.x, r.position.y)), C_ROCK_DARK, 3.0)


func _draw_water_front() -> void:
	var vs := get_viewport_rect().size
	var wy := w2s(Vector2(0, BridgeSim.WATER_Y)).y
	var x := -20.0
	while x < vs.x + 20:
		var o := sin(anim_t * 1.6 + x * 0.05) * 3.0
		draw_line(Vector2(x, wy + 6 + o), Vector2(x + 18, wy + 6 + o), C_WATER_HI, 2.0)
		x += 44.0
	if splash_t >= 0.0 and splash_t < 1.6:
		var p := w2s(splash_at)
		for i in 9:
			var a := PI + PI * (i + 0.5) / 9.0
			var t := splash_t * 2.2
			var dd := Vector2(cos(a) * 1.6, sin(a) * 3.2) * t * ppm * 0.6
			dd.y += 0.5 * 9.8 * t * t * ppm * 0.18
			draw_circle(p + dd, maxf(1.0, ppm * 0.12 * (1.0 - splash_t / 1.6)), Color(1, 1, 1, 0.85 - splash_t * 0.5))


func _draw_build_grid() -> void:
	var r := maxf(1.5, ppm * 0.05)
	for y in range(-6, int(BridgeSim.WATER_Y)):
		for x in range(-2, gap + 3):
			var g := dot(x, y)
			if point_problem(g) == "":
				draw_circle(gpos(g), r, C_DOT)
	loupe_caption = ""
	if drag_from != NONE and dragging and tool != Tool.ERASE:
		var q := _snap(drag_pos, drag_from)
		var plan := plan_line(drag_from, q) if q != drag_from else {"pieces": [], "why": "x"}
		var ok: bool = plan.why == ""
		var col := (C_ROAD if tool == Tool.ROAD else C_WOOD) if ok else C_BAD
		col.a = 0.75
		draw_line(gpos(drag_from), gpos(q), col, _beam_w(tool))
		var n := 0
		for pq in plan.pieces:
			n += 1
			for g: Vector2i in [pq[0], pq[1]]:
				var c := gpos(g)
				draw_circle(c, maxf(5.0, ppm * 0.15), C_INK)
				draw_circle(c, maxf(3.5, ppm * 0.11), C_JOINT)
		if not ok:
			draw_circle(gpos(q), maxf(5.0, ppm * 0.15), C_BAD)
		elif is_locked_target(q):
			draw_arc(gpos(q), maxf(10.0, ppm * 0.3), 0, TAU, 28, C_GOOD, 3.0)
		if ok and plan.pieces.size() > 0:
			var L := BridgeSim.wpos(plan.pieces[0][0]).distance_to(BridgeSim.wpos(plan.pieces[0][1]))
			var lbl := "%d × %.1f m" % [n, L] if n > 1 else "%.1f m" % L
			loupe_caption = "%s · %d material" % [lbl, _plan_cost(plan)]
			if loupe_active():
				return
			var fs := int(14 * ui)
			var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := gpos(q) + Vector2(16 * ui, 28 * ui)
			at.x = minf(at.x, get_viewport_rect().size.x - tw - 16)
			_box(Rect2(at - Vector2(6, fs), Vector2(tw + 12, fs + 10)), Color(1, 1, 1, 0.85), 8)
			_text(lbl, at + Vector2(0, -2), 14, C_INK)


func _plan_cost(plan: Dictionary) -> int:
	var c := 0
	for pq in plan.pieces:
		c += BridgeSim.beam_cost(BridgeSim.beam(pq[0], pq[1], tool))
	return c


func _beam_w(m: int) -> float:
	return maxf(3.0, ppm * (0.2 if m == BridgeSim.Mat.ROAD else 0.12))


func _draw_beam(a: Vector2, b: Vector2, m: int, stress: float, alpha := 1.0, width := -1.0) -> void:
	var w := _beam_w(m) if width < 0.0 else width
	if m == BridgeSim.Mat.ROAD:
		var col := C_ROAD.lerp(C_STRESS, clampf(stress, 0.0, 1.0))
		col.a = alpha
		draw_line(a, b, col, w)
		var lc := C_ROAD_LINE
		lc.a = alpha * 0.9
		var d := b - a
		if d.length() > 4.0:
			draw_line(a + d * 0.25, a + d * 0.5, lc, maxf(1.0, w * 0.15))
	else:
		var col := C_WOOD.lerp(C_STRESS, clampf(stress, 0.0, 1.0))
		col.a = alpha
		draw_line(a, b, C_WOOD_DARK if alpha >= 1.0 else Color(C_WOOD_DARK, alpha), w + 2.0)
		draw_line(a, b, col, w)


func _draw_joint(p: Vector2, anchor: bool, hi := false) -> void:
	var r := maxf(4.0, ppm * (0.16 if anchor else 0.12))
	if hi:
		draw_circle(p, r + 5.0 + sin(anim_t * 6.0) * 1.5, Color(1, 1, 1, 0.6))
	draw_circle(p, r + 1.5, C_INK)
	draw_circle(p, r, C_ANCHOR if anchor else C_JOINT)


func _draw_design() -> void:
	var d := shown_design()
	var show_last := phase == Phase.BUILD and not last_loads.is_empty()
	for b in d:
		var st := 0.0
		var snapped_beam := false
		if show_last:
			var k := _key(b.p, b.q)
			if last_loads.has(k):
				st = clampf((float(last_loads[k].load) - 0.4) / 0.6, 0.0, 1.0) * 0.9
				snapped_beam = bool(last_loads[k].broken)
		_draw_beam(gpos(b.p), gpos(b.q), int(b.m), st)
		if snapped_beam:
			var mid := (gpos(b.p) + gpos(b.q)) * 0.5
			var s := maxf(5.0, ppm * 0.14)
			draw_line(mid - Vector2(s, s), mid + Vector2(s, s), C_BAD, 3.0)
			draw_line(mid - Vector2(s, -s), mid + Vector2(s, -s), C_BAD, 3.0)
	var seen := {}
	for a in anchors:
		seen[a] = true
		_draw_joint(gpos(a), true, a == selected and phase == Phase.BUILD)
	for b in d:
		for g: Vector2i in [b.p, b.q]:
			if not seen.has(g):
				seen[g] = true
				_draw_joint(gpos(g), false, g == selected and phase == Phase.BUILD)


func _draw_sim() -> void:
	for b in sim.ba.size():
		var a := w2s(sim.node_pos(sim.ba[b]))
		var c := w2s(sim.node_pos(sim.bb[b]))
		var m := sim.mat[b]
		if sim.broken[b] == 1:
			_draw_beam(a, a.lerp(c, 0.3), m, 1.0, 0.9)
			_draw_beam(c, c.lerp(a, 0.3), m, 1.0, 0.9)
		else:
			_draw_beam(a, c, m, sim.load[b])
	for i in sim.bridge_node_count():
		_draw_joint(w2s(sim.node_pos(i)), sim.inv[i] == 0.0)
	_draw_vehicle(sim.node_pos(sim.w0), sim.node_pos(sim.w1), sim.spin)


func _draw_vehicle_parked() -> void:
	var v := vehicle()
	var r := float(v.r)
	var fx := -3.5
	_draw_vehicle(Vector2(fx - float(v.base), -r), Vector2(fx, -r), 0.0)


func _draw_vehicle(rear: Vector2, front: Vector2, spin: float) -> void:
	var v := vehicle()
	var r := float(v.r)
	var base := float(v.base)
	var ang := atan2(front.y - rear.y, front.x - rear.x)
	var mid := (rear + front) * 0.5
	var col := Color(String(v.color))
	draw_set_transform(w2s(mid), ang, Vector2.ONE)
	var s := ppm
	var body_len := base + r * 2.0 + 0.5
	var bx := -body_len * 0.5
	match vehicle_i:
		0: # hatchback
			_rbox(Rect2(bx * s, -r * 1.9 * s, body_len * s, r * 1.25 * s), col)
			var cab := PackedVector2Array([Vector2(bx + 0.35, -r * 1.85) * s, Vector2(bx + 0.75, -r * 3.2) * s,
				Vector2(bx + body_len * 0.72, -r * 3.2) * s, Vector2(bx + body_len * 0.92, -r * 1.85) * s])
			draw_colored_polygon(cab, col.darkened(0.1))
			draw_colored_polygon(PackedVector2Array([Vector2(bx + 0.55, -r * 1.95) * s, Vector2(bx + 0.85, -r * 3.0) * s,
				Vector2(bx + body_len * 0.68, -r * 3.0) * s, Vector2(bx + body_len * 0.84, -r * 1.95) * s]), Color("cfe8f5"))
		1: # camper van
			_rbox(Rect2(bx * s, -r * 4.0 * s, body_len * s, r * 3.4 * s), col)
			_rbox(Rect2((bx + body_len - 0.75) * s, -r * 3.5 * s, 0.6 * s, r * 1.3 * s), Color("cfe8f5"))
			_rbox(Rect2((bx + 0.3) * s, -r * 3.5 * s, (body_len - 1.3) * s, r * 1.1 * s), Color("cfe8f5"))
			draw_rect(Rect2(bx * s, -r * 1.7 * s, body_len * s, r * 0.35 * s), Color(1, 1, 1, 0.8))
		_: # pickup
			_rbox(Rect2(bx * s, -r * 1.95 * s, body_len * s, r * 1.3 * s), col)
			_rbox(Rect2((bx + body_len * 0.52) * s, -r * 3.4 * s, body_len * 0.4 * s, r * 1.6 * s), col.darkened(0.08))
			_rbox(Rect2((bx + body_len * 0.66) * s, -r * 3.15 * s, body_len * 0.22 * s, r * 0.9 * s), Color("cfe8f5"))
			draw_rect(Rect2(bx * s, -r * 2.15 * s, body_len * 0.5 * s, r * 0.25 * s), col.darkened(0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for w in [rear, front]:
		var c := w2s(w)
		draw_circle(c, r * s, Color("1d1f24"))
		draw_circle(c, r * s * 0.5, Color("b9c0c8"))
		for k in 3:
			var a := spin + k * TAU / 3.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * r * s * 0.48, Color("5c636c"), maxf(1.5, s * 0.05))


func _rbox(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.25))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


# ------------------------------------------------------------------ magnifier (loupe)

## The loupe shows while a finger/mouse is held on a joint to draw a line.
func loupe_active() -> bool:
	return phase == Phase.BUILD and pressed and drag_from != NONE and tool != Tool.ERASE \
		and not gesture and not tut_open and not dev_open


## Where the loupe sits: above the finger (the hand covers below it), or beside it near the top.
func loupe_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var L := minf(LOUPE_SIZE * ui, minf(vs.x, vs.y) * 0.46)
	var f := drag_pos
	var r := Rect2(f.x - L / 2.0, f.y - LOUPE_LIFT - L, L, L)
	if r.position.y < 8.0:
		r.position.y = clampf(f.y - L / 2.0, 8.0, vs.y - L - 8.0)
		r.position.x = f.x + LOUPE_LIFT * 0.8 if f.x < vs.x / 2.0 else f.x - LOUPE_LIFT * 0.8 - L
	r.position.x = clampf(r.position.x, 8.0, vs.x - L - 8.0)
	return r


func _draw_loupe() -> void:
	var R := loupe_rect()
	var lppm := maxf(ppm * LOUPE_ZOOM, 90.0)
	var wc := s2w(drag_pos)
	var c := R.get_center()
	var inner := R.grow(-3)
	var ls := func(w: Vector2) -> Vector2: return c + (w - wc) * lppm
	var clip := PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)])
	_box(R.grow(3), Color(0, 0, 0, 0.35), 18)
	_box(R, C_SKY_LOW, 16, Color(C_INK, 0.45))
	# water, banks, ledges and pillars (the real collision shapes), clipped to the loupe
	var g := float(gap)
	var d := float(dy)
	var deep := BridgeSim.WATER_Y + 20.0
	var shapes: Array = [
		[[Vector2(-80, BridgeSim.WATER_Y), Vector2(g + 80, BridgeSim.WATER_Y), Vector2(g + 80, deep), Vector2(-80, deep)], C_WATER],
		[[Vector2(-80, 0), Vector2(0, 0), Vector2(0, deep), Vector2(-80, deep)], C_ROCK],
		[[Vector2(g, d), Vector2(g + 80, d), Vector2(g + 80, deep), Vector2(g, deep)], C_ROCK],
	]
	for r: Rect2 in lv.get("rocks", []):
		shapes.append([[r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)], C_ROCK])
	for sh in shapes:
		var poly := PackedVector2Array()
		for w: Vector2 in sh[0]:
			poly.append(ls.call(w))
		for part in Geometry2D.intersect_polygons(poly, clip):
			draw_colored_polygon(part, sh[1])
	for top in [[Vector2(-80, 0), Vector2(0, 0)], [Vector2(g, d), Vector2(g + 80, d)]]:
		var seg := _clip_seg(ls.call(top[0]), ls.call(top[1]), inner)
		if not seg.is_empty():
			draw_line(seg[0], seg[1], C_GRASS, maxf(3.0, lppm * 0.12))
	# grid dots
	var half := R.size.x / 2.0 / lppm
	for gx in range(floori(wc.x - half), ceili(wc.x + half) + 1):
		for gy in range(floori(wc.y - half), ceili(wc.y + half) + 1):
			var dp := dot(gx, gy)
			if point_problem(dp) != "":
				continue
			var sp: Vector2 = ls.call(BridgeSim.wpos(dp))
			if inner.grow(-4).has_point(sp):
				draw_circle(sp, 3.0, Color(1, 1, 1, 0.8))
	# beams
	for b in design:
		var seg := _clip_seg(ls.call(BridgeSim.wpos(b.p)), ls.call(BridgeSim.wpos(b.q)), inner)
		if not seg.is_empty():
			_draw_beam(seg[0], seg[1], int(b.m), 0.0, 1.0, lppm * (0.2 if int(b.m) == BridgeSim.Mat.ROAD else 0.12))
	# the line being drawn
	var q := NONE
	var plan_ok := false
	var pts: Array = []
	if dragging:
		q = _snap(drag_pos, drag_from)
		var plan := plan_line(drag_from, q)
		plan_ok = plan.why == ""
		if plan_ok:
			for pq in plan.pieces:
				var seg := _clip_seg(ls.call(BridgeSim.wpos(pq[0])), ls.call(BridgeSim.wpos(pq[1])), inner)
				if not seg.is_empty():
					_draw_beam(seg[0], seg[1], tool, 0.0, 0.7, lppm * 0.15)
				pts.append(pq[1])
		else:
			var seg := _clip_seg(ls.call(BridgeSim.wpos(drag_from)), ls.call(BridgeSim.wpos(q)), inner)
			if not seg.is_empty():
				draw_line(seg[0], seg[1], Color(C_BAD, 0.7), lppm * 0.12)
	# joints + anchors
	var jr := maxf(5.0, lppm * 0.09)
	for k in joints() + pts:
		var sp: Vector2 = ls.call(BridgeSim.wpos(k))
		if inner.grow(-jr).has_point(sp):
			draw_circle(sp, jr + 1.5, C_INK)
			draw_circle(sp, jr, C_ANCHOR if anchors.has(k) else C_JOINT)
	# start joint and target
	var s0: Vector2 = ls.call(BridgeSim.wpos(drag_from))
	if inner.has_point(s0):
		draw_arc(s0, jr + 6, 0, TAU, 24, C_BTN_ON, 2.5)
	if q != NONE:
		var st: Vector2 = ls.call(BridgeSim.wpos(q))
		if inner.grow(-6).has_point(st):
			var locked := is_locked_target(q)
			draw_arc(st, jr + 8, 0, TAU, 28, C_GOOD if locked and plan_ok else (C_BTN_ON if plan_ok else C_BAD), 3.0)
	# crosshair where the finger actually is
	var cc := Color(C_INK, 0.8)
	draw_line(c + Vector2(-14, 0), c + Vector2(-5, 0), cc, 2.0)
	draw_line(c + Vector2(5, 0), c + Vector2(14, 0), cc, 2.0)
	draw_line(c + Vector2(0, -14), c + Vector2(0, -5), cc, 2.0)
	draw_line(c + Vector2(0, 5), c + Vector2(0, 14), cc, 2.0)
	# caption
	var cap := loupe_caption if plan_ok else ""
	if q != NONE and plan_ok and is_locked_target(q):
		cap = "locked · " + cap
	elif q != NONE and not plan_ok:
		cap = plan_line(drag_from, q).why
	if cap == "":
		cap = "drag to a dot or joint"
	var csz := 15
	while csz > 10 and font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, int(csz * ui)).x > R.size.x - 20:
		csz -= 1
	var ch := 26.0 * ui
	var cr := Rect2(R.position.x + 6, R.end.y - ch - 6, R.size.x - 12, ch)
	_box(cr, Color(0.12, 0.16, 0.2, 0.85), 10)
	_text_c(cap, cr.get_center(), csz, Color.WHITE)


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


# ------------------------------------------------------------------ hud

func _box(r: Rect2, col: Color, radius: float, border := Color(0, 0, 0, 0)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _text(s: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, int(size * ui), col)


func _text_c(s: String, center: Vector2, size: int, col: Color) -> void:
	var fs := int(size * ui)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(center.x - w * 0.5, center.y + fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Wrapped text, vertically centred in r.
func _para_c(s: String, r: Rect2, size: int, col: Color, max_lines := 2) -> void:
	var fs := int(size * ui)
	var lines := ceili(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / maxf(1.0, r.size.x))
	lines = clampi(lines, 1, max_lines)
	var lh := fs * 1.25
	var y := r.get_center().y - lh * lines * 0.5 + fs * 0.95
	draw_multiline_string(font, Vector2(r.position.x, y), s, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs, max_lines, col)


func _level_line() -> String:
	var v := vehicle()
	var s := "%s · %d kg · %d m gap" % [String(v.name), int(v.mass), gap]
	if dy < 0:
		s += " · %d m uphill" % -dy
	elif dy > 0:
		s += " · %d m downhill" % dy
	return s


func _draw_header() -> void:
	var r := head_rect
	_box(r, C_PANEL, 14)
	var pad := 14.0 * ui
	_text("Daily Bridge", r.position + Vector2(pad, r.size.y * 0.47), 24, C_INK)
	_text("#%d · %s" % [puzzle_no, date], r.position + Vector2(pad, r.size.y * 0.84), 14, C_MUTED)
	var right := cal_rect.position.x - 12 * ui
	_text("Attempts left: %d" % tries_left(), Vector2(r.position.x, r.position.y + r.size.y * 0.47), 16, C_INK, HORIZONTAL_ALIGNMENT_RIGHT, right - r.position.x)
	if target_score > 0:
		_text("Score to beat: %d" % target_score, Vector2(r.position.x, r.position.y + r.size.y * 0.84), 14, C_BTN_ON, HORIZONTAL_ALIGNMENT_RIGHT, right - r.position.x)
	_box(help_rect, C_BTN, 20 * ui)
	_text_c("?", help_rect.get_center(), 22, C_INK)
	var cal_a := 0.4 if phase == Phase.RUN else 1.0
	_box(cal_rect, Color(C_BTN, cal_a), 20 * ui)
	_draw_calendar(cal_rect.get_center() + Vector2(0, 1), Color(C_INK, cal_a))
	if date != today and not dev_sandbox:
		var sub_w := font.get_string_size("#%d · %s" % [puzzle_no, date], HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * ui)).x
		_text("PAST DAY", r.position + Vector2(pad + sub_w + 10 * ui, r.size.y * 0.84), 14, C_BTN_PRIMARY)
	# today's job, as a label in the sky
	var info := _level_line()
	var fs := int(15 * ui)
	var w := font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20 * ui
	var chip := Rect2(view_rect.position.x + 8, view_rect.position.y + 6, w, fs + 14 * ui)
	_box(chip, Color(1, 1, 1, 0.7), 10)
	_text(info, Vector2(chip.position.x + 10 * ui, chip.get_center().y + fs * 0.36), 15, C_INK)


func _draw_panel() -> void:
	var r := panel_rect
	_box(r, C_PANEL, 14)
	var pad := 10.0
	var row_h := (r.size.y - pad * 3) / 2.0
	var line := Rect2(r.position.x + pad, r.position.y + pad, r.size.x - pad * 2, row_h)
	match phase:
		Phase.RUN:
			_draw_budget(line, BridgeSim.design_cost(sim_design))
		Phase.RESULT:
			_draw_result_line(line, tries.back())
		Phase.FINAL:
			_draw_final_line(line)
		Phase.BUILD:
			var br := Rect2(r.position.x, r.position.y - 42 * ui, r.size.x, 36 * ui)
			_box(br, C_PANEL, 10)
			_draw_budget(br.grow(-6), cost())
	if archive_open:
		return
	for b in buttons:
		if b.kind != "zoom":
			_draw_button(b)


func _draw_budget(r: Rect2, used: int) -> void:
	# label · bar (ideal marked) · projected score
	var lbl := "Material %d · ideal %s" % [used, str(ideal) if ideal > 0 else "…"]
	var lw := font.get_string_size("Material 888 · ideal 888", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * ui)).x
	var sc := "Score %d" % score_for(used) if used > 0 and ideal > 0 else "Score —"
	var sw := font.get_string_size("Score 888", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * ui)).x
	var cy := r.get_center().y + 6 * ui
	_text(lbl, Vector2(r.position.x + 6, cy), 16, C_INK)
	var col := C_MUTED
	if ideal > 0:
		col = C_GOOD if used <= ideal else (Color("e0a33a") if used <= ideal * 1.5 else C_BAD)
	_text(sc, Vector2(r.end.x - sw - 6, cy), 16, col if used > 0 else C_MUTED)
	var bar := Rect2(r.position.x + lw + 16, r.position.y + r.size.y * 0.3, r.size.x - lw - sw - 32, r.size.y * 0.4)
	_box(bar, Color("d5dde4"), 6)
	if ideal <= 0:
		# still working out the ideal: a gentle sweeping shimmer
		var t := fmod(anim_t * 0.6, 1.0)
		_box(Rect2(bar.position.x + bar.size.x * t * 0.8, bar.position.y, bar.size.x * 0.2, bar.size.y), Color(1, 1, 1, 0.8), 6)
		return
	var span := ideal * 2.0                  # the bar shows 0 .. 2x ideal; ideal sits in the middle
	var f := clampf(used / span, 0.0, 1.0)
	if f > 0.0:
		_box(Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * f), bar.size.y)), col, 6)
	var tx := bar.position.x + bar.size.x * 0.5
	draw_line(Vector2(tx, bar.position.y - 4), Vector2(tx, bar.end.y + 4), C_INK, 2.0)


func _draw_result_line(r: Rect2, t: Dictionary) -> void:
	var msg := ""
	var col := C_INK
	if t.crossed:
		var sc := try_score(t)
		msg = "Made it across! Score %s (%d material)." % [str(sc) if sc >= 0 else "…", int(t.cost)]
		col = C_GOOD
	else:
		match String(t.outcome):
			"splash": msg = "Splash! %d beam%s snapped." % [int(t.snapped), "" if int(t.snapped) == 1 else "s"]
			_: msg = "The %s got stuck." % String(vehicle().name).to_lower()
		col = C_BAD
		if tries_left() > 0:
			msg += " Snapped beams are marked ×."
	_para_c(msg, r.grow_individual(-6, 0, -6, 0), 17, col)


func _draw_final_line(r: Rect2) -> void:
	var msg := ""
	var col := C_INK
	if show_ideal:
		msg = "Ideal bridge: %d material, scores 100. Replay to watch it." % ideal
		col = C_IDEAL
	else:
		var bt := best_try()
		if not bt.is_empty():
			msg = "Best score %d (%d material, ideal %d)." % [best_score(), int(bt.cost), ideal]
			col = C_GOOD
		else:
			msg = "No crossing today — score 0."
		if date == today:
			msg += "  Next bridge in " + _countdown()
	_para_c(msg, r.grow_individual(-6, 0, -6, 0), 17, col)


func _countdown() -> String:
	var t := Time.get_datetime_dict_from_system(false)
	var left := 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	return "%dh %02dm" % [left / 3600, (left % 3600) / 60]


func _draw_button(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	if b.id == "lock":
		var on: bool = b.on
		_box(r, Color(C_GOOD, 0.92) if on else Color(C_BTN, 0.85), 10)
		var ink := Color.WHITE if on else C_MUTED
		_text_c("LOCK", r.get_center() + Vector2(0, -7 * ui), 13, ink)
		_text_c("ON" if on else "OFF", r.get_center() + Vector2(0, 9 * ui), 12, ink)
		return
	var col := C_BTN
	var ink := C_INK
	if b.primary:
		col = C_BTN_PRIMARY
		ink = Color.WHITE
	if b.on:
		col = C_IDEAL if b.id == "ideal" else C_BTN_ON
		ink = Color.WHITE
	if not b.enabled:
		col = col.lerp(Color("cfd6dc"), 0.7)
		ink = Color(ink, 0.5)
	if b.kind == "zoom":
		col = Color(col, 0.85)
	_box(r, col, 10)
	var id := String(b.id)
	if id == "road" or id == "wood":
		var cy := r.get_center().y
		var x := r.position.x + 12 * ui
		var m := BridgeSim.Mat.ROAD if id == "road" else BridgeSim.Mat.WOOD
		draw_line(Vector2(x, cy), Vector2(x + 18 * ui, cy), C_ROAD if id == "road" else C_WOOD, (7.0 if id == "road" else 5.0) * ui)
		var price := "%d per m" % int(BridgeSim.COST[m])
		var tx := x + 26 * ui
		if r.size.x > 170 * ui:
			_text("%s · %s" % [String(b.label), price], Vector2(tx, cy + 6 * ui), 16, ink)
		else:
			_text(String(b.label), Vector2(tx, cy - 1 * ui), 17, ink)
			_text(price, Vector2(tx, cy + 15 * ui), 12, Color(ink, 0.75))
		return
	_text_c(String(b.label), r.get_center(), 24 if b.kind == "zoom" else 18, ink)


func _draw_toast() -> void:
	var vs := get_viewport_rect().size
	var fs := int(16 * ui)
	var w := minf(vs.x - 24, font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 40)
	var h := fs + 22 * ui
	var r := Rect2((vs.x - w) * 0.5, view_rect.end.y - h - 10, w, h)
	var c := Color(0.12, 0.16, 0.2, 0.9 * minf(1.0, toast_t * 3.0))
	_box(r, c, 12)
	_text_c(toast, r.get_center(), 16, Color(1, 1, 1, c.a / 0.9))


# ------------------------------------------------------------------ overlays

func _tut_card() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 24, 560 * ui)
	var h := minf(vs.y - 40, 560 * ui)
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)


func _draw_tutorial() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.08, 0.12, 0.55))
	var c := _tut_card()
	_box(c, Color("fbfaf7"), 18)
	_text_c("Get the vehicle across", Vector2(c.get_center().x, c.position.y + 36 * ui), 26, C_INK)
	var ty := c.position.y + 112 * ui
	var s := minf(34.0 * ui, (c.size.x - 80) / 6.0)
	var x0 := c.get_center().x - s * 3
	var deck: Array = []
	for i in 4:
		deck.append(Vector2(x0 + i * s * 2, ty))
	for i in 3:
		var top := Vector2(x0 + s + i * s * 2, ty - s * 1.4)
		_draw_beam_s(deck[i], top, BridgeSim.Mat.WOOD, s)
		_draw_beam_s(top, deck[i + 1], BridgeSim.Mat.WOOD, s)
		if i < 2:
			_draw_beam_s(top, Vector2(x0 + s * 3 + i * s * 2, ty - s * 1.4), BridgeSim.Mat.WOOD, s)
		_draw_beam_s(deck[i], deck[i + 1], BridgeSim.Mat.ROAD, s)
	for i in 4:
		draw_circle(deck[i], s * 0.16, C_ANCHOR if i == 0 or i == 3 else C_JOINT)
	var lines := [
		"Drag from a joint to any dot, at any angle. The line is split into equal pieces no longer than the length you pick (1–4 m). Red joints are anchored to the rock.",
		"Road is what the vehicle drives on. Wood is lighter and cheaper: brace the road with triangles. Long pieces buckle when squeezed.",
		"While you draw, a magnifier above your finger shows where the line lands, and LOCK (on by default) snaps it onto nearby joints. Pinch or use + / − to zoom; drag empty space to pan.",
		"3 attempts a day. Matching today's ideal bridge scores 100; less material scores higher.",
	]
	var y := ty + 34 * ui
	var fs := int(16 * ui)
	var tw := c.size.x - 44 * ui - 24
	for l in lines:
		draw_circle(Vector2(c.position.x + 26 * ui, y + 2), 4 * ui, C_BTN_ON)
		draw_multiline_string(font, Vector2(c.position.x + 40 * ui, y + 8 * ui), l, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 4, C_INK)
		var lines_n := ceili(font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / tw * 1.06)
		y += lines_n * fs * 1.2 + 12 * ui
	for b in buttons:
		_draw_button(b)


func _draw_beam_s(a: Vector2, b: Vector2, m: int, s: float) -> void:
	var w := s * (0.22 if m == BridgeSim.Mat.ROAD else 0.14)
	if m == BridgeSim.Mat.WOOD:
		draw_line(a, b, C_WOOD_DARK, w + 2)
	draw_line(a, b, C_ROAD if m == BridgeSim.Mat.ROAD else C_WOOD, w)


func _dev_card() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 24, 460 * ui)
	var h := 92 * ui + 5 * 50 * ui + 10 * ui
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)


func _draw_dev() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
	var c := _dev_card()
	_box(c, Color("fbfaf7"), 16)
	_text_c("Dev · %s (#%d)" % [date, puzzle_no], Vector2(c.get_center().x, c.position.y + 28 * ui), 20, C_INK)
	var info := "seed %d · %s · ideal %s%s" % [hash("daily-bridge:v2:" + date), _level_line(),
		str(ideal) if ideal > 0 else "…", " · not saving" if dev_sandbox else ""]
	_para_c(info, Rect2(c.position.x + 16, c.position.y + 44 * ui, c.size.x - 32, 40 * ui), 12, C_MUTED)
	for b in buttons:
		_draw_button(b)


# ------------------------------------------------------------------ agent hooks

func get_agent_state() -> Dictionary:
	var st := {
		"phase": ["build", "run", "result", "final"][phase], "state": ["playing", "playing", "playing", "won" if best_score() > 0 else "lost"][phase],
		"day": date, "puzzle": puzzle_no, "seed": hash("daily-bridge:v2:" + date),
		"gap": gap, "dy": dy, "vehicle": String(vehicle().name), "anchors": anchors.size(), "rocks": lv.get("rocks", []).size(),
		"ideal": ideal, "cost": cost(), "beams": design.size(), "tries": tries.size(), "tries_left": tries_left(),
		"best_score": best_score(), "finished": finished, "tool": ["road", "wood", "erase"][tool],
		"piece_len": piece_len, "auto_lock": auto_lock, "loupe": loupe_active(), "zoom": snappedf(zoom, 0.01), "show_ideal": show_ideal,
		"tutorial": tut_open, "dev_mode": dev_mode, "share_text": share_text() if phase == Phase.FINAL else "",
		"archive_open": archive_open, "archive_page": archive_page, "today": today,
	}
	if sim != null:
		st["sim"] = sim.summary()
	return st
