extends Node2D
## Drinkle: the UI. Everything that decides the game lives in core/ (pure, tested);
## this script only lays out, draws and routes input.

const Schema = preload("res://core/schema.gd")
const DB = preload("res://core/db.gd")
const Cmp = preload("res://core/compare.gd")
const Search = preload("res://core/search.gd")
const Hints = preload("res://core/hints.gd")
const Explain = preload("res://core/explain.gd")
const Game = preload("res://core/game.gd")
const Share = preload("res://core/share.gd")
const Save = preload("res://core/save.gd")
const Daily = preload("res://core/daily.gd")
const Analysis = preload("res://core/analysis.gd")

const DEFAULT_URL := "https://jprier.github.io/GameTests/drinkle/"
const GOAL := "Name the mystery drink in 6 guesses."
const TIER_NAMES := ["Easy", "Medium", "Hard"]
const COL_LABELS := ["Family", "Base", "Fruit", "Bubbles", "Sweet", "Strength"]
const KEY_ROWS := ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
const ARCHIVE_ROWS := 7
const WIN_WORDS := ["Bullseye!", "Brilliant!", "Splendid!", "Great pour!", "Nice!", "Phew!"]

const C_BG := Color("181223")
const C_PANEL := Color("231a31")
const C_CARD := Color("2d233f")
const C_LINE := Color("43375a")
const C_INK := Color("f4eefc")
const C_MUTED := Color("a99bc0")
const C_FAINT := Color("6d5f86")
const C_ACCENT := Color("f2b84b")
const C_ACCENT_INK := Color("2a1d05")
const C_PINK := Color("e8577a")
const C_GREEN := Color("3d9a5f")
const C_YELLOW := Color("d6a634")
const C_RED := Color("9a3a4d")
const C_ARROW := Color("4560a8")
const C_KEY := Color("3a2f50")
const C_SHADOW := Color(0, 0, 0, 0.35)

# --- state
var today := ""
var today_override := ""
var date := ""
var game = null
var number := 0
var tier := 0
var save = null
var base_url := DEFAULT_URL
var dev_mode := false
var dev_open := false
var dev_show_answer := false
var picked_past := false

var query := ""
var selected_id := ""
var panel_open := false
var suggestions: Array = []
var sugg_scroll := 0.0
var sugg_hover := -1

var modal := ""                     # "", "help", "end", "archive"
var modal_scroll := 0.0
var modal_content_h := 0.0
var archive_page := 0
var archive_results: Dictionary = {}
var end_delay := -1.0
var message := ""
var message_kind := ""             # "", "clue", "hint"
var toast := ""
var toast_t := 0.0
var reveal_row := -1
var reveal_t := 0.0
var shake_t := 0.0
var anim_t := 0.0
var clock_t := 0.0
var share_pending := false
var last_share_text := ""
var title_taps := 0
var title_tap_t := -10.0

# --- layout
var cv: CanvasItem                  # where the draw helpers paint (self, or the clipped modal layer)
var clip_layer: Node2D
var list_layer: Node2D              # the picker's rows, clipped to panel_list_rect
var modal_painter := Callable()
var font: Font
var bold: Font
var portrait := true
var col := Rect2()
var head_rect := Rect2()
var title_rect := Rect2()
var hero_rect := Rect2()
var glass_rect := Rect2()
var colhead_rect := Rect2()
var known_rect := Rect2()
var msg_rect := Rect2()
var rows_rect := Rect2()
var slot_h := 96.0
var input_rect := Rect2()
var field_rect := Rect2()
var kb_rect := Rect2()
var panel_rect := Rect2()
var panel_list_rect := Rect2()
var modal_rect := Rect2()
var modal_body := Rect2()
var dev_rect := Rect2()
var buttons: Array = []
const SUGG_ROW_H := 118.0          # name line + up to two lines of ingredients
const PANEL_HEAD := 44.0

# --- pointer
var pressing := false
var press_pos := Vector2()
var press_btn := ""
var press_area := ""                # "sugg", "modal", ""
var dragging := false
var drag_last := Vector2()


func _ready() -> void:
	cv = self
	clip_layer = Node2D.new()
	clip_layer.name = "ModalClip"
	add_child(clip_layer)
	clip_layer.draw.connect(_draw_clip_layer)
	list_layer = Node2D.new()
	list_layer.name = "PickerList"
	add_child(list_layer)
	list_layer.draw.connect(_draw_list_layer)
	font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = font
	fv.variation_embolden = 0.7
	bold = fv
	GTUI.setup(self, {
		"bg": C_BG, "surface": C_PANEL, "surface_high": C_CARD, "text": C_INK, "text_muted": C_MUTED,
		"border": C_LINE, "accent": C_ACCENT, "on_accent": C_ACCENT_INK,
		"success": C_GREEN, "danger": C_PINK, "focus": C_ACCENT, "scrim": Color(0.05, 0.03, 0.08, 0.78),
	})
	RenderingServer.set_default_clear_color(C_BG)
	_add_key_action("submit", [KEY_ENTER, KEY_KP_ENTER])
	_add_key_action("erase", [KEY_BACKSPACE])
	_add_key_action("close", [KEY_ESCAPE])
	_add_key_action("dev", [KEY_QUOTELEFT])
	get_viewport().size_changed.connect(_on_resize)
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_mode = OS.is_debug_build() or String(url.get("dev", "")) == "1"
	dev_open = String(url.get("dev", "")) == "1"
	save = Save.new(dev_mode)
	today = current_today()
	var want := today
	var d := String(url.get("d", "")) if String(url.get("d", "")) != "" else String(url.get("day", ""))
	if dev_mode and Daily.valid_date(d):
		want = d
	elif d != "":
		_clean_url()          # links always open today; past days are picked in-game
	load_day(want)
	if not bool(save.load_meta().get("tutorial", false)) and not game.finished:
		modal = "help"
		_build_buttons()


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


func current_today() -> String:
	return today_override if today_override != "" else Daily.today_local()


# ------------------------------------------------------------------ days

func load_day(d: String) -> void:
	_save_now()
	date = d
	var t: Dictionary = Daily.target(d)
	game = Game.new(d, t)
	number = Daily.day_number(d)
	tier = int(Daily.difficulty_of(t.id).tier) if not t.is_empty() else 0
	var data: Dictionary = save.load_day(d)
	if not data.is_empty():
		game.load_dict(data)
	query = ""
	selected_id = ""
	panel_open = false
	suggestions = []
	reveal_row = -1
	end_delay = -1.0
	modal_scroll = 0.0
	message = ""
	message_kind = ""
	if not game.facts.is_empty():
		var f: Dictionary = game.facts[-1]
		message = String(f.get("text", ""))
		message_kind = String(f.get("source", "clue"))
	elif not game.hint_texts.is_empty():
		message = String(game.hint_texts[-1].text)
		message_kind = "hint"
	if game.finished:
		modal = "end"
	elif modal == "end" or modal == "archive":
		modal = ""
	_layout()
	queue_redraw()


func _save_now() -> void:
	if game == null or save == null or game.guesses.is_empty() and game.hints_used == 0:
		return
	save.save_day(date, game.to_dict())
	var label: String = game.result_label()
	if label != "":
		save.record_result(date, label)


# ------------------------------------------------------------------ typing & guessing

func can_play() -> bool:
	return game != null and not game.finished and modal == ""


func type_text(s: String) -> void:
	for ch in s:
		press_char(ch)


func press_char(ch: String) -> void:
	if not can_play():
		return
	if query.length() >= 28:
		return
	if ch == " " and (query == "" or query.ends_with(" ")):
		return
	query += ch.to_lower()
	selected_id = ""
	_update_suggestions(true)


func backspace() -> void:
	if not can_play():
		return
	if selected_id != "":
		selected_id = ""
		query = ""
	elif query != "":
		query = query.substr(0, query.length() - 1)
	_update_suggestions(query != "" or panel_open)


func clear_query() -> void:
	query = ""
	selected_id = ""
	_update_suggestions(false)


func _update_suggestions(open: bool) -> void:
	if query.strip_edges() == "":
		suggestions = Search.alphabetical() if open else []
	else:
		suggestions = Search.search(query)
	panel_open = open and can_play()
	sugg_scroll = 0.0
	sugg_hover = 0 if not suggestions.is_empty() and query.strip_edges() != "" else -1
	_layout()
	queue_redraw()


func open_browse() -> void:
	if not can_play():
		return
	if selected_id != "":
		selected_id = ""
		query = ""
	_update_suggestions(true)


func close_panel() -> void:
	panel_open = false
	sugg_hover = -1
	_build_buttons()
	queue_redraw()


## Picks a suggestion (index into the current list) as the drink to guess.
func select_suggestion(i: int) -> bool:
	if i < 0 or i >= suggestions.size() or not can_play():
		return false
	var id: String = suggestions[i]
	if game.guesses.has(id):
		_toast("You already tried the %s." % DB.name_of(id))
		_shake()
		return false
	selected_id = id
	query = DB.name_of(id)
	panel_open = false
	_build_buttons()
	queue_redraw()
	return true


## Submits the selected drink, an exact name/alias, or the only match.
func submit() -> Dictionary:
	if not can_play():
		return {"ok": false, "error": "not playing"}
	var id := selected_id
	if id == "":
		id = Search.resolve(query)
	if id == "" and query.strip_edges() != "":
		var m := Search.search(query)
		if m.size() == 1:
			id = m[0]
		elif panel_open and sugg_hover >= 0 and sugg_hover < suggestions.size():
			id = suggestions[sugg_hover]
	if id == "":
		if query.strip_edges() == "":
			_toast("Type a drink, or tap the box to browse them all.")
			open_browse()
		else:
			_toast("Pick a drink from the list.")
			_update_suggestions(true)
		_shake()
		return {"ok": false, "error": "no drink"}
	return guess_drink(id)


func guess_drink(id: String) -> Dictionary:
	if not can_play():
		return {"ok": false, "error": "not playing"}
	var r: Dictionary = game.guess(id)
	if not r.ok:
		match String(r.error):
			"repeat": _toast("You already tried the %s." % DB.name_of(id))
			_: _toast("That drink isn't in the list.")
		_shake()
		return r
	query = ""
	selected_id = ""
	panel_open = false
	suggestions = []
	reveal_row = game.guesses.size() - 1
	reveal_t = 0.0
	if not r.clue.is_empty():
		message = "Clue: " + String(r.clue.text)
		message_kind = "clue"
	_save_now()
	if game.finished:
		_mark_played()
		end_delay = 1.3
	_layout()
	queue_redraw()
	return r


func use_hint() -> Dictionary:
	if not can_play():
		return {}
	if not game.can_hint():
		_toast("No hints left today.")
		return {}
	var h: Dictionary = game.use_hint()
	message = "Hint %d: %s" % [h.level, h.text]
	message_kind = "hint"
	_save_now()
	_build_buttons()
	queue_redraw()
	return h


func _shake() -> void:
	shake_t = 0.35
	queue_redraw()


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 2.6
	queue_redraw()


# ------------------------------------------------------------------ modals

func open_help() -> void:
	modal = "help"
	modal_scroll = 0.0
	close_panel()
	_build_buttons()
	queue_redraw()


func close_modal() -> void:
	if modal == "help":
		save.set_meta_value("tutorial", true)
	modal = ""
	modal_scroll = 0.0
	_build_buttons()
	queue_redraw()


func show_end() -> void:
	if game.finished:
		modal = "end"
		modal_scroll = 0.0
		_build_buttons()
		queue_redraw()


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
	var idx := clampi(Daily.day_number(today) - Daily.day_number(date), 0, archive_count() - 1)
	archive_page = idx / ARCHIVE_ROWS
	modal = "archive"
	close_panel()
	_build_buttons()
	queue_redraw()


func pick_day(d: String) -> void:
	modal = ""
	if Daily.valid_date(d) and (dev_mode or (d >= Daily.EPOCH and d <= today)):
		picked_past = d != today
		if d != date:
			load_day(d)
	_build_buttons()
	queue_redraw()


# ------------------------------------------------------------------ sharing

## Always the plain game URL; past days are picked inside the game.
func share_link() -> String:
	return base_url


func share_text() -> String:
	if game == null or game.guesses.is_empty():
		return ""
	return Share.text(number, game, share_link())


## Tells the GameTests home page this day is played (not in dev mode).
func _mark_played() -> void:
	if dev_mode or not OS.has_feature("web"):
		return
	var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
		JSON.stringify("gametests:drinkle:" + date), JSON.stringify(JSON.stringify({"result": game.result_label()}))]
	JavaScriptBridge.eval(js, true)


func share() -> void:
	last_share_text = share_text()
	if last_share_text == "":
		return
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__mdShare='pending';
			var done=function(r){if(window.__mdShare==='pending'){window.__mdShare=r;}};
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
					setTimeout(function(){if(window.__mdShare==='pending'){ask();}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},ask);
				}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__mdCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__mdCopyNext=true;done('share_failed');}
				});
			}else{window.__mdCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied! Paste it anywhere.")


func copy_result() -> void:
	last_share_text = share_text()
	if last_share_text == "":
		return
	if OS.has_feature("web"):
		var js := """(function(t){window.__mdShare='pending';window.__mdCopyNext=true;})(0)"""
		JavaScriptBridge.eval(js, true)
		share()
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied! Paste it anywhere.")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__mdShare||''", true)
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


# ------------------------------------------------------------------ date rollover

## Called about once a second. When the calendar day changes, an untouched today's game moves to
## the new day; one in progress (or a past day) stays put and a toast points to the new drink.
func check_rollover() -> void:
	var now := current_today()
	if now == today:
		return
	var was_today := date == today
	today = now
	if was_today and (game == null or game.guesses.is_empty()) and modal != "end":
		load_day(today)
	else:
		_toast("A new mystery drink is ready. Open the calendar to play it.")
	_build_buttons()
	queue_redraw()


# ------------------------------------------------------------------ dev mode

func dev_set_day(d: String) -> void:
	if dev_mode and Daily.valid_date(d):
		modal = ""
		load_day(d)


func dev_set_today(d: String) -> void:
	if dev_mode and Daily.valid_date(d):
		today_override = d
		check_rollover()


func dev_shift(days: int) -> void:
	dev_set_day(Daily.add_days(date, days))


func dev_random_day() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	dev_set_day(Daily.add_days(Daily.EPOCH, rng.randi_range(-30, 1000)))


func dev_reset() -> void:
	if not dev_mode:
		return
	save.wipe_day(date)
	modal = ""
	game = null           # so load_day doesn't save the old game back first
	load_day(date)


func dev_win() -> void:
	if not dev_mode or game.finished:
		return
	modal = ""
	guess_drink(game.target.id)
	end_delay = 0.05


func dev_lose() -> void:
	if not dev_mode or game.finished:
		return
	modal = ""
	var order: Array = Search.alphabetical()
	for id in order:
		if game.finished:
			break
		if id != game.target.id and not game.guesses.has(id):
			guess_drink(id)
	end_delay = 0.05


func get_agent_state() -> Dictionary:
	var rows: Array = []
	if game:
		for i in game.guesses.size():
			rows.append({"drink": DB.name_of(game.guesses[i]), "feedback": Cmp.key(game.feedback(i))})
	var known := {}
	if game:
		var k: Dictionary = game.knowledge()
		for id in Schema.ids():
			known[id] = Hints.known_text(id, k[id])
	var sug: Array = []
	for i in mini(6, suggestions.size()):
		sug.append(DB.name_of(suggestions[i]))
	return {
		"day": date, "today": today, "number": number, "tier": TIER_NAMES[tier],
		"seed": Daily.seed_for(date),
		"state": "playing" if game and not game.finished else ("won" if game and game.won else "lost"),
		"guesses": rows, "guesses_left": game.guesses_left() if game else 0,
		"hints": game.hints_used if game else 0, "message": message, "known": known,
		"query": query, "selected": selected_id, "panel_open": panel_open, "suggestions": sug,
		"modal": modal, "dev_mode": dev_mode, "share_text": share_text(),
		"answer": game.target.name if dev_mode and game else "",
		"candidates_left": game.remaining().size() if dev_mode and game else -1,
	}


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	anim_t += delta
	var redraw := false
	if reveal_row >= 0:
		reveal_t += delta
		redraw = true
		if reveal_t > 1.2:
			reveal_row = -1
	if shake_t > 0.0:
		shake_t -= delta
		redraw = true
	if toast_t > 0.0:
		toast_t -= delta
		redraw = true
	if end_delay > 0.0:
		end_delay -= delta
		if end_delay <= 0.0:
			end_delay = -1.0
			show_end()
	clock_t += delta
	if clock_t > 1.0:
		clock_t = 0.0
		check_rollover()
	if share_pending:
		_poll_share()
	if Input.is_action_just_pressed("dev") and dev_mode:
		dev_open = not dev_open
		_build_buttons()
		redraw = true
	if redraw:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		check_rollover()


# ------------------------------------------------------------------ layout

func _layout() -> void:
	layout_for(get_viewport_rect().size)


## Lays everything out for a canvas of size vs (tests call this with phone and desktop sizes).
func layout_for(vs: Vector2) -> void:
	portrait = vs.x < vs.y * 1.15
	var pad := 16.0
	if portrait:
		var cw := minf(vs.x - pad * 2, 760.0)
		col = Rect2((vs.x - cw) * 0.5, 0, cw, vs.y)
		var x := col.position.x
		var y := 12.0
		head_rect = Rect2(x, y, cw, _head_h())
		y += _head_h() + 6
		var hero_h := clampf(vs.y * 0.085, 96.0, 132.0)
		hero_rect = Rect2(x, y, cw, hero_h)
		y += hero_h + 8
		colhead_rect = Rect2(x, y, cw, 28)
		y += 28 + 2
		known_rect = Rect2(x, y, cw, 58)
		y += 58 + 8
		msg_rect = Rect2(x, y, cw, 56)
		y += 56 + 10
		var key_h := maxf(GTUI.target(), clampf(vs.y * 0.046, 54.0, 74.0))
		var kb_h := key_h * 3 + 8 * 2
		kb_rect = Rect2(x, vs.y - 12 - kb_h, cw, kb_h)
		input_rect = Rect2(x, kb_rect.position.y - 12 - 68, cw, 68)
		rows_rect = Rect2(x, y, cw, maxf(60.0, input_rect.position.y - 12 - y))
		slot_h = minf(rows_rect.size.y / 6.0, 108.0)
		rows_rect.size.y = slot_h * 6
		# the list never covers the Known row unless the screen is too short for 2.5 rows
		var room := input_rect.position.y - 8 - (msg_rect.end.y + 6)
		if room < PANEL_HEAD + SUGG_ROW_H * 2.5:
			room = input_rect.position.y - 8 - colhead_rect.position.y
		var ph := minf(PANEL_HEAD + SUGG_ROW_H * 5.5, room)
		panel_rect = Rect2(x, input_rect.position.y - 8 - ph, cw, ph)
		glass_rect = Rect2(hero_rect.position.x + 4, hero_rect.position.y, hero_rect.size.y * 0.8, hero_rect.size.y)
	else:
		var total := minf(vs.x - pad * 3, 1320.0)
		var lw := clampf(total * 0.56, 470.0, 800.0)
		var rw := total - lw
		var x0 := (vs.x - total - pad) * 0.5
		col = Rect2(x0, 0, lw, vs.y)
		var y := 10.0
		head_rect = Rect2(x0, y, lw, _head_h())
		y += _head_h() + 6
		colhead_rect = Rect2(x0, y, lw, 26)
		y += 26 + 2
		known_rect = Rect2(x0, y, lw, 52)
		y += 52 + 6
		msg_rect = Rect2(x0, y, lw, 50)
		y += 50 + 8
		rows_rect = Rect2(x0, y, lw, vs.y - 10 - y)
		slot_h = minf(rows_rect.size.y / 6.0, 104.0)
		rows_rect.size.y = slot_h * 6
		var rx := x0 + lw + pad
		var key_h := maxf(GTUI.target(), clampf(vs.y * 0.075, 46.0, 66.0))
		var kb_h := key_h * 3 + 8 * 2
		kb_rect = Rect2(rx, vs.y - 10 - kb_h, rw, kb_h)
		input_rect = Rect2(rx, kb_rect.position.y - 10 - 64, rw, 64)
		hero_rect = Rect2(rx, 10, rw, input_rect.position.y - 20)
		var gh := minf(hero_rect.size.y * 0.62, 220.0)
		glass_rect = Rect2(rx + (rw - gh * 0.8) * 0.5, hero_rect.position.y + 8, gh * 0.8, gh)
		panel_rect = Rect2(rx, 10, rw, input_rect.position.y - 18)
	panel_list_rect = Rect2(panel_rect.position.x, panel_rect.position.y + PANEL_HEAD, panel_rect.size.x, panel_rect.size.y - PANEL_HEAD)
	title_rect = Rect2(head_rect.position.x, head_rect.position.y, head_rect.size.x - 120, head_rect.size.y)
	modal_rect = GTUI.modal_rect(self, 600, minf(vs.y - GTUI.dp(GTUI.SP_L) * 2, GTUI.dp(820)))
	var mc := GTUI.modal_content(modal_rect)
	modal_body = Rect2(mc.position, mc.size - Vector2(0, GTUI.target() + GTUI.dp(GTUI.SP_XL)))
	_clamp_scrolls()
	_build_buttons()


func _clamp_scrolls() -> void:
	var max_s := maxf(0.0, suggestions.size() * SUGG_ROW_H - panel_list_rect.size.y)
	sugg_scroll = clampf(sugg_scroll, 0.0, max_s)
	modal_scroll = clampf(modal_scroll, 0.0, maxf(0.0, modal_content_h - modal_body.size.y))


func cell_rect(row_rect: Rect2, i: int) -> Rect2:
	var gap := 6.0
	var w := (row_rect.size.x - gap * 5) / 6.0
	return Rect2(row_rect.position.x + i * (w + gap), row_rect.position.y, w, row_rect.size.y)


func slot_rect(i: int) -> Rect2:
	return Rect2(rows_rect.position.x, rows_rect.position.y + i * slot_h, rows_rect.size.x, slot_h - 8)


func slot_cells_rect(i: int) -> Rect2:
	var r := slot_rect(i)
	var name_h := clampf(slot_h * 0.3, 24.0, 32.0)
	return Rect2(r.position.x, r.position.y + name_h, r.size.x, r.size.y - name_h)


# ------------------------------------------------------------------ buttons

func _btn(id: String, r: Rect2, label: String, style: String, enabled := true) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "style": style, "enabled": enabled})


func _build_buttons() -> void:
	buttons = []
	var vs := get_viewport_rect().size
	if modal != "":
		_modal_buttons(vs)
		if dev_mode and dev_open:
			_dev_buttons(vs)
		return
	var hr := head_rect
	var icons := GTUI.icon_row(hr.end.x, hr.position.y + (hr.size.y - GTUI.target()) / 2.0, ["archive", "help"])
	_btn("help", icons["help"], "?", "icon")
	_btn("archive", icons["archive"], "cal", "icon")
	if game and game.finished:
		var bw := (input_rect.size.x - 12) * 0.5
		_btn("result", Rect2(input_rect.position.x, input_rect.position.y, bw, input_rect.size.y), "See result", "ghost")
		_btn("share", Rect2(input_rect.position.x + bw + 12, input_rect.position.y, bw, input_rect.size.y), "Share", "primary")
		if date != today:
			_btn("today", Rect2(kb_rect.position.x, kb_rect.position.y, kb_rect.size.x, 60), "Play today's drink", "ghost")
	else:
		var gw := maxf(128.0, GTUI.dp(88))
		var hw := maxf(104.0, GTUI.text_width("Hint (3)", GTUI.FS_LABEL + 2, true) + GTUI.dp(GTUI.SP_M) * 2)
		field_rect = Rect2(input_rect.position.x, input_rect.position.y, input_rect.size.x - gw - hw - 16, input_rect.size.y)
		_btn("hint", Rect2(field_rect.end.x + 8, input_rect.position.y, hw, input_rect.size.y),
			"Hint", "ghost", game != null and game.can_hint())
		_btn("guess", Rect2(input_rect.end.x - gw, input_rect.position.y, gw, input_rect.size.y), "Guess", "primary",
			selected_id != "" or query.strip_edges() != "")
		_keyboard_buttons()
		if panel_open:
			var t := GTUI.target()
			_btn("panel_close", Rect2(panel_rect.end.x - t - 2, panel_rect.position.y + (PANEL_HEAD - t) / 2.0, t, t), "x", "icon_small")
	if dev_mode and dev_open:
		_dev_buttons(vs)


func _keyboard_buttons() -> void:
	var r := kb_rect
	var gap := 6.0
	var key_h := (r.size.y - 16) / 3.0
	var kw := (r.size.x - gap * 9) / 10.0
	for ri in KEY_ROWS.size():
		var row: String = KEY_ROWS[ri]
		var y := r.position.y + ri * (key_h + 8)
		if ri < 2:
			var x := r.position.x + (r.size.x - (row.length() * kw + (row.length() - 1) * gap)) * 0.5
			for ch in row:
				_btn("k_" + ch, Rect2(x, y, kw, key_h), ch, "key")
				x += kw + gap
		else:
			var wide := (r.size.x - row.length() * (kw + gap) - gap) * 0.5
			_btn("k_SPACE", Rect2(r.position.x, y, wide, key_h), "space", "key_wide")
			var x2 := r.position.x + wide + gap
			for ch in row:
				_btn("k_" + ch, Rect2(x2, y, kw, key_h), ch, "key")
				x2 += kw + gap
			_btn("k_DEL", Rect2(x2, y, r.end.x - x2, key_h), "del", "key_wide")


func _modal_buttons(_vs: Vector2) -> void:
	var m := modal_rect
	var row := GTUI.modal_buttons_rect(GTUI.modal_content(m))
	_btn("close", GTUI.modal_close_rect(m), "x", "modal_x")
	match modal:
		"help":
			_btn("close", row, "Let's play", "primary")
		"end":
			var rr := GTUI.row(row, 2, [1.0, 1.4])
			_btn("copy", rr[0], "Copy result", "ghost")
			_btn("share", rr[1], "Share", "primary")
		"archive":
			var rr := GTUI.row(row, 2)
			_btn("arch_newer", rr[0], "Newer", "ghost", archive_page > 0)
			_btn("arch_older", rr[1], "Older", "ghost", archive_page < archive_pages() - 1)
			var days := archive_page_days(archive_page)
			var y0 := modal_body.position.y + GTUI.line_height(GTUI.FS_CAPTION) + GTUI.dp(GTUI.SP_S)
			var rh := GTUI.target() + GTUI.dp(GTUI.SP_S)
			for i in days.size():
				_btn("day_" + String(days[i]), Rect2(modal_body.position.x, y0 + i * rh, modal_body.size.x, GTUI.target()), "", "day")


func _dev_buttons(vs: Vector2) -> void:
	var w := minf(360.0, vs.x - 20)
	dev_rect = Rect2(vs.x - w - 10, 10, w, 300)
	var x := dev_rect.position.x + 10
	var y := dev_rect.position.y + 140
	var bw := (w - 20 - 12) / 3.0
	var ids := [["dev_prev", "< Day"], ["dev_today", "Today"], ["dev_next", "Day >"],
		["dev_week_back", "-7"], ["dev_random", "Random"], ["dev_week_fwd", "+7"],
		["dev_reset", "Reset"], ["dev_win", "Win"], ["dev_lose", "Lose"],
		["dev_answer", "Answer"], ["dev_tomorrow", "Rollover"], ["dev_hide", "Hide"]]
	for i in ids.size():
		_btn(ids[i][0], Rect2(x + (i % 3) * (bw + 6), y + (i / 3) * 38, bw, 32), ids[i][1], "dev")   # dev-only, not registered


func _button_at(p: Vector2) -> Dictionary:
	for i in range(buttons.size() - 1, -1, -1):
		var b: Dictionary = buttons[i]
		if b.enabled and b.rect.has_point(p):
			return b
	return {}


func button_center(id: String) -> Vector2:
	for b in buttons:
		if b.id == id:
			return b.rect.get_center()
	return Vector2(-1, -1)


func suggestion_center(i: int) -> Vector2:
	return Vector2(panel_list_rect.get_center().x, panel_list_rect.position.y + i * SUGG_ROW_H + SUGG_ROW_H * 0.5 - sugg_scroll)


func activate(id: String) -> void:
	if id.begins_with("k_"):
		var k := id.substr(2)
		match k:
			"SPACE": press_char(" ")
			"DEL": backspace()
			_: press_char(k)
		return
	if id.begins_with("day_"):
		pick_day(id.substr(4))
		return
	match id:
		"help": open_help()
		"archive": open_archive()
		"close": close_modal()
		"hint": use_hint()
		"guess": submit()
		"panel_close": close_panel()
		"share": share()
		"copy": copy_result()
		"result": show_end()
		"today": pick_day(today)
		"arch_newer":
			archive_page = maxi(0, archive_page - 1)
			_build_buttons()
		"arch_older":
			archive_page = mini(archive_pages() - 1, archive_page + 1)
			_build_buttons()
		"dev_prev": dev_shift(-1)
		"dev_next": dev_shift(1)
		"dev_week_back": dev_shift(-7)
		"dev_week_fwd": dev_shift(7)
		"dev_today": dev_set_day(today)
		"dev_random": dev_random_day()
		"dev_reset": dev_reset()
		"dev_win": dev_win()
		"dev_lose": dev_lose()
		"dev_answer": dev_show_answer = not dev_show_answer
		"dev_tomorrow": dev_set_today(Daily.add_days(today, 1))
		"dev_hide": dev_open = false
	_build_buttons()
	queue_redraw()


# ------------------------------------------------------------------ input

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.keycode
		if k == KEY_QUOTELEFT:
			return
		if ev.is_action("close"):
			if modal == "help" or modal == "archive" or modal == "end":
				close_modal()
			elif panel_open:
				close_panel()
			get_viewport().set_input_as_handled()
			return
		if modal != "":
			if ev.is_action("submit") and modal == "help":
				close_modal()
			return
		if ev.is_action("submit"):
			submit()
		elif ev.is_action("erase"):
			backspace()
		elif k == KEY_DOWN and panel_open:
			sugg_hover = mini(sugg_hover + 1, suggestions.size() - 1)
			_ensure_hover_visible()
		elif k == KEY_UP and panel_open:
			sugg_hover = maxi(sugg_hover - 1, 0)
			_ensure_hover_visible()
		elif k == KEY_SPACE:
			press_char(" ")
		elif ev.unicode > 0:
			var ch := char(ev.unicode)
			if ch.to_lower() != ch.to_upper() or (ch >= "0" and ch <= "9") or ch == "&" or ch == "'":
				press_char(ch)
		get_viewport().set_input_as_handled()
		queue_redraw()


func _ensure_hover_visible() -> void:
	var top := sugg_hover * SUGG_ROW_H
	if top < sugg_scroll:
		sugg_scroll = top
	elif top + SUGG_ROW_H > sugg_scroll + panel_list_rect.size.y:
		sugg_scroll = top + SUGG_ROW_H - panel_list_rect.size.y
	_clamp_scrolls()
	queue_redraw()


func _input(ev: InputEvent) -> void:
	var gt := GTUI.handle_input(ev)
	if gt.has("activate"):
		for e in GTUI.tap_events(gt.pos):
			_input(e)
		get_viewport().set_input_as_handled()
		return
	if gt.has("consumed"):
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed:
				var dy := -60.0 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0
				if modal != "":
					modal_scroll += dy
				elif panel_open:
					sugg_scroll += dy
				_clamp_scrolls()
				queue_redraw()
			return
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return
		if ev.pressed:
			pressing = true
			dragging = false
			press_pos = ev.position
			drag_last = ev.position
			press_btn = String(_button_at(ev.position).get("id", ""))
			press_area = ""
			if modal != "" and modal_body.has_point(ev.position):
				press_area = "modal"
			elif modal == "" and panel_open and panel_list_rect.has_point(ev.position):
				press_area = "sugg"
		else:
			if not pressing:
				return
			pressing = false
			if dragging:
				dragging = false
				return
			var b := _button_at(ev.position)
			if press_btn != "" and String(b.get("id", "")) == press_btn:
				activate(press_btn)
			elif press_btn == "":
				_tap(ev.position)
			get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and pressing:
		if not dragging and ev.position.distance_to(press_pos) > 12.0 and press_area != "":
			dragging = true
			press_btn = ""
		if dragging:
			var dy: float = drag_last.y - ev.position.y
			if press_area == "modal":
				modal_scroll += dy
			elif press_area == "sugg":
				sugg_scroll += dy
			_clamp_scrolls()
			queue_redraw()
		drag_last = ev.position


func _tap(p: Vector2) -> void:
	if modal == "archive" or modal == "help" or modal == "end":
		if not modal_rect.has_point(p) and modal != "help":
			close_modal()
		return
	if dev_mode and dev_open and dev_rect.has_point(p):
		return
	if title_rect.has_point(p):
		_title_tap()
		return
	if panel_open and panel_list_rect.has_point(p):
		var i := int((p.y - panel_list_rect.position.y + sugg_scroll) / SUGG_ROW_H)
		select_suggestion(i)
		return
	if panel_open and panel_rect.has_point(p):
		return
	if field_rect.has_point(p) and can_play():
		open_browse()
		return
	if panel_open:
		close_panel()
		return
	if glass_rect.has_point(p) and game and game.finished:
		show_end()


func _title_tap() -> void:
	if anim_t - title_tap_t > 1.5:
		title_taps = 0
	title_tap_t = anim_t
	title_taps += 1
	if title_taps >= 5:
		title_taps = 0
		dev_mode = true
		dev_open = true
		save = Save.new(true)
		load_day(date)
		_toast("Dev mode on (saves kept separately).")


# ------------------------------------------------------------------ text helpers

func _wrap(text: String, width: float, size: int, f: Font) -> Array:
	var lines: Array = []
	for para in text.split("\n"):
		var words := para.split(" ", false)
		var line := ""
		for w in words:
			var t := w if line == "" else line + " " + w
			if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width or line == "":
				line = t
			else:
				lines.append(line)
				line = w
		lines.append(line)
	return lines


## {lines, size}: the largest size from `size` down to `min_size` at which the text fits in
## max_lines lines of `width`. Never truncates.
func fit(text: String, width: float, size: int, min_size: int, max_lines: int, f: Font = null) -> Dictionary:
	if f == null:
		f = font
	var s := size
	while s >= min_size:
		var lines := _wrap(text, width, s, f)
		var ok := lines.size() <= max_lines
		if ok:
			for l in lines:
				if f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
					ok = false
					break
		if ok:
			return {"lines": lines, "size": s}
		s -= 1
	return {"lines": _wrap(text, width, min_size, f), "size": min_size}


func text_fits(text: String, width: float, size: int, min_size: int, max_lines: int, f: Font = null) -> bool:
	if f == null:
		f = font
	var r := fit(text, width, size, min_size, max_lines, f)
	if r.lines.size() > max_lines:
		return false
	for l in r.lines:
		if f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, r.size).x > width + 0.5:
			return false
	return true


func _draw_lines_centered(r: Rect2, lines: Array, size: int, color: Color, f: Font = null) -> void:
	if f == null:
		f = font
	var lh := f.get_height(size) * 0.98
	var total := lh * lines.size()
	var y := r.position.y + (r.size.y - total) * 0.5 + f.get_ascent(size)
	for l in lines:
		cv.draw_string(f, Vector2(r.position.x, y), l, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, color)
		y += lh


func _draw_text_in(r: Rect2, text: String, size: int, min_size: int, max_lines: int, color: Color, f: Font = null) -> void:
	var ft := fit(text, r.size.x, size, min_size, max_lines, f)
	_draw_lines_centered(r, ft.lines, ft.size, color, f)


## Left-aligned wrapped text from the top-left; returns the height used.
func _draw_para(pos: Vector2, width: float, text: String, size: int, color: Color, f: Font = null, draw := true) -> float:
	if f == null:
		f = font
	var lines := _wrap(text, width, size, f)
	var lh := f.get_height(size) * 1.05
	if draw:
		var y := pos.y + f.get_ascent(size)
		for l in lines:
			cv.draw_string(f, Vector2(pos.x, y), l, HORIZONTAL_ALIGNMENT_LEFT, width, size, color)
			y += lh
	return lh * lines.size()


func _rrect(r: Rect2, color: Color, radius := 12.0, filled := true, width := 2.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(radius))
	if filled:
		sb.bg_color = color
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = color
		sb.set_border_width_all(int(width))
	sb.anti_aliasing = true
	cv.draw_style_box(sb, r)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	GTUI.begin()
	var vs := get_viewport_rect().size
	if modal != "help" and modal != "end":
		modal_painter = Callable()
		clip_layer.queue_redraw()
	list_layer.queue_redraw()
	cv.draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	if game == null:
		return
	_draw_head()
	_draw_hero()
	_draw_colheads()
	_draw_known()
	_draw_message()
	for i in Game.MAX_GUESSES:
		_draw_slot(i)
	_draw_input_area()
	_draw_buttons_layer(false)
	if panel_open and modal == "":
		_draw_panel()
	if modal != "":
		match modal:
			"help": _draw_help()
			"end": _draw_end()
			"archive": _draw_archive()
		_draw_buttons_layer(true)
	if dev_mode and dev_open:
		_draw_dev()
	if toast_t > 0.0 and toast != "":
		_draw_toast(vs)


func _draw_head() -> void:
	var r := head_rect
	var lh_t := GTUI.line_height(GTUI.FS_HEADING)
	var lh_m := GTUI.line_height(GTUI.FS_LABEL)
	var ty := r.position.y + (r.size.y - lh_t - lh_m + GTUI.dp(GTUI.SP_XS)) / 2.0
	var tw := r.size.x - GTUI.target() * 2 - GTUI.dp(GTUI.SP_L)
	GTUI.text_in(self, Rect2(r.position.x, ty, tw, lh_t), "Drinkle", GTUI.FS_HEADING, C_INK, -1, true)
	var sub := "#%d · %s · %s" % [number, Daily.short_date(date), TIER_NAMES[tier]]
	if date < today:
		sub += " · past day"
	elif date > today:
		sub += " · preview"
	GTUI.text_in(self, Rect2(r.position.x, ty + lh_t - GTUI.dp(GTUI.SP_XS), tw, lh_m), sub, GTUI.FS_LABEL, C_MUTED, -1)


func _draw_hero() -> void:
	var r := hero_rect
	var revealed: bool = game.finished
	var t: Dictionary = game.target
	if revealed:
		_draw_glass(glass_rect, String(t.get("glass", "coupe")), Color(String(t.get("color", "#e8577a"))), false)
	else:
		_draw_glass(glass_rect, "coupe", Color("6b4fa0"), true)
	var tx: float
	var tw: float
	var ty: float
	if portrait:
		tx = glass_rect.end.x + 18
		tw = r.end.x - tx
		ty = r.position.y + 8
	else:
		tx = r.position.x
		tw = r.size.x
		ty = glass_rect.end.y + 14
	var line1 := GOAL
	if game.finished:
		line1 = ("It was the %s!" % t.name) if game.won else ("It was the %s." % t.name)
	var h := _draw_para(Vector2(tx, ty), tw, line1, 26 if portrait else 24, C_INK, bold)
	# pips: one glass per guess
	var py := ty + h + 12
	var pr := 13.0
	for i in Game.MAX_GUESSES:
		var c := Vector2(tx + pr + i * (pr * 2 + 10), py + pr)
		if i < game.guesses.size():
			var won_here: bool = game.won and i == game.guesses.size() - 1
			cv.draw_circle(c, pr, C_GREEN if won_here else C_PINK)
		else:
			cv.draw_arc(c, pr - 1, 0, TAU, 32, C_LINE, 2.5, true)
	var left: int = game.guesses_left()
	var status := "Solved in %d" % game.guesses.size() if game.won else ("%d guess%s left" % [left, "" if left == 1 else "es"])
	if game.finished and not game.won:
		status = "Out of guesses"
	cv.draw_string(font, Vector2(tx + Game.MAX_GUESSES * (pr * 2 + 10) + 6, py + pr + 8), status, HORIZONTAL_ALIGNMENT_LEFT, maxf(10.0, tw - Game.MAX_GUESSES * (pr * 2 + 10) - 6), GTUI.fs(GTUI.FS_TITLE), C_MUTED)


func _draw_colheads() -> void:
	for i in 6:
		var c := cell_rect(colhead_rect, i)
		_draw_text_in(c, COL_LABELS[i], 18, 13, 1, C_MUTED, bold)


func _draw_known() -> void:
	var k: Dictionary = game.knowledge()
	var ids := Schema.ids()
	for i in ids.size():
		var c := cell_rect(known_rect, i)
		var e: Dictionary = k[ids[i]]
		var txt := Hints.known_text(ids[i], e)
		var col_c := C_LINE
		var ink := C_FAINT
		if e.exact:
			col_c = C_GREEN
			ink = C_INK
			_rrect(c, Color(C_GREEN, 0.22), 10)
		elif txt != "?":
			col_c = C_YELLOW if not Schema.is_ordinal(ids[i]) else C_ARROW.lightened(0.25)
			ink = C_INK
		_rrect(c, col_c, 10, false, 2.0)
		_draw_text_in(c.grow(-5), txt, 19, 12, 2, ink, bold if e.exact else font)


func _draw_message() -> void:
	var r := msg_rect
	GTUI.panel(self, r)
	var txt := message
	var ink := C_INK
	if txt == "":
		ink = C_MUTED
		if game.guesses.is_empty():
			txt = "The Known row fills in as you guess. Tap the box below to browse every drink."
		else:
			txt = "Green = same, yellow = related, red = no. Arrows point toward the mystery drink."
	elif message_kind == "clue":
		ink = C_ACCENT
	_draw_text_in(Rect2(r.position.x + GTUI.dp(GTUI.SP_M), r.position.y, r.size.x - GTUI.dp(GTUI.SP_M) * 2, r.size.y), txt, GTUI.fs(GTUI.FS_LABEL), GTUI.fs(GTUI.FS_CAPTION), 2, ink)


func _code_color(code: int) -> Color:
	match code:
		Schema.EXACT: return C_GREEN
		Schema.PARTIAL: return C_YELLOW
		Schema.HIGHER, Schema.LOWER: return C_ARROW
	return C_RED


func _draw_slot(i: int) -> void:
	var r := slot_rect(i)
	var cells := slot_cells_rect(i)
	var name_h := cells.position.y - r.position.y
	if i >= game.guesses.size():
		cv.draw_string(font, Vector2(r.position.x + 2, r.position.y + name_h - 8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_FAINT)  # gt:art
		for j in 6:
			_rrect(cell_rect(cells, j), Color(C_LINE, 0.55), 10, false, 1.5)
		return
	var id: String = game.guesses[i]
	var d := DB.get_drink(id)
	var fb: PackedInt32Array = game.feedback(i)
	var dx := 0.0
	if i == game.guesses.size() - 1 and shake_t > 0.0:
		dx = sin(shake_t * 60.0) * 6.0 * shake_t
	var nm := "%d  %s" % [i + 1, d.name]
	cv.draw_string(bold, Vector2(r.position.x + 2 + dx, r.position.y + name_h - 8), nm, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 22, C_INK)  # gt:art
	var ids := Schema.ids()
	for j in 6:
		var c := cell_rect(cells, j)
		var show := 1.0
		if i == reveal_row:
			show = clampf((reveal_t - j * 0.09) / 0.18, 0.0, 1.0)
		if show <= 0.0:
			_rrect(c, C_CARD, 10)
			continue
		var cc := c
		if show < 1.0:
			var hh := c.size.y * show
			cc = Rect2(c.position.x, c.get_center().y - hh * 0.5, c.size.x, hh)
		var code := fb[j]
		_rrect(cc, _code_color(code), 10)
		if show < 1.0:
			continue
		var ink := C_ACCENT_INK if code == Schema.PARTIAL else Color.WHITE
		var label := Schema.value_label(ids[j], d.get(ids[j]))
		var tr := c.grow(-5)
		if code == Schema.HIGHER or code == Schema.LOWER:
			var ah := minf(16.0, c.size.y * 0.24)
			_draw_arrow(Vector2(c.get_center().x, c.position.y + 6 + ah * 0.5), ah, code == Schema.HIGHER, Color.WHITE)
			tr = Rect2(c.position.x + 4, c.position.y + 6 + ah, c.size.x - 8, c.size.y - 10 - ah)
		_draw_text_in(tr, label, 20, 12, 2, ink, bold)


func _draw_arrow(center: Vector2, size: float, up: bool, color: Color) -> void:
	var h := size * 0.5
	var pts: PackedVector2Array
	if up:
		pts = PackedVector2Array([center + Vector2(0, -h), center + Vector2(h * 1.1, h), center + Vector2(-h * 1.1, h)])
	else:
		pts = PackedVector2Array([center + Vector2(0, h), center + Vector2(-h * 1.1, -h), center + Vector2(h * 1.1, -h)])
	cv.draw_colored_polygon(pts, color)


func _draw_input_area() -> void:
	if game.finished:
		return
	var r := field_rect
	GTUI.register("field", r, can_play())
	var active := panel_open or query != ""
	GTUI.box(self, r, C_CARD, GTUI.R_CONTROL, C_ACCENT if active else C_LINE, GTUI.FOCUS_WIDTH if active else GTUI.BORDER)
	var txt := query
	var ink := C_INK
	var f := font
	if selected_id != "":
		txt = DB.name_of(selected_id)
		f = bold
	elif txt == "":
		txt = "Type or tap to browse"
		ink = C_MUTED
	var pad := GTUI.dp(GTUI.SP_M)
	var ft := fit(txt, r.size.x - pad * 2, GTUI.fs(GTUI.FS_BODY + 2), GTUI.fs(GTUI.FS_CAPTION), 1, f)
	var y := r.position.y + (r.size.y + f.get_ascent(ft.size) - f.get_descent(ft.size)) * 0.5
	cv.draw_string(f, Vector2(r.position.x + pad, y), ft.lines[0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - pad * 2, ft.size, ink)
	if (query != "" or panel_open) and selected_id == "" and fmod(anim_t, 1.0) < 0.6:
		var w := f.get_string_size(query, HORIZONTAL_ALIGNMENT_LEFT, -1, ft.size).x
		cv.draw_rect(Rect2(r.position.x + pad + 1 + w, r.position.y + r.size.y * 0.25, 2, r.size.y * 0.5), C_ACCENT)
		queue_redraw()
	GTUI.focus_ring(self, "field", r)


func _draw_buttons_layer(modal_layer: bool) -> void:
	if modal_layer != (modal != ""):
		return
	for b in buttons:
		if not String(b.id).begins_with("dev_"):
			_draw_button(b)


func _draw_button(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var en: bool = b.enabled
	var id := String(b.id)
	match String(b.style):
		"primary":
			GTUI.button(self, id, r, b.label, "primary", en)
		"accent":
			GTUI.button(self, id, r, b.label, "primary", en)
		"ghost":
			var lbl: String = b.label
			if b.id == "hint" and game:
				lbl = "Hint (%d)" % (Game.MAX_HINTS - game.hints_used) if game.can_hint() else "No hints"
			GTUI.button(self, id, r, lbl, "secondary", en)
		"key", "key_wide":
			# on-screen keyboard: compact keys (width may go below 44 dp; height may not)
			GTUI.register(id, r, en, true)
			var fill := C_KEY if b.style == "key" else C_KEY.darkened(0.15)
			if GTUI.is_pressed(id, r):
				fill = fill.lightened(0.16)
			elif GTUI.is_hover(id):
				fill = fill.lightened(0.08)
			GTUI.box(self, r, fill, GTUI.R_CONTROL)
			if b.label == "del":
				_draw_backspace(r)
			elif b.style == "key":
				GTUI.text_in(self, r, b.label, GTUI.FS_BODY + 2, C_INK, 0, true)
			else:
				GTUI.text_in(self, r.grow(-4), b.label, GTUI.FS_LABEL, C_MUTED, 0, true)
			GTUI.focus_ring(self, id, r)
		"icon":
			GTUI.icon_button(self, id, r, "help" if b.label == "?" else "calendar")
		"icon_small":
			GTUI.icon_button(self, id, r, "close")
		"modal_x":
			pass   # drawn by GTUI.modal()
		"day":
			_draw_day_row(b)
		"dev":
			pass


func _draw_backspace(r: Rect2) -> void:
	var c := r.get_center()
	var w := minf(r.size.x * 0.42, 40.0)
	var h := minf(r.size.y * 0.38, 24.0)
	var pts := PackedVector2Array([c + Vector2(-w * 0.5, 0), c + Vector2(-w * 0.2, -h * 0.5), c + Vector2(w * 0.5, -h * 0.5),
		c + Vector2(w * 0.5, h * 0.5), c + Vector2(-w * 0.2, h * 0.5), c + Vector2(-w * 0.5, 0)])
	cv.draw_polyline(pts, C_INK, 2.5, true)
	_draw_x(c + Vector2(w * 0.15, 0), h * 0.22, C_INK)


func _draw_x(c: Vector2, s: float, color: Color) -> void:
	cv.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), color, 3.0, true)
	cv.draw_line(c + Vector2(-s, s), c + Vector2(s, -s), color, 3.0, true)


func _draw_panel() -> void:
	var r := panel_rect
	GTUI.box(self, r, C_PANEL, GTUI.R_PANEL, C_LINE)
	var head := "All %d drinks, A to Z" % DB.size() if query.strip_edges() == "" else (
		"%d match%s for \"%s\"" % [suggestions.size(), "" if suggestions.size() == 1 else "es", query.strip_edges()])
	if suggestions.is_empty():
		head = "No drink matches \"%s\"" % query.strip_edges()
	GTUI.text_in(self, Rect2(r.position.x + GTUI.dp(GTUI.SP_L), r.position.y, r.size.x - GTUI.target() - GTUI.dp(GTUI.SP_L) * 2, PANEL_HEAD), head, GTUI.FS_LABEL, C_MUTED, -1)
	var lr := panel_list_rect
	# scroll bar
	var content := suggestions.size() * SUGG_ROW_H
	if content > lr.size.y:
		var bh := maxf(30.0, lr.size.y * lr.size.y / content)
		var by2 := lr.position.y + (lr.size.y - bh) * (sugg_scroll / (content - lr.size.y))
		cv.draw_rect(Rect2(lr.end.x - 6, by2, 3, bh), C_FAINT)


## Picker rows: drink name, and underneath it what goes into the drink. Drawn on a child canvas
## clipped to the list, so rows scroll cleanly under the header and above the input.
func _draw_list_layer() -> void:
	var ci := list_layer.get_canvas_item()
	var on := panel_open and modal == "" and game != null
	RenderingServer.canvas_item_set_custom_rect(ci, true, panel_list_rect)
	RenderingServer.canvas_item_set_clip(ci, on)
	if not on:
		return
	cv = list_layer
	var lr := panel_list_rect
	var first := int(sugg_scroll / SUGG_ROW_H)
	var last := mini(suggestions.size(), first + int(lr.size.y / SUGG_ROW_H) + 2)
	for i in range(first, last):
		var row := Rect2(lr.position.x + 8, lr.position.y + i * SUGG_ROW_H - sugg_scroll + 3, lr.size.x - 16, SUGG_ROW_H - 6)
		_draw_sugg_row(row, i)
	cv = self


## Text widths inside a picker row: [name width (room left for "tried"), ingredients width].
func sugg_text_widths() -> Array:
	var w := panel_list_rect.size.x - 16 - 28
	return [w - 76, w]


## Ingredients joined with dots; each ingredient's own spaces are non-breaking so a line never
## splits "Celery / salt".
static func ingredients_text(d: Dictionary) -> String:
	var parts: Array = []
	for ing in d.get("ingredients", []):
		parts.append(String(ing).replace(" ", "\u00a0"))
	return "\u00a0· ".join(parts)     # the dot stays with the ingredient before it


## Text sizes for one picker row: {name, ingredients, height}. Ingredients take up to two lines;
## only when a list can't fit two lines (the narrowest desktop window) does it drop to three
## smaller lines, with a smaller name so the row height never changes.
func sugg_row_layout(d: Dictionary) -> Dictionary:
	var widths := sugg_text_widths()
	var text := ingredients_text(d)
	var nf := fit(d.name, widths[0], 27, 16, 1, bold)
	var inf := fit(text, widths[1], 21, 14, 2, font)
	if not text_fits(text, widths[1], 21, 14, 2, font):
		nf = fit(d.name, widths[0], 21, 15, 1, bold)
		inf = fit(text, widths[1], 15, 13, 3, font)
	var h: float = bold.get_height(nf.size) + 4 + font.get_height(inf.size) * inf.lines.size()
	return {"name": nf, "ingredients": inf, "height": h, "text": text}


func _draw_sugg_row(row: Rect2, i: int) -> void:
	var id: String = suggestions[i]
	var d := DB.get_drink(id)
	var used: bool = game.guesses.has(id)
	if i == sugg_hover and not used:
		_rrect(row, C_CARD.lightened(0.08), GTUI.dp(GTUI.R_CONTROL))
	elif i % 2 == 0:
		_rrect(row, C_CARD, GTUI.dp(GTUI.R_CONTROL))
	var widths := sugg_text_widths()
	var lay := sugg_row_layout(d)
	var nf: Dictionary = lay.name
	var inf: Dictionary = lay.ingredients
	var name_h := bold.get_height(nf.size)
	var lh := font.get_height(inf.size)
	var block: float = name_h + 4 + lh * inf.lines.size()
	var y: float = row.position.y + (row.size.y - block) * 0.5
	var x := row.position.x + 14
	cv.draw_string(bold, Vector2(x, y + bold.get_ascent(nf.size)), nf.lines[0], HORIZONTAL_ALIGNMENT_LEFT, widths[0], nf.size,
		C_FAINT if used else C_INK)
	if used:
		cv.draw_string(font, Vector2(row.end.x - 84, y + bold.get_ascent(nf.size)), "tried", HORIZONTAL_ALIGNMENT_RIGHT, 70, GTUI.fs(GTUI.FS_LABEL), C_FAINT)
	var iy: float = y + name_h + 4 + font.get_ascent(inf.size)
	for l in inf.lines:
		cv.draw_string(font, Vector2(x, iy), l, HORIZONTAL_ALIGNMENT_LEFT, widths[1], inf.size, C_FAINT if used else C_MUTED)
		iy += lh


func _draw_toast(vs: Vector2) -> void:
	var a := clampf(toast_t / GTUI.T_NORMAL, 0.0, 1.0)
	var bottom := head_rect.end.y + GTUI.dp(GTUI.SP_S) + GTUI.target() if modal == "" else modal_rect.position.y - GTUI.dp(GTUI.SP_S)
	GTUI.toast(self, toast, a, maxf(bottom, GTUI.target() + 6.0))


# ------------------------------------------------------------------ glasses

## A glass silhouette in rect r. mystery: generic glass with a "?" instead of the real shape.
func _draw_glass(r: Rect2, kind: String, liquid: Color, mystery: bool) -> void:
	var outline := Color(C_INK, 0.85)
	var vessel := _vessel(kind)
	var pts := PackedVector2Array()
	for p in vessel.body:
		pts.append(r.position + Vector2(p.x * r.size.x, p.y * r.size.y))
	var fill_top: float = vessel.fill
	var cut := PackedVector2Array([r.position + Vector2(-10, fill_top * r.size.y), r.position + Vector2(r.size.x + 10, fill_top * r.size.y),
		r.position + Vector2(r.size.x + 10, r.size.y + 10), r.position + Vector2(-10, r.size.y + 10)])
	var liq := Geometry2D.intersect_polygons(pts, cut)
	cv.draw_colored_polygon(pts, Color(1, 1, 1, 0.06))
	for poly in liq:
		cv.draw_colored_polygon(poly, liquid)
	var closed := pts.duplicate()
	closed.append(pts[0])
	cv.draw_polyline(closed, outline, 3.0, true)
	for seg in vessel.extra:
		var a: Vector2 = r.position + Vector2(seg[0].x * r.size.x, seg[0].y * r.size.y)
		var b: Vector2 = r.position + Vector2(seg[1].x * r.size.x, seg[1].y * r.size.y)
		cv.draw_line(a, b, outline, 3.0, true)
	if mystery:
		var c := r.position + Vector2(r.size.x * 0.5, r.size.y * (fill_top + 0.1))
		var qs := int(r.size.y * 0.26)
		cv.draw_string(bold, Vector2(c.x - r.size.x * 0.5, c.y + qs * 0.35), "?", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, qs, C_INK)


func _vessel(kind: String) -> Dictionary:
	var V := func(x, y): return Vector2(x, y)
	match kind:
		"martini":
			return {"body": [V.call(0.05, 0.12), V.call(0.95, 0.12), V.call(0.5, 0.55)], "fill": 0.2,
				"extra": [[V.call(0.5, 0.55), V.call(0.5, 0.9)], [V.call(0.28, 0.92), V.call(0.72, 0.92)]]}
		"rocks":
			return {"body": [V.call(0.14, 0.34), V.call(0.86, 0.34), V.call(0.8, 0.92), V.call(0.2, 0.92)], "fill": 0.48, "extra": []}
		"highball":
			return {"body": [V.call(0.24, 0.06), V.call(0.76, 0.06), V.call(0.72, 0.94), V.call(0.28, 0.94)], "fill": 0.18, "extra": []}
		"pint":
			return {"body": [V.call(0.2, 0.06), V.call(0.8, 0.06), V.call(0.68, 0.94), V.call(0.32, 0.94)], "fill": 0.16, "extra": []}
		"flute":
			return {"body": [V.call(0.36, 0.04), V.call(0.64, 0.04), V.call(0.6, 0.5), V.call(0.5, 0.6), V.call(0.4, 0.5)], "fill": 0.14,
				"extra": [[V.call(0.5, 0.6), V.call(0.5, 0.9)], [V.call(0.32, 0.92), V.call(0.68, 0.92)]]}
		"wine":
			var body: Array = [V.call(0.18, 0.08), V.call(0.82, 0.08)]
			for k in 13:
				var a := PI * k / 12.0
				body.append(V.call(0.5 + cos(a) * 0.32, 0.2 + sin(a) * 0.32))
			return {"body": body, "fill": 0.26,
				"extra": [[V.call(0.5, 0.52), V.call(0.5, 0.9)], [V.call(0.3, 0.92), V.call(0.7, 0.92)]]}
		"mug":
			return {"body": [V.call(0.12, 0.2), V.call(0.72, 0.2), V.call(0.72, 0.92), V.call(0.12, 0.92)], "fill": 0.3,
				"extra": [[V.call(0.72, 0.36), V.call(0.92, 0.4)], [V.call(0.92, 0.4), V.call(0.92, 0.68)], [V.call(0.92, 0.68), V.call(0.72, 0.74)]]}
		"hurricane":
			return {"body": [V.call(0.3, 0.04), V.call(0.7, 0.04), V.call(0.76, 0.3), V.call(0.62, 0.55), V.call(0.68, 0.76),
				V.call(0.56, 0.84), V.call(0.44, 0.84), V.call(0.32, 0.76), V.call(0.38, 0.55), V.call(0.24, 0.3)], "fill": 0.14,
				"extra": [[V.call(0.5, 0.84), V.call(0.5, 0.92)], [V.call(0.3, 0.94), V.call(0.7, 0.94)]]}
	# coupe
	var bowl: Array = [V.call(0.04, 0.2)]
	for k in range(1, 12):
		var a2 := PI * k / 12.0
		bowl.append(V.call(0.5 - cos(a2) * 0.46, 0.2 + sin(a2) * 0.26))
	bowl.append(V.call(0.96, 0.2))
	return {"body": bowl, "fill": 0.26, "extra": [[V.call(0.5, 0.46), V.call(0.5, 0.9)], [V.call(0.28, 0.92), V.call(0.72, 0.92)]]}


# ------------------------------------------------------------------ modals

## Overlay card + title + close button; the scrolled body is painted by the clip layer.
func _modal_frame(title: String) -> void:
	GTUI.modal(self, modal_rect, title, "close")


func _scroll_body(painter: Callable, _top_offset: float) -> void:
	modal_content_h = float(painter.call(0.0, false))
	_clamp_scrolls()
	modal_painter = painter
	clip_layer.queue_redraw()
	if modal_content_h > modal_body.size.y:
		var vis := modal_body.size.y
		var bh := maxf(30.0, vis * vis / modal_content_h)
		var t := modal_scroll / maxf(1.0, modal_content_h - vis)
		cv.draw_rect(Rect2(modal_rect.end.x - GTUI.dp(GTUI.SP_M), modal_body.position.y + (vis - bh) * t, 3, bh), C_FAINT)


func _draw_clip_layer() -> void:
	var ci := clip_layer.get_canvas_item()
	var on := (modal == "help" or modal == "end") and modal_painter.is_valid()
	RenderingServer.canvas_item_set_custom_rect(ci, true, modal_body)
	RenderingServer.canvas_item_set_clip(ci, on)
	if not on:
		return
	cv = clip_layer
	modal_painter.call(modal_body.position.y - modal_scroll, true)
	cv = self


func _draw_help() -> void:
	_modal_frame("How to play")
	_scroll_body(func(y0, draw): return _help_content(y0, draw), 0.0)


func _help_content(y0: float, draw: bool) -> float:
	var x := modal_body.position.x
	var w := modal_body.size.x
	var y := y0
	var paras := [
		["Guess the mystery drink in 6 tries. Everyone gets the same drink each day.", true],
		["Each guess shows how that drink compares on six things. The cells show your guess's value, coloured by how close it is:", false],
	]
	for p in paras:
		y += _draw_para(Vector2(x, y), w, p[0], GTUI.fs(GTUI.FS_BODY), C_INK, bold if p[1] else font, draw) + 12
	var legend := [[C_GREEN, "", "Same as the mystery drink"], [C_YELLOW, "", "Related (same group, see below)"],
		[C_RED, "", "Not it"], [C_ARROW, "up", "The mystery drink is higher (sweeter or stronger)"],
		[C_ARROW, "down", "The mystery drink is lower"]]
	for l in legend:
		if draw:
			var cr := Rect2(x, y, GTUI.dp(40), GTUI.dp(30))
			_rrect(cr, l[0], 8)
			if l[1] != "":
				_draw_arrow(cr.get_center(), 16, l[1] == "up", Color.WHITE)
		var lh := _draw_para(Vector2(x + GTUI.dp(52), y + GTUI.dp(4)), w - GTUI.dp(52), l[2], GTUI.fs(GTUI.FS_BODY), C_INK, font, draw)
		y += maxf(GTUI.dp(30), lh + GTUI.dp(4)) + GTUI.dp(GTUI.SP_S)
	y += 8
	y += _draw_para(Vector2(x, y), w, "The six columns", GTUI.fs(GTUI.FS_TITLE), C_ACCENT, bold, draw) + 8
	for a in Schema.attrs():
		var t := "%s: %s" % [a.label, a.help]
		y += _draw_para(Vector2(x, y), w, t, GTUI.fs(GTUI.FS_BODY), C_INK, font, draw) + 4
		if a.id == "family":
			var fams: Array = []
			for k in a.values:
				fams.append("%s (%s)" % [a.values[k], a.describe[k]])
			y += _draw_para(Vector2(x + 16, y), w - 16, "; ".join(fams) + ".", GTUI.fs(GTUI.FS_LABEL), C_MUTED, font, draw) + 4
		for g in a.get("groups", []):
			var names: Array = []
			for mbr in g.members:
				names.append(Schema.value_label(a.id, mbr))
			y += _draw_para(Vector2(x + 16, y), w - 16, "Yellow: %s (%s)" % [g.label, ", ".join(names)], GTUI.fs(GTUI.FS_LABEL), C_MUTED, font, draw) + 2
		y += 8
	y += 6
	y += _draw_para(Vector2(x, y), w, "Tips", GTUI.fs(GTUI.FS_TITLE), C_ACCENT, bold, draw) + 8
	for t in ["Don't know a drink? Each one in the list shows what goes into it.",
			"A guess you know is wrong can still be a great test. Pick a drink that checks the things you're unsure of.",
			"The Known row sums up everything your guesses have pinned down.",
			"Stuck? Hints point you at what to test, then reveal facts. A clue appears for free after guesses 4 and 5.",
			"Past days are in the calendar."]:
		y += _draw_para(Vector2(x, y), w, "• " + t, GTUI.fs(GTUI.FS_BODY), C_INK, font, draw) + 6
	return y - y0 + 10


func _draw_end() -> void:
	_modal_frame(_end_title())
	_scroll_body(func(y0, draw): return _end_content(y0, draw), 0.0)


func _end_title() -> String:
	if game.won:
		return WIN_WORDS[clampi(game.guesses.size() - 1, 0, WIN_WORDS.size() - 1)]
	return "Out of guesses"


func _end_content(y0: float, draw: bool) -> float:
	var x := modal_body.position.x
	var w := modal_body.size.x
	var t: Dictionary = game.target
	var y := y0
	var sub := "Drinkle #%d · %s" % [number, game.result_label()]
	if game.hints_used > 0:
		sub += " · %d hint%s" % [game.hints_used, "" if game.hints_used == 1 else "s"]
	y += _draw_para(Vector2(x, y), w, sub, GTUI.fs(GTUI.FS_BODY), C_MUTED, font, draw) + 14
	var gh := 150.0
	if draw:
		_draw_glass(Rect2(x, y, gh * 0.8, gh), String(t.get("glass", "coupe")), Color(String(t.get("color", "#e8577a"))), false)
	var tx := x + gh * 0.8 + 20
	var tw := w - gh * 0.8 - 20
	var ny := y + 6
	ny += _draw_para(Vector2(tx, ny), tw, t.name, GTUI.fs(GTUI.FS_HEADING), C_INK, bold, draw) + 8
	ny += _draw_para(Vector2(tx, ny), tw, " • ".join(t.get("profile", [])), GTUI.fs(GTUI.FS_BODY), C_ACCENT, font, draw) + 10
	ny += _draw_para(Vector2(tx, ny), tw, "Typical ingredients", GTUI.fs(GTUI.FS_LABEL), C_MUTED, bold, draw) + 4
	for ing in t.get("ingredients", []):
		ny += _draw_para(Vector2(tx, ny), tw, "• " + String(ing), GTUI.fs(GTUI.FS_LABEL), C_INK, font, draw) + 1
	y = maxf(y + gh, ny) + 16
	# the answer's six values, all green
	var ids := Schema.ids()
	var cw := (w - 5 * 6) / 6.0
	if draw:
		for j in 6:
			cv.draw_string(bold, Vector2(x + j * (cw + 6), y + 16), COL_LABELS[j], HORIZONTAL_ALIGNMENT_CENTER, cw, 15, C_MUTED)  # gt:art
	y += 22
	for j in 6:
		var c := Rect2(x + j * (cw + 6), y, cw, 56)
		if draw:
			_rrect(c, C_GREEN, 10)
			_draw_text_in(c.grow(-4), Schema.value_label(ids[j], t.get(ids[j])), 19, 11, 2, Color.WHITE, bold)
	y += 56 + 22
	if not game.won:
		var l := Explain.loss(t, game.history(), game.facts)
		y += _draw_para(Vector2(x, y), w, String(l.text), GTUI.fs(GTUI.FS_BODY), C_INK, font, draw) + 6
		if l.left.size() > 1:
			y += _draw_para(Vector2(x, y), w, "Still possible: " + ", ".join(l.left), GTUI.fs(GTUI.FS_LABEL), C_MUTED, font, draw) + 6
		y += 14
	y += _draw_para(Vector2(x, y), w, "Your deduction path", GTUI.fs(GTUI.FS_TITLE), C_ACCENT, bold, draw) + 10
	var p := Explain.path(game.history(), game.facts)
	for i in p.size():
		var line: Dictionary = p[i]
		var fb: PackedInt32Array = game.feedback(i)
		if draw:
			for j in 6:
				_rrect(Rect2(x + j * 16, y + 8, 13, 13), _code_color(fb[j]), 3)
		var nh := _draw_para(Vector2(x + 110, y), w - 110, "%d. %s" % [i + 1, line.name], GTUI.fs(GTUI.FS_BODY), C_INK, bold, draw)
		y += nh + 2
		var note: String = "solved!" if line.solved else " · ".join(line.notes)
		if not line.solved:
			note += " · %d drink%s left" % [line.left, "" if line.left == 1 else "s"]
		y += _draw_para(Vector2(x + 110, y), w - 110, note, GTUI.fs(GTUI.FS_LABEL), C_MUTED, font, draw) + 12
	if not game.hint_texts.is_empty() or not game.facts.is_empty():
		y += 6
		y += _draw_para(Vector2(x, y), w, "Clues and hints", GTUI.fs(GTUI.FS_BODY), C_MUTED, bold, draw) + 6
		for f in game.facts:
			y += _draw_para(Vector2(x, y), w, "• %s (%s)" % [f.get("text", ""), f.get("source", "")], GTUI.fs(GTUI.FS_LABEL), C_MUTED, font, draw) + 3
	y += 10
	y += _draw_para(Vector2(x, y), w, "A new drink arrives tomorrow. Past days are in the calendar.", GTUI.fs(GTUI.FS_LABEL), C_FAINT, font, draw) + 8
	return y - y0


func _draw_archive() -> void:
	_modal_frame("Past drinks")
	GTUI.text(self, modal_body.position, "Page %d of %d" % [archive_page + 1, archive_pages()], GTUI.FS_CAPTION, C_MUTED)


func _draw_day_row(b: Dictionary) -> void:
	var d := String(b.id).substr(4)
	var cur := d == date
	var res := String(archive_results.get(d, ""))
	if res == "" and cur and game and not game.guesses.is_empty() and not game.finished:
		res = "In progress"
	var right: String = res if res != "" else TIER_NAMES[Daily.tier_for(d)]
	var ink := C_GREEN.lightened(0.3) if res.contains("/") and not res.begins_with("X") else (C_PINK if res.begins_with("X") else Color(0, 0, 0, 0))
	GTUI.list_row(self, String(b.id), b.rect, "#%d" % Daily.day_number(d), "Today" if d == today else Daily.short_date(d), right, cur, ink)


func _draw_dev() -> void:
	var r := dev_rect
	_rrect(r, Color(0, 0, 0, 0.85), 10)
	var t: Dictionary = game.target
	var df := Daily.difficulty_of(t.id)
	var lines := [
		"DEV  %s  #%d  (today %s)" % [date, number, today],
		"tier %s  score %d  seed %d" % [TIER_NAMES[tier], df.score, Daily.seed_for(date) % 100000],
		"state %s  guesses %d  hints %d" % ["won" if game.won else ("lost" if game.finished else "playing"), game.guesses.size(), game.hints_used],
		"answer: %s" % (t.name if dev_show_answer else "(tap Answer)"),
		"candidates left: %d" % game.remaining().size(),
	]
	var y := r.position.y + 22
	for l in lines:
		cv.draw_string(font, Vector2(r.position.x + 10, y), l, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, GTUI.fs(GTUI.FS_BODY), Color("9ff0b0"))
		y += 22
	for b in buttons:
		if String(b.id).begins_with("dev_"):
			_rrect(b.rect, Color("2f4a38"), 6)
			_draw_text_in(b.rect, b.label, 16, 11, 1, Color("d8ffe0"))


func _head_h() -> float:
	return maxf(GTUI.target(), GTUI.line_height(GTUI.FS_HEADING) + GTUI.line_height(GTUI.FS_LABEL) - GTUI.dp(GTUI.SP_XS))