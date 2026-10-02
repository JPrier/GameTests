extends Node2D
## Bloom — a daily Conway's Game of Life puzzle.
## Everyone gets the same map each day: walls, bonus stars and a green planting zone.
## Plant a limited number of seed cells in the zone, then let Life run for GENS generations.
## Impact = every cell your colony ever touched, plus a bonus for each star it reached.
## Three tries per day; your best counts. Share sends your score and a link to the same map.

const W := 56
const H := 56
const GENS := 150
const MAX_TRIES := 3
const STAR_BONUS := 5
const EPOCH := "2026-10-01"           # puzzle #1
const DEFAULT_URL := "https://jprier.github.io/GameTests/bloom/"
const RUN_SPEED := 32.0               # generations per second while animating

enum Phase { PLAN, RUN, RESULT, FINAL }
enum Cell { OPEN, WALL, STAR }

const C_BG := Color("0f1420")
const C_GRID_BG := Color("161d2e")
const C_LINE := Color(1, 1, 1, 0.045)
const C_WALL := Color("3a4258")
const C_WALL_HI := Color("4c5672")
const C_ZONE := Color(0.36, 0.86, 0.55, 0.13)
const C_ZONE_EDGE := Color(0.36, 0.86, 0.55, 0.75)
const C_ALIVE := Color("7cf2b0")
const C_SEED := Color("b8ffd6")
const C_TOUCHED := Color(0.18, 0.62, 0.62, 0.42)
const C_STAR := Color("ffcf5a")
const C_INK := Color("eef2fb")
const C_MUTED := Color("94a0bd")
const C_ACCENT := Color("7cf2b0")
const C_BTN := Color("26304a")
const C_BTN_PRIMARY := Color("2fbf7a")

# puzzle
var date := ""
var today := ""
var puzzle_no := 1
var budget := 10
var zone := Rect2i()
var tiles := PackedByteArray()
var star_total := 0

# player
var seeds: Dictionary = {}          # cell index -> true
var tries: Array = []               # [{score, touched, stars, alive, cells:[int]}]
var finished := false
var phase: int = Phase.PLAN
var target_score := 0               # score to beat, from a shared link (?s=)
var base_url := DEFAULT_URL

# simulation
var alive := PackedByteArray()
var touched := PackedByteArray()
var gen := 0
var gen_acc := 0.0

# ui
var buttons: Array = []             # [{id, rect, label, primary, enabled}]
var grid_rect := Rect2()            # main board on screen
var main_region := Rect2i()         # which cells the main board shows
var mini_rect := Rect2()            # inset board (plant phase only)
var text_rect := Rect2()
var zoomed := true                  # plant phase: main board zoomed on the zone
var panel_rect := Rect2()
var head_rect := Rect2()
var cell_px := 10.0
var paint_value := -1               # -1 idle, 1 adding, 0 erasing
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""
var anim_t := 0.0
var dev_open := false               # hidden dev menu: tap the title 5x quickly, or ?dev=1
var dev_taps := 0
var dev_last_tap := -10.0
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(C_BG)
	_add_key_action("run", [KEY_ENTER, KEY_SPACE])
	_add_key_action("clear", [KEY_BACKSPACE, KEY_DELETE])
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
	load_puzzle(want)
	_demo_reset()
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


# ------------------------------------------------------------------ puzzle generation

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
	generate(d)
	seeds.clear()
	tries.clear()
	finished = false
	_load_state()
	if finished or tries.size() >= MAX_TRIES:
		_enter_final()
	else:
		_show_cells(seeds.keys())
		phase = Phase.PLAN


## Build the map for a date. Deterministic: same date -> same map on every device.
func generate(d: String) -> void:
	date = d
	puzzle_no = day_number(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("bloom2:" + d).hash()   # bump the salt when generation rules change
	tiles = PackedByteArray()
	tiles.resize(W * H)
	budget = rng.randi_range(16, 28)
	var zw := rng.randi_range(10, 14)
	var zh := rng.randi_range(10, 14)
	zone = Rect2i(rng.randi_range(4, W - zw - 4), rng.randi_range(4, H - zh - 4), zw, zh)
	var guard := zone.grow(3)
	# wall segments
	for i in rng.randi_range(18, 28):
		var horiz := rng.randf() < 0.5
		var length := rng.randi_range(5, 18)
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(0, H - 1)
		for k in length:
			var p := Vector2i(x + (k if horiz else 0), y + (0 if horiz else k))
			if p.x >= W or p.y >= H:
				break
			if not guard.has_point(p):
				tiles[p.y * W + p.x] = Cell.WALL
	# scattered pillars
	for i in rng.randi_range(30, 56):
		var p := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))
		if not guard.has_point(p):
			tiles[p.y * W + p.x] = Cell.WALL
	# bonus stars, kept away from the zone
	star_total = 0
	var want_stars := rng.randi_range(16, 24)
	var far := zone.grow(5)
	var attempts := 0
	while star_total < want_stars and attempts < 5000:
		attempts += 1
		var p := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))
		var i := p.y * W + p.x
		if tiles[i] != Cell.OPEN or far.has_point(p):
			continue
		tiles[i] = Cell.STAR
		star_total += 1


func in_zone(i: int) -> bool:
	return zone.has_point(Vector2i(i % W, i / W))


# ------------------------------------------------------------------ simulation (B3/S23, walls are dead)

func _reset_sim() -> void:
	alive = PackedByteArray()
	alive.resize(W * H)
	touched = PackedByteArray()
	touched.resize(W * H)
	gen = 0
	gen_acc = 0.0


func _start_sim(cells: Array) -> void:
	_reset_sim()
	for c in cells:
		alive[int(c)] = 1
		touched[int(c)] = 1


func step() -> void:
	# Count neighbours by visiting live cells only (boards are mostly empty).
	var counts := PackedByteArray()
	counts.resize(W * H)
	for i in W * H:
		if alive[i] == 0:
			continue
		var x := i % W
		var y := i / W
		for dy in range(-1, 2):
			var yy := y + dy
			if yy < 0 or yy >= H:
				continue
			for dx in range(-1, 2):
				var xx := x + dx
				if (dx != 0 or dy != 0) and xx >= 0 and xx < W:
					counts[yy * W + xx] += 1
	var nxt := PackedByteArray()
	nxt.resize(W * H)
	for i in W * H:
		var n := counts[i]
		if (n == 3 or (n == 2 and alive[i] == 1)) and tiles[i] != Cell.WALL:
			nxt[i] = 1
			touched[i] = 1
	alive = nxt
	gen += 1


func current_score() -> Dictionary:
	var t := 0
	var s := 0
	for i in W * H:
		if touched[i] == 1:
			t += 1
			if tiles[i] == Cell.STAR:
				s += 1
	return {"score": t + s * STAR_BONUS, "touched": t, "stars": s, "alive": alive.count(1)}


## Run a pattern to the end and return its score (leaves the final state on the board).
func simulate(cells: Array) -> Dictionary:
	_start_sim(cells)
	while gen < GENS:
		step()
	return current_score()


func _show_cells(cells: Array) -> void:
	_start_sim(cells)


# ------------------------------------------------------------------ game flow

func run() -> void:
	if phase != Phase.PLAN or seeds.is_empty():
		return
	_start_sim(seeds.keys())
	phase = Phase.RUN


func skip() -> void:
	if phase == Phase.RUN:
		while gen < GENS:
			step()
		_finish_try()


func _finish_try() -> void:
	var r := current_score()
	var cells: Array = seeds.keys()
	cells.sort()
	r["cells"] = cells
	tries.append(r)
	_save_state()
	if tries.size() >= MAX_TRIES:
		_enter_final(false)
	else:
		phase = Phase.RESULT


func try_again() -> void:
	if phase == Phase.RESULT:
		_show_cells(seeds.keys())
		phase = Phase.PLAN
		zoomed = true


func finish() -> void:
	if not tries.is_empty():
		finished = true
		_save_state()
		_enter_final()


func _enter_final(resimulate := true) -> void:
	phase = Phase.FINAL
	if resimulate and not tries.is_empty():
		simulate(best_try().cells)


func clear_seeds() -> void:
	if phase == Phase.PLAN:
		seeds.clear()
		_reset_sim()


func toggle(i: int) -> bool:
	if phase == Phase.RESULT:
		try_again()
	if phase != Phase.PLAN:
		return false
	if seeds.has(i):
		seeds.erase(i)
	elif _can_place(i):
		seeds[i] = true
	else:
		return false
	_show_cells(seeds.keys())
	return true


func _can_place(i: int) -> bool:
	return i >= 0 and i < W * H and in_zone(i) and tiles[i] != Cell.WALL and seeds.size() < budget


func best_try() -> Dictionary:
	var best: Dictionary = {}
	for t in tries:
		if best.is_empty() or int(t.score) > int(best.score):
			best = t
	return best


func best_score() -> int:
	return int(best_try().get("score", 0))


# ------------------------------------------------------------------ saving (user:// is IndexedDB on the web)

func _save_path() -> String:
	return "user://bloom2_%s.json" % date   # bloom2: 56x56 maps (old bloom_ saves used 28x28)


func _save_state() -> void:
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"tries": tries, "seeds": seeds.keys(), "finished": finished}))


func _load_state() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if not data is Dictionary:
		return
	for t in data.get("tries", []):
		var cells: Array = []
		for c in t.get("cells", []):
			cells.append(int(c))
		tries.append({"score": int(t.score), "touched": int(t.touched), "stars": int(t.stars),
			"alive": int(t.get("alive", 0)), "cells": cells})
	for c in data.get("seeds", []):
		seeds[int(c)] = true
	finished = bool(data.get("finished", false))


## Forget today's progress (used by tests).
func wipe_save() -> void:
	_wipe_file(_save_path())
	_flush_storage()


## Overwrite then delete: on the web a write is what reliably reaches IndexedDB,
## and an empty file loads as a fresh day even if the delete doesn't persist.
func _wipe_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("{}")
		f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## On the web, user:// is IndexedDB and only syncs after a file write closes,
## so deletions need a write afterwards to actually persist.
func _flush_storage() -> void:
	var f := FileAccess.open("user://.sync", FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


# ------------------------------------------------------------------ sharing

func share_link() -> String:
	return "%s?d=%s&s=%d" % [base_url, date, best_score()]


func share_text() -> String:
	var scores := PackedStringArray()
	for t in tries:
		scores.append(str(t.score))
	var best := best_try()
	var lines := PackedStringArray()
	lines.append("Bloom #%d 🌱 %s" % [puzzle_no, date])
	lines.append("Impact %d  ⭐ %d/%d" % [best_score(), int(best.get("stars", 0)), star_total])
	lines.append("Tries: " + " → ".join(scores))
	if target_score > 0:
		if best_score() > target_score:
			lines.append("Beat the %d I was sent 💥" % target_score)
		else:
			lines.append("Couldn't beat %d — can you?" % target_score)
	lines.append("Can you beat it? " + share_link())
	return "\n".join(lines)


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__bloomShare='pending';
			var done=function(r){if(window.__bloomShare==='pending'){window.__bloomShare=r;}};
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
					setTimeout(function(){if(window.__bloomShare==='pending'){ask();}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},ask);
				}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__bloomCopyNext){
				// Never fall back to the clipboard from here: the share sheet has used up the tap's
				// user gesture, and a clipboard write without one makes Chrome show a permission prompt.
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__bloomCopyNext=true;done('share_failed');}
				});
			}else{window.__bloomCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Result copied — paste it anywhere")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__bloomShare||''", true)
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


# ------------------------------------------------------------------ frame + input

func _process(delta: float) -> void:
	anim_t += delta
	if tut_open:
		_tut_process(delta)
	elif pg_open and not dev_open:
		_pg_process(delta)
	if toast_t > 0.0:
		toast_t -= delta
	if share_pending:
		_poll_share()
	if phase == Phase.RUN:
		gen_acc += delta * RUN_SPEED
		while gen_acc >= 1.0 and gen < GENS:
			gen_acc -= 1.0
			step()
		if gen >= GENS:
			_finish_try()
	if tut_open:
		if Input.is_action_just_pressed("run"):
			tut_next()
	elif pg_open:
		pass
	elif Input.is_action_just_pressed("run"):
		match phase:
			Phase.PLAN: run()
			Phase.RUN: skip()
			Phase.RESULT: try_again()
	if Input.is_action_just_pressed("clear") and not tut_open and not pg_open:
		clear_seeds()
	_layout()
	queue_redraw()


func _input(ev: InputEvent) -> void:
	if pg_open and not tut_open and not dev_open:
		_pg_input(ev)
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			if dev_open or tut_open:
				_press_button(p)
				return
			if help_rect.grow(10).has_point(p):
				open_tutorial()
				return
			if pg_entry_rect.has_area() and pg_entry_rect.grow(6).has_point(p):
				open_playground()
				return
			if Rect2(head_rect.position, Vector2(170, 60)).has_point(p):
				_dev_tap()
				return
			if _press_button(p):
				return
			if phase == Phase.PLAN and mini_rect.has_area() and mini_rect.grow(8).has_point(p):
				toggle_zoom()
				return
			if phase == Phase.RESULT and grid_rect.has_point(p):
				try_again()   # back to planting (zoomed) — the next tap edits
				return
			var c := _cell_at(p)
			if c >= 0 and phase == Phase.PLAN:
				if seeds.has(c):
					paint_value = 0
				elif in_zone(c):
					paint_value = 1
					if seeds.size() >= budget:
						_toast("All %d seeds planted — tap one to remove it" % budget)
				else:
					_toast("Plant inside the green zone")
				_paint(c)
		else:
			paint_value = -1
	elif ev is InputEventMouseMotion and paint_value >= 0:
		_paint(_cell_at(make_input_local(ev).position))


func _dev_tap() -> void:
	dev_taps = dev_taps + 1 if anim_t - dev_last_tap < 0.6 else 1
	dev_last_tap = anim_t
	if dev_taps >= 5:
		dev_taps = 0
		dev_open = true


## Dev: forget today's tries and seeds.
func dev_reset_today() -> void:
	wipe_save()
	load_puzzle(date)
	dev_open = false
	_toast("Dev: today's progress reset")


## Dev: forget every saved day.
func dev_reset_all() -> void:
	var n := 0
	var dir := DirAccess.open("user://")
	if dir:
		for f in dir.get_files():
			if f.begins_with("bloom") and f.ends_with(".json"):
				_wipe_file("user://" + f)
				n += 1
	_wipe_file(TUT_FLAG)
	_flush_storage()
	load_puzzle(date)
	dev_open = false
	_toast("Dev: cleared %d saved day(s) + tutorial" % n)


func toggle_zoom() -> void:
	zoomed = not zoomed


func _paint(c: int) -> void:
	if c < 0 or phase != Phase.PLAN:
		return
	if paint_value == 1 and not seeds.has(c) and _can_place(c):
		toggle(c)
	elif paint_value == 0 and seeds.has(c):
		toggle(c)


## Square block of cells around the planting zone, used for the zoomed plant view.
func plant_region() -> Rect2i:
	var r := zone.grow(1)
	var side: int = min(max(r.size.x, r.size.y), min(W, H))
	var x: int = clamp(r.position.x - (side - r.size.x) / 2, 0, W - side)
	var y: int = clamp(r.position.y - (side - r.size.y) / 2, 0, H - side)
	return Rect2i(x, y, side, side)


func _region_for_main() -> Rect2i:
	if phase == Phase.PLAN and zoomed:
		return plant_region()
	return Rect2i(0, 0, W, H)


func _board_cell_px(rect: Rect2, region: Rect2i) -> float:
	return min(rect.size.x / region.size.x, rect.size.y / region.size.y)


func _cell_at(p: Vector2) -> int:
	if not grid_rect.has_point(p):
		return -1
	var x := main_region.position.x + int((p.x - grid_rect.position.x) / cell_px)
	var y := main_region.position.y + int((p.y - grid_rect.position.y) / cell_px)
	if not main_region.has_point(Vector2i(x, y)):
		return -1
	return y * W + x


func _press_button(p: Vector2) -> bool:
	for b in buttons:
		if b.rect.has_point(p):
			if b.enabled:
				match b.id:
					"run": run()
					"clear": clear_seeds()
					"skip": skip()
					"again": try_again()
					"finish": finish()
					"share": share()
					"today": play_today()
					"dev_today": dev_reset_today()
					"dev_all": dev_reset_all()
					"dev_close": dev_open = false
					"tut_skip": close_tutorial()
					"tut_next": tut_next()
					"tut_back": tut_back()
					"pg_play": pg_toggle_play()
					"pg_step":
						pg_running = false
						pg_step()
					"pg_reset": pg_reset()
					"pg_clear": pg_clear()
			return true
	return false


# ------------------------------------------------------------------ layout + drawing

func _layout() -> void:
	if pg_open:
		buttons.clear()
		_pg_layout()
		if tut_open or dev_open:
			_build_buttons()   # overlay buttons replace the playground controls
		return
	var vs := get_viewport_rect().size
	var m := 20.0
	var portrait := vs.y >= vs.x * 1.05
	var plan := phase == Phase.PLAN
	if portrait:
		head_rect = Rect2(m, m, vs.x - m * 2, 110)
		var g: float = min(vs.x - m * 2, vs.y - head_rect.end.y - 360)
		g = max(g, 200.0)
		grid_rect = Rect2((vs.x - g) / 2.0, head_rect.end.y + 8, g, g)
		panel_rect = Rect2(m, grid_rect.end.y + 28, vs.x - m * 2, vs.y - grid_rect.end.y - 28 - m)
		text_rect = Rect2(panel_rect.position, panel_rect.size - Vector2(0, 80))
		mini_rect = Rect2()
		if plan:
			var ms: float = min(230.0, panel_rect.size.y - 80 - 16)
			ms = min(ms, panel_rect.size.x * 0.42)
			mini_rect = Rect2(panel_rect.position + Vector2(4, 4), Vector2(ms, ms))
			text_rect = Rect2(panel_rect.position.x + ms + 28, panel_rect.position.y, panel_rect.size.x - ms - 28, text_rect.size.y)
	else:
		var g: float = min(vs.y - m * 2, vs.x * 0.58)
		grid_rect = Rect2(m * 1.5, (vs.y - g) / 2.0, g, g)
		var px := grid_rect.end.x + 32
		head_rect = Rect2(px, grid_rect.position.y, vs.x - px - m * 1.5, 110)
		panel_rect = Rect2(px, head_rect.end.y + 12, head_rect.size.x, grid_rect.end.y - head_rect.end.y - 12)
		text_rect = Rect2(panel_rect.position, panel_rect.size - Vector2(0, 80))
		mini_rect = Rect2()
		if plan:
			var ms: float = min(170.0, panel_rect.size.x * 0.6, panel_rect.size.y * 0.4)
			mini_rect = Rect2(panel_rect.position + Vector2(4, 4), Vector2(ms, ms))
			text_rect = Rect2(panel_rect.position.x, mini_rect.end.y + 40, panel_rect.size.x, panel_rect.end.y - 80 - mini_rect.end.y - 40)
	main_region = _region_for_main()
	cell_px = _board_cell_px(grid_rect, main_region)
	grid_rect.size = Vector2(main_region.size) * cell_px
	_build_buttons()


func _build_buttons() -> void:
	buttons.clear()
	if tut_open and not dev_open:
		_tut_layout()
		return
	if dev_open:
		var vs := get_viewport_rect().size
		var w: float = min(vs.x - 80, 420.0)
		var x := (vs.x - w) / 2.0
		var y := vs.y / 2.0 - 110
		for l in [["dev_today", "Reset today", true], ["dev_all", "Reset all days", true], ["dev_close", "Close", false]]:
			buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": true, "rect": Rect2(x, y, w, 64)})
			y += 78
		return
	var labels: Array = []
	match phase:
		Phase.PLAN:
			labels = [["run", "Run", true, not seeds.is_empty()], ["clear", "Clear", false, not seeds.is_empty()]]
		Phase.RUN:
			labels = [["skip", "Skip to end", false, true]]
		Phase.RESULT:
			labels = [["again", "Retry (%d left)" % (MAX_TRIES - tries.size()), true, true], ["finish", "Finish", false, true]]
		Phase.FINAL:
			labels = [["share", "Share score", true, true]]
			if date != today:
				labels.append(["today", "Play today's", false, true])
	var bh := 64.0
	var gap := 12.0
	var y := panel_rect.end.y - bh
	var n := labels.size()
	var x := panel_rect.position.x
	var free := panel_rect.size.x - gap * (n - 1)
	for i in n:
		var l: Array = labels[i]
		var w: float = free if n == 1 else free * (0.62 if i == 0 else 0.38)
		buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": l[3], "rect": Rect2(x, y, w, bh)})
		x += w + gap


func _draw() -> void:
	if buttons.is_empty() and phase != Phase.RUN:
		_layout()
	if pg_open:
		_pg_draw()
	else:
		_draw_header()
		_draw_board(grid_rect, main_region, phase == Phase.PLAN or phase == Phase.RESULT)
		if mini_rect.has_area():
			var full := Rect2i(0, 0, W, H)
			var mini_region: Rect2i = plant_region() if not zoomed else full
			var mr := mini_rect
			mr.size = Vector2(mini_region.size) * _board_cell_px(mini_rect, mini_region)
			_draw_board(mr, mini_region, true)
			if zoomed:
				# outline the part of the map the big view shows
				var cp := _board_cell_px(mr, full)
				var pr := plant_region()
				draw_rect(Rect2(mr.position + Vector2(pr.position) * cp, Vector2(pr.size) * cp), C_INK, false, 2.0)
			_box(mr.grow(6), Color(0, 0, 0, 0), 10, Color(C_INK, 0.25))
			var hint := "Tap: full map" if zoomed else "Tap: zoom in"
			_text_c(hint, Vector2(mr.get_center().x, mr.end.y + 30), 18, C_MUTED)
		_draw_panel()
		_draw_help_button()
	if tut_open and not dev_open:
		_draw_tutorial()
	if dev_open:
		var vs := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72))
		_text_c("Dev menu", Vector2(vs.x / 2.0, vs.y / 2.0 - 140), 32, C_STAR)
		_text_c("Saved progress for #%d (%s)" % [puzzle_no, date], Vector2(vs.x / 2.0, vs.y / 2.0 - 180), 20, C_MUTED)
	for b in buttons:
		_draw_button(b)
	if toast_t > 0.0 and toast != "":
		var a: float = clamp(toast_t * 2.0, 0.0, 1.0)
		var vs := get_viewport_rect().size
		var tw := font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 40
		var ty: float = buttons[0].rect.position.y - 64.0 if not buttons.is_empty() else grid_rect.position.y + 14
		var r := Rect2((vs.x - tw) / 2.0, ty, tw, 48)
		_box(r, Color(0.05, 0.07, 0.12, 0.92 * a), 24, Color(C_ACCENT, 0.6 * a))
		_text_c(toast, r.get_center() + Vector2(0, 8), 24, Color(C_INK, a))


func _draw_header() -> void:
	var r := head_rect
	draw_string(font, r.position + Vector2(0, 52), "Bloom", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, C_INK)
	draw_string(font, r.position + Vector2(0, 90), "#%d · %s" % [puzzle_no, date], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_MUTED)
	var label := "seeds left"
	var big := str(budget - seeds.size())
	match phase:
		Phase.FINAL:
			label = "best impact"
			big = str(best_score())
		Phase.RUN:
			label = "impact"
			big = str(current_score().score)
		Phase.RESULT:
			label = "impact"
			big = str(tries[-1].score)
	label = label.to_upper()
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, Vector2(r.end.x - lw, r.position.y + 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_MUTED)
	var bw := font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
	draw_string(font, Vector2(r.end.x - bw, r.position.y + 62), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, C_ACCENT)


## Draw the cells of `region` into `rect` (rect is already sized to whole cells).
func _draw_board(rect: Rect2, region: Rect2i, show_zone: bool) -> void:
	var cp := rect.size.x / region.size.x
	_box(rect.grow(6), C_GRID_BG, 10)
	var zr := Rect2i(zone).intersection(region)
	var zrect := Rect2(rect.position + Vector2(zr.position - region.position) * cp, Vector2(zr.size) * cp)
	if show_zone and zr.has_area():
		draw_rect(zrect, C_ZONE)
	if cp >= 6.0:
		for k in range(1, region.size.x):
			var x := rect.position.x + k * cp
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), C_LINE, 1.0)
		for k in range(1, region.size.y):
			var y := rect.position.y + k * cp
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), C_LINE, 1.0)
	var inset: float = max(0.5, cp * 0.08)
	var have_sim := alive.size() == W * H
	for cy in range(region.position.y, region.end.y):
		for cx in range(region.position.x, region.end.x):
			var i := cy * W + cx
			var cr := Rect2(rect.position + Vector2(cx - region.position.x, cy - region.position.y) * cp, Vector2(cp, cp))
			var t := tiles[i]
			if t == Cell.WALL:
				draw_rect(cr.grow(-inset * 0.5), C_WALL)
				if cp >= 8.0:
					draw_rect(Rect2(cr.position + Vector2(inset * 0.5, inset * 0.5), Vector2(cr.size.x - inset, inset * 1.5)), C_WALL_HI)
				continue
			var was_hit := have_sim and touched[i] == 1
			var is_alive := have_sim and alive[i] == 1
			if was_hit and not is_alive:
				draw_rect(cr.grow(-inset), C_TOUCHED)
			if t == Cell.STAR:
				_draw_star(cr.get_center(), cp * 0.42, was_hit)
			if is_alive:
				var col := C_ALIVE
				if phase == Phase.PLAN and seeds.has(i):
					col = C_SEED
				if cp >= 14.0:
					_box(cr.grow(-inset), col, cp * 0.22)
				else:
					draw_rect(cr.grow(-inset), col)   # cheaper for small cells on the big map
	if show_zone and zr.has_area():
		draw_rect(zrect, C_ZONE_EDGE, false, 2.0)


func _draw_star(c: Vector2, r: float, hit: bool) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	if hit:
		draw_circle(c, r * 1.15, Color(C_STAR, 0.28))
		draw_colored_polygon(pts, C_STAR)
	else:
		draw_colored_polygon(pts, Color(C_STAR, 0.6 + 0.25 * sin(anim_t * 3.0)))


func _draw_panel() -> void:
	var r := text_rect
	var lines: Array = []   # [text, size, color]
	match phase:
		Phase.PLAN:
			lines.append(["Plant up to %d seeds in the green zone." % budget, 26, C_INK])
			lines.append(["Press Run to play %d steps. Score = squares your life reaches, +%d per gold star." % [GENS, STAR_BONUS], 22, C_MUTED])
			lines.append(["Try %d of %d" % [tries.size() + 1, MAX_TRIES] + ("  ·  " + _tries_line() if not tries.is_empty() else ""), 22, C_MUTED])
		Phase.RUN:
			var s := current_score()
			lines.append(["Step %d of %d" % [gen, GENS], 28, C_INK])
			lines.append(["%d squares reached · %d/%d stars · %d alive now" % [s.touched, s.stars, star_total, s.alive], 22, C_MUTED])
		Phase.RESULT:
			var t: Dictionary = tries[-1]
			lines.append(["Impact %d" % t.score, 32, C_ACCENT])
			lines.append(["%d squares reached + %d stars × %d" % [t.touched, t.stars, STAR_BONUS], 22, C_MUTED])
			lines.append([_tries_line(), 22, C_MUTED])
			lines.append(["Tap the board to tweak your seeds.", 22, C_MUTED])
		Phase.FINAL:
			var b := best_try()
			lines.append(["Best impact %d" % best_score(), 32, C_ACCENT])
			lines.append([_tries_line() + "  ·  %d/%d stars" % [int(b.get("stars", 0)), star_total], 22, C_MUTED])
			if date == today:
				lines.append(["Next Bloom in " + _countdown(), 22, C_MUTED])
			else:
				lines.append(["Today's puzzle is waiting.", 22, C_MUTED])
	if target_score > 0:
		var beat := phase == Phase.FINAL and best_score() > target_score
		lines.append([("You beat %d!" if beat else "Score to beat: %d") % target_score, 24, C_STAR])
	var y := r.position.y + 4
	for l in lines:
		var sz: int = l[1]
		var h := font.get_multiline_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x, sz).y
		draw_multiline_string(font, Vector2(r.position.x, y + font.get_ascent(sz)), l[0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x, sz, -1, l[2])
		y += h + 10.0


func _tries_line() -> String:
	var parts := PackedStringArray()
	for t in tries:
		parts.append(str(t.score))
	return "Tries: " + ", ".join(parts)


func _countdown() -> String:
	var t := Time.get_time_dict_from_system()
	var left := 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	return "%dh %02dm" % [left / 3600, (left % 3600) / 60]


func _draw_button(b: Dictionary) -> void:
	var col: Color = C_BTN_PRIMARY if b.primary else C_BTN
	if not b.enabled:
		col = Color(col, 0.35)
	_box(b.rect, col, 14)
	var sz := 28
	while sz > 16 and font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > b.rect.size.x - 20:
		sz -= 2
	_text_c(b.label, b.rect.get_center() + Vector2(0, sz * 0.36), sz, C_INK if b.enabled else Color(C_INK, 0.4))


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


# ------------------------------------------------------------------ shared mini-board helpers

## One Life step on a small standalone grid (used by the tutorial demos and the playground).
static func life_step(cells: PackedByteArray, w: int, h: int, wrap: bool) -> PackedByteArray:
	var counts := PackedByteArray()
	counts.resize(w * h)
	for i in w * h:
		if cells[i] == 0:
			continue
		var x := i % w
		var y := i / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var xx := x + dx
				var yy := y + dy
				if wrap:
					xx = posmod(xx, w)
					yy = posmod(yy, h)
				elif xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				counts[yy * w + xx] += 1
	var nxt := PackedByteArray()
	nxt.resize(w * h)
	for i in w * h:
		var n := counts[i]
		if n == 3 or (n == 2 and cells[i] == 1):
			nxt[i] = 1
	return nxt


## Draw a small w x h board of cells into rect (square cells, centred).
func _draw_cells(rect: Rect2, cells: PackedByteArray, w: int, h: int, col := C_ALIVE) -> Rect2:
	var cp: float = min(rect.size.x / w, rect.size.y / h)
	var r := Rect2(rect.position + (rect.size - Vector2(w, h) * cp) / 2.0, Vector2(w, h) * cp)
	_box(r.grow(4), C_GRID_BG, 8)
	if cp >= 6.0:
		for k in range(1, w):
			draw_line(Vector2(r.position.x + k * cp, r.position.y), Vector2(r.position.x + k * cp, r.end.y), C_LINE)
		for k in range(1, h):
			draw_line(Vector2(r.position.x, r.position.y + k * cp), Vector2(r.end.x, r.position.y + k * cp), C_LINE)
	for i in w * h:
		if cells[i] == 1:
			var cr := Rect2(r.position + Vector2(i % w, i / w) * cp, Vector2(cp, cp)).grow(-max(0.5, cp * 0.08))
			if cp >= 14.0:
				_box(cr, col, cp * 0.22)
			else:
				draw_rect(cr, col)
	return r


# ------------------------------------------------------------------ shape library

const KIND_COL := {
	"Stays still": Color("8fb3ff"), "Blinks": Color("ffcf5a"), "Travels": Color("7cf2b0"),
	"Grows": Color("ff8fb8"), "Factory": Color("ffa25a"),
}
const SHAPES := [
	{"name": "Block", "kind": "Stays still", "rows": ["OO", "OO"],
		"desc": "4 squares in a square. Each one has exactly 3 neighbours, so nothing ever changes."},
	{"name": "Beehive", "kind": "Stays still", "rows": [".OO.", "O..O", ".OO."],
		"desc": "Another perfectly balanced shape. It just sits there forever."},
	{"name": "Blinker", "kind": "Blinks", "rows": ["OOO"],
		"desc": "3 in a row. It flips between lying flat and standing up, forever."},
	{"name": "Toad", "kind": "Blinks", "rows": [".OOO", "OOO."],
		"desc": "Two offset rows that wobble back and forth every step."},
	{"name": "Beacon", "kind": "Blinks", "rows": ["OO..", "OO..", "..OO", "..OO"],
		"desc": "Two blocks touching at a corner. The middle corners flash on and off."},
	{"name": "Pulsar", "kind": "Blinks", "rows": [
		"..OOO...OOO..", ".............", "O....O.O....O", "O....O.O....O", "O....O.O....O",
		"..OOO...OOO..", ".............", "..OOO...OOO..", "O....O.O....O", "O....O.O....O",
		"O....O.O....O", ".............", "..OOO...OOO.."],
		"desc": "A big, symmetric shape that cycles through 3 different looks."},
	{"name": "Glider", "kind": "Travels", "rows": [".O.", "..O", "OOO"],
		"desc": "Only 5 squares, but it walks diagonally: one square every 4 steps, until it hits something."},
	{"name": "Spaceship", "kind": "Travels", "rows": [".O..O", "O....", "O...O", "OOOO."],
		"desc": "A bigger traveller that moves sideways across the board."},
	{"name": "R-pentomino", "kind": "Grows", "rows": [".OO", "OO.", ".O."],
		"desc": "Just 5 squares that explode into a huge, messy colony for over 1,000 steps. Great for spreading!"},
	{"name": "Acorn", "kind": "Grows", "rows": [".O.....", "...O...", "OO..OOO"],
		"desc": "7 squares that keep growing and spreading for thousands of steps."},
	{"name": "Glider gun", "kind": "Factory", "rows": [
		"........................O...........", "......................O.O...........",
		"............OO......OO............OO", "...........O...O....OO............OO",
		"OO........O.....O...OO..............", "OO........O...O.OO....O.O...........",
		"..........O.....O.........O.........", "...........O...O....................",
		"............OO......................"],
		"desc": "A machine that builds and fires a new glider every 30 steps."},
]


static func shape_cells(idx: int) -> Array:
	var out: Array = []
	var rows: Array = SHAPES[idx].rows
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "O":
				out.append(Vector2i(x, y))
	return out


static func shape_size(idx: int) -> Vector2i:
	var rows: Array = SHAPES[idx].rows
	return Vector2i(String(rows[0]).length(), rows.size())


# ------------------------------------------------------------------ tutorial modal

const TUT_FLAG := "user://bloom_tutorial_seen"
const TUT_PAGES := 4
const DEMO_STEP := 0.7              # seconds per step in the tutorial animations
const DEMO_N := 7                   # each demo board is DEMO_N x DEMO_N, wrapping at the edges
const DEMOS := [["Block", "Stays still"], ["Blinker", "Flips back and forth"], ["Glider", "Walks away"]]

var tut_open := false
var tut_page := 0
var tut_rect := Rect2()
var help_rect := Rect2()            # the "?" button in the header
var pg_entry_rect := Rect2()        # the "Playground" chip in the header
var demos: Array = []               # PackedByteArray per demo board
var demo_t := 0.0
var demo_gen := 0


func open_tutorial() -> void:
	tut_open = true
	tut_page = 0
	_demo_reset()


func close_tutorial() -> void:
	tut_open = false
	var f := FileAccess.open(TUT_FLAG, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()


func tutorial_seen() -> bool:
	return FileAccess.file_exists(TUT_FLAG)


func tut_next() -> void:
	if tut_page < TUT_PAGES - 1:
		tut_page += 1
		_demo_reset()
	else:
		close_tutorial()


func tut_back() -> void:
	tut_page = max(tut_page - 1, 0)
	_demo_reset()


func _shape_index(name: String) -> int:
	for i in SHAPES.size():
		if SHAPES[i].name == name:
			return i
	return -1


func _demo_reset() -> void:
	demos.clear()
	for d in DEMOS:
		var cells := PackedByteArray()
		cells.resize(DEMO_N * DEMO_N)
		var idx := _shape_index(d[0])
		var sz := shape_size(idx)
		var off := Vector2i((DEMO_N - sz.x) / 2, (DEMO_N - sz.y) / 2)
		if d[0] == "Glider":
			off = Vector2i(1, 1)
		for c in shape_cells(idx):
			var p: Vector2i = c + off
			cells[p.y * DEMO_N + p.x] = 1
		demos.append(cells)
	demo_t = 0.0
	demo_gen = 0


func _demo_step() -> void:
	for i in demos.size():
		demos[i] = life_step(demos[i], DEMO_N, DEMO_N, true)
	demo_gen += 1


func _tut_process(delta: float) -> void:
	if tut_page != 2:
		return
	demo_t += delta
	while demo_t >= DEMO_STEP:
		demo_t -= DEMO_STEP
		_demo_step()


func _tut_layout() -> void:
	var vs := get_viewport_rect().size
	var w: float = min(vs.x - 32, 680.0)
	var h: float = min(vs.y - 32, 900.0)
	tut_rect = Rect2((vs.x - w) / 2.0, (vs.y - h) / 2.0, w, h)
	var bh := 64.0
	var pad := 24.0
	var y := tut_rect.end.y - pad - bh
	var bw := (tut_rect.size.x - pad * 2 - 12) / 2.0
	var x0 := tut_rect.position.x + pad
	var left := ["tut_skip", "Skip"] if tut_page == 0 else ["tut_back", "Back"]
	var right := "Let's play" if tut_page == TUT_PAGES - 1 else "Next"
	buttons.append({"id": left[0], "label": left[1], "primary": false, "enabled": true, "rect": Rect2(x0, y, bw, bh)})
	buttons.append({"id": "tut_next", "label": right, "primary": true, "enabled": true, "rect": Rect2(x0 + bw + 12, y, bw, bh)})


## Draws wrapped text at y and returns the y below it.
func _para(text: String, x: float, y: float, w: float, size: int, col: Color) -> float:
	draw_multiline_string(font, Vector2(x, y + font.get_ascent(size)), text, HORIZONTAL_ALIGNMENT_LEFT, w, size, -1, col)
	return y + font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, size).y


func _draw_tutorial() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.06, 0.82))
	_box(tut_rect, Color("18203a"), 18, Color(C_ACCENT, 0.35))
	var pad := 28.0
	var x := tut_rect.position.x + pad
	var w := tut_rect.size.x - pad * 2
	var y := tut_rect.position.y + pad
	var bottom: float = tut_rect.end.y - 24.0 - 64.0 - 20.0   # above the button row
	for i in TUT_PAGES:
		draw_circle(Vector2(tut_rect.end.x - pad - (TUT_PAGES - 1 - i) * 22, y + 12), 6, C_ACCENT if i == tut_page else Color(C_INK, 0.25))
	_text_c("%d / %d" % [tut_page + 1, TUT_PAGES], Vector2(tut_rect.end.x - pad - (TUT_PAGES - 1) * 11, y + 44), 16, C_MUTED)
	match tut_page:
		0: _tut_page_board(x, y, w, bottom)
		1: _tut_page_rules(x, y, w, bottom)
		2: _tut_page_watch(x, y, w, bottom)
		_: _tut_page_bloom(x, y, w, bottom)


func _tut_page_board(x: float, y: float, w: float, bottom: float) -> void:
	y = _para("How life works here", x, y, w - 110, 34, C_INK) + 14
	y = _para("Bloom is built on a famous puzzle called the Game of Life. The board is a field of little squares:", x, y, w, 22, C_MUTED) + 14
	# legend
	var lg := 30.0
	_box(Rect2(x, y, lg, lg), C_ALIVE, 7)
	_para("green = alive", x + lg + 10, y + 2, 200, 22, C_INK)
	_box(Rect2(x + 230, y, lg, lg), C_GRID_BG, 7, Color(C_INK, 0.2))
	_para("dark = empty", x + 230 + lg + 10, y + 2, 200, 22, C_INK)
	y += lg + 22
	# neighbour diagram: 5x5, centre square and its 8 neighbours
	var cell: float = clamp((bottom - y - 200) / 5.0, 26.0, 44.0)
	var side := cell * 5
	var at := Vector2(x + (w - side) / 2.0, y)
	_box(Rect2(at, Vector2(side, side)).grow(4), C_GRID_BG, 8)
	draw_rect(Rect2(at + Vector2(cell, cell), Vector2(cell * 3, cell * 3)), Color(C_STAR, 0.10))
	for k in range(1, 5):
		draw_line(at + Vector2(k * cell, 0), at + Vector2(k * cell, side), C_LINE)
		draw_line(at + Vector2(0, k * cell), at + Vector2(side, k * cell), C_LINE)
	for c in [Vector2i(2, 2), Vector2i(1, 1), Vector2i(3, 2), Vector2i(2, 3), Vector2i(0, 4), Vector2i(4, 0)]:
		_box(Rect2(at + Vector2(c) * cell, Vector2(cell, cell)).grow(-cell * 0.1), C_ALIVE, cell * 0.2)
	draw_rect(Rect2(at + Vector2(cell, cell), Vector2(cell * 3, cell * 3)), C_STAR, false, 2.0)
	draw_rect(Rect2(at + Vector2(cell * 2, cell * 2), Vector2(cell, cell)), C_INK, false, 3.0)
	y += side + 16
	y = _para("The 8 squares touching a square (sides and corners, inside the gold box) are its neighbours. The middle square here has 3 living neighbours.", x, y, w, 20, C_MUTED) + 16
	y = _para("Life moves in steps. At every step, each square counts its living neighbours, and that number decides if it lives, dies, or is born. You don't steer it: you only choose where life starts.", x, y, w, 22, C_INK)


func _tut_page_rules(x: float, y: float, w: float, bottom: float) -> void:
	y = _para("The 4 rules", x, y, w - 110, 34, C_INK) + 8
	y = _para("Every step, every square checks its neighbours:", x, y, w, 22, C_MUTED) + 18
	var rules := [
		["Too lonely", "A living square with 0 or 1 living neighbours dies.", [2], true, false, Color("ff8f8f")],
		["Just right", "A living square with 2 or 3 living neighbours stays alive.", [0, 4], true, true, C_ACCENT],
		["Too crowded", "A living square with 4 or more living neighbours dies.", [0, 2, 4, 6], true, false, Color("ff8f8f")],
		["New life", "An empty square with exactly 3 living neighbours comes alive.", [0, 2, 5], false, true, C_STAR],
	]
	var row_h: float = (bottom - y - 50) / 4.0
	var cell: float = clamp((row_h - 16) / 3.0, 14.0, 26.0)
	var patch := cell * 3
	var gap := 34.0
	var diag_w := patch * 2 + gap
	_text_c("before", Vector2(x + patch / 2.0, y - 4), 16, C_MUTED)
	_text_c("after", Vector2(x + patch * 1.5 + gap, y - 4), 16, C_MUTED)
	y += 10
	for rule in rules:
		_draw_patch(Vector2(x, y), cell, rule[2], rule[3])
		var ay := y + patch / 2.0
		var ax := x + patch + gap / 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(ax - 8, ay - 8), Vector2(ax + 7, ay), Vector2(ax - 8, ay + 8)]), C_MUTED)
		_draw_patch(Vector2(x + patch + gap, y), cell, rule[2], rule[4], true)
		var tx := x + diag_w + 22
		var ty := _para(rule[0], tx, y - 2, w - diag_w - 22, 24, rule[5])
		_para(rule[1], tx, ty + 2, w - diag_w - 22, 20, C_INK)
		y += max(row_h, patch + 14)
	_para("The middle square (white outline) is the one being checked. All squares update at the same moment.", x, y, w, 18, C_MUTED)


## A 3x3 patch: centre cell plus the listed neighbour slots (0..7, clockwise from top-left) alive.
func _draw_patch(at: Vector2, cell: float, alive_n: Array, centre: bool, faded := false) -> void:
	var slots := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 1)]
	var r := Rect2(at, Vector2(cell * 3, cell * 3))
	_box(r.grow(3), C_GRID_BG, 4)
	for k in range(1, 3):
		draw_line(at + Vector2(k * cell, 0), at + Vector2(k * cell, cell * 3), C_LINE)
		draw_line(at + Vector2(0, k * cell), at + Vector2(cell * 3, k * cell), C_LINE)
	for s in alive_n:
		var p: Vector2i = slots[int(s)]
		_box(Rect2(at + Vector2(p) * cell, Vector2(cell, cell)).grow(-1.5), Color(C_ALIVE, 0.35 if faded else 1.0), 3)
	var c := Rect2(at + Vector2(cell, cell), Vector2(cell, cell))
	if centre:
		_box(c.grow(-1.5), C_ALIVE, 3)
	draw_rect(c, C_INK, false, 2.0)


func _tut_page_watch(x: float, y: float, w: float, bottom: float) -> void:
	y = _para("Watch it happen", x, y, w - 110, 34, C_INK) + 8
	y = _para("Same 4 rules, different starting shapes, and very different results:", x, y, w, 22, C_MUTED) + 22
	var gap := 18.0
	var bw := (w - gap * 2) / 3.0
	for i in DEMOS.size():
		var r := Rect2(x + i * (bw + gap), y, bw, bw)
		_draw_cells(r, demos[i], DEMO_N, DEMO_N)
		_text_c(DEMOS[i][0], Vector2(r.get_center().x, r.end.y + 32), 22, C_INK)
		_text_c(DEMOS[i][1], Vector2(r.get_center().x, r.end.y + 58), 18, C_MUTED)
	y += bw + 84
	_text_c("Step %d" % demo_gen, Vector2(x + w / 2.0, y), 22, C_ACCENT)
	y += 26
	y = _para("Some shapes freeze, some blink, some travel, and some explode into big colonies. In Bloom, shapes that spread and travel reach the most squares.", x, y, w, 22, C_INK) + 14
	if y + 30 < bottom:
		_para("Want to experiment? Tap \"Playground\" at the top of the game any time.", x, y, w, 20, C_MUTED)


func _tut_page_bloom(x: float, y: float, w: float, bottom: float) -> void:
	y = _para("Today's puzzle", x, y, w - 110, 34, C_INK) + 16
	var icon := 28.0
	var tx := x + icon + 18
	var tw := w - icon - 18
	var rows := [
		["zone", "You get %d seeds (living squares). Tap squares inside the green box to plant them. Tap again to remove." % budget],
		["play", "Press Run. The 4 rules play out for %d steps across the whole map." % GENS],
		["touch", "Your score (Impact) counts every square your life ever reached, even if it died later."],
		["star", "Gold stars give +%d bonus each when your life reaches them." % STAR_BONUS],
		["wall", "Grey walls always stay empty. Life can't grow through them."],
		["tries", "You have %d tries a day and your best one counts. Everyone gets the same map, so you can compare scores." % MAX_TRIES],
	]
	for row in rows:
		var ir := Rect2(x, y + 2, icon, icon)
		match row[0]:
			"zone":
				draw_rect(ir, C_ZONE)
				draw_rect(ir, C_ZONE_EDGE, false, 2.0)
				_box(Rect2(ir.position + Vector2(8, 8), Vector2(12, 12)), C_SEED, 3)
			"play":
				_box(ir, C_BTN_PRIMARY, 6)
				draw_colored_polygon(PackedVector2Array([ir.position + Vector2(10, 7), ir.position + Vector2(21, 14), ir.position + Vector2(10, 21)]), C_INK)
			"touch":
				_box(ir.grow(-2), C_TOUCHED, 4)
			"star":
				_draw_star(ir.get_center(), 13, true)
			"wall":
				draw_rect(ir.grow(-2), C_WALL)
				draw_rect(Rect2(ir.position + Vector2(2, 2), Vector2(ir.size.x - 4, 5)), C_WALL_HI)
			"tries":
				_text_c(str(MAX_TRIES), ir.get_center() + Vector2(0, 9), 26, C_ACCENT)
		var ny := _para(row[1], tx, y, tw, 21, C_INK)
		y = max(ny, y + icon + 4) + 14
		if y > bottom:
			break
	if y + 40 < bottom:
		_para("Tip: start with a shape that grows or travels, then try small changes between tries.", x, y + 6, w, 19, C_MUTED)


func _draw_help_button() -> void:
	var tw := font.get_string_size("Bloom", HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
	help_rect = Rect2(head_rect.position + Vector2(tw + 16, 18), Vector2(40, 40))
	draw_circle(help_rect.get_center(), 19, C_BTN)
	draw_arc(help_rect.get_center(), 19, 0, TAU, 32, Color(C_INK, 0.35), 2.0)
	_text_c("?", help_rect.get_center() + Vector2(0, 9), 26, C_INK)
	# "Playground" chip on the date line
	var dw := font.get_string_size("#%d · %s" % [puzzle_no, date], HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var label := "Playground"
	var cw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 28
	pg_entry_rect = Rect2(head_rect.position + Vector2(dw + 16, 66), Vector2(cw, 34))
	if phase == Phase.RUN:
		pg_entry_rect = Rect2()
		return
	_box(pg_entry_rect, C_BTN, 17, Color(C_ACCENT, 0.5))
	_text_c(label, pg_entry_rect.get_center() + Vector2(0, 6), 18, C_ACCENT)


# ------------------------------------------------------------------ playground

const PG_N := 40
const PG_SPEED := 8.0               # steps per second while playing

var pg_open := false
var pg_cells := PackedByteArray()
var pg_start := PackedByteArray()   # board as it was when Play/Step was last started from step 0
var pg_gen := 0
var pg_running := false
var pg_acc := 0.0
var pg_shape := -1                  # -1 = draw mode, otherwise index into SHAPES
var pg_paint := -1
var pg_chips: Array = []            # [{rect, idx}]
var pg_back_rect := Rect2()


func open_playground() -> void:
	pg_open = true
	if pg_cells.size() != PG_N * PG_N:
		pg_cells.resize(PG_N * PG_N)
		# start with a few examples so Play shows something straight away
		pg_stamp(_shape_index("Block"), Vector2i(8, 8))
		pg_stamp(_shape_index("Blinker"), Vector2i(20, 8))
		pg_stamp(_shape_index("Glider"), Vector2i(31, 7))
		pg_stamp(_shape_index("R-pentomino"), Vector2i(20, 26))
		pg_start = pg_cells.duplicate()
		pg_select(_shape_index("Glider"))


func close_playground() -> void:
	pg_open = false
	pg_running = false


func pg_select(idx: int) -> void:
	pg_shape = idx


func pg_stamp(idx: int, center: Vector2i) -> void:
	var sz := shape_size(idx)
	var off := center - sz / 2
	for c in shape_cells(idx):
		var p: Vector2i = c + off
		if p.x >= 0 and p.y >= 0 and p.x < PG_N and p.y < PG_N:
			pg_cells[p.y * PG_N + p.x] = 1


func pg_toggle_play() -> void:
	if not pg_running and pg_gen == 0:
		pg_start = pg_cells.duplicate()
	pg_running = not pg_running
	pg_acc = 1.0   # take the first step right away


func pg_step() -> void:
	if pg_gen == 0:
		pg_start = pg_cells.duplicate()
	pg_cells = life_step(pg_cells, PG_N, PG_N, false)
	pg_gen += 1


func pg_reset() -> void:
	pg_running = false
	if pg_start.size() == PG_N * PG_N:
		pg_cells = pg_start.duplicate()
	pg_gen = 0


func pg_clear() -> void:
	pg_running = false
	pg_cells = PackedByteArray()
	pg_cells.resize(PG_N * PG_N)
	pg_start = pg_cells.duplicate()
	pg_gen = 0


func _pg_process(delta: float) -> void:
	if pg_running:
		pg_acc += delta * PG_SPEED
		if pg_acc >= 1.0:
			pg_acc = min(pg_acc - 1.0, 1.0)
			pg_step()
	if Input.is_action_just_pressed("run"):
		pg_toggle_play()


func _pg_layout() -> void:
	var vs := get_viewport_rect().size
	var m := 20.0
	var portrait := vs.y >= vs.x * 1.05
	if portrait:
		head_rect = Rect2(m, m, vs.x - m * 2, 110)
		var g: float = min(vs.x - m * 2, vs.y - head_rect.end.y - 380)
		g = max(g, 200.0)
		grid_rect = Rect2((vs.x - g) / 2.0, head_rect.end.y + 8, g, g)
		panel_rect = Rect2(m, grid_rect.end.y + 22, vs.x - m * 2, vs.y - grid_rect.end.y - 22 - m)
	else:
		var g: float = min(vs.y - m * 2, vs.x * 0.56)
		grid_rect = Rect2(m * 1.5, (vs.y - g) / 2.0, g, g)
		var px := grid_rect.end.x + 28
		head_rect = Rect2(px, grid_rect.position.y, vs.x - px - m * 1.5, 110)
		panel_rect = Rect2(px, head_rect.end.y + 8, head_rect.size.x, grid_rect.end.y - head_rect.end.y - 8)
	cell_px = floor(grid_rect.size.x / PG_N * 100.0) / 100.0
	grid_rect.size = Vector2(PG_N, PG_N) * cell_px
	# shape chips, flowing left to right
	pg_chips.clear()
	var fs := 18
	var ch := 40.0
	var x := panel_rect.position.x
	var y := panel_rect.position.y
	var names: Array = ["Draw"]
	for s in SHAPES:
		names.append(s.name)
	for i in names.size():
		var cw: float = font.get_string_size(names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 30
		if x + cw > panel_rect.end.x and x > panel_rect.position.x:
			x = panel_rect.position.x
			y += ch + 8
		pg_chips.append({"rect": Rect2(x, y, cw, ch), "idx": i - 1, "label": names[i]})
		x += cw + 8
	# controls
	var bh := 60.0
	var gap := 10.0
	var by := panel_rect.end.y - bh
	var labels := [["pg_play", "Pause" if pg_running else "Play", true], ["pg_step", "Step", false], ["pg_reset", "Reset", false], ["pg_clear", "Clear", false]]
	var bw := (panel_rect.size.x - gap * 3) / 4.0
	for i in labels.size():
		buttons.append({"id": labels[i][0], "label": labels[i][1], "primary": labels[i][2], "enabled": true,
			"rect": Rect2(panel_rect.position.x + i * (bw + gap), by, bw, bh)})


func _pg_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if not ev.pressed:
			pg_paint = -1
			return
		if pg_back_rect.grow(6).has_point(p):
			close_playground()
			return
		if help_rect.grow(10).has_point(p):
			open_tutorial()
			return
		if _press_button(p):
			return
		for chip in pg_chips:
			if chip.rect.has_point(p):
				pg_select(chip.idx)
				return
		var c := _pg_cell_at(p)
		if c < 0:
			return
		if pg_shape >= 0:
			pg_stamp(pg_shape, Vector2i(c % PG_N, c / PG_N))
			if pg_gen > 0 and not pg_running:
				pg_gen = 0   # edited after running: the next Play starts a fresh run from here
		else:
			pg_paint = 0 if pg_cells[c] == 1 else 1
			pg_cells[c] = pg_paint
	elif ev is InputEventMouseMotion and pg_paint >= 0:
		var c := _pg_cell_at(make_input_local(ev).position)
		if c >= 0:
			pg_cells[c] = pg_paint


func _pg_cell_at(p: Vector2) -> int:
	if not grid_rect.has_point(p):
		return -1
	var x := int((p.x - grid_rect.position.x) / cell_px)
	var y := int((p.y - grid_rect.position.y) / cell_px)
	if x < 0 or y < 0 or x >= PG_N or y >= PG_N:
		return -1
	return y * PG_N + x


func _pg_draw() -> void:
	var r := head_rect
	draw_string(font, r.position + Vector2(0, 52), "Playground", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, C_INK)
	var tw := font.get_string_size("Playground", HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	help_rect = Rect2(head_rect.position + Vector2(tw + 16, 16), Vector2(40, 40))
	draw_circle(help_rect.get_center(), 19, C_BTN)
	draw_arc(help_rect.get_center(), 19, 0, TAU, 32, Color(C_INK, 0.35), 2.0)
	_text_c("?", help_rect.get_center() + Vector2(0, 9), 26, C_INK)
	var back := "Back to puzzle"
	var bw := font.get_string_size(back, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 28
	pg_back_rect = Rect2(r.position + Vector2(0, 66), Vector2(bw, 34))
	_box(pg_back_rect, C_BTN, 17, Color(C_ACCENT, 0.5))
	_text_c(back, pg_back_rect.get_center() + Vector2(0, 6), 18, C_ACCENT)
	var big := str(pg_gen)
	var lw := font.get_string_size("STEP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, Vector2(r.end.x - lw, r.position.y + 14), "STEP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_MUTED)
	var bigw := font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
	draw_string(font, Vector2(r.end.x - bigw, r.position.y + 62), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, C_ACCENT)
	var al := "%d alive" % pg_cells.count(1)
	var aw := font.get_string_size(al, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(r.end.x - aw, r.position.y + 92), al, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_MUTED)
	_draw_cells(grid_rect, pg_cells, PG_N, PG_N)
	# chips
	for chip in pg_chips:
		var sel: bool = chip.idx == pg_shape
		var kc: Color = C_INK if chip.idx < 0 else KIND_COL[SHAPES[chip.idx].kind]
		_box(chip.rect, Color(kc, 0.22) if sel else C_BTN, 20, kc if sel else Color(kc, 0.35))
		_text_c(chip.label, chip.rect.get_center() + Vector2(0, 6), 18, C_INK if sel else Color(C_INK, 0.8))
	# description of the selected tool
	var top: float = pg_chips[-1].rect.end.y + 18
	var bottom: float = panel_rect.end.y - 60.0 - 12.0
	var x := panel_rect.position.x
	var w := panel_rect.size.x
	if pg_shape < 0:
		var y := _para("Draw", x, top, w, 24, C_INK) + 4
		_para("Tap or drag on the board to add or remove living squares. Pick a shape above to drop in a famous pattern instead.", x, y, w, 20, C_MUTED)
	else:
		var s: Dictionary = SHAPES[pg_shape]
		var sz := shape_size(pg_shape)
		var pv: float = min(110.0, bottom - top - 10)
		var tx := x
		if pv >= 60.0:
			var cells := PackedByteArray()
			cells.resize((sz.x + 2) * (sz.y + 2))
			for c in shape_cells(pg_shape):
				cells[(c.y + 1) * (sz.x + 2) + c.x + 1] = 1
			_draw_cells(Rect2(x + 4, top + 4, pv, pv), cells, sz.x + 2, sz.y + 2, KIND_COL[s.kind])
			tx = x + pv + 22
		var y := _para(s.name, tx, top, w - (tx - x), 24, C_INK)
		y = _para(s.kind.to_upper(), tx, y + 2, w - (tx - x), 16, KIND_COL[s.kind]) + 6
		y = _para(s.desc, tx, y, w - (tx - x), 20, C_MUTED) + 6
		if y + 24 < bottom:
			_para("Tap the board to place it, then press Play.", tx, y, w - (tx - x), 18, C_ACCENT)


# ------------------------------------------------------------------ agent hooks

func get_agent_state() -> Dictionary:
	var sc: Dictionary = current_score() if alive.size() == W * H else {}
	return {
		"phase": Phase.keys()[phase], "date": date, "puzzle": puzzle_no, "budget": budget,
		"seeds": seeds.size(), "zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y],
		"gen": gen, "score": sc, "zoomed": zoomed, "tutorial": tut_open, "tut_page": tut_page, "playground": pg_open, "pg_gen": pg_gen, "pg_alive": pg_cells.count(1), "tries": tries.map(func(t): return t.score), "best": best_score(),
		"stars": star_total, "target": target_score, "share": share_text() if not tries.is_empty() else "",
	}
