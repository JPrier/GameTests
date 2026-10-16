extends Node2D
## Seating Chart — a daily wedding seating logic puzzle.
##
## This script is only the UI: drawing, input, timer, saving and sharing. Puzzle model,
## constraints, solvers, generator, difficulty, hints and share formatting live in core/ and
## have no dependency on anything here.

const Model = preload("res://core/model.gd")
const C = preload("res://core/constraints.gd")
const Gen = preload("res://core/generator.gd")
const Board = preload("res://core/board.gd")
const Hints = preload("res://core/hints.gd")
const Share = preload("res://core/share.gd")
const Save = preload("res://core/save.gd")
const Daily = preload("res://core/daily.gd")
const D = preload("res://core/difficulty.gd")
const Names = preload("res://core/names.gd")

const DEFAULT_URL := "https://jprier.github.io/GameTests/seating-chart/"
const GOAL := "Seat every guest so that every clue is true."

const C_BG := Color("f6efe4")
const C_PAPER := Color("fffaf2")
const C_CARD := Color("ffffff")
const C_INK := Color("2b2230")
const C_MUTED := Color("7d7080")
const C_FAINT := Color("d9cfc2")
const C_GOLD := Color("c49a3c")
const C_GOLD_SOFT := Color("f3e3b8")
const C_ROSE := Color("c4506a")
const C_ROSE_SOFT := Color("f6d9df")
const C_OK := Color("3f8f5a")
const C_BAD := Color("d0453f")
const C_BAD_SOFT := Color("fbe0dc")
const C_BTN := Color("efe5d6")
const C_SHADOW := Color(0.2, 0.12, 0.1, 0.10)

const ARCHIVE_ROWS := 6

# ------------------------------------------------------------------ game state
var today := ""
var date := ""
var model = null
var board = null
var save = null
var base_url := DEFAULT_URL
var dev_mode := false
var dev_open := false
var loading := true
var load_frames := 0
var pending_day := ""

var elapsed := 0.0
var mistakes := 0
var hints_used := 0
var finished := false
var revealed := false
var final_seconds := 0
var timer_running := false
var paused := false
var save_t := 0.0

# ------------------------------------------------------------------ ui state
var font: Font
var bold: Font
var selected := -1                 # selected guest
var focus_clue := -1               # tapped clue
var hint: Dictionary = {}
var hint_level := 0
var hint_open := false
var wrong_marks: Dictionary = {}   # guest -> seconds left
var toast := ""
var toast_t := 0.0
var modal := ""                    # "", "help", "end", "archive"
var end_delay := -1.0
var archive_page := 0
var archive_results: Dictionary = {}
var buttons: Array = []
var confetti: Array = []
var title_taps := 0
var title_tap_t := -10.0
var anim_t := 0.0
var share_pending := false
var last_share_text := ""

# layout
var portrait := true
var head_rect := Rect2()
var title_rect := Rect2()
var tables_rect := Rect2()
var status_rect := Rect2()
var tray_rect := Rect2()
var clues_rect := Rect2()
var bar_rect := Rect2()
var chip := Vector2(100, 46)
var table_r := 60.0
var table_centers: Array = []
var seat_pos: Array = []           # seat -> centre
var slot_rects: Array = []         # guest -> card rect in the guest list
var clue_rows: Array = []          # [{i, y, h, lines}]
var clue_font := 20
var desc_font := 15
var compact := false
var clue_scroll := 0.0
var clue_content_h := 0.0
var hint_rect := Rect2()

# pointer
var pressing := false
var press_pos := Vector2()
var press_guest := -1
var press_in_clues := false
var dragging := false
var drag_pos := Vector2()
var scroll_dragging := false
var scroll_last := Vector2()


func _ready() -> void:
	font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = font
	fv.variation_embolden = 0.6
	bold = fv
	RenderingServer.set_default_clear_color(C_BG)
	_add_key_action("undo", [KEY_Z, KEY_BACKSPACE, KEY_U])
	_add_key_action("hint", [KEY_H])
	_add_key_action("check", [KEY_C])
	_add_key_action("dev", [KEY_QUOTELEFT])
	get_viewport().size_changed.connect(_on_resize)
	today = Daily.today_local()
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_mode = OS.is_debug_build() or String(url.get("dev", "")) == "1"
	dev_open = String(url.get("dev", "")) == "1"
	save = Save.new(dev_mode)
	var want := today
	var d := String(url.get("d", "")) if String(url.get("d", "")) != "" else String(url.get("day", ""))
	if dev_mode and Daily.valid_date(d):
		want = d
	elif d != "":
		_clean_url()          # links always open today; past days are picked in-game
	_layout()
	request_day(want)


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _on_resize() -> void:
	_layout()
	queue_redraw()


# ------------------------------------------------------------------ days

## Shows the "setting the tables" card for a frame, then builds the day (generating can take
## a moment on a slow phone the first time a day is opened; after that it's cached).
func request_day(d: String) -> void:
	_save_now()
	loading = true
	load_frames = 0
	pending_day = d
	queue_redraw()


func load_day(d: String) -> void:
	date = d
	model = puzzle_for(d)
	board = Board.new(model)
	selected = -1
	focus_clue = -1
	hint = {}
	hint_level = 0
	hint_open = false
	wrong_marks = {}
	elapsed = 0.0
	mistakes = 0
	hints_used = 0
	finished = false
	revealed = false
	final_seconds = 0
	end_delay = -1.0
	confetti = []
	clue_scroll = 0.0
	_load_progress()
	loading = false
	timer_running = not finished
	if modal == "" and not finished and not _tutorial_seen():
		modal = "help"
	if finished and modal == "":
		modal = "end"
	_layout()
	queue_redraw()


## The puzzle for a date: from the local cache if present, otherwise generated (and cached).
func puzzle_for(d: String):
	var cached = Save.load_cached_puzzle(d)
	if cached != null and String(cached.get("date", "")) == d:
		var m = Model.from_dict(cached)
		if m.clues.size() > 0 and m.solution.size() == m.guest_count():
			return m
	var m2 = Gen.for_date(d)
	Save.cache_puzzle(d, m2.to_dict())
	return m2


func _load_progress() -> void:
	var data: Dictionary = save.load_day(date)
	if data.is_empty():
		return
	board.load_dict(data.get("board", {}))
	elapsed = float(data.get("elapsed", 0.0))
	mistakes = int(data.get("mistakes", 0))
	hints_used = int(data.get("hints", 0))
	finished = bool(data.get("finished", false))
	revealed = bool(data.get("revealed", false))
	final_seconds = int(data.get("final", 0))
	if finished and not revealed and not board.is_solved():
		finished = false        # stale save from another puzzle version


func _save_now() -> void:
	if model == null or board == null or loading:
		return
	save.save_day(date, {"board": board.to_dict(), "elapsed": elapsed, "mistakes": mistakes,
		"hints": hints_used, "finished": finished, "revealed": revealed, "final": final_seconds})


func result_dict() -> Dictionary:
	return {"seconds": final_seconds if finished else int(elapsed), "mistakes": mistakes,
		"hints": hints_used, "hinted": board.hinted.keys() if board else [], "revealed": revealed}


func result_label() -> String:
	if revealed:
		return "Revealed"
	var s := Share.clock(final_seconds)
	if hints_used > 0:
		s += " · %d hint%s" % [hints_used, "" if hints_used == 1 else "s"]
	return s


func _tutorial_seen() -> bool:
	return FileAccess.file_exists("user://%stutorial_seen" % save.prefix)


func _mark_tutorial() -> void:
	var f := FileAccess.open("user://%stutorial_seen" % save.prefix, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()
	Save.flush()


# ------------------------------------------------------------------ moves (also used by tests)

func place_guest(g: int, s: int) -> bool:
	if not _can_play():
		return false
	if board.place(g, s):
		_after_change()
		return true
	return false


func unseat_guest(g: int) -> bool:
	if not _can_play():
		return false
	if board.unseat(g):
		_after_change()
		return true
	return false


func undo() -> bool:
	if not _can_play():
		return false
	if board.undo():
		_after_change()
		return true
	return false


func reset_board() -> bool:
	if not _can_play():
		return false
	if board.reset():
		selected = -1
		_after_change()
		_toast("Board cleared. Undo brings it back.")
		return true
	return false


func _can_play() -> bool:
	return not loading and model != null and not finished


func _after_change() -> void:
	hint_open = false
	hint_level = 0
	hint = {}
	wrong_marks = {}
	if board.is_solved():
		_win()
	_save_now()
	_build_buttons()
	queue_redraw()


func _win() -> void:
	finished = true
	timer_running = false
	final_seconds = int(elapsed)
	selected = -1
	focus_clue = -1
	hint_open = false
	_save_now()
	save.record_result(date, result_label())
	_mark_played()
	_burst()
	end_delay = 0.9


## Check: tells you whether everyone seated so far fits the answer.
## Costs a "wrong check" only when someone is misplaced.
func check_board() -> Dictionary:
	if not _can_play():
		return {}
	if board.seated_count() == 0:
		_toast("Seat someone first, then check.")
		return {"wrong": []}
	var wrong: Array = board.wrong_guests()
	if wrong.is_empty():
		_toast("So far, so good: everyone seated fits.")
	else:
		mistakes += 1
		for g in wrong:
			wrong_marks[g] = 3.0
		_toast("%d guest%s in the wrong seat." % [wrong.size(), " is" if wrong.size() == 1 else "s are"])
	_save_now()
	queue_redraw()
	return {"wrong": wrong}


## Progressive hint: 1 highlights the clues, 2 explains the deduction, 3 makes the move.
func use_hint() -> Dictionary:
	if not _can_play():
		return {}
	if hint_level == 0 or hint.is_empty():
		hint = Hints.next(model, board.seat_of)
		hint_level = 0
	if String(hint.get("kind", "")) == "done":
		return hint
	hint_level = mini(hint_level + 1, 3)
	hints_used += 1
	hint_open = true
	selected = -1
	focus_clue = -1
	if hint_level == 3:
		var h := hint.duplicate()
		var g: int = hint.guest
		if String(hint.kind) == "wrong":
			board.unseat(g)
			_toast("%s goes back to the guest list." % model.guest_name(g))
		elif int(hint.seat) >= 0:
			board.place(g, int(hint.seat))
			board.hinted[g] = true
			_toast("%s is seated." % model.guest_name(g))
		hint_open = false
		hint_level = 0
		hint = {}
		if board.is_solved():
			_win()
		_save_now()
		_build_buttons()
		queue_redraw()
		return h
	_build_buttons()
	_scroll_to_hint_clues()
	queue_redraw()
	return hint


## Scroll the clue list so the hint's first clue sits at the top of the visible list.
func _scroll_to_hint_clues() -> void:
	var cl: Array = hint.get("clues", [])
	if cl.is_empty():
		return
	for row in clue_rows:
		if int(row.i) == int(cl.min()):
			clue_scroll = clampf(float(row.y) - 38.0, 0.0, maxf(0.0, clue_content_h - clues_rect.size.y))
			return


# ------------------------------------------------------------------ sharing

## Always the plain game URL; past days are picked inside the game.
func share_link() -> String:
	return base_url


func share_text() -> String:
	if model == null or board == null:
		return ""
	return Share.text(model, board.seat_of, result_dict(), share_link())


## Tells the GameTests home page this day is played (not in dev mode).
func _mark_played() -> void:
	if dev_mode or not OS.has_feature("web"):
		return
	var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
		JSON.stringify("gametests:seating-chart:" + date), JSON.stringify(JSON.stringify({"result": result_label()}))]
	JavaScriptBridge.eval(js, true)


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__scShare='pending';
			var done=function(r){if(window.__scShare==='pending'){window.__scShare=r;}};
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
					setTimeout(function(){if(window.__scShare==='pending'){ask();}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},ask);
				}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__scCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__scCopyNext=true;done('share_failed');}
				});
			}else{window.__scCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied! Paste it anywhere.")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__scShare||''", true)
	if typeof(r) != TYPE_STRING or r == "pending" or r == "":
		return
	share_pending = false
	match r:
		"copied": _toast("Copied! Paste it anywhere.")
		"shared": _toast("Shared!")
		"prompted", "cancelled": pass
		"share_failed": _toast("Couldn't share. Tap again to copy.")
		_: _toast("Couldn't share. Try again.")


func _read_url() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var r = JavaScriptBridge.eval("""(function(){var p=new URLSearchParams(location.search);
		return JSON.stringify({d:p.get('d')||'',day:p.get('day')||'',dev:p.get('dev')||'',base:location.origin+location.pathname});})()""", true)
	if typeof(r) != TYPE_STRING:
		return {}
	var d = JSON.parse_string(r)
	return d if d is Dictionary else {}


func _clean_url() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{history.replaceState(null,'',location.pathname)}catch(e){}", true)


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 2.8
	queue_redraw()


# ------------------------------------------------------------------ past days

func archive_count() -> int:
	return maxi(1, Daily.day_number(today))


func archive_pages() -> int:
	return ceili(float(archive_count()) / ARCHIVE_ROWS)


func archive_page_days(page: int) -> Array:
	var out: Array = []
	for i in range(page * ARCHIVE_ROWS, mini((page + 1) * ARCHIVE_ROWS, archive_count())):
		out.append(Daily.add_days(today, -i))
	return out


func open_archive() -> void:
	_save_now()
	archive_results = save.load_results()
	if model != null and not finished and board.seated_count() > 0 and not archive_results.has(date):
		archive_results[date] = "In progress"
	var idx := clampi(Daily.day_number(today) - Daily.day_number(date), 0, archive_count() - 1)
	archive_page = idx / ARCHIVE_ROWS
	modal = "archive"
	_build_buttons()
	queue_redraw()


func pick_day(d: String) -> void:
	modal = ""
	if d != date and Daily.valid_date(d) and (dev_mode or (d >= Daily.EPOCH and d <= today)):
		request_day(d)
	_build_buttons()
	queue_redraw()


# ------------------------------------------------------------------ dev mode

func dev_set_day(d: String) -> void:
	if dev_mode and Daily.valid_date(d):
		_save_now()
		modal = ""
		load_day(d)


func dev_shift(days: int) -> void:
	dev_set_day(Daily.add_days(date, days))


func dev_random_day() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	dev_set_day(Daily.add_days(Daily.EPOCH, rng.randi_range(-200, 900)))


func dev_reset() -> void:
	if not dev_mode:
		return
	save.wipe_day(date)
	modal = ""
	load_day(date)


func dev_win() -> void:
	if not dev_mode or finished or model == null:
		return
	board.seat_of = model.solution.duplicate()
	board.history = []
	_after_change()


func dev_reveal() -> void:
	if not dev_mode or model == null or finished:
		return
	board.seat_of = model.solution.duplicate()
	board.history = []
	revealed = true
	_win()


func get_agent_state() -> Dictionary:
	var seats: Array = []
	if board:
		for s in board.seat_of:
			seats.append(s)
	return {
		"day": date, "today": today, "number": model.number if model else 0,
		"seed": model.seed_value if model else 0, "tier": D.tier_name(model.tier) if model else "",
		"state": "loading" if loading else ("won" if finished else "playing"),
		"seated": board.seated_count() if board else 0, "seats": seats,
		"broken": board.broken_clues().size() if board else 0, "clues": model.clues.size() if model else 0,
		"elapsed": int(elapsed), "mistakes": mistakes, "hints": hints_used, "revealed": revealed,
		"modal": modal, "dev_mode": dev_mode, "share_text": share_text(),
	}


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	anim_t += delta
	if loading:
		load_frames += 1
		if load_frames >= 2:
			load_day(pending_day)
		queue_redraw()
		return
	if timer_running and not paused and modal != "help" and not finished:
		var before := int(elapsed)
		elapsed += delta
		if int(elapsed) != before:
			queue_redraw()
		save_t += delta
		if save_t > 5.0:
			save_t = 0.0
			_save_now()
	if toast_t > 0.0:
		toast_t -= delta
		queue_redraw()
	if not wrong_marks.is_empty():
		for g in wrong_marks.keys():
			wrong_marks[g] -= delta
			if wrong_marks[g] <= 0.0:
				wrong_marks.erase(g)
		queue_redraw()
	if end_delay > 0.0:
		end_delay -= delta
		if end_delay <= 0.0:
			end_delay = -1.0
			modal = "end"
			_build_buttons()
			queue_redraw()
	if not confetti.is_empty():
		_step_confetti(delta)
		queue_redraw()
	if share_pending:
		_poll_share()
	if Input.is_action_just_pressed("undo") and modal == "":
		undo()
	if Input.is_action_just_pressed("hint") and modal == "":
		use_hint()
	if Input.is_action_just_pressed("check") and modal == "":
		check_board()
	if Input.is_action_just_pressed("dev") and dev_mode:
		dev_open = not dev_open
		_build_buttons()
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		paused = true
		_save_now()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		paused = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	portrait = vs.y >= vs.x * 1.05
	var pad := 16.0
	var col_w: float = minf(vs.x - pad * 2, 720.0 - pad * 2) if portrait else minf(vs.x * 0.56, 720.0) - pad * 2
	var left_x := (vs.x - col_w) / 2.0 if portrait else pad
	var y := 10.0
	head_rect = Rect2(left_x, y, col_w, 84)
	title_rect = Rect2(left_x, y, col_w * 0.55, 84)
	y += 88
	# two tables side by side; the seat cards must fit in half the column each
	var half := col_w / 2.0
	chip = Vector2(clampf(half * 0.29, 76, 104), 46)
	var ring_r := minf(half / 2.0 - chip.x / 2.0 - 2.0, 118.0)
	table_r = ring_r * 0.52
	var tables_h := ring_r * 1.81 + chip.y + 8.0
	tables_rect = Rect2(left_x, y, col_w, tables_h)
	table_centers = []
	for t in 2:
		table_centers.append(Vector2(left_x + half * (t + 0.5), y + chip.y / 2.0 + ring_r + 2.0))
	seat_pos = []
	for t in 2:
		for p in 5:
			var ang := deg_to_rad(-90.0 + p * 72.0)
			seat_pos.append(table_centers[t] + Vector2(cos(ang), sin(ang)) * ring_r)
	y += tables_h + 4
	status_rect = Rect2(left_x, y, col_w, 36)
	y += 42
	# guest list: 5 x 2 cards
	var gap := 8.0
	var cw := (col_w - gap * 4) / 5.0
	desc_font = 15 if cw >= 118 else 13
	var ch := _card_height(cw)
	# short screens: drop the flavour lines so the clue list keeps room for several clues
	compact = portrait and (vs.y - 76 - 12 - (y + ch * 2 + gap + 14)) < 300
	if compact:
		ch = 46.0
	tray_rect = Rect2(left_x, y, col_w, ch * 2 + gap)
	slot_rects = []
	for g in 10:
		slot_rects.append(Rect2(left_x + (g % 5) * (cw + gap), y + (g / 5) * (ch + gap), cw, ch))
	y += tray_rect.size.y + 14
	var bar_h := 64.0
	if portrait:
		bar_rect = Rect2(left_x, vs.y - bar_h - 12, col_w, bar_h)
		clues_rect = Rect2(left_x, y, col_w, maxf(bar_rect.position.y - 12 - y, 120))
	else:
		var rx := left_x + col_w + pad * 2
		var rw := vs.x - rx - pad
		bar_rect = Rect2(rx, vs.y - bar_h - 12, rw, bar_h)
		clues_rect = Rect2(rx, 14, rw, bar_rect.position.y - 26)
	_layout_clues()
	_build_buttons()


## Card height that fits a name plus the longest description of the day at this width.
func _card_height(w: float) -> float:
	var lines := 3
	if model != null:
		lines = 1
		for gd in model.guests:
			lines = maxi(lines, _wrap(String(gd.desc), desc_font, w - 14, font).size())
	return 36.0 + lines * (desc_font + 3) + 10.0


func _layout_clues() -> void:
	clue_rows = []
	if model == null:
		return
	clue_font = 20 if clues_rect.size.x >= 420 else 18
	var y := 38.0
	var text_w := clues_rect.size.x - 44 - 44
	for i in model.clues.size():
		var lines := _wrap(C.text(model.clues[i], model), clue_font, text_w, font)
		var h := maxf(44.0, lines.size() * (clue_font + 5) + 18)
		clue_rows.append({"i": i, "y": y, "h": h, "lines": lines})
		y += h + 6
	clue_content_h = y
	clue_scroll = clampf(clue_scroll, 0.0, maxf(0.0, clue_content_h - clues_rect.size.y))


func _clue_rect(row: Dictionary) -> Rect2:
	return Rect2(clues_rect.position.x, clues_rect.position.y + row.y - clue_scroll, clues_rect.size.x, row.h)


func _build_buttons() -> void:
	buttons = []
	var vs := get_viewport_rect().size
	if loading or model == null:
		return
	if modal == "" and finished:
		var done_labels := [["end_archive", "Past days"], ["results", "Results"], ["share", "Share"]]
		var gap2 := 10.0
		var bw4 := (bar_rect.size.x - gap2 * 2) / 3.0
		for k in 3:
			buttons.append({"id": done_labels[k][0], "label": done_labels[k][1], "enabled": true, "primary": k == 2,
				"rect": Rect2(bar_rect.position.x + k * (bw4 + gap2), bar_rect.position.y, bw4, bar_rect.size.y)})
	if modal == "":
		var labels := [["undo", "Undo"], ["reset", "Reset"], ["hint", "Hint"], ["check", "Check"]]
		var gap := 10.0
		var bw := (bar_rect.size.x - gap * 3) / 4.0
		for k in (0 if finished else 4):
			var id: String = labels[k][0]
			var en := _can_play()
			if id == "undo":
				en = en and not board.history.is_empty()
			if id == "reset":
				en = en and board.seated_count() > 0
			buttons.append({"id": id, "label": labels[k][1], "enabled": en, "primary": id == "hint",
				"rect": Rect2(bar_rect.position.x + k * (bw + gap), bar_rect.position.y, bw, bar_rect.size.y)})
		var r := head_rect
		buttons.append({"id": "help", "label": "?", "enabled": true, "icon": true,
			"rect": Rect2(r.end.x - 52, r.position.y + 6, 52, 52)})
		buttons.append({"id": "archive", "label": "", "enabled": true, "icon": true,
			"rect": Rect2(r.end.x - 112, r.position.y + 6, 52, 52)})
		if hint_open:
			_layout_hint()
			buttons.append({"id": "hint_close", "label": "Close", "enabled": true, "hintcard": true,
				"rect": Rect2(hint_rect.end.x - 252, hint_rect.end.y - 60, 112, 46)})
			buttons.append({"id": "hint_more", "label": "Seat them" if hint_level == 2 else "More help", "enabled": true,
				"primary": true, "hintcard": true, "rect": Rect2(hint_rect.end.x - 132, hint_rect.end.y - 60, 118, 46)})
	elif modal == "help":
		var c := _modal_card(_help_height())
		buttons.append({"id": "help_close", "label": "Let's seat them", "enabled": true, "primary": true,
			"rect": Rect2(c.position.x + 24, c.end.y - 82, c.size.x - 48, 60)})
	elif modal == "end":
		var c2 := _modal_card(470)
		var bw2 := (c2.size.x - 48 - 12) / 2.0
		buttons.append({"id": "share", "label": "Share", "enabled": true, "primary": true,
			"rect": Rect2(c2.position.x + 24, c2.end.y - 146, c2.size.x - 48, 60)})
		buttons.append({"id": "end_archive", "label": "Past days", "enabled": true,
			"rect": Rect2(c2.position.x + 24, c2.end.y - 76, bw2, 54)})
		buttons.append({"id": "end_close", "label": "View tables", "enabled": true,
			"rect": Rect2(c2.position.x + 36 + bw2, c2.end.y - 76, bw2, 54)})
	elif modal == "archive":
		var c3 := _archive_card()
		var rh := _archive_row_h()
		var days := archive_page_days(archive_page)
		for i in days.size():
			buttons.append({"id": "day_" + String(days[i]), "label": "", "enabled": true, "kind": "row",
				"rect": Rect2(c3.position.x + 20, c3.position.y + 82 + i * rh, c3.size.x - 40, rh - 10)})
		var bw3 := (c3.size.x - 40 - 24) / 3.0
		var by := c3.end.y - 80
		buttons.append({"id": "arch_newer", "label": "Newer", "enabled": archive_page > 0,
			"rect": Rect2(c3.position.x + 20, by, bw3, 60)})
		buttons.append({"id": "arch_close", "label": "Close", "enabled": true, "primary": true,
			"rect": Rect2(c3.position.x + 32 + bw3, by, bw3, 60)})
		buttons.append({"id": "arch_older", "label": "Older", "enabled": archive_page < archive_pages() - 1,
			"rect": Rect2(c3.position.x + 44 + bw3 * 2, by, bw3, 60)})
	if dev_mode and dev_open:
		var ids := [["dev_prev", "< Day"], ["dev_next", "Day >"], ["dev_m7", "-7"], ["dev_p7", "+7"],
			["dev_today", "Today"], ["dev_rand", "Random"], ["dev_reset", "Reset"], ["dev_reveal", "Reveal"],
			["dev_win", "Win"], ["dev_hide", "Hide"]]
		var pr := _dev_rect()
		for k in ids.size():
			buttons.append({"id": ids[k][0], "label": ids[k][1], "enabled": true, "dev": true,
				"rect": Rect2(pr.position.x + 8 + (k % 5) * 76, pr.position.y + 98 + (k / 5) * 46, 72, 40)})


func _dev_rect() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(8, vs.y - 8 - 196, 396, 196)


func _modal_card(h: float) -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 32, 560)
	h = minf(h, vs.y - 32)
	return Rect2((vs.x - w) / 2.0, (vs.y - h) / 2.0, w, h)


func _archive_row_h() -> float:
	var vs := get_viewport_rect().size
	return clampf((vs.y - 40.0 - 180.0) / ARCHIVE_ROWS, 60.0, 80.0)


func _archive_card() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 32, 600)
	var h := 82.0 + ARCHIVE_ROWS * _archive_row_h() + 96.0
	return Rect2((vs.x - w) / 2.0, maxf(16.0, (vs.y - h) / 2.0), w, h)


func _layout_hint() -> void:
	var w := clues_rect.size.x
	var lines := _hint_lines(w - 32)
	var h := 46.0 + lines.size() * 24.0 + 72.0
	hint_rect = Rect2(clues_rect.position.x, bar_rect.position.y - 10 - h, w, h)


func _hint_lines(w: float) -> Array:
	if hint.is_empty():
		return []
	var txt := ""
	if hint_level <= 1:
		txt = String(hint.get("nudge", ""))
		var cl: Array = hint.get("clues", [])
		if String(hint.kind) == "deduce" and not cl.is_empty():
			var nums: Array = []
			for i in cl:
				nums.append(str(int(i) + 1))
			if nums.size() == 1:
				txt = "Look closely at clue %s." % nums[0]
			else:
				txt = "Look at clues %s and %s together." % [", ".join(nums.slice(0, nums.size() - 1)), nums[-1]]
			if hint.get("uses_board", false):
				txt += " Use the guests already seated, too."
	else:
		var parts: Array = []
		if String(hint.kind) == "deduce":
			for s in hint.get("chain", []):
				if String(s) != String(hint.text):
					parts.append(String(s))
		parts.append(String(hint.text))
		txt = " ".join(parts)
	return Array(_wrap(txt, 18, w, font))


const HELP_TIPS := [
	"Seat all 10 guests so that every clue is true.",
	"Drag a guest onto a seat, or tap a guest and then a seat. Drag a seated guest back to the list to unseat them.",
	"\"Next to\" means the seats directly either side at the same round table.",
	"Tap a clue to light up its guests. Tap a guest to light up their clues.",
	"Clues tick green when they hold and turn red as soon as they're broken.",
	"Stuck? Hint explains the next step. Check tells you if anyone seated is in the wrong spot.",
]


func _help_height() -> float:
	var c := _modal_card(2000)
	var h := 86.0
	for t in HELP_TIPS:
		h += _wrap(t, 19, c.size.x - 74, font).size() * 24 + 12
	return h + 100.0


# ------------------------------------------------------------------ input

func _input(ev: InputEvent) -> void:
	if loading:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and modal == "" and clues_rect.has_point(mb.position):
				_scroll_clues(-40.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 40.0)
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press(mb.position)
		else:
			_release(mb.position)
	elif ev is InputEventMouseMotion and pressing:
		_motion((ev as InputEventMouseMotion).position)


func _press(p: Vector2) -> void:
	pressing = true
	press_pos = p
	dragging = false
	scroll_dragging = false
	press_guest = -1
	press_in_clues = false
	if modal != "" or _button_at(p) != null:
		return
	if hint_open and hint_rect.has_point(p):
		return
	var g := _guest_at_point(p)
	if g >= 0 and _can_play():
		press_guest = g
	elif clues_rect.has_point(p):
		press_in_clues = true
		scroll_last = p


func _motion(p: Vector2) -> void:
	if press_guest >= 0 and not dragging and p.distance_to(press_pos) > 12.0:
		dragging = true
		selected = -1
		focus_clue = -1
	if dragging:
		drag_pos = p
		queue_redraw()
	elif press_in_clues and (scroll_dragging or p.distance_to(press_pos) > 10.0):
		scroll_dragging = true
		_scroll_clues(scroll_last.y - p.y)
		scroll_last = p


func _scroll_clues(dy: float) -> void:
	clue_scroll = clampf(clue_scroll + dy, 0.0, maxf(0.0, clue_content_h - clues_rect.size.y))
	queue_redraw()


func _release(p: Vector2) -> void:
	if not pressing:
		return
	pressing = false
	if dragging:
		dragging = false
		var g := press_guest
		press_guest = -1
		var s := _seat_near(p + Vector2(0, -34), 74.0)
		if s >= 0:
			place_guest(g, s)
		elif tray_rect.grow(10).has_point(p):
			unseat_guest(g)
		queue_redraw()
		return
	if scroll_dragging:
		scroll_dragging = false
		return
	press_guest = -1
	var b = _button_at(p)
	if b != null and b.rect.has_point(press_pos):
		if b.enabled:
			_on_button(String(b.id))
		return
	if modal != "":
		if modal == "end" or modal == "archive":
			var card := _modal_card(470) if modal == "end" else _archive_card()
			if not card.has_point(p) and not card.has_point(press_pos):
				modal = ""
				_build_buttons()
				queue_redraw()
		return
	if title_rect.has_point(p):
		_title_tap()
	tap(p)


## A tap (no drag) at a screen point.
func tap(p: Vector2) -> void:
	if hint_open and hint_rect.has_point(p):
		return
	var s := _seat_at_point(p)
	var g := _guest_at_point(p)
	# a guest is selected and a seat was tapped: move them there (swapping if taken)
	if _can_play() and selected >= 0 and s >= 0:
		if board.occupant(s) == selected:
			selected = -1
		else:
			place_guest(selected, s)
			selected = -1
		queue_redraw()
		return
	if g >= 0:
		if selected == g:
			selected = -1
		elif _can_play() and selected >= 0 and board.seat_of[selected] >= 0 and _slot_at_point(p) == selected:
			unseat_guest(selected)
			selected = -1
		else:
			selected = g
			focus_clue = -1
		queue_redraw()
		return
	if _can_play() and selected >= 0 and board.seat_of[selected] >= 0 and tray_rect.has_point(p):
		unseat_guest(selected)
		selected = -1
		queue_redraw()
		return
	if clues_rect.has_point(p):
		for row in clue_rows:
			if _clue_rect(row).has_point(p):
				focus_clue = -1 if focus_clue == int(row.i) else int(row.i)
				selected = -1
				queue_redraw()
				return
	selected = -1
	focus_clue = -1
	queue_redraw()


func _title_tap() -> void:
	if anim_t - title_tap_t > 1.2:
		title_taps = 0
	title_tap_t = anim_t
	title_taps += 1
	if title_taps >= 5:
		title_taps = 0
		if not dev_mode:
			dev_mode = true
			save = Save.new(true)
		dev_open = true
		_toast("Dev mode")
		_build_buttons()
		queue_redraw()


func _on_button(id: String) -> void:
	match id:
		"undo": undo()
		"reset": reset_board()
		"hint", "hint_more": use_hint()
		"check": check_board()
		"hint_close":
			hint_open = false
		"help":
			modal = "help"
		"help_close":
			modal = ""
			_mark_tutorial()
		"archive", "end_archive":
			open_archive()
			return
		"share": share()
		"results":
			modal = "end"
		"end_close":
			modal = ""
		"arch_newer":
			archive_page = maxi(0, archive_page - 1)
		"arch_older":
			archive_page = mini(archive_pages() - 1, archive_page + 1)
		"arch_close":
			modal = ""
		"dev_prev": dev_shift(-1)
		"dev_next": dev_shift(1)
		"dev_m7": dev_shift(-7)
		"dev_p7": dev_shift(7)
		"dev_today": dev_set_day(today)
		"dev_rand": dev_random_day()
		"dev_reset": dev_reset()
		"dev_reveal": dev_reveal()
		"dev_win": dev_win()
		"dev_hide":
			dev_open = false
		_:
			if id.begins_with("day_"):
				pick_day(id.substr(4))
				return
	_build_buttons()
	queue_redraw()


func _button_at(p: Vector2):
	for b in buttons:                  # dev panel sits on top of everything
		if b.get("dev", false) and b.rect.has_point(p):
			return b
	for b in buttons:
		if not b.get("dev", false) and b.rect.has_point(p):
			return b
	return null


func _seat_at_point(p: Vector2) -> int:
	for s in seat_pos.size():
		if Rect2(seat_pos[s] - chip / 2.0, chip).grow(4).has_point(p):
			return s
	return -1


func _seat_near(p: Vector2, radius: float) -> int:
	var best := -1
	var bd := radius
	for s in seat_pos.size():
		var dd: float = p.distance_to(seat_pos[s])
		if dd < bd:
			bd = dd
			best = s
	return best


func _slot_at_point(p: Vector2) -> int:
	for g in slot_rects.size():
		if slot_rects[g].has_point(p):
			return g
	return -1


## The guest under a point: a seated guest's card at a table, or a card in the guest list.
func _guest_at_point(p: Vector2) -> int:
	if board == null:
		return -1
	var s := _seat_at_point(p)
	if s >= 0:
		return board.occupant(s)
	return _slot_at_point(p)


## Screen centre of a seat / of a guest's card (for scripted input in tests).
func seat_center(s: int) -> Vector2:
	return seat_pos[s]


func card_center(g: int) -> Vector2:
	return slot_rects[g].get_center()


# ------------------------------------------------------------------ text helpers

func _wrap(text: String, size: int, width: float, f: Font) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for w in text.split(" ", false):
		var test := w if cur == "" else cur + " " + w
		if cur == "" or f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			cur = test
		else:
			out.append(cur)
			cur = w
	if cur != "":
		out.append(cur)
	return out


func _tw(text: String, size: int, f: Font = null) -> float:
	return (f if f else font).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _text(pos: Vector2, text: String, size: int, col: Color, f: Font = null) -> void:
	draw_string(f if f else font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Text centred in a rect, shrinking the font until it fits (never cut off or overlapping).
func _text_center(r: Rect2, text: String, size: int, col: Color, f: Font = null) -> void:
	var ff: Font = f if f else font
	while size > 10 and _tw(text, size, ff) > r.size.x - 8:
		size -= 1
	var w := _tw(text, size, ff)
	var base := r.position.y + (r.size.y + ff.get_ascent(size) - ff.get_descent(size)) / 2.0
	draw_string(ff, Vector2(r.position.x + (r.size.x - w) / 2.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _box(r: Rect2, col: Color, radius: float = 12.0, border := Color(0, 0, 0, 0), bw := 2.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(bw))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _dashed_box(r: Rect2, col: Color) -> void:
	var pts := [r.position + Vector2(8, 0), Vector2(r.end.x - 8, r.position.y), Vector2(r.end.x, r.position.y + 8),
		Vector2(r.end.x, r.end.y - 8), Vector2(r.end.x - 8, r.end.y), Vector2(r.position.x + 8, r.end.y),
		Vector2(r.position.x, r.end.y - 8), Vector2(r.position.x, r.position.y + 8)]
	for i in range(0, 8, 2):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var t := 0.0
		while t < L:
			draw_line(a + dir * t, a + dir * minf(t + 7.0, L), col, 2.0)
			t += 12.0


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	if loading or model == null:
		_draw_loading()
		return
	_draw_header()
	_draw_tables()
	_draw_status()
	_draw_tray()
	_draw_clues()
	_draw_bar()
	if hint_open:
		_draw_hint()
	if dragging and press_guest >= 0:
		var r := Rect2(drag_pos - chip / 2.0 - Vector2(0, 34), chip)
		_box(Rect2(r.position + Vector2(0, 8), r.size), C_SHADOW, 12)
		_draw_chip(r, press_guest, true)
	_draw_confetti()
	match modal:
		"help": _draw_help()
		"end": _draw_end()
		"archive": _draw_archive()
	if toast_t > 0.0 and toast != "":
		_draw_toast()
	if dev_mode:
		_draw_dev()


func _draw_loading() -> void:
	var vs := get_viewport_rect().size
	var c := vs / 2.0
	draw_circle(c + Vector2(0, -50), 34, C_PAPER)
	draw_arc(c + Vector2(0, -50), 34, 0, TAU, 48, C_GOLD, 3, true)
	for k in 5:
		var a := TAU * k / 5.0 - PI / 2.0
		draw_circle(c + Vector2(0, -50) + Vector2(cos(a), sin(a)) * 9, 6, C_ROSE_SOFT)
	draw_circle(c + Vector2(0, -50), 5, C_GOLD)
	_text_center(Rect2(0, c.y, vs.x, 40), "Setting the tables...", 26, C_INK, bold)


func _draw_header() -> void:
	var r := head_rect
	_text(r.position + Vector2(2, 38), "Seating Chart", 34, C_INK, bold)
	var sub := "#%d · %s · %s" % [model.number, Daily.short_date(date), D.tier_name(model.tier)]
	_text(r.position + Vector2(2, 70), sub, 19, C_MUTED)
	var secs := final_seconds if finished else int(elapsed)
	var clock := Share.clock(secs)
	var tx := r.end.x - 124 - _tw(clock, 26, bold)
	_text(Vector2(tx, r.position.y + 42), clock, 26, C_OK if finished else C_INK, bold)


func _draw_tables() -> void:
	var at: PackedInt32Array = board.guest_at()
	var hl := _highlight_guests()
	var target_seat := -1
	if hint_open and hint_level >= 2 and String(hint.get("kind", "")) == "deduce":
		target_seat = int(hint.seat)
	for t in 2:
		var c: Vector2 = table_centers[t]
		draw_circle(c + Vector2(0, 5), table_r + 2, C_SHADOW)
		draw_circle(c, table_r, C_PAPER)
		draw_arc(c, table_r, 0, TAU, 64, C_GOLD, 3.0, true)
		draw_arc(c, table_r - 7, 0, TAU, 64, Color(C_GOLD, 0.35), 1.5, true)
		for k in 5:      # a little posy as the centrepiece
			var a := TAU * k / 5.0 - PI / 2.0
			draw_circle(c + Vector2(cos(a), sin(a)) * 7 + Vector2(0, -16), 5, C_ROSE_SOFT)
		draw_circle(c + Vector2(0, -16), 4, C_GOLD)
		_text_center(Rect2(c.x - table_r, c.y - 2, table_r * 2, 30), model.table_name(t), 18, C_INK, bold)
	for s in 10:
		var r := Rect2(seat_pos[s] - chip / 2.0, chip)
		var g: int = at[s]
		if g >= 0 and not (dragging and g == press_guest):
			if g == selected:
				_box(r.grow(5), C_ROSE, 16)
			elif hl.has(g):
				_box(r.grow(5), C_GOLD, 16)
			_draw_chip(r, g, false)
		else:
			var empty_col := C_FAINT
			if (selected >= 0 or dragging) and _can_play():
				empty_col = C_GOLD
			if s == target_seat:
				empty_col = C_ROSE
			_box(r, Color(C_PAPER, 0.85), 12)
			_dashed_box(r.grow(-1), empty_col)


func _draw_chip(r: Rect2, g: int, floating: bool) -> void:
	var col: Color = Names.COLORS[int(model.guests[g].color) % Names.COLORS.size()]
	_box(Rect2(r.position + Vector2(0, 3), r.size), C_SHADOW, 12)
	_box(r, col, 12, col.darkened(0.25), 2)
	_text_center(r, model.guest_name(g), 21, C_INK, bold)
	if floating:
		return
	if _guest_broken(g):
		draw_circle(r.position + Vector2(r.size.x - 6, 6), 7, C_BAD)
	if board.hinted.has(g):
		draw_circle(r.position + Vector2(8, 8), 5, C_GOLD)
	if wrong_marks.has(g):
		var c := r.get_center()
		draw_line(c + Vector2(-14, -14), c + Vector2(14, 14), C_BAD, 5)
		draw_line(c + Vector2(14, -14), c + Vector2(-14, 14), C_BAD, 5)


func _guest_broken(g: int) -> bool:
	var st: Array = board.clue_states()
	for i in st.size():
		if st[i] == C.FALSE and C.mentions(model.clues[i], g):
			return true
	return false


## Guests to glow: the tapped clue's guests, or the guests in the hint's clues.
func _highlight_guests() -> Dictionary:
	var out := {}
	if focus_clue >= 0:
		for g in C.guests_of(model.clues[focus_clue]):
			out[g] = true
	if hint_open and hint_level >= 1:
		for i in hint.get("clues", []):
			for g in C.guests_of(model.clues[i]):
				out[g] = true
		if hint_level >= 2 and int(hint.get("guest", -1)) >= 0:
			out[int(hint.guest)] = true
	return out


func _draw_status() -> void:
	var broken: int = board.broken_clues().size()
	var txt := GOAL
	var col := C_MUTED
	if finished:
		txt = "Everyone is happily seated!" if not revealed else "Here's how everyone sits."
		col = C_OK
	elif broken > 0:
		txt = "%d clue%s broken" % [broken, " is" if broken == 1 else "s are"]
		col = C_BAD
	elif board.seated_count() > 0:
		txt = "%d of 10 seated. No clue broken." % board.seated_count()
	_text_center(status_rect, txt, 19, col, bold if broken > 0 or finished else null)


func _draw_tray() -> void:
	var hl := _highlight_guests()
	for g in 10:
		var r: Rect2 = slot_rects[g]
		var gd: Dictionary = model.guests[g]
		var col: Color = Names.COLORS[int(gd.color) % Names.COLORS.size()]
		var seated: bool = board.seat_of[g] >= 0
		var lifted := dragging and press_guest == g and not seated
		if seated or lifted:
			var edge := C_FAINT
			if g == selected:
				edge = C_ROSE
			elif hl.has(g):
				edge = C_GOLD
			_box(r, Color(C_PAPER, 0.6), 12, edge, 2)
			_text(r.position + Vector2(10, 30), String(gd.name), 18, C_MUTED, bold)
			if seated:
				_draw_check(r.position + Vector2(r.size.x - 18, 22), C_OK, 0.8)
		else:
			if g == selected:
				_box(r.grow(4), C_ROSE, 15)
			elif hl.has(g):
				_box(r.grow(4), C_GOLD, 15)
			_box(Rect2(r.position + Vector2(0, 3), r.size), C_SHADOW, 12)
			_box(r, C_CARD, 12)
			_box(Rect2(r.position, Vector2(r.size.x, 8)), col, 4)
			_text(r.position + Vector2(10, 32), String(gd.name), 20, C_INK, bold)
		if compact:
			continue
		var lines := _wrap(String(gd.desc), desc_font, r.size.x - 14, font)
		for k in lines.size():
			_text(r.position + Vector2(8, 36 + (k + 1) * (desc_font + 3)), lines[k], desc_font,
				Color(C_MUTED, 0.6) if seated else C_MUTED)


func _draw_check(c: Vector2, col: Color, s: float = 1.0) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-8, 0) * s, c + Vector2(-2, 6) * s, c + Vector2(9, -7) * s]), col, 3.0 * s, true)


func _draw_clues() -> void:
	var r := clues_rect
	var st: Array = board.clue_states()
	var hint_clues: Array = hint.get("clues", []) if hint_open and hint_level >= 1 else []
	var view := Rect2(r.position.x, r.position.y + 34, r.size.x, r.size.y - 34)
	for row in clue_rows:
		var cr := _clue_rect(row)
		if cr.end.y < view.position.y or cr.position.y > view.end.y:
			continue
		var i: int = row.i
		var c: Dictionary = model.clues[i]
		var involved := selected >= 0 and C.mentions(c, selected)
		var bg := C_CARD
		var border := Color(0, 0, 0, 0)
		if st[i] == C.FALSE:
			bg = C_BAD_SOFT
		if involved or focus_clue == i or hint_clues.has(i):
			border = C_GOLD
			if bg == C_CARD:
				bg = Color("fff6df")
		var dim := selected >= 0 and not involved
		_box(cr, bg, 10, border, 3)
		var nc := Vector2(cr.position.x + 22, cr.position.y + 22)
		draw_circle(nc, 14, C_GOLD_SOFT if st[i] != C.FALSE else C_ROSE_SOFT)
		_text_center(Rect2(nc - Vector2(14, 14), Vector2(28, 28)), str(i + 1), 15, C_INK, bold)
		var lines: PackedStringArray = row.lines
		var tc := C_INK if not dim else Color(C_INK, 0.45)
		if st[i] == C.TRUE and not finished:
			tc = Color(C_INK, 0.55) if not dim else Color(C_INK, 0.35)
		for k in lines.size():
			_text(Vector2(cr.position.x + 44, cr.position.y + 15 + clue_font * 0.85 + k * (clue_font + 5)), lines[k], clue_font, tc)
		var sc := Vector2(cr.end.x - 22, cr.position.y + cr.size.y / 2.0)
		if st[i] == C.TRUE:
			_draw_check(sc, C_OK)
		elif st[i] == C.FALSE:
			draw_line(sc + Vector2(-7, -7), sc + Vector2(7, 7), C_BAD, 3.5)
			draw_line(sc + Vector2(7, -7), sc + Vector2(-7, 7), C_BAD, 3.5)
		else:
			draw_arc(sc, 7, 0, TAU, 24, C_FAINT, 2.5, true)
	# cover rows scrolled out of the list area, then the header on top
	var top := tray_rect.end.y + 2 if portrait else 0.0
	draw_rect(Rect2(r.position.x - 8, top, r.size.x + 16, r.position.y + 34 - top), C_BG)
	draw_rect(Rect2(r.position.x - 8, r.end.y, r.size.x + 16, get_viewport_rect().size.y - r.end.y), C_BG)
	var max_scroll := maxf(0.0, clue_content_h - r.size.y)
	if clue_scroll > 1.0:
		_fade(Rect2(r.position.x, view.position.y, r.size.x, 18), true)
	if clue_scroll < max_scroll - 1.0:
		_fade(Rect2(r.position.x, r.end.y - 24, r.size.x, 24), false)
	_text(r.position + Vector2(2, 24), "Clues", 22, C_INK, bold)
	var note := "Tap a clue or guest to highlight"
	if max_scroll > 1.0:
		note = "Scroll for more · tap to highlight"
	_text(Vector2(r.end.x - _tw(note, 15), r.position.y + 22), note, 15, C_MUTED)


func _fade(r: Rect2, top: bool) -> void:
	var steps := 6
	for k in steps:
		var a := (1.0 - float(k) / steps) * 0.9
		var y := r.position.y + (k * r.size.y / steps if top else r.size.y - (k + 1) * r.size.y / steps)
		draw_rect(Rect2(r.position.x, y, r.size.x, r.size.y / steps + 1), Color(C_BG, a))


func _draw_bar() -> void:
	if modal != "":
		return
	for b in buttons:
		if b.get("dev", false) or b.get("hintcard", false):
			continue
		if b.get("icon", false):
			_draw_icon_button(b)
		else:
			_draw_button(b)


func _draw_button(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var en: bool = b.enabled
	var primary: bool = b.get("primary", false)
	var bg := C_ROSE if primary else C_BTN
	if not en:
		bg = Color(bg, 0.45)
	_box(Rect2(r.position + Vector2(0, 3), r.size), C_SHADOW, 14)
	_box(r, bg, 14)
	var label := String(b.label)
	if String(b.id) == "hint" and hint_open and hint_level > 0 and hint_level < 3:
		label = "Hint %d/3" % (hint_level + 1)
	var tc := Color.WHITE if primary else C_INK
	if not en:
		tc = Color(tc, 0.5)
	_text_center(r, label, 21, tc, bold)


func _draw_icon_button(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var c := r.get_center()
	draw_circle(c, 24, C_BTN)
	if String(b.id) == "help":
		_text_center(r, "?", 26, C_INK, bold)
	else:
		var cr := Rect2(c.x - 11, c.y - 9, 22, 20)
		draw_rect(cr, C_INK, false, 2.2)
		draw_rect(Rect2(cr.position, Vector2(cr.size.x, 5.5)), C_INK)
		draw_line(Vector2(c.x - 5, c.y - 13), Vector2(c.x - 5, c.y - 6), C_INK, 2.2)
		draw_line(Vector2(c.x + 5, c.y - 13), Vector2(c.x + 5, c.y - 6), C_INK, 2.2)
		for i in 3:
			draw_rect(Rect2(c.x - 8 + i * 6, c.y + 1, 4, 4), C_INK)


func _draw_hint() -> void:
	var r := hint_rect
	_box(Rect2(r.position + Vector2(0, 4), r.size), C_SHADOW, 16)
	_box(r, C_PAPER, 16, C_GOLD, 2)
	_text(r.position + Vector2(16, 30), "Hint %d of 3" % hint_level, 18, C_GOLD.darkened(0.25), bold)
	var lines := _hint_lines(r.size.x - 32)
	for k in lines.size():
		_text(r.position + Vector2(16, 58 + k * 24), lines[k], 18, C_INK)
	for b in buttons:
		if b.get("hintcard", false):
			_draw_button(b)


func _dim() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.17, 0.12, 0.16, 0.55))


func _draw_modal_buttons() -> void:
	for b in buttons:
		if not b.get("dev", false) and b.get("kind", "") != "row":
			_draw_button(b)


func _draw_help() -> void:
	_dim()
	var c := _modal_card(_help_height())
	_box(c, C_PAPER, 20, C_GOLD, 2)
	_text_center(Rect2(c.position.x, c.position.y + 18, c.size.x, 44), "How to play", 30, C_INK, bold)
	var y := c.position.y + 92
	for t in HELP_TIPS:
		var lines := _wrap(t, 19, c.size.x - 74, font)
		draw_circle(Vector2(c.position.x + 32, y - 6), 5, C_ROSE)
		for k in lines.size():
			_text(Vector2(c.position.x + 48, y + k * 24), lines[k], 19, C_INK)
		y += lines.size() * 24 + 12
	_draw_modal_buttons()


func _draw_end() -> void:
	_dim()
	var c := _modal_card(470)
	_box(c, C_PAPER, 20, C_GOLD, 2)
	var title := "Everyone's seated!" if not revealed else "Answer revealed"
	_text_center(Rect2(c.position.x, c.position.y + 20, c.size.x, 44), title, 32, C_INK, bold)
	_text_center(Rect2(c.position.x, c.position.y + 64, c.size.x, 30), "#%d · %s · %s" % [model.number, Daily.short_date(date), D.tier_name(model.tier)], 19, C_MUTED)
	_text_center(Rect2(c.position.x, c.position.y + 98, c.size.x, 70), Share.clock(final_seconds), 54, C_ROSE, bold)
	var summary := ""
	if revealed:
		summary = "Better luck tomorrow"
	elif mistakes == 0 and hints_used == 0:
		summary = "Flawless: no hints, no wrong checks"
	else:
		summary = "%d hint%s · %d wrong check%s" % [hints_used, "" if hints_used == 1 else "s", mistakes, "" if mistakes == 1 else "s"]
	_text_center(Rect2(c.position.x, c.position.y + 172, c.size.x, 30), summary, 20, C_INK)
	var sq := 22.0
	var gx := c.get_center().x - (5 * sq + 4 * 6) / 2.0
	var at: PackedInt32Array = board.guest_at()
	for t in 2:
		for p in 5:
			var g: int = at[model.seat(t, p)]
			var col := C_OK
			if revealed:
				col = C_FAINT
			elif board.hinted.has(g):
				col = C_GOLD
			_box(Rect2(gx + p * (sq + 6), c.position.y + 214 + t * (sq + 6), sq, sq), col, 5)
	_draw_modal_buttons()


func _draw_archive() -> void:
	_dim()
	var c := _archive_card()
	_box(c, C_PAPER, 20, C_GOLD, 2)
	_text(c.position + Vector2(24, 50), "Past days", 30, C_INK, bold)
	var pg := "Page %d of %d" % [archive_page + 1, archive_pages()]
	_text(Vector2(c.end.x - 24 - _tw(pg, 18), c.position.y + 48), pg, 18, C_MUTED)
	for b in buttons:
		if b.get("kind", "") != "row":
			continue
		var d := String(b.id).substr(4)
		var r: Rect2 = b.rect
		_box(r, C_CARD, 12, C_ROSE if d == date else C_FAINT, 2)
		var mid := r.get_center().y + 8
		_text(Vector2(r.position.x + 16, mid), "#%d" % Daily.day_number(d), 22, C_ROSE, bold)
		_text(Vector2(r.position.x + 84, mid), "Today" if d == today else Daily.short_date(d), 22, C_INK)
		var res := String(archive_results.get(d, ""))
		var txt := res if res != "" else D.tier_name(Daily.tier_for(d))
		_text(Vector2(r.end.x - 16 - _tw(txt, 19), mid), txt, 19, C_OK if res != "" and res != "In progress" else C_MUTED)
	_draw_modal_buttons()


func _draw_toast() -> void:
	var vs := get_viewport_rect().size
	var w := minf(_tw(toast, 20) + 40, vs.x - 32)
	var lines := _wrap(toast, 20, w - 40, font)
	var h := 22.0 + lines.size() * 26
	var y := bar_rect.position.y - h - 14
	if hint_open:
		y = hint_rect.position.y - h - 10
	var r := Rect2((vs.x - w) / 2.0, y, w, h)
	_box(r, Color(C_INK, 0.92), 14)
	for k in lines.size():
		_text_center(Rect2(r.position.x, r.position.y + 10 + k * 26, r.size.x, 26), lines[k], 20, Color.WHITE)


func _draw_dev() -> void:
	if not dev_open:
		_text(Vector2(6, get_viewport_rect().size.y - 4), "dev", 11, Color(C_MUTED, 0.5))
		return
	var r := _dev_rect()
	_box(r, Color(0.1, 0.08, 0.12, 0.92), 10)
	var rt: Dictionary = model.rating
	var lines := [
		"%s  #%d  %s  seed %d  try %d" % [date, model.number, D.tier_name(model.tier), model.seed_value, model.attempts],
		"levels %s  score %s  clues %d" % [str(rt.get("by_level", [])), str(rt.get("score", "")), model.clues.size()],
		"%s  seated %d  broken %d  hints %d  checks %d" % ["won" if finished else "playing", board.seated_count(), board.broken_clues().size(), hints_used, mistakes],
	]
	var ans := ""
	var at: PackedInt32Array = model.guest_at_from(model.solution)
	for t in 2:
		var ring: Array = []
		for p in 5:
			ring.append(model.guest_name(at[model.seat(t, p)]))
		ans += "T%d %s  " % [t + 1, "-".join(ring)]
	lines.append(ans)
	for k in lines.size():
		_text(r.position + Vector2(10, 20 + k * 19), lines[k], 13, Color.WHITE)
	for b in buttons:
		if b.get("dev", false):
			_box(b.rect, Color(1, 1, 1, 0.15), 8)
			_text_center(b.rect, String(b.label), 15, Color.WHITE)


# ------------------------------------------------------------------ confetti

func _burst() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	confetti = []
	var cols := [C_ROSE, C_GOLD, Color("9cc7f2"), Color("a8dc9b"), Color("f2b8cf")]
	for k in 90:
		var c: Vector2 = table_centers[k % 2]
		confetti.append({"p": c, "v": Vector2(rng.randf_range(-260, 260), rng.randf_range(-620, -200)),
			"c": cols[k % cols.size()], "r": rng.randf_range(0, TAU), "w": rng.randf_range(-8, 8), "life": 2.6})


func _step_confetti(delta: float) -> void:
	var keep: Array = []
	for q in confetti:
		q.v.y += 700 * delta
		q.v.x *= 0.99
		q.p += q.v * delta
		q.r += q.w * delta
		q.life -= delta
		if q.life > 0:
			keep.append(q)
	confetti = keep


func _draw_confetti() -> void:
	for q in confetti:
		var dd := Vector2(cos(q.r), sin(q.r)) * 6
		draw_line(q.p - dd, q.p + dd, Color(q.c, clampf(q.life, 0, 1)), 5)
