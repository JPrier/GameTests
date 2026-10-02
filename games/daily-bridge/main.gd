extends Node2D
## Daily Bridge — a daily bridge-building physics puzzle.
## Everyone gets the same canyon, anchors, vehicle and material budget each day.
## Drag beams between joints (road for the vehicle to drive on, wood to brace it),
## stay within the budget, then press Go: one vehicle tries to cross. The physics is
## deterministic (bridge_sim.gd), so the same bridge always plays out the same way.
## Three attempts a day; the score is the material left over on your cheapest crossing.

const EPOCH := "2026-10-02"           # puzzle #1
const DEFAULT_URL := "https://jprier.github.io/GameTests/daily-bridge/"
const MAX_TRIES := 3
const BUILD_MIN_X := -2
const BUILD_MIN_Y := -5
const BUILD_MAX_Y := 4
const MAX_HISTORY := 60
## Room above the cheapest known crossing, so several designs fit and saving material still scores.
const BUDGET_SLACK := 1.25
const TUT_FLAG := "user://daily_bridge_tutorial_seen"

## Cheapest known crossing (BridgeSim.candidates) per "pillar-gap-vehicle".
## tests/test_main.gd re-runs the physics to keep this table honest.
const BEST_KNOWN := {
	"0-8-0": 292, "0-8-1": 292, "0-8-2": 356,
	"0-10-0": 370, "0-10-1": 450, "0-10-2": 450,
	"0-12-0": 544, "0-12-1": 544, "0-12-2": 544,
	"2-8-0": 292, "2-8-1": 292, "2-8-2": 312,
	"2-10-0": 370, "2-10-1": 414, "2-10-2": 414,
	"2-12-0": 468, "2-12-1": 468, "2-12-2": 468,
}

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

# puzzle
var date := ""
var today := ""
var puzzle_no := 1
var gap := 10
var vehicle_i := 0
var pillar_h := 0
var low_y := 2
var anchors: Array = []
var budget := 300

# player
var design: Array = []              # [{p:Vector2i, q:Vector2i, m:int}]
var history: Array = []             # undo stack of designs
var tool: int = Tool.ROAD
var tries: Array = []               # [{crossed, outcome, cost, saved, snapped, design}]
var finished := false
var phase: int = Phase.BUILD
var target_score := -1              # material saved by whoever sent the link (?s=)
var base_url := DEFAULT_URL
var last_loads := {}                # beam key -> {load, broken} from the previous attempt

# run
var sim: BridgeSim
var sim_design: Array = []
var sim_acc := 0.0
var fast := false
var splash_t := -1.0
var splash_at := Vector2.ZERO

# ui
var buttons: Array = []
var view_rect := Rect2()
var head_rect := Rect2()
var panel_rect := Rect2()
var help_rect := Rect2()
var origin := Vector2.ZERO
var ppm := 30.0                     # pixels per metre
var drag_from := Vector2i(999, 999) # joint a beam is being dragged from
var dragging := false
var drag_pos := Vector2.ZERO
var press_pos := Vector2.ZERO
var selected := Vector2i(999, 999)  # tap-tap building: the joint the next beam starts at
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""
var anim_t := 0.0
var tut_open := false
var dev_open := false
var dev_taps := 0
var dev_last_tap := -10.0
var font: Font
var ui := 1.0                       # UI scale: bigger on narrow (phone) screens

const NONE := Vector2i(999, 999)


func _ready() -> void:
	font = ThemeDB.fallback_font
	_add_key_action("go", [KEY_ENTER, KEY_SPACE])
	_add_key_action("undo", [KEY_Z, KEY_BACKSPACE])
	_add_key_action("tool_road", [KEY_1])
	_add_key_action("tool_wood", [KEY_2])
	_add_key_action("tool_erase", [KEY_3])
	today = Time.get_date_string_from_system(false)
	var want := today
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	if _valid_date(String(url.get("d", ""))):
		want = String(url.d)
	dev_open = String(url.get("dev", "")) == "1"
	var s := String(url.get("s", ""))
	target_score = int(s) if s.is_valid_int() else -1
	load_puzzle(want)
	if not dev_open and not tutorial_seen():
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
	dragging = false
	sim = null
	_load_state()
	phase = Phase.FINAL if finished else Phase.BUILD
	if finished:
		_show_best()


func generate(d: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily-bridge:" + d)
	gap = [8, 10, 10, 12][rng.randi_range(0, 3)]
	vehicle_i = rng.randi_range(0, BridgeSim.VEHICLES.size() - 1)
	pillar_h = 2 if rng.randf() < 0.3 else 0
	low_y = rng.randi_range(2, 3)
	anchors = [Vector2i(0, 0), Vector2i(gap, 0), Vector2i(0, low_y), Vector2i(gap, low_y)]
	if pillar_h > 0:
		anchors.append(Vector2i(gap / 2, pillar_h))
	var best: int = BEST_KNOWN.get("%d-%d-%d" % [pillar_h, gap, vehicle_i], 999)
	budget = ceili(best * BUDGET_SLACK / 10.0) * 10


func level() -> Dictionary:
	return {"gap": gap, "vehicle": vehicle_i, "pillar_h": pillar_h, "anchors": anchors}


func vehicle() -> Dictionary:
	return BridgeSim.VEHICLES[vehicle_i]


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
	return anchors.has(g) or _beam_count(g) > 0


func _beam_count(g: Vector2i) -> int:
	var n := 0
	for b in design:
		if b.p == g or b.q == g:
			n += 1
	return n


static func _key(p: Vector2i, q: Vector2i) -> String:
	if p.x > q.x or (p.x == q.x and p.y > q.y):
		var t := p
		p = q
		q = t
	return "%d,%d,%d,%d" % [p.x, p.y, q.x, q.y]


## Why a joint can't go at g ("" when it can).
func point_problem(g: Vector2i) -> String:
	if anchors.has(g):
		return ""
	if g.x < BUILD_MIN_X or g.x > gap - BUILD_MIN_X or g.y < BUILD_MIN_Y or g.y > BUILD_MAX_Y:
		return "Out of the build area"
	if g.y >= 0 and (g.x <= 0 or g.x >= gap):
		return "That's solid rock"
	if pillar_h > 0 and g.y >= pillar_h and absi(g.x - gap / 2) <= 0:
		return "That's solid rock"
	return ""


## Why a beam p→q can't be built ("" when it can).
func beam_problem(p: Vector2i, q: Vector2i) -> String:
	if p == q:
		return "Pick a different point"
	if Vector2(p).distance_to(Vector2(q)) > BridgeSim.MAX_LEN + 0.001:
		return "Too long — beams reach %.1f m at most" % BridgeSim.MAX_LEN
	var pp := point_problem(p)
	if pp == "":
		pp = point_problem(q)
	if pp != "":
		return pp
	var k := _key(p, q)
	for b in design:
		if _key(b.p, b.q) == k:
			return "There's already a beam there"
	return ""


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


func remove_beam(i: int) -> void:
	if i < 0 or i >= design.size() or phase != Phase.BUILD:
		return
	_push_history()
	design.remove_at(i)
	if not is_joint(selected):
		selected = NONE
	_design_changed()


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


# ------------------------------------------------------------------ attempts

func tries_left() -> int:
	return MAX_TRIES - tries.size()


func can_go() -> bool:
	return phase == Phase.BUILD and tries_left() > 0 and not design.is_empty() and cost() <= budget


func go() -> void:
	if phase != Phase.BUILD:
		return
	if design.is_empty():
		_toast("Build something first")
		return
	if cost() > budget:
		_toast("Over budget by %d" % (cost() - budget))
		return
	if tries_left() <= 0:
		return
	_start_sim(design)
	selected = NONE


func _start_sim(d: Array) -> void:
	sim_design = d.duplicate(true)
	sim = BridgeSim.new()
	sim.setup(level(), sim_design)
	sim_acc = 0.0
	splash_t = -1.0
	phase = Phase.RUN


## Run a design to the end without touching game state (tests, previews).
func simulate(d: Array) -> Dictionary:
	var s := BridgeSim.new()
	s.setup(level(), d)
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
	var c := BridgeSim.design_cost(sim_design)
	tries.append({"crossed": bool(r.crossed), "outcome": String(r.outcome), "cost": c,
		"saved": budget - c if r.crossed else -1, "snapped": int(r.snapped),
		"design": _pack(sim_design)})
	last_loads = {}
	for b in sim.ba.size():
		var d: Dictionary = sim_design[b]
		last_loads[_key(d.p, d.q)] = {"load": sim.peak[b], "broken": sim.broken[b] == 1}
	if tries.size() >= MAX_TRIES:
		finished = true
	phase = Phase.RESULT
	_save_state()


var _is_replay := false


## Watch the last (or best, once finished) run again. Doesn't use an attempt.
func replay() -> void:
	if phase != Phase.RESULT and phase != Phase.FINAL:
		return
	var t: Dictionary = best_try() if phase == Phase.FINAL else tries.back()
	if t.is_empty():
		return
	_is_replay = true
	_start_sim(_unpack(t.design))


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
	_show_best()


func _show_best() -> void:
	var t := best_try()
	if t.is_empty() and not tries.is_empty():
		t = tries.back()
	sim = null
	if not t.is_empty():
		design = _unpack(t.design)


func best_try() -> Dictionary:
	var best := {}
	for t in tries:
		if t.crossed and (best.is_empty() or int(t.saved) > int(best.saved)):
			best = t
	return best


func best_score() -> int:
	var b := best_try()
	return int(b.saved) if not b.is_empty() else -1


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
	return "user://bridge_%s.json" % date


func _save_state() -> void:
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
				"cost": int(t.get("cost", 0)), "saved": int(t.get("saved", -1)),
				"snapped": int(t.get("snapped", 0)), "design": t.get("design", [])})
	finished = bool(data.get("finished", false)) or tries.size() >= MAX_TRIES


## Forget today's progress (used by tests).
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
	var s := best_score()
	return "%s?d=%s&s=%d" % [base_url, date, s] if s >= 0 else "%s?d=%s" % [base_url, date]


func share_text() -> String:
	var lines := PackedStringArray()
	lines.append("Daily Bridge #%d 🌉 %s" % [puzzle_no, date])
	lines.append("%s across %d m" % [String(vehicle().name), gap])
	var marks := PackedStringArray()
	for t in tries:
		marks.append("✅" if t.crossed else "💥")
	var best := best_score()
	if best >= 0:
		lines.append("Made it with %d of %d material to spare" % [best, budget])
	else:
		lines.append("Didn't make it across")
	lines.append("Attempts: " + " ".join(marks))
	if target_score >= 0:
		if best > target_score:
			lines.append("Beat the %d I was sent 🏆" % target_score)
		else:
			lines.append("Couldn't beat %d — can you?" % target_score)
	lines.append("Can you build it cheaper? " + share_link())
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
		_toast("Result copied — paste it anywhere")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__bridgeShare||''", true)
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
		target_score = -1
		load_puzzle(today)


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
		dev_open = true


func dev_reset_today() -> void:
	wipe_save()
	load_puzzle(date)
	dev_open = false
	_toast("Dev: today's progress reset")


func dev_reset_all() -> void:
	var n := 0
	var dir := DirAccess.open("user://")
	if dir:
		for f in dir.get_files():
			if f.begins_with("bridge_") and f.ends_with(".json"):
				_wipe_file("user://" + f)
				n += 1
	_wipe_file(TUT_FLAG)
	_flush_storage()
	load_puzzle(date)
	dev_open = false
	_toast("Dev: cleared %d saved day(s) + tutorial" % n)


func dev_load_reference() -> void:
	dev_open = false
	if phase != Phase.BUILD:
		return
	var best: Array = []
	for c in BridgeSim.candidates(level()):
		if simulate(c).crossed and (best.is_empty() or BridgeSim.design_cost(c) < BridgeSim.design_cost(best)):
			best = c
	_push_history()
	set_design(best)
	_toast("Dev: loaded the cheapest reference bridge")


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
	if not tut_open and not dev_open:
		if Input.is_action_just_pressed("go"):
			match phase:
				Phase.BUILD: go()
				Phase.RUN: fast = not fast
				Phase.RESULT:
					if tries_left() > 0 and not (tries.back().crossed):
						repair()
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


# ------------------------------------------------------------------ input

func w2s(v: Vector2) -> Vector2:
	return origin + v * ppm


func s2w(p: Vector2) -> Vector2:
	return (p - origin) / ppm


func _snap(p: Vector2) -> Vector2i:
	var w := s2w(p)
	return Vector2i(roundi(w.x), roundi(w.y))


## Nearest joint to a screen point, within a finger's reach.
func _joint_at(p: Vector2) -> Vector2i:
	var best := NONE
	var bd := maxf(26.0 * ui, ppm * 0.45)
	for g in joints():
		var d := w2s(Vector2(g)).distance_to(p)
		if d < bd:
			bd = d
			best = g
	return best


func _beam_at(p: Vector2) -> int:
	var best := -1
	var bd := maxf(18.0 * ui, ppm * 0.3)
	for i in design.size():
		var b: Dictionary = design[i]
		var a := w2s(Vector2(b.p))
		var c := w2s(Vector2(b.q))
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, c))
		if d < bd:
			bd = d
			best = i
	return best


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			_on_press(p)
		else:
			_on_release(p)
	elif ev is InputEventMouseMotion:
		drag_pos = make_input_local(ev).position


func _on_press(p: Vector2) -> void:
	drag_pos = p
	press_pos = p
	if dev_open or tut_open:
		_press_button(p)
		return
	if help_rect.grow(10).has_point(p):
		open_tutorial()
		return
	if Rect2(head_rect.position, Vector2(220, head_rect.size.y)).has_point(p):
		_dev_tap()
		return
	if _press_button(p):
		return
	if phase != Phase.BUILD or not view_rect.has_point(p):
		return
	if tool == Tool.ERASE:
		var bi := _beam_at(p)
		if bi >= 0:
			remove_beam(bi)
		else:
			_toast("Tap a beam to remove it")
		return
	var j := _joint_at(p)
	if j != NONE:
		drag_from = j
		dragging = true
	elif selected != NONE:
		add_beam(selected, _snap(p), tool)
		var q := _snap(p)
		if is_joint(q):
			selected = q
	else:
		_toast("Start a beam from a joint — drag from a dot")


func _on_release(p: Vector2) -> void:
	if not dragging:
		return
	dragging = false
	var q := _snap(p)
	var j := _joint_at(p)
	if j != NONE:
		q = j
	if q == drag_from or p.distance_to(press_pos) < 10.0:
		# a tap on a joint: select it (tap again elsewhere to build from it), or build from the selection
		if selected != NONE and selected != drag_from:
			if add_beam(selected, drag_from, tool):
				selected = drag_from
		else:
			selected = NONE if selected == drag_from else drag_from
		return
	if add_beam(drag_from, q, tool):
		selected = q


# ------------------------------------------------------------------ buttons

func _press_button(p: Vector2) -> bool:
	for b in buttons:
		if b.rect.has_point(p):
			if b.enabled:
				_do(String(b.id))
			return true
	return false


func _do(id: String) -> void:
	match id:
		"road": set_tool(Tool.ROAD)
		"wood": set_tool(Tool.WOOD)
		"erase": set_tool(Tool.ERASE)
		"undo": undo()
		"clear": clear_design()
		"go": go()
		"fast": fast = not fast
		"skip": skip()
		"repair": repair()
		"finish": finish()
		"replay": replay()
		"share": share()
		"today": play_today()
		"tut_close": close_tutorial()
		"dev_today": dev_reset_today()
		"dev_all": dev_reset_all()
		"dev_ref": dev_load_reference()
		"dev_close": dev_open = false


func _btn(id: String, r: Rect2, label: String, primary := false, enabled := true, on := false) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "primary": primary, "enabled": enabled, "on": on})


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	ui = clampf(1.0 + (860.0 - vs.x) / 300.0, 1.0, 1.5)
	var m := 12.0
	var head_h := 64.0 * ui
	head_rect = Rect2(m, m, vs.x - m * 2, head_h)
	help_rect = Rect2(head_rect.end.x - 46 * ui, head_rect.position.y + (head_h - 40 * ui) * 0.5, 40 * ui, 40 * ui)
	var narrow := vs.x < 560
	var panel_h := 128.0 * ui
	panel_rect = Rect2(m, vs.y - panel_h - m, vs.x - m * 2, panel_h)
	var area := Rect2(0, head_rect.end.y + 4, vs.x, panel_rect.position.y - head_rect.end.y - 50 * ui)
	# world bounds shown: a bit of each cliff, sky above, water below
	var wmin := Vector2(-5.0, -5.6)
	var wmax := Vector2(gap + 4.5, BridgeSim.WATER_Y + 1.2)
	var wsize := wmax - wmin
	ppm = minf(area.size.x / wsize.x, area.size.y / wsize.y)
	var used := wsize * ppm
	var top_left := area.position + (area.size - used) * Vector2(0.5, 0.45)
	view_rect = Rect2(top_left, used)
	origin = top_left - wmin * ppm
	_build_buttons(narrow)


func _build_buttons(_narrow: bool) -> void:
	buttons.clear()
	if tut_open:
		var card := _tut_card()
		_btn("tut_close", Rect2(card.position.x + 24, card.end.y - 70 * ui, card.size.x - 48, 50 * ui), "Start building", true)
		return
	if dev_open:
		var card := _dev_card()
		var y := card.position.y + 56 * ui
		for e in [["dev_today", "Reset today"], ["dev_all", "Reset every day + tutorial"],
				["dev_ref", "Load reference bridge"], ["dev_close", "Close"]]:
			_btn(e[0], Rect2(card.position.x + 20, y, card.size.x - 40, 44 * ui), e[1], e[0] == "dev_close")
			y += 54 * ui
		return
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
			var cw := bw
			_btn("clear", Rect2(x0, y2, cw, row_h), "Clear", false, not design.is_empty())
			var label := "Go!  (attempt %d of %d)" % [tries.size() + 1, MAX_TRIES]
			if cost() > budget:
				label = "Over budget"
			_btn("go", Rect2(x0 + cw + pad, y2, w - cw - pad, row_h), label, true, can_go())
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
			var hw := (w - pad) / 2.0
			if date != today:
				_btn("today", Rect2(x0, y2, hw, row_h), "Play today's bridge")
			else:
				_btn("replay", Rect2(x0, y2, hw, row_h), "Replay", false, not tries.is_empty())
			_btn("share", Rect2(x0 + hw + pad, y2, hw, row_h), "Share result", true)


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
	if toast_t > 0.0 and toast != "":
		_draw_toast()
	if tut_open:
		_draw_tutorial()
	if dev_open:
		_draw_dev()


func _draw_backdrop(vs: Vector2) -> void:
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)])
	draw_polygon(pts, PackedColorArray([C_SKY_TOP, C_SKY_TOP, C_SKY_LOW, C_SKY_LOW]))
	# far hills
	var hills := PackedVector2Array()
	var base_y := w2s(Vector2(0, 1.5)).y
	hills.append(Vector2(0, vs.y))
	for i in 25:
		var x := vs.x * i / 24.0
		hills.append(Vector2(x, base_y - 40.0 - 26.0 * sin(i * 0.9 + 1.3) - 14.0 * sin(i * 2.1)))
	hills.append(Vector2(vs.x, vs.y))
	draw_colored_polygon(hills, C_HILL)
	# clouds
	for c in [[0.18, 0.12, 1.0], [0.62, 0.08, 0.8], [0.86, 0.2, 0.6]]:
		var cx := fmod(vs.x * float(c[0]) + anim_t * 6.0 * float(c[2]), vs.x + 160.0) - 80.0
		var cy := head_rect.end.y + 20.0 + vs.y * float(c[1]) * 0.4
		var s := 22.0 * float(c[2]) + 10.0
		for k in [[-1.0, 0.2, 0.8], [0.0, 0.0, 1.0], [1.0, 0.25, 0.75]]:
			draw_circle(Vector2(cx + float(k[0]) * s, cy + float(k[1]) * s), s * float(k[2]), Color(1, 1, 1, 0.75))


func _draw_terrain() -> void:
	var vs := get_viewport_rect().size
	var g := float(gap)
	var bottom := vs.y + 10.0
	# water body (behind the cliffs' feet)
	var wy := w2s(Vector2(0, BridgeSim.WATER_Y)).y
	draw_rect(Rect2(0, wy, vs.x, bottom - wy), C_WATER)
	# cliffs
	var left := PackedVector2Array([Vector2(-10, w2s(Vector2(0, 0)).y), w2s(Vector2(0, 0)),
		w2s(Vector2(0.15, 2.0)), w2s(Vector2(-0.1, 4.0)), w2s(Vector2(0.25, BridgeSim.WATER_Y + 2)), Vector2(-10, bottom)])
	var right := PackedVector2Array([w2s(Vector2(g, 0)), Vector2(vs.x + 10, w2s(Vector2(0, 0)).y),
		Vector2(vs.x + 10, bottom), w2s(Vector2(g - 0.25, BridgeSim.WATER_Y + 2)), w2s(Vector2(g + 0.1, 4.0)), w2s(Vector2(g - 0.15, 2.0))])
	draw_colored_polygon(left, C_ROCK)
	draw_colored_polygon(right, C_ROCK)
	for strata in [1.2, 2.6, 4.2]:
		var y := w2s(Vector2(0, strata)).y
		draw_line(Vector2(-10, y), Vector2(w2s(Vector2(-0.1, 0)).x, y), C_ROCK_DARK, 2.0)
		draw_line(Vector2(w2s(Vector2(g + 0.1, 0)).x, y), Vector2(vs.x + 10, y), C_ROCK_DARK, 2.0)
	var gy := w2s(Vector2(0, 0)).y
	draw_rect(Rect2(-10, gy - 2, w2s(Vector2(0, 0)).x + 10, ppm * 0.22), C_GRASS)
	draw_rect(Rect2(w2s(Vector2(g, 0)).x, gy - 2, vs.x, ppm * 0.22), C_GRASS)
	if pillar_h > 0:
		var c := g * 0.5
		var pil := PackedVector2Array([w2s(Vector2(c - 0.5, pillar_h)), w2s(Vector2(c + 0.5, pillar_h)),
			w2s(Vector2(c + 0.75, BridgeSim.WATER_Y + 2)), w2s(Vector2(c - 0.75, BridgeSim.WATER_Y + 2))])
		draw_colored_polygon(pil, C_ROCK)
		draw_line(w2s(Vector2(c - 0.5, pillar_h)), w2s(Vector2(c + 0.5, pillar_h)), C_ROCK_DARK, 3.0)


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
			var d := Vector2(cos(a) * 1.6, sin(a) * 3.2 - 0.0) * t * ppm * 0.6
			d.y += 0.5 * 9.8 * t * t * ppm * 0.18
			draw_circle(p + d, maxf(1.0, ppm * 0.12 * (1.0 - splash_t / 1.6)), Color(1, 1, 1, 0.85 - splash_t * 0.5))


func _draw_build_grid() -> void:
	var r := maxf(1.5, ppm * 0.05)
	for y in range(BUILD_MIN_Y, BUILD_MAX_Y + 1):
		for x in range(BUILD_MIN_X, gap - BUILD_MIN_X + 1):
			var g := Vector2i(x, y)
			if point_problem(g) == "":
				draw_circle(w2s(Vector2(g)), r, C_DOT)
	# reach preview while dragging or with a joint selected
	var from := drag_from if dragging else selected
	if from != NONE and tool != Tool.ERASE:
		draw_arc(w2s(Vector2(from)), BridgeSim.MAX_LEN * ppm, 0, TAU, 64, Color(1, 1, 1, 0.5), 1.5)
		if dragging:
			var q := _snap(drag_pos)
			var ok := beam_problem(from, q) == ""
			var col := (C_ROAD if tool == Tool.ROAD else C_WOOD) if ok else C_BAD
			col.a = 0.75
			draw_line(w2s(Vector2(from)), w2s(Vector2(q)), col, _beam_w(tool))
			draw_circle(w2s(Vector2(q)), ppm * 0.14, col)


func _beam_w(m: int) -> float:
	return maxf(3.0, ppm * (0.2 if m == BridgeSim.Mat.ROAD else 0.12))


func _draw_beam(a: Vector2, b: Vector2, m: int, stress: float, alpha := 1.0) -> void:
	var w := _beam_w(m)
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
	if anchor:
		draw_circle(p, r + 1.5, C_INK)
		draw_circle(p, r, C_ANCHOR)
	else:
		draw_circle(p, r + 1.5, C_INK)
		draw_circle(p, r, C_JOINT)


func _draw_design() -> void:
	var show_last := phase == Phase.BUILD and not last_loads.is_empty()
	for b in design:
		var st := 0.0
		var snapped_beam := false
		if show_last:
			var k := _key(b.p, b.q)
			if last_loads.has(k):
				st = float(last_loads[k].load) * 0.8
				snapped_beam = bool(last_loads[k].broken)
		_draw_beam(w2s(Vector2(b.p)), w2s(Vector2(b.q)), int(b.m), st)
		if snapped_beam:
			var mid := (w2s(Vector2(b.p)) + w2s(Vector2(b.q))) * 0.5
			var s := maxf(5.0, ppm * 0.14)
			draw_line(mid - Vector2(s, s), mid + Vector2(s, s), C_BAD, 3.0)
			draw_line(mid - Vector2(s, -s), mid + Vector2(s, -s), C_BAD, 3.0)
	for g in joints():
		_draw_joint(w2s(Vector2(g)), anchors.has(g), g == selected and phase == Phase.BUILD)


func _draw_sim() -> void:
	for b in sim.ba.size():
		var a := w2s(sim.node_pos(sim.ba[b]))
		var c := w2s(sim.node_pos(sim.bb[b]))
		var m := sim.mat[b]
		if sim.broken[b] == 1:
			# snapped: two stubs left hanging from each end
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


func _draw_header() -> void:
	var r := head_rect
	_box(r, C_PANEL, 14)
	var pad := 14.0 * ui
	_text("Daily Bridge", r.position + Vector2(pad, r.size.y * 0.47), 24, C_INK)
	_text("#%d · %s" % [puzzle_no, date], r.position + Vector2(pad, r.size.y * 0.84), 14, C_MUTED)
	var right := help_rect.position.x - 12 * ui
	var tl := "Attempts left: %d" % tries_left()
	_text(tl, Vector2(r.position.x, r.position.y + r.size.y * 0.47), 16, C_INK, HORIZONTAL_ALIGNMENT_RIGHT, right - r.position.x)
	if target_score >= 0:
		_text("To beat: %d spare" % target_score, Vector2(r.position.x, r.position.y + r.size.y * 0.84), 14, C_BTN_ON, HORIZONTAL_ALIGNMENT_RIGHT, right - r.position.x)
	_box(help_rect, C_BTN, 20 * ui)
	_text_c("?", help_rect.get_center(), 22, C_INK)
	# today's job, as a label in the sky over the vehicle
	var v := vehicle()
	var info := "%s · %d kg · %d m gap" % [String(v.name), int(v.mass), gap]
	if pillar_h > 0:
		info += " · rock pillar"
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
	var y1 := r.position.y + pad
	match phase:
		Phase.BUILD, Phase.RUN:
			if phase == Phase.RUN:
				_draw_budget(Rect2(r.position.x + pad, y1, r.size.x - pad * 2, row_h), BridgeSim.design_cost(sim_design))
		Phase.RESULT:
			_draw_result_line(Rect2(r.position.x + pad, y1, r.size.x - pad * 2, row_h), tries.back())
		Phase.FINAL:
			_draw_final_line(Rect2(r.position.x + pad, y1, r.size.x - pad * 2, row_h))
	if phase == Phase.BUILD:
		# budget bar lives just above the panel so the tools stay in thumb reach
		var br := Rect2(r.position.x, r.position.y - 42 * ui, r.size.x, 36 * ui)
		_box(br, C_PANEL, 10)
		_draw_budget(br.grow(-6), cost())
	for b in buttons:
		_draw_button(b)


func _draw_budget(r: Rect2, used: int) -> void:
	var over := used > budget
	var lbl := "Material %d / %d" % [used, budget]
	var lw := font.get_string_size("Material 888 / 888", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * ui)).x
	_text(lbl, Vector2(r.position.x + 6, r.get_center().y + 6 * ui), 16, C_BAD if over else C_INK)
	var bar := Rect2(r.position.x + lw + 20, r.position.y + r.size.y * 0.3, r.size.x - lw - 26, r.size.y * 0.4)
	_box(bar, Color("d5dde4"), 6)
	var f := clampf(float(used) / float(budget), 0.0, 1.0)
	if f > 0.0:
		_box(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), C_BAD if over else (Color("e0a33a") if f > 0.9 else C_GOOD), 6)


func _draw_result_line(r: Rect2, t: Dictionary) -> void:
	var msg := ""
	var col := C_INK
	if t.crossed:
		msg = "Made it across! %d material to spare." % int(t.saved)
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
	var best := best_score()
	var msg := ""
	if best >= 0:
		msg = "Best: crossed with %d of %d to spare." % [best, budget]
	else:
		msg = "No crossing today."
	if date == today:
		msg += "  Next bridge in " + _countdown()
	_para_c(msg, r.grow_individual(-6, 0, -6, 0), 17, C_GOOD if best >= 0 else C_INK)


func _countdown() -> String:
	var t := Time.get_datetime_dict_from_system(false)
	var left := 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	return "%dh %02dm" % [left / 3600, (left % 3600) / 60]


func _draw_button(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var col := C_BTN
	var ink := C_INK
	if b.primary:
		col = C_BTN_PRIMARY
		ink = Color.WHITE
	if b.on:
		col = C_BTN_ON
		ink = Color.WHITE
	if not b.enabled:
		col = col.lerp(Color("cfd6dc"), 0.7)
		ink = Color(ink, 0.5)
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
	_text_c(String(b.label), r.get_center(), 18, ink)


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
	var h := minf(vs.y - 40, 540 * ui)
	return Rect2((vs.x - w) * 0.5, (vs.y - h) * 0.5, w, h)


func _draw_tutorial() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.08, 0.12, 0.55))
	var c := _tut_card()
	_box(c, Color("fbfaf7"), 18)
	_text_c("How to build", Vector2(c.get_center().x, c.position.y + 36 * ui), 26, C_INK)
	# a little truss diagram
	var dy := c.position.y + 112 * ui
	var s := minf(34.0 * ui, (c.size.x - 80) / 6.0)
	var x0 := c.get_center().x - s * 3
	var deck: Array = []
	for i in 4:
		deck.append(Vector2(x0 + i * s * 2, dy))
	for i in 3:
		var top := Vector2(x0 + s + i * s * 2, dy - s * 1.4)
		_draw_beam_s(deck[i], top, BridgeSim.Mat.WOOD, s)
		_draw_beam_s(top, deck[i + 1], BridgeSim.Mat.WOOD, s)
		if i < 2:
			_draw_beam_s(top, Vector2(x0 + s * 3 + i * s * 2, dy - s * 1.4), BridgeSim.Mat.WOOD, s)
		_draw_beam_s(deck[i], deck[i + 1], BridgeSim.Mat.ROAD, s)
	for i in 4:
		draw_circle(deck[i], s * 0.16, C_ANCHOR if i == 0 or i == 3 else C_JOINT)
	var lines := [
		"Drag from a joint to place a beam (or tap a joint, then tap where it should go). Red joints are anchored to the rock.",
		"Road is what the vehicle drives on. Wood is lighter and cheaper — brace the road with triangles.",
		"Stay within today's material budget, then press Go. Strained beams glow red, then snap.",
		"3 attempts a day. Cross with material to spare — the more you save, the better your score.",
	]
	var y := dy + 34 * ui
	var fs := int(17 * ui)
	var tw := c.size.x - 44 * ui - 24
	for l in lines:
		draw_circle(Vector2(c.position.x + 26 * ui, y + 2), 4 * ui, C_BTN_ON)
		draw_multiline_string(font, Vector2(c.position.x + 40 * ui, y + 8 * ui), l, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 4, C_INK)
		var lines_n := ceili(font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / tw * 1.06)
		y += lines_n * fs * 1.2 + 14 * ui
	for b in buttons:
		_draw_button(b)


func _draw_beam_s(a: Vector2, b: Vector2, m: int, s: float) -> void:
	var w := s * (0.22 if m == BridgeSim.Mat.ROAD else 0.14)
	if m == BridgeSim.Mat.WOOD:
		draw_line(a, b, C_WOOD_DARK, w + 2)
	draw_line(a, b, C_ROAD if m == BridgeSim.Mat.ROAD else C_WOOD, w)


func _dev_card() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 40, 380 * ui)
	return Rect2((vs.x - w) * 0.5, vs.y * 0.5 - 150 * ui, w, 290 * ui)


func _draw_dev() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
	var c := _dev_card()
	_box(c, Color("fbfaf7"), 16)
	_text_c("Dev menu", Vector2(c.get_center().x, c.position.y + 30 * ui), 22, C_INK)
	for b in buttons:
		_draw_button(b)


# ------------------------------------------------------------------ agent hooks

func get_agent_state() -> Dictionary:
	var st := {
		"phase": ["build", "run", "result", "final"][phase], "date": date, "puzzle": puzzle_no,
		"gap": gap, "vehicle": String(vehicle().name), "pillar_h": pillar_h, "budget": budget,
		"cost": cost(), "beams": design.size(), "tries": tries.size(), "tries_left": tries_left(),
		"best_saved": best_score(), "finished": finished, "tool": ["road", "wood", "erase"][tool],
		"tutorial": tut_open,
	}
	if sim != null:
		st["sim"] = sim.summary()
	return st
