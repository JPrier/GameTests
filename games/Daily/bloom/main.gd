extends Node2D
## Bloom — a daily Conway's Game of Life puzzle.
## Everyone gets the same map each day: walls, bonus stars and a green planting zone.
## Plant a limited number of seed cells in the zone, then let Life run for GENS generations.
## Impact = every cell your colony ever touched, plus a bonus for each star it reached.
## Three tries per day; your best counts. Share sends your score and a link to the same map.

const W := 56
const H := 56
const GENS := 150
const MAX_TRIES := 5
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
	GTUI.setup(self, {
		"bg": C_BG, "surface": C_GRID_BG, "surface_high": C_BTN, "text": C_INK, "text_muted": C_MUTED,
		"border": Color(C_INK, 0.12), "accent": C_BTN_PRIMARY, "on_accent": Color("06180e"),
		"success": C_ALIVE, "danger": Color("ff8f8f"), "focus": C_ACCENT,
	})
	RenderingServer.set_default_clear_color(C_BG)
	_add_key_action("run", [KEY_ENTER, KEY_SPACE])
	_add_key_action("clear", [KEY_BACKSPACE, KEY_DELETE])
	today = Time.get_date_string_from_system(false)
	var want := today
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_open = String(url.get("dev", "")) == "1"
	# Links always open today's puzzle; past days are picked in-game. Only ?dev=1 honours ?d= / ?s=.
	if dev_open:
		if _valid_date(String(url.get("d", ""))):
			want = String(url.d)
		var s := String(url.get("s", ""))
		target_score = int(s) if s.is_valid_int() else 0
	elif String(url.get("d", "")) != "" or String(url.get("s", "")) != "":
		_clean_url()
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
	practice = false
	no_limits = false
	if tool >= 0 and not DAILY_TOOLS.has(SHAPES[tool].name):
		tool = -1
	generate(d)
	zoomed = true
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
	build_map("bloom3:" + d)   # bump the salt when generation rules change


## Cave-style map: random noise smoothed into open blobs of wall, then any open area
## that life could never reach from the planting zone is filled in.
func build_map(seed_text: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_text.hash()
	tiles = PackedByteArray()
	tiles.resize(W * H)
	budget = rng.randi_range(16, 28)
	var zw := rng.randi_range(10, 14)
	var zh := rng.randi_range(10, 14)
	zone = Rect2i(rng.randi_range(4, W - zw - 4), rng.randi_range(4, H - zh - 4), zw, zh)
	var guard := zone.grow(3)
	var density := rng.randf_range(0.44, 0.47)
	for i in W * H:
		if rng.randf() < density and not guard.has_point(Vector2i(i % W, i / W)):
			tiles[i] = Cell.WALL
	# smooth: a wall stays with 4+ wall neighbours, an open square becomes wall with 5+
	for it in 4:
		var nxt := PackedByteArray()
		nxt.resize(W * H)
		for y in H:
			for x in W:
				var n := 0
				for dy in range(-1, 2):
					var yy := y + dy
					if yy < 0 or yy >= H:
						continue
					for dx in range(-1, 2):
						var xx := x + dx
						if (dx != 0 or dy != 0) and xx >= 0 and xx < W and tiles[yy * W + xx] == Cell.WALL:
							n += 1
				var i := y * W + x
				var wall := n >= 4 if tiles[i] == Cell.WALL else n >= 5
				if wall and not guard.has_point(Vector2i(x, y)):
					nxt[i] = Cell.WALL
		tiles = nxt
	# fill pockets that can't be reached from the zone (4-way flood fill)
	var seen := PackedByteArray()
	seen.resize(W * H)
	var start := zone.position.y * W + zone.position.x
	var stack: Array[int] = [start]
	seen[start] = 1
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % W
		var y := i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = x + d.x
			var yy: int = y + d.y
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var j := yy * W + xx
			if seen[j] == 0 and tiles[j] != Cell.WALL:
				seen[j] = 1
				stack.append(j)
	for i in W * H:
		if tiles[i] == Cell.OPEN and seen[i] == 0:
			tiles[i] = Cell.WALL
	# bonus stars on open squares, kept away from the zone
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


## True if every open square can be reached from the zone (used by tests).
func all_reachable() -> bool:
	var seen := PackedByteArray()
	seen.resize(W * H)
	var start := zone.position.y * W + zone.position.x
	var stack: Array[int] = [start]
	seen[start] = 1
	var count := 1
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = i % W + d.x
			var yy: int = i / W + d.y
			if xx < 0 or yy < 0 or xx >= W or yy >= H:
				continue
			var j := yy * W + xx
			if seen[j] == 0 and tiles[j] != Cell.WALL:
				seen[j] = 1
				count += 1
				stack.append(j)
	return count == W * H - tiles.count(Cell.WALL)


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
	if practice:
		phase = Phase.RESULT   # unlimited tries, nothing saved
		return
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
	if not practice and not tries.is_empty():
		_mark_played()
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
	if i < 0 or i >= W * H or tiles[i] == Cell.WALL:
		return false
	if _unlimited():
		return true
	return in_zone(i) and seeds.size() < budget


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
	return "user://bloom3_%s.json" % date   # bloom3: cave maps (older saves are for different maps)


func _save_state() -> void:
	if practice:
		return
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

## Always the plain game URL, so an old share still opens on today's puzzle.
func share_link() -> String:
	return base_url


## Remembers the day's best for the past-days picker and the GameTests home page.
func _mark_played() -> void:
	var label := "Impact %d" % best_score()
	_record_result(date, label)
	if OS.has_feature("web"):
		var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
			JSON.stringify("gametests:bloom:" + date), JSON.stringify(JSON.stringify({"result": label}))]
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
	var idx := clampi(day_number(today) - day_number(date), 0, archive_count() - 1) if not practice else 0
	archive_page = int(idx / ARCHIVE_ROWS)
	archive_open = true
	_layout()


func archive_shift(pages: int) -> void:
	archive_page = clampi(archive_page + pages, 0, archive_pages() - 1)
	_layout()


## Opens a past (or today's) puzzle from the picker.
func pick_day(d: String) -> void:
	archive_open = false
	if d < EPOCH or d > today:
		_layout()
		return
	if d != date or practice:
		target_score = 0
		load_puzzle(d)
	_layout()


func _results_path() -> String:
	return "user://bloom_results.json"


func _load_results() -> Dictionary:
	var out: Dictionary = {}
	if FileAccess.file_exists(_results_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_results_path()))
		if data is Dictionary:
			out = data
	return out


## Results for the picker: finished days, plus days with saved tries from before results were recorded.
func _picker_results() -> Dictionary:
	var out := _load_results()
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	for f in dir.get_files():
		if not (f.begins_with("bloom3_") and f.ends_with(".json")):
			continue
		var d := f.trim_prefix("bloom3_").trim_suffix(".json")
		if out.has(d):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("user://" + f))
		if not data is Dictionary or data.get("tries", []).is_empty():
			continue
		var best := 0
		for t in data.tries:
			best = maxi(best, int(t.get("score", 0)))
		var done: bool = data.get("finished", false) or data.tries.size() >= MAX_TRIES
		out[d] = ("Impact %d" if done else "Best %d so far") % best
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


func _archive_card() -> Rect2:
	var rh := _archive_row_h()
	var content_h := GTUI.line_height(GTUI.FS_CAPTION) + GTUI.dp(GTUI.SP_S) + ARCHIVE_ROWS * rh - GTUI.dp(GTUI.SP_S)
	return GTUI.modal_rect(self, 480, GTUI.modal_height(content_h))


func _archive_row_h() -> float:
	return GTUI.target() + GTUI.dp(GTUI.SP_S)


func _archive_buttons() -> void:
	var card := _archive_card()
	var c := GTUI.modal_content(card)
	var rh := _archive_row_h()
	var y0 := c.position.y + GTUI.line_height(GTUI.FS_CAPTION) + GTUI.dp(GTUI.SP_S)
	var days := archive_page_days(archive_page)
	for i in days.size():
		buttons.append({"id": "day_" + String(days[i]), "label": "", "primary": false, "enabled": true, "row": true,
			"rect": Rect2(c.position.x, y0 + i * rh, c.size.x, GTUI.target())})
	var pr := GTUI.row(GTUI.modal_buttons_rect(c), 2)
	buttons.append({"id": "arch_newer", "label": "Newer", "primary": false, "enabled": archive_page > 0, "rect": pr[0]})
	buttons.append({"id": "arch_older", "label": "Older", "primary": false, "enabled": archive_page < archive_pages() - 1, "rect": pr[1]})
	buttons.append({"id": "arch_close", "label": "", "primary": false, "enabled": true, "row": true, "rect": GTUI.modal_close_rect(card)})


func _draw_archive() -> void:
	var card := _archive_card()
	var c := GTUI.modal(self, card, "Past puzzles", "arch_close")
	GTUI.text(self, c.position, "Page %d of %d" % [archive_page + 1, archive_pages()], GTUI.FS_CAPTION, C_MUTED)
	for b in buttons:
		if not String(b.id).begins_with("day_"):
			continue
		var d := String(b.id).substr(4)
		var res := String(archive_results.get(d, ""))
		GTUI.list_row(self, String(b.id), b.rect, "#%d" % day_number(d), "Today" if d == today else _short_date(d),
			res if res != "" else "Not played", d == date and not practice, C_ACCENT if res != "" else Color(0, 0, 0, 0))


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
	if tut_open:
		_tut_process(delta)
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
	var keys_free := GTUI.focused_id() == ""   # Enter/Space press the focused control instead
	if tut_open:
		if keys_free and Input.is_action_just_pressed("run"):
			tut_next()
	elif keys_free and not archive_open and Input.is_action_just_pressed("run"):
		match phase:
			Phase.PLAN: run()
			Phase.RUN: skip()
			Phase.RESULT: try_again()
	if Input.is_action_just_pressed("clear") and not tut_open:
		clear_seeds()
	_layout()
	queue_redraw()


func _input(ev: InputEvent) -> void:
	var gt := GTUI.handle_input(make_input_local(ev))
	if gt.has("activate"):
		for e in GTUI.tap_events(gt.pos):
			_input(e)
		return
	if gt.has("cancel"):
		if dev_open:
			dev_open = false
		elif tut_open:
			close_tutorial()
		elif archive_open:
			archive_open = false
		_layout()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(ev).position
		if ev.pressed:
			if dev_open or tut_open or archive_open:
				_press_button(p)
				return
			if help_rect.grow(10).has_point(p):
				open_tutorial()
				return
			if cal_rect.has_area() and cal_rect.grow(10).has_point(p):
				open_archive()
				return
			if mode_rect.has_area() and mode_rect.grow(6).has_point(p):
				if practice:
					close_playground()
				else:
					open_playground()
				return
			if Rect2(head_rect.position, Vector2(170, 60)).has_point(p):
				_dev_tap()
				return
			if _press_button(p):
				return
			if phase == Phase.PLAN:
				for chip in chips:
					if chip.rect.has_point(p):
						_chip_pressed(chip)
						return
			if phase == Phase.PLAN and mini_rect.has_area() and mini_rect.grow(8).has_point(p):
				toggle_zoom()
				return
			if phase == Phase.RESULT and grid_rect.has_point(p):
				try_again()   # back to planting (zoomed) — the next tap edits
				return
			var c := _cell_at(p)
			if c >= 0 and phase == Phase.PLAN:
				if tool >= 0 and not seeds.has(c):
					stamp(tool, Vector2i(c % W, c / W))
					return
				if seeds.has(c):
					paint_value = 0
				elif _unlimited() or in_zone(c):
					paint_value = 1
					if seeds.size() >= budget and not _unlimited():
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
					"arch_newer": archive_shift(-1)
					"arch_older": archive_shift(1)
					"arch_close":
						archive_open = false
						_layout()
					_:
						if String(b.id).begins_with("day_"):
							pick_day(String(b.id).substr(4))
					"tut_skip": close_tutorial()
					"tut_next": tut_next()
					"tut_back": tut_back()
					"start_over":
						try_again()
						clear_seeds()
			return true
	return false


# ------------------------------------------------------------------ layout + drawing

func _layout() -> void:
	var vs := get_viewport_rect().size
	var m := GTUI.dp(GTUI.SP_L)
	var gap := GTUI.dp(GTUI.SP_L)
	var bh := GTUI.target()
	var portrait := vs.y >= vs.x * 1.05
	var plan := phase == Phase.PLAN
	if portrait:
		head_rect = Rect2(m, m, vs.x - m * 2, _head_h())
		var g: float = min(vs.x - m * 2, vs.y - head_rect.end.y - GTUI.dp(300))
		g = max(g, 200.0)
		grid_rect = Rect2((vs.x - g) / 2.0, head_rect.end.y + gap, g, g)
		panel_rect = Rect2(m, grid_rect.end.y + GTUI.dp(GTUI.SP_XL), vs.x - m * 2, vs.y - grid_rect.end.y - GTUI.dp(GTUI.SP_XL) - m)
	else:
		var g: float = min(vs.y - m * 2, vs.x * 0.58)
		grid_rect = Rect2(m * 1.5, (vs.y - g) / 2.0, g, g)
		var px := grid_rect.end.x + GTUI.dp(GTUI.SP_2XL)
		head_rect = Rect2(px, grid_rect.position.y, vs.x - px - m * 1.5, _head_h())
		panel_rect = Rect2(px, head_rect.end.y + gap, head_rect.size.x, grid_rect.end.y - head_rect.end.y - gap)
	text_rect = Rect2(panel_rect.position, panel_rect.size - Vector2(0, bh + gap))
	mini_rect = Rect2()
	chips.clear()
	if plan:
		# from the bottom: buttons, shape chips, then mini map + text in what's left
		var chips_h := _flow_chips(panel_rect.position.x, panel_rect.size.x, 0.0)
		var chips_top := panel_rect.end.y - bh - gap - chips_h
		for c in chips:
			c.rect.position.y += chips_top
		var top_h := chips_top - gap - panel_rect.position.y
		var hint_h := GTUI.line_height(GTUI.FS_LABEL) + GTUI.dp(GTUI.SP_S)
		var ms: float = clamp(min(top_h - hint_h, panel_rect.size.x * 0.42), 0.0, GTUI.dp(150))
		var tx := panel_rect.position.x
		if ms >= GTUI.dp(56):
			mini_rect = Rect2(panel_rect.position + Vector2(4, 4), Vector2(ms, ms))
			tx += ms + GTUI.dp(GTUI.SP_XL)
		text_rect = Rect2(tx, panel_rect.position.y, panel_rect.end.x - tx, top_h)
	main_region = _region_for_main()
	cell_px = _board_cell_px(grid_rect, main_region)
	grid_rect.size = Vector2(main_region.size) * cell_px
	_build_buttons()


func _build_buttons() -> void:
	buttons.clear()
	if tut_open and not dev_open:
		_tut_layout()
		return
	if archive_open and not dev_open:
		_archive_buttons()
		return
	if dev_open:
		var c := _dev_card()
		var y := c.position.y
		for l in [["dev_today", "Reset today", false], ["dev_all", "Reset all days", false], ["dev_close", "Close", true]]:
			buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": true, "rect": Rect2(c.position.x, y, c.size.x, GTUI.target())})
			y += GTUI.target() + GTUI.dp(GTUI.SP_S)
		return
	var labels: Array = []
	match phase:
		Phase.PLAN:
			labels = [["clear", "Clear", false, not seeds.is_empty()], ["run", "Run", true, not seeds.is_empty()]]
		Phase.RUN:
			labels = [["skip", "Skip to end", false, true]]
		Phase.RESULT:
			if practice:
				labels = [["start_over", "Clear seeds", false, true], ["again", "Try again", true, true]]
			else:
				labels = [["finish", "Finish", false, true], ["again", "Retry (%d left)" % (MAX_TRIES - tries.size()), true, true]]
		Phase.FINAL:
			if date != today:
				labels.append(["today", "Play today's", false, true])
			labels.append(["share", "Share score", true, true])
	var row := Rect2(panel_rect.position.x, panel_rect.end.y - GTUI.target(), panel_rect.size.x, GTUI.target())
	var weights: Array = []
	for l in labels:
		weights.append(1.6 if l[2] else 1.0)
	var rects := GTUI.row(row, labels.size(), weights)
	for i in labels.size():
		var l: Array = labels[i]
		buttons.append({"id": l[0], "label": l[1], "primary": l[2], "enabled": l[3], "rect": rects[i]})


func _draw() -> void:
	GTUI.begin()
	if buttons.is_empty() and phase != Phase.RUN:
		_layout()
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
		GTUI.box(self, mr.grow(6), Color(0, 0, 0, 0), GTUI.R_PANEL, Color(C_INK, 0.25))
		var hint := "Tap: full map" if zoomed else "Tap: zoom in"
		GTUI.text_in(self, Rect2(mr.position.x - 6, mr.end.y + GTUI.dp(GTUI.SP_S), mr.size.x + 12, GTUI.line_height(GTUI.FS_LABEL)), hint, GTUI.FS_LABEL, C_MUTED)
	_draw_panel()
	_draw_chips()
	if tut_open and not dev_open:
		_draw_tutorial()
	if archive_open and not dev_open:
		_draw_archive()
	if dev_open:
		var card := GTUI.modal_rect(self, 420, GTUI.modal_height(GTUI.line_height(GTUI.FS_LABEL) + GTUI.dp(GTUI.SP_L) + GTUI.target() * 3 + GTUI.dp(GTUI.SP_S) * 2, true, false))
		var c := GTUI.modal(self, card, "Dev menu")
		GTUI.text(self, c.position, "Saved progress for #%d (%s)" % [puzzle_no, date], GTUI.FS_LABEL, C_MUTED)
	for b in buttons:
		if not b.get("row", false):
			_draw_button(b)
	if toast_t > 0.0 and toast != "":
		var ty: float = buttons[0].rect.position.y - GTUI.dp(GTUI.SP_M) if not buttons.is_empty() else grid_rect.end.y - GTUI.dp(GTUI.SP_M)
		GTUI.toast(self, toast, GTUI.toast_alpha(toast_t, 2.6), ty)


func _draw_header() -> void:
	var r := head_rect
	var th := GTUI.target()
	# Row 1: game name (Bloom's own lettering) + standard icon buttons, right-aligned.
	var title_px := GTUI.fs(GTUI.FS_HEADING)
	draw_string(font, Vector2(r.position.x, r.position.y + (th + font.get_ascent(title_px) - font.get_descent(title_px)) / 2.0), "Bloom", HORIZONTAL_ALIGNMENT_LEFT, -1, title_px, C_INK)
	var ids := ["help"] if practice else ["calendar", "help"]
	var icons := GTUI.icon_row(r.end.x, r.position.y, ids)
	help_rect = icons["help"]
	GTUI.icon_button(self, "help", help_rect, "help")
	cal_rect = Rect2()
	if not practice:
		cal_rect = icons["calendar"]
		GTUI.icon_button(self, "calendar", cal_rect, "calendar", phase != Phase.RUN)
	# Row 2: puzzle meta + mode switch on the left, the live stat on the right.
	var y2 := r.position.y + th + GTUI.dp(GTUI.SP_S)
	var meta := "Playground · practice map" if practice else "#%d · %s" % [puzzle_no, _short_date(date)]
	var meta_w := GTUI.text_width(meta, GTUI.FS_LABEL)
	GTUI.text_in(self, Rect2(r.position.x, y2, meta_w + 2, th), meta, GTUI.FS_LABEL, C_MUTED if date == today or practice else C_STAR, -1)
	mode_rect = Rect2()
	if phase != Phase.RUN:
		var label := "Back to daily" if practice else "Playground"
		var mw := GTUI.text_width(label, GTUI.FS_LABEL + 2, true) + GTUI.dp(GTUI.SP_L) * 2
		mode_rect = Rect2(r.position.x + meta_w + GTUI.dp(GTUI.SP_M), y2, mw, th)
		GTUI.button(self, "mode", mode_rect, label, "secondary")
	var label := "seeds left"
	var big := str(budget - seeds.size())
	if _unlimited():
		label = "seeds"
		big = str(seeds.size())
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
	GTUI.stat(self, Vector2(r.end.x, y2), label, big, 1, C_ACCENT)


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
	var lines: Array = []   # [text, size, color, bold]
	var B := GTUI.FS_BODY
	match phase:
		Phase.PLAN:
			if tool >= 0:
				_draw_tool_info(r)
				return
			if practice:
				lines.append(["Playground: a practice map that never changes.", B, C_INK, true])
				if no_limits:
					lines.append(["No limits is on: plant anywhere, as many seeds as you like.", B, C_ACCENT, false])
				else:
					lines.append(["Same rules as the daily puzzle. Try as often as you like; scores here don't count.", B, C_MUTED, false])
				if not tries.is_empty():
					lines.append([_tries_line(), B, C_MUTED, false])
			else:
				lines.append(["Plant up to %d seeds in the green zone." % budget, B, C_INK, true])
				lines.append(["Tap squares one by one, or pick a shape below. Press Run to play %d steps." % GENS, B, C_MUTED, false])
				lines.append(["Try %d of %d" % [tries.size() + 1, MAX_TRIES] + ("  ·  " + _tries_line() if not tries.is_empty() else ""), B, C_MUTED, false])
		Phase.RUN:
			var s := current_score()
			lines.append(["Step %d of %d" % [gen, GENS], GTUI.FS_TITLE, C_INK, true])
			lines.append(["%d squares reached · %d/%d stars · %d alive now" % [s.touched, s.stars, star_total, s.alive], B, C_MUTED, false])
		Phase.RESULT:
			var t: Dictionary = tries[-1]
			lines.append(["Impact %d" % t.score, GTUI.FS_TITLE, C_ACCENT, true])
			lines.append(["%d squares reached + %d stars × %d" % [t.touched, t.stars, STAR_BONUS], B, C_MUTED, false])
			lines.append([_tries_line(), B, C_MUTED, false])
			lines.append(["Tap the board to tweak your seeds.", B, C_MUTED, false])
		Phase.FINAL:
			var b := best_try()
			lines.append(["Best impact %d" % best_score(), GTUI.FS_TITLE, C_ACCENT, true])
			lines.append([_tries_line() + "  ·  %d/%d stars" % [int(b.get("stars", 0)), star_total], B, C_MUTED, false])
			if date == today:
				lines.append(["Next Bloom in " + _countdown(), B, C_MUTED, false])
			else:
				lines.append(["Today's puzzle is waiting.", B, C_MUTED, false])
	if target_score > 0 and not practice:
		var beat := phase == Phase.FINAL and best_score() > target_score
		lines.append([("You beat %d!" if beat else "Score to beat: %d") % target_score, B, C_STAR, true])
	var y := r.position.y
	for l in lines:
		var h := GTUI.paragraph(self, r.position.x, y, r.size.x, l[0], l[1], l[2], l[3], false) - y
		if y + h > r.end.y and phase == Phase.PLAN:
			break
		y = GTUI.paragraph(self, r.position.x, y, r.size.x, l[0], l[1], l[2], l[3]) + GTUI.dp(GTUI.SP_XS)


func _tries_line() -> String:
	var parts := PackedStringArray()
	for t in tries.slice(-5) if practice else tries:
		parts.append(str(t.score))
	if practice:
		return "Recent: " + ", ".join(parts) + "  ·  best %d" % best_score()
	return "Tries: " + ", ".join(parts)


func _countdown() -> String:
	return GTUI.countdown()


func _draw_button(b: Dictionary) -> void:
	GTUI.button(self, String(b.id), b.rect, String(b.label), "primary" if b.primary else "secondary", b.enabled)


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
const TUT_TITLES := ["How life works here", "The 4 rules", "Watch it happen", "Today's puzzle"]
const DEMO_STEP := 0.7              # seconds per step in the tutorial animations
const DEMO_N := 7                   # each demo board is DEMO_N x DEMO_N, wrapping at the edges
const DEMOS := [["Block", "Stays still"], ["Blinker", "Flips back and forth"], ["Glider", "Walks away"]]

var tut_open := false
var tut_page := 0
var tut_rect := Rect2()
var help_rect := Rect2()            # the "?" button in the header
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
	tut_rect = GTUI.modal_rect(self, 560, minf(vs.y - GTUI.dp(GTUI.SP_L) * 2, GTUI.dp(720)))
	var c := GTUI.modal_content(tut_rect)
	var rects := GTUI.row(GTUI.modal_buttons_rect(c), 2)
	var right := "Let's play" if tut_page == TUT_PAGES - 1 else "Next"
	buttons.append({"id": "tut_back", "label": "Back", "primary": false, "enabled": tut_page > 0, "rect": rects[0]})
	buttons.append({"id": "tut_next", "label": right, "primary": true, "enabled": true, "rect": rects[1]})
	buttons.append({"id": "tut_skip", "label": "", "primary": false, "enabled": true, "row": true, "rect": GTUI.modal_close_rect(tut_rect)})


## Draws wrapped text (size in dp) at y and returns the y below it.
func _para(text: String, x: float, y: float, w: float, size: int, col: Color) -> float:
	return GTUI.paragraph(self, x, y, w, text, size, col)


func _draw_tutorial() -> void:
	var c := GTUI.modal(self, tut_rect, TUT_TITLES[tut_page], "tut_skip")
	var x := c.position.x
	var w := c.size.x
	var y := c.position.y
	var bottom: float = c.end.y - GTUI.target() - GTUI.dp(GTUI.SP_XL)   # above the button row
	# page dots, centred just above the buttons
	var dot := GTUI.dp(6)
	var dots_w := TUT_PAGES * dot + (TUT_PAGES - 1) * GTUI.dp(GTUI.SP_S)
	for i in TUT_PAGES:
		var dc := Vector2(c.get_center().x - dots_w / 2.0 + dot / 2.0 + i * (dot + GTUI.dp(GTUI.SP_S)), bottom + GTUI.dp(GTUI.SP_M))
		draw_circle(dc, dot / 2.0, C_ACCENT if i == tut_page else Color(C_INK, 0.25))
	bottom -= GTUI.dp(GTUI.SP_S)
	match tut_page:
		0: _tut_page_board(x, y, w, bottom)
		1: _tut_page_rules(x, y, w, bottom)
		2: _tut_page_watch(x, y, w, bottom)
		_: _tut_page_bloom(x, y, w, bottom)


func _tut_page_board(x: float, y: float, w: float, bottom: float) -> void:
	var B := GTUI.FS_BODY
	y = _para("Bloom is built on a famous puzzle called the Game of Life. The board is a field of little squares:", x, y, w, B, C_MUTED) + GTUI.dp(GTUI.SP_M)
	# legend
	var lg := GTUI.line_height(B)
	_box(Rect2(x, y, lg, lg), C_ALIVE, GTUI.dp(4))
	GTUI.text_in(self, Rect2(x + lg + GTUI.dp(GTUI.SP_S), y, w / 2.0, lg), "green = alive", B, C_INK, -1)
	var x2 := x + w / 2.0
	_box(Rect2(x2, y, lg, lg), C_GRID_BG, GTUI.dp(4), Color(C_INK, 0.2))
	GTUI.text_in(self, Rect2(x2 + lg + GTUI.dp(GTUI.SP_S), y, w / 2.0 - lg, lg), "dark = empty", B, C_INK, -1)
	y += lg + GTUI.dp(GTUI.SP_L)
	var t1 := "The 8 squares touching a square (sides and corners, inside the gold box) are its neighbours. The middle square here has 3 living neighbours."
	var t2 := "Life moves in steps. At every step, each square counts its living neighbours, and that number decides if it lives, dies, or is born. You don't steer it: you only choose where life starts."
	var text_h := GTUI.paragraph(self, x, 0, w, t1, GTUI.FS_LABEL, C_MUTED, false, false) + GTUI.paragraph(self, x, 0, w, t2, B, C_INK, false, false)
	# neighbour diagram: 5x5, centre square and its 8 neighbours
	var cell: float = clamp((bottom - y - text_h - GTUI.dp(GTUI.SP_XL)) / 5.0, _u(20), _u(44))
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
	y += side + GTUI.dp(GTUI.SP_L)
	y = _para(t1, x, y, w, GTUI.FS_LABEL, C_MUTED) + GTUI.dp(GTUI.SP_S)
	_para(t2, x, y, w, B, C_INK)


func _tut_page_rules(x: float, y: float, w: float, bottom: float) -> void:
	y = _para("Every step, every square checks its neighbours:", x, y, w, GTUI.FS_BODY, C_MUTED) + GTUI.dp(GTUI.SP_L)
	var rules := [
		["Too lonely", "A living square with 0 or 1 living neighbours dies.", [2], true, false, Color("ff8f8f")],
		["Just right", "A living square with 2 or 3 living neighbours stays alive.", [0, 4], true, true, C_ACCENT],
		["Too crowded", "A living square with 4 or more living neighbours dies.", [0, 2, 4, 6], true, false, Color("ff8f8f")],
		["New life", "An empty square with exactly 3 living neighbours comes alive.", [0, 2, 5], false, true, C_STAR],
	]
	var foot := "The middle square (white outline) is the one being checked. All squares update at the same moment."
	var foot_h := GTUI.paragraph(self, x, 0, w, foot, GTUI.FS_LABEL, C_MUTED, false, false)
	var row_h: float = (bottom - y - foot_h - GTUI.line_height(GTUI.FS_CAPTION)) / 4.0
	var cell: float = clamp((row_h - GTUI.dp(GTUI.SP_M)) / 3.0, _u(14), _u(26))
	var patch := cell * 3
	var gap := _u(34)
	var diag_w := patch * 2 + gap
	GTUI.text_in(self, Rect2(x, y, patch, GTUI.line_height(GTUI.FS_CAPTION)), "before", GTUI.FS_CAPTION, C_MUTED)
	GTUI.text_in(self, Rect2(x + patch + gap, y, patch, GTUI.line_height(GTUI.FS_CAPTION)), "after", GTUI.FS_CAPTION, C_MUTED)
	y += GTUI.line_height(GTUI.FS_CAPTION)
	for rule in rules:
		_draw_patch(Vector2(x, y), cell, rule[2], rule[3])
		var ay := y + patch / 2.0
		var ax := x + patch + gap / 2.0
		var a := _u(8)
		draw_colored_polygon(PackedVector2Array([Vector2(ax - a, ay - a), Vector2(ax + a, ay), Vector2(ax - a, ay + a)]), C_MUTED)
		_draw_patch(Vector2(x + patch + gap, y), cell, rule[2], rule[4], true)
		var tx := x + diag_w + GTUI.dp(GTUI.SP_L)
		var ty := GTUI.paragraph(self, tx, y, w - diag_w - GTUI.dp(GTUI.SP_L), rule[0], GTUI.FS_BODY, rule[5], true)
		_para(rule[1], tx, ty, w - diag_w - GTUI.dp(GTUI.SP_L), GTUI.FS_LABEL, C_INK)
		y += max(row_h, patch + GTUI.dp(GTUI.SP_M))
	_para(foot, x, y, w, GTUI.FS_LABEL, C_MUTED)


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
	y = _para("Same 4 rules, different starting shapes, and very different results:", x, y, w, GTUI.FS_BODY, C_MUTED) + GTUI.dp(GTUI.SP_L)
	var gap := GTUI.dp(GTUI.SP_M)
	var bw := minf((w - gap * 2) / 3.0, GTUI.dp(140))
	var x0 := x + (w - (bw * 3 + gap * 2)) / 2.0
	for i in DEMOS.size():
		var r := Rect2(x0 + i * (bw + gap), y, bw, bw)
		_draw_cells(r, demos[i], DEMO_N, DEMO_N)
		GTUI.text_in(self, Rect2(r.position.x - gap / 2.0, r.end.y + GTUI.dp(GTUI.SP_S), bw + gap, GTUI.line_height(GTUI.FS_BODY)), DEMOS[i][0], GTUI.FS_BODY, C_INK, 0, true)
		GTUI.text_in(self, Rect2(r.position.x - gap / 2.0, r.end.y + GTUI.dp(GTUI.SP_S) + GTUI.line_height(GTUI.FS_BODY), bw + gap, GTUI.line_height(GTUI.FS_LABEL)), DEMOS[i][1], GTUI.FS_LABEL, C_MUTED)
	y += bw + GTUI.dp(GTUI.SP_S) + GTUI.line_height(GTUI.FS_BODY) + GTUI.line_height(GTUI.FS_LABEL) + GTUI.dp(GTUI.SP_M)
	GTUI.text_in(self, Rect2(x, y, w, GTUI.line_height(GTUI.FS_BODY)), "Step %d" % demo_gen, GTUI.FS_BODY, C_ACCENT, 0, true)
	y += GTUI.line_height(GTUI.FS_BODY) + GTUI.dp(GTUI.SP_S)
	y = _para("Some shapes freeze, some blink, some travel, and some explode into big colonies. In Bloom, shapes that spread and travel reach the most squares.", x, y, w, GTUI.FS_BODY, C_INK) + GTUI.dp(GTUI.SP_M)
	_para_fit("Want to experiment? Tap Playground at the top any time. It has more shapes and a practice map.", x, y, w, GTUI.FS_LABEL, C_MUTED, bottom)


func _tut_page_bloom(x: float, y: float, w: float, bottom: float) -> void:
	var icon := GTUI.dp(20)
	var k := icon / 28.0   # icon art below was drawn in a 28 px box
	var tx := x + icon + GTUI.dp(GTUI.SP_M)
	var tw := w - icon - GTUI.dp(GTUI.SP_M)
	var rows := [
		["zone", "You get %d seeds (living squares). Tap squares inside the green box to plant them. Tap again to remove." % budget],
		["shape", "Shortcut buttons drop in a whole Blinker or Glider for you. Rotate turns them to aim."],
		["play", "Press Run. The 4 rules play out for %d steps across the whole map." % GENS],
		["touch", "Your score (Impact) counts every square your life ever reached, even if it died later."],
		["star", "Gold stars give +%d bonus each when your life reaches them." % STAR_BONUS],
		["wall", "Grey walls always stay empty. Life can't grow through them."],
		["tries", "You have %d tries a day and your best one counts. Everyone gets the same map, so you can compare scores." % MAX_TRIES],
	]
	for row in rows:
		var ny := GTUI.paragraph(self, tx, y, tw, row[1], GTUI.FS_BODY, C_INK, false, false)
		if ny > bottom:
			break
		var ir := Rect2(x, y + (GTUI.line_height(GTUI.FS_BODY) - icon) / 2.0, icon, icon)
		match row[0]:
			"zone":
				draw_rect(ir, C_ZONE)
				draw_rect(ir, C_ZONE_EDGE, false, 2.0)
				_box(Rect2(ir.position + Vector2(8, 8) * k, Vector2(12, 12) * k), C_SEED, 3)
			"play":
				_box(ir, C_BTN_PRIMARY, GTUI.dp(GTUI.R_CONTROL))
				draw_colored_polygon(PackedVector2Array([ir.position + Vector2(10, 7) * k, ir.position + Vector2(21, 14) * k, ir.position + Vector2(10, 21) * k]), Color("06180e"))
			"touch":
				_box(ir.grow(-2), C_TOUCHED, 4)
			"shape":
				for c in [Vector2i(1, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]:
					draw_rect(Rect2(ir.position + (Vector2(c) * 9.5 + Vector2(1, 1)) * k, Vector2(8, 8) * k), C_ALIVE)
			"star":
				_draw_star(ir.get_center(), 13 * k, true)
			"wall":
				draw_rect(ir.grow(-2), C_WALL)
				draw_rect(Rect2(ir.position + Vector2(2, 2), Vector2(ir.size.x - 4, 5 * k)), C_WALL_HI)
			"tries":
				GTUI.text_in(self, ir, str(MAX_TRIES), GTUI.FS_BODY, C_ACCENT, 0, true)
		y = GTUI.paragraph(self, tx, y, tw, row[1], GTUI.FS_BODY, C_INK) + GTUI.dp(GTUI.SP_S)
	_para_fit("Tip: start with a shape that grows or travels, then try small changes between tries.", x, y + GTUI.dp(GTUI.SP_XS), w, GTUI.FS_LABEL, C_MUTED, bottom)


# ------------------------------------------------------------------ playground (practice map) + shape tools

const PRACTICE_SEED := "bloom3:practice:3"   # chosen to have open room for the 36x9 glider gun
const DAILY_TOOLS := ["Blinker", "Glider"]   # shapes offered in the daily puzzle
const C_MODE := Color("6d5dfc")              # Playground / Back button

var practice := false               # playing the fixed practice map instead of the daily one
var no_limits := false              # practice only: plant anywhere, any number of seeds
var tool := -1                      # -1 = single square, otherwise index into SHAPES
var tool_rot := 0                   # quarter turns clockwise
var chips: Array = []               # [{rect, id, idx, label}]
var mode_rect := Rect2()            # Playground / Back button in the header


func open_playground() -> void:
	if not practice:
		_save_state()
	practice = true
	no_limits = false
	tool = _shape_index("Glider")
	tool_rot = 0
	build_map(PRACTICE_SEED)
	seeds.clear()
	tries.clear()
	finished = false
	_reset_sim()
	phase = Phase.PLAN
	zoomed = true


func close_playground() -> void:
	load_puzzle(date)


func _unlimited() -> bool:
	return practice and no_limits


static func rotated_cells(idx: int, rot: int) -> Array:
	var cells := shape_cells(idx)
	var sz := shape_size(idx)
	for r in posmod(rot, 4):
		var out: Array = []
		for c in cells:
			out.append(Vector2i(sz.y - 1 - c.y, c.x))
		cells = out
		sz = Vector2i(sz.y, sz.x)
	return cells


static func rotated_size(idx: int, rot: int) -> Vector2i:
	var sz := shape_size(idx)
	return sz if posmod(rot, 2) == 0 else Vector2i(sz.y, sz.x)


## Place the current tool's shape centred on a square. All of it must fit; each square uses a seed.
func stamp(idx: int, center: Vector2i) -> bool:
	if phase == Phase.RESULT:
		try_again()
	if phase != Phase.PLAN:
		return false
	var sz := rotated_size(idx, tool_rot)
	var off := center - sz / 2
	var add: Array = []
	for c in rotated_cells(idx, tool_rot):
		var p: Vector2i = c + off
		if p.x < 0 or p.y < 0 or p.x >= W or p.y >= H:
			_toast("It doesn't fit there")
			return false
		var i := p.y * W + p.x
		if tiles[i] == Cell.WALL:
			_toast("That spot overlaps a wall")
			return false
		if not (_unlimited() or in_zone(i)):
			_toast("The whole shape has to fit inside the green box")
			return false
		if not seeds.has(i):
			add.append(i)
	if not _unlimited() and seeds.size() + add.size() > budget:
		_toast("That needs %d seeds — you have %d left" % [add.size(), budget - seeds.size()])
		return false
	for i in add:
		seeds[i] = true
	_show_cells(seeds.keys())
	return true


func _chip_defs() -> Array:
	var out: Array = [{"id": "tool", "idx": -1, "label": "Draw"}]
	if practice:
		for i in SHAPES.size():
			out.append({"id": "tool", "idx": i, "label": SHAPES[i].name})
	else:
		for n in DAILY_TOOLS:
			out.append({"id": "tool", "idx": _shape_index(n), "label": n})
	out.append({"id": "rotate", "idx": -2, "label": "Rotate"})
	if practice:
		out.append({"id": "limits", "idx": -3, "label": "No limits"})
	return out


func _flow_chips(x0: float, w: float, top: float) -> float:
	chips.clear()
	var ch := GTUI.target()
	var gap := GTUI.dp(GTUI.SP_S)
	var x := x0
	var y := 0.0
	for c in _chip_defs():
		var cw: float = GTUI.text_width(c.label, GTUI.FS_LABEL, true) + GTUI.dp(GTUI.SP_L) * 2
		if x + cw > x0 + w and x > x0:
			x = x0
			y += ch + gap
		c["rect"] = Rect2(x, y, cw, ch)
		chips.append(c)
		x += cw + gap
	var h := y + ch
	for c in chips:
		c.rect.position.y += top
	return h


func _chip_pressed(c: Dictionary) -> void:
	match c.id:
		"tool":
			tool = c.idx
		"rotate":
			if tool < 0:
				_toast("Pick a shape first, then rotate it")
			else:
				tool_rot = (tool_rot + 1) % 4
		"limits":
			no_limits = not no_limits
			if not no_limits:
				# drop seeds the normal rules don't allow
				for i in seeds.keys():
					if not in_zone(i):
						seeds.erase(i)
				while seeds.size() > budget:
					seeds.erase(seeds.keys()[-1])
				_show_cells(seeds.keys())
				_toast("Normal rules: green box only, %d seeds" % budget)
			else:
				_toast("No limits: plant anywhere, as many as you like")


func _draw_chips() -> void:
	for i in chips.size():
		var c: Dictionary = chips[i]
		match c.id:
			"tool":
				GTUI.chip(self, "chip_%d" % i, c.rect, c.label, c.idx == tool)
			"rotate":
				GTUI.chip(self, "chip_%d" % i, c.rect, c.label, false, tool >= 0)
			"limits":
				GTUI.chip(self, "chip_%d" % i, c.rect, c.label, no_limits)


## Draws text only if it fits above `bottom`; returns the y below it (or y unchanged). Size in dp.
func _para_fit(text: String, x: float, y: float, w: float, size: int, col: Color, bottom: float) -> float:
	if GTUI.paragraph(self, x, y, w, text, size, col, false, false) > bottom:
		return y
	return GTUI.paragraph(self, x, y, w, text, size, col)


func _draw_tool_info(r: Rect2) -> void:
	var s: Dictionary = SHAPES[tool]
	var sz := rotated_size(tool, tool_rot)
	var cells := rotated_cells(tool, tool_rot)
	var pv: float = min(GTUI.dp(64), r.size.y * 0.55, r.size.x * 0.34)
	var grid := PackedByteArray()
	grid.resize((sz.x + 2) * (sz.y + 2))
	for c in cells:
		grid[(c.y + 1) * (sz.x + 2) + c.x + 1] = 1
	_draw_cells(Rect2(r.position + Vector2(2, 4), Vector2(pv, pv)), grid, sz.x + 2, sz.y + 2, KIND_COL[s.kind])
	var tx := r.position.x + pv + GTUI.dp(GTUI.SP_L)
	var tw := r.end.x - tx
	var y := GTUI.paragraph(self, tx, r.position.y, tw, s.name, GTUI.FS_BODY, C_INK, true)
	y = GTUI.paragraph(self, tx, y, tw, String(s.kind).to_upper(), GTUI.FS_CAPTION, KIND_COL[s.kind], true)
	y = GTUI.paragraph(self, tx, y, tw, "Uses %d seeds" % cells.size(), GTUI.FS_LABEL, C_MUTED)
	y = max(y, r.position.y + pv + 8) + GTUI.dp(GTUI.SP_S)
	y = _para_fit(s.desc, r.position.x, y, r.size.x, GTUI.FS_LABEL, C_MUTED, r.end.y)
	_para_fit("Tap the board to place it." if _unlimited() else "Tap inside the green box to place it.", r.position.x, y, r.size.x, GTUI.FS_LABEL, C_ACCENT, r.end.y)


# ------------------------------------------------------------------ agent hooks

func get_agent_state() -> Dictionary:
	var sc: Dictionary = current_score() if alive.size() == W * H else {}
	return {
		"phase": Phase.keys()[phase], "date": date, "puzzle": puzzle_no, "budget": budget,
		"seeds": seeds.size(), "zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y],
		"gen": gen, "score": sc, "zoomed": zoomed, "tutorial": tut_open, "tut_page": tut_page, "practice": practice, "no_limits": no_limits, "tool": SHAPES[tool].name if tool >= 0 else "Draw", "tool_rot": tool_rot, "walls": tiles.count(Cell.WALL), "tries": tries.map(func(t): return t.score), "best": best_score(),
		"stars": star_total, "target": target_score, "share": share_text() if not tries.is_empty() else "",
		"archive_open": archive_open, "archive_page": archive_page, "today": today,
	}


func _head_h() -> float:
	return GTUI.target() + GTUI.dp(GTUI.SP_S) + maxf(GTUI.target(), GTUI.line_height(GTUI.FS_CAPTION) + GTUI.line_height(GTUI.FS_HEADING))


func _dev_card() -> Rect2:
	var card := GTUI.modal_rect(self, 420, GTUI.modal_height(GTUI.line_height(GTUI.FS_LABEL) + GTUI.dp(GTUI.SP_L) + GTUI.target() * 3 + GTUI.dp(GTUI.SP_S) * 2, true, false))
	var c := GTUI.modal_content(card)
	c.position.y += GTUI.line_height(GTUI.FS_LABEL) + GTUI.dp(GTUI.SP_L)
	return c


## Tutorial illustrations were drawn for the 720 px canvas; this keeps them in proportion with dp text.
func _u(v: float) -> float:
	return GTUI.dp(v * 0.72)