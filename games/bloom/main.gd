extends Node2D
## Bloom — a daily Conway's Game of Life puzzle.
## Everyone gets the same map each day: walls, bonus stars and a green planting zone.
## Plant a limited number of seed cells in the zone, then let Life run for GENS generations.
## Impact = every cell your colony ever touched, plus a bonus for each star it reached.
## Three tries per day; your best counts. Share sends your score and a link to the same map.

const W := 28
const H := 28
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
var grid_rect := Rect2()
var panel_rect := Rect2()
var head_rect := Rect2()
var cell_px := 10.0
var paint_value := -1               # -1 idle, 1 adding, 0 erasing
var toast := ""
var toast_t := 0.0
var share_pending := false
var last_share_text := ""
var anim_t := 0.0
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
	var s := String(url.get("s", ""))
	target_score = int(s) if s.is_valid_int() else 0
	load_puzzle(want)


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
	rng.seed = ("bloom:" + d).hash()
	tiles = PackedByteArray()
	tiles.resize(W * H)
	budget = rng.randi_range(8, 14)
	var zw := rng.randi_range(6, 8)
	var zh := rng.randi_range(6, 8)
	zone = Rect2i(rng.randi_range(2, W - zw - 2), rng.randi_range(2, H - zh - 2), zw, zh)
	var guard := zone.grow(2)
	# wall segments
	for i in rng.randi_range(5, 8):
		var horiz := rng.randf() < 0.5
		var length := rng.randi_range(4, 12)
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(0, H - 1)
		for k in length:
			var p := Vector2i(x + (k if horiz else 0), y + (0 if horiz else k))
			if p.x >= W or p.y >= H:
				break
			if not guard.has_point(p):
				tiles[p.y * W + p.x] = Cell.WALL
	# scattered pillars
	for i in rng.randi_range(8, 16):
		var p := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))
		if not guard.has_point(p):
			tiles[p.y * W + p.x] = Cell.WALL
	# bonus stars, kept away from the zone
	star_total = 0
	var want_stars := rng.randi_range(8, 12)
	var far := zone.grow(3)
	var attempts := 0
	while star_total < want_stars and attempts < 2000:
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
	var nxt := PackedByteArray()
	nxt.resize(W * H)
	for y in H:
		for x in W:
			var i := y * W + x
			if tiles[i] == Cell.WALL:
				continue
			var n := 0
			for dy in range(-1, 2):
				var yy := y + dy
				if yy < 0 or yy >= H:
					continue
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var xx := x + dx
					if xx >= 0 and xx < W:
						n += alive[yy * W + xx]
			if n == 3 or (n == 2 and alive[i] == 1):
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
	return "user://bloom_%s.json" % date


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
	if FileAccess.file_exists(_save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))


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
			if(navigator.share&&touch){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}else{copy();}
				});
			}else{copy();}
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
		return JSON.stringify({d:p.get('d')||'',s:p.get('s')||'',base:location.origin+location.pathname});})()""", true)
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
	if phase == Phase.RUN:
		gen_acc += delta * RUN_SPEED
		while gen_acc >= 1.0 and gen < GENS:
			gen_acc -= 1.0
			step()
		if gen >= GENS:
			_finish_try()
	if Input.is_action_just_pressed("run"):
		match phase:
			Phase.PLAN: run()
			Phase.RUN: skip()
			Phase.RESULT: try_again()
	if Input.is_action_just_pressed("clear"):
		clear_seeds()
	_layout()
	queue_redraw()


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			if _press_button(p):
				return
			var c := _cell_at(p)
			if c >= 0 and (phase == Phase.PLAN or phase == Phase.RESULT):
				try_again()
				if seeds.has(c):
					paint_value = 0
				elif in_zone(c):
					paint_value = 1
					if seeds.size() >= budget:
						_toast("All %d seeds planted — tap one to remove it" % budget)
				_paint(c)
		else:
			paint_value = -1
	elif ev is InputEventMouseMotion and paint_value >= 0:
		_paint(_cell_at(make_input_local(ev).position))


func _paint(c: int) -> void:
	if c < 0 or phase != Phase.PLAN:
		return
	if paint_value == 1 and not seeds.has(c) and _can_place(c):
		toggle(c)
	elif paint_value == 0 and seeds.has(c):
		toggle(c)


func _cell_at(p: Vector2) -> int:
	if not grid_rect.has_point(p):
		return -1
	var x := int((p.x - grid_rect.position.x) / cell_px)
	var y := int((p.y - grid_rect.position.y) / cell_px)
	if x < 0 or y < 0 or x >= W or y >= H:
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
			return true
	return false


# ------------------------------------------------------------------ layout + drawing

func _layout() -> void:
	var vs := get_viewport_rect().size
	var m := 20.0
	var portrait := vs.y >= vs.x * 1.05
	if portrait:
		head_rect = Rect2(m, m, vs.x - m * 2, 110)
		var g: float = min(vs.x - m * 2, vs.y - head_rect.end.y - 330)
		g = max(g, 200.0)
		grid_rect = Rect2((vs.x - g) / 2.0, head_rect.end.y + 8, g, g)
		panel_rect = Rect2(m, grid_rect.end.y + 30, vs.x - m * 2, vs.y - grid_rect.end.y - 30 - m)
	else:
		var g: float = min(vs.y - m * 2, vs.x * 0.6)
		grid_rect = Rect2(m * 1.5, (vs.y - g) / 2.0, g, g)
		var px := grid_rect.end.x + 32
		head_rect = Rect2(px, grid_rect.position.y, vs.x - px - m * 1.5, 110)
		panel_rect = Rect2(px, head_rect.end.y + 12, head_rect.size.x, grid_rect.end.y - head_rect.end.y - 12)
	cell_px = grid_rect.size.x / W
	_build_buttons()


func _build_buttons() -> void:
	buttons.clear()
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
	_draw_header()
	_draw_grid()
	_draw_panel()
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


func _cell_rect(i: int) -> Rect2:
	return Rect2(grid_rect.position + Vector2(i % W, i / W) * cell_px, Vector2(cell_px, cell_px))


func _draw_grid() -> void:
	_box(grid_rect.grow(6), C_GRID_BG, 10)
	var zr := Rect2(grid_rect.position + Vector2(zone.position) * cell_px, Vector2(zone.size) * cell_px)
	var show_zone := phase == Phase.PLAN or phase == Phase.RESULT
	if show_zone:
		draw_rect(zr, C_ZONE)
	for k in range(1, W):
		var x := grid_rect.position.x + k * cell_px
		draw_line(Vector2(x, grid_rect.position.y), Vector2(x, grid_rect.end.y), C_LINE, 1.0)
		var y := grid_rect.position.y + k * cell_px
		draw_line(Vector2(grid_rect.position.x, y), Vector2(grid_rect.end.x, y), C_LINE, 1.0)
	var inset: float = max(1.0, cell_px * 0.08)
	var have_sim := alive.size() == W * H
	for i in W * H:
		var cr := _cell_rect(i)
		var t := tiles[i]
		if t == Cell.WALL:
			draw_rect(cr.grow(-inset * 0.5), C_WALL)
			draw_rect(Rect2(cr.position + Vector2(inset * 0.5, inset * 0.5), Vector2(cr.size.x - inset, inset * 1.5)), C_WALL_HI)
			continue
		var was_hit := have_sim and touched[i] == 1
		if was_hit and alive[i] == 0:
			draw_rect(cr.grow(-inset), C_TOUCHED)
		if t == Cell.STAR:
			_draw_star(cr.get_center(), cell_px * 0.42, was_hit)
		if have_sim and alive[i] == 1:
			var col := C_SEED if (phase == Phase.PLAN and seeds.has(i)) else C_ALIVE
			_box(cr.grow(-inset), col, cell_px * 0.22)
	if show_zone:
		draw_rect(zr, C_ZONE_EDGE, false, 2.0)


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
	var r := panel_rect
	var lines: Array = []   # [text, size, color]
	match phase:
		Phase.PLAN:
			lines.append(["Plant up to %d seeds in the green zone, then run Life for %d generations." % [budget, GENS], 26, C_INK])
			lines.append(["Impact = every cell your colony touches, +%d for each gold star it reaches." % STAR_BONUS, 22, C_MUTED])
			lines.append(["Try %d of %d" % [tries.size() + 1, MAX_TRIES] + ("  ·  " + _tries_line() if not tries.is_empty() else ""), 22, C_MUTED])
		Phase.RUN:
			var s := current_score()
			lines.append(["Generation %d / %d" % [gen, GENS], 28, C_INK])
			lines.append(["%d cells touched · %d/%d stars · %d alive" % [s.touched, s.stars, star_total, s.alive], 22, C_MUTED])
		Phase.RESULT:
			var t: Dictionary = tries[-1]
			lines.append(["Impact %d" % t.score, 32, C_ACCENT])
			lines.append(["%d cells + %d stars × %d" % [t.touched, t.stars, STAR_BONUS], 22, C_MUTED])
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


# ------------------------------------------------------------------ agent hooks

func get_agent_state() -> Dictionary:
	var sc: Dictionary = current_score() if alive.size() == W * H else {}
	return {
		"phase": Phase.keys()[phase], "date": date, "puzzle": puzzle_no, "budget": budget,
		"seeds": seeds.size(), "zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y],
		"gen": gen, "score": sc, "tries": tries.map(func(t): return t.score), "best": best_score(),
		"stars": star_total, "target": target_score, "share": share_text() if not tries.is_empty() else "",
	}
