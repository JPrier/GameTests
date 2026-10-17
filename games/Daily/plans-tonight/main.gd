extends Control
## Plans Tonight? — UI, input, save/load, sharing, past days and dev mode.
## The puzzle itself lives in res://engine (pure data + functions, no nodes).

const URL := PTShare.URL

const C_BG := Color("141021")
const C_PANEL := Color("1b152b")
const C_CARD := Color("241c38")
const C_CARD_DIM := Color("1c162c")
const C_LINE := Color(1, 1, 1, 0.09)
const C_INK := Color("f4effc")
const C_MUTED := Color("a99fc2")
const C_DIM := Color("6d6386")
const C_ACCENT := Color("ffb84d")
const C_GOOD := Color("4ade80")
const C_BAD := Color("fb7185")
const C_HINT := Color("facc15")
const C_BTN := Color("3a2d58")
const C_BTN_HI := Color("4a3a70")

const TOPIC_ICON := {"price": "1f4b5", "time": "1f557", "travel": "1f6b6", "food": "1f37d", "activity": "1f3f7",
	"noise": "1f509", "setting": "1f3e0"}
const WIN_LINES := [
	"Chris is already ten minutes late.", "Someone has already made a group photo album.",
	"The group chat has finally gone quiet.", "Everyone pretends this was their idea.",
	"Somebody is already asking about next week.", "Peace has been restored to the group chat.",
]
const MAX_W := 520.0
const ARCHIVE_ROWS := 7

enum Modal { NONE, WRONG, HINT, WIN, HELP, ARCHIVE }

# --- day + puzzle
var today := ""
var date := ""
var puzzle_no := 1
var puzzle: Dictionary = {}
var st: Dictionary = PTSave.fresh()
var base_url := URL
var dev_mode := false
var dev_reveal := false
var selected := -1
var new_day_ready := false

# --- ui
var font_bold: FontVariation
var tex_cache: Dictionary = {}
var frame: VBoxContainer
var title_label: Label
var sub_label: Label
var goal_label: Label
var scroll: ScrollContainer
var content: VBoxContainer
var friends_box: VBoxContainer
var plans_box: VBoxContainer
var status_label: Label
var hint_btn: Button
var lock_btn: Button
var friend_cards: Array = []
var plan_cards: Array = []
var modal_layer: Control
var modal_panel: PanelContainer
var modal_box: VBoxContainer
var modal := Modal.NONE
var modal_hint_used := false
var archive_page := 0
var toast_label: Label
var toast_t := 0.0
var dev_panel: PanelContainer
var dev_info: Label
var dev_date_edit: LineEdit
var share_pending := false
var last_share_text := ""
var title_taps: Array = []
var save_t := 0.0
var rollover_t := 0.0


func _ready() -> void:
	font_bold = FontVariation.new()
	font_bold.base_font = ThemeDB.fallback_font
	font_bold.variation_embolden = 0.7
	GTUI.setup(self, {
		"bg": C_BG, "surface": C_PANEL, "surface_high": C_BTN, "text": C_INK, "text_muted": C_MUTED,
		"border": C_LINE, "accent": C_ACCENT, "on_accent": C_BG,
		"success": C_GOOD, "danger": C_BAD, "focus": C_ACCENT, "scrim": Color(0.03, 0.02, 0.06, 0.72),
	})
	theme = _make_theme()
	_add_key_action("lock_in", [KEY_ENTER, KEY_KP_ENTER])
	_add_key_action("hint", [KEY_H])
	_add_key_action("back", [KEY_ESCAPE])
	_add_key_action("dev_toggle", [KEY_QUOTELEFT])
	for i in 8:
		_add_key_action("pick_%d" % (i + 1), [KEY_1 + i])
	_build_ui()
	today = PTDaily.today()
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_mode = OS.is_debug_build() or String(url.get("dev", "")) == "1"
	var want := today
	var d := String(url.get("day", ""))
	# Links always open today's plans; past days are picked in-game. Only dev mode honours ?day=.
	if dev_mode and PTDaily.is_date(d):
		want = d
	elif d != "":
		_clean_url()
	load_day(want)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ================================================================ day loading

func load_day(d: String) -> void:
	date = d
	puzzle_no = PTDaily.day_number(d)
	puzzle = PTGen.generate(d)
	st = _load_state()
	selected = -1
	dev_reveal = false
	_close_modal()
	_build_board()
	refresh()
	scroll.scroll_vertical = 0
	if st.done:
		_show_win(false)


func is_done() -> bool:
	return bool(st.done)


func ruled_out() -> Array:
	var out: Array = []
	for g in st.guesses:
		if int(g) != int(puzzle.target):
			out.append(int(g))
	if int(st.hint_plan) >= 0 and not out.has(int(st.hint_plan)):
		out.append(int(st.hint_plan))
	if not st.hint_conflict.is_empty() and not out.has(int(st.hint_conflict.plan)):
		out.append(int(st.hint_conflict.plan))
	return out


func wrong_guesses() -> Array:
	return st.guesses.filter(func(g): return int(g) != int(puzzle.target))


# ================================================================ actions

## Selects a plan card (doesn't guess yet).
func select_plan(id: int) -> void:
	if is_done() or id < 0 or id >= puzzle.plans.size() or id in wrong_guesses():
		return
	selected = id
	refresh()


func toggle_cross(id: int) -> void:
	if is_done() or id < 0 or id >= puzzle.plans.size() or id in ruled_out():
		return
	if st.crossed.has(id):
		st.crossed.erase(id)
	else:
		st.crossed.append(id)
		if selected == id:
			selected = -1
	_save_state()
	refresh()


## Locks in the selected plan. Returns true when it was the answer.
func lock_in() -> bool:
	if is_done() or selected < 0 or modal != Modal.NONE:
		return false
	return guess_plan(selected)


## Guesses a plan directly (used by lock_in, tests and agents).
func guess_plan(id: int) -> bool:
	if is_done() or id < 0 or id >= puzzle.plans.size() or st.guesses.has(id):
		return false
	st.guesses.append(id)
	st.crossed.erase(id)
	selected = -1
	var right := id == int(puzzle.target)
	if right:
		st.done = true
	_save_state()
	refresh()
	if right:
		_pop_card(id)
		get_tree().create_timer(0.45).timeout.connect(func(): if is_done() and date == puzzle.get("date", ""): _show_win(true))
	else:
		_shake_card(id)
		_show_wrong(id)
	return right


func hint_available() -> bool:
	if is_done() or int(st.hints) >= PTHints.MAX:
		return false
	match int(st.hints):
		1: return PTHints.eliminate(puzzle, ruled_out()) >= 0
		2: return not PTHints.conflict(puzzle, ruled_out()).is_empty()
	return true


## Applies the next hint immediately (the button asks first; agents/tests call this).
func use_hint() -> bool:
	if not hint_available():
		return false
	match int(st.hints):
		1: st.hint_plan = PTHints.eliminate(puzzle, ruled_out())
		2: st.hint_conflict = PTHints.conflict(puzzle, ruled_out())
	st.hints = int(st.hints) + 1
	if selected >= 0 and selected in ruled_out():
		selected = -1
	_save_state()
	refresh()
	return true


func hint_text(n: int) -> String:
	match n:
		1:
			var f: Dictionary = puzzle.friends[PTHints.restrictive_friend(puzzle)]
			return "Start with %s. Their rules rule out the most plans." % f.name
		2:
			if int(st.hint_plan) >= 0:
				return "%s can't work." % puzzle.plans[int(st.hint_plan)].name
		3:
			var c: Dictionary = st.hint_conflict
			if not c.is_empty():
				var f: Dictionary = puzzle.friends[int(c.friend)]
				return "%s breaks %s's rule: %s." % [puzzle.plans[int(c.plan)].name, f.name,
					PTRules.text(f.rules[int(c.rule)])]
	return ""


func hint_preview(n: int) -> String:
	match n:
		1: return "Find out which friend to start with."
		2: return "Rule out one plan that can't work."
		3: return "See exactly which rule one plan breaks."
	return ""


# ================================================================ persistence

func _save_path(d := date) -> String:
	return "user://%splans_%s.json" % ["dev_" if dev_mode else "", d]


func _load_state() -> Dictionary:
	if not FileAccess.file_exists(_save_path()):
		return PTSave.fresh()
	return PTSave.decode(puzzle, JSON.parse_string(FileAccess.get_file_as_string(_save_path())))


func _save_state() -> void:
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(PTSave.encode(puzzle, st)))
		f.close()
	if st.done:
		_mark_played()
	_flush_storage()


func wipe_save() -> void:
	if FileAccess.file_exists(_save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))
	if FileAccess.file_exists(_results_path()):
		var res := _read_results_file()
		res.erase(date)
		_write_results_file(res)
	_flush_storage()


## Godot's web build syncs user:// to IndexedDB when a file is closed; touch one to be sure.
func _flush_storage() -> void:
	var f := FileAccess.open("user://.sync", FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


func _results_path() -> String:
	return "user://%splans_results.json" % ("dev_" if dev_mode else "")


func _read_results_file() -> Dictionary:
	if not FileAccess.file_exists(_results_path()):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_results_path()))
	return d if d is Dictionary else {}


func _write_results_file(res: Dictionary) -> void:
	var f := FileAccess.open(_results_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(res))
		f.close()


## Records the result for the past-days list and the GameTests home page (never from dev mode).
func _mark_played() -> void:
	var res := _read_results_file()
	var h := int(st.hints)
	res[date] = PTShare.label(puzzle, st.guesses) + ("" if h == 0 else " · %d hint%s" % [h, "" if h == 1 else "s"])
	_write_results_file(res)
	if dev_mode or not OS.has_feature("web"):
		return
	var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
		JSON.stringify("gametests:%s:%s" % [PTDaily.GAME, date]),
		JSON.stringify(JSON.stringify({"result": PTShare.label(puzzle, st.guesses)}))]
	JavaScriptBridge.eval(js, true)


func load_results() -> Dictionary:
	var out := _read_results_file()
	if OS.has_feature("web") and not dev_mode:
		var r = JavaScriptBridge.eval("""(function(){var o={},p='gametests:plans-tonight:';try{for(var i=0;i<localStorage.length;i++){
			var k=localStorage.key(i);if(k&&k.indexOf(p)===0){try{o[k.substr(p.length)]=JSON.parse(localStorage.getItem(k)).result||'';}catch(e){}}}}catch(e){}
			return JSON.stringify(o);})()""", true)
		if typeof(r) == TYPE_STRING:
			var ls = JSON.parse_string(r)
			if ls is Dictionary:
				for k in ls:
					if not out.has(k):
						out[k] = ls[k]
	return out


# ================================================================ sharing

func share_link() -> String:
	return base_url


func share_text() -> String:
	return PTShare.text(puzzle, puzzle_no, st.guesses, int(st.hints), int(st.seconds), share_link())


func share() -> void:
	last_share_text = share_text()
	if OS.has_feature("web"):
		var js := """(function(t){
			window.__ptShare='pending';
			var done=function(r){if(window.__ptShare==='pending'){window.__ptShare=r;}};
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
				if(navigator.clipboard&&navigator.clipboard.writeText){
					setTimeout(function(){if(window.__ptShare==='pending'){if(legacy()){done('copied');}else{ask();}}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},function(){if(legacy()){done('copied');}else{ask();}});
				}else if(legacy()){done('copied');}else{ask();}
			};
			var touch=('ontouchstart' in window)||navigator.maxTouchPoints>0;
			if(navigator.share&&touch&&!window.__ptCopyNext){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}
					else{window.__ptCopyNext=true;done('share_failed');}
				});
			}else{window.__ptCopyNext=false;copy();}
		})(%s)""" % JSON.stringify(last_share_text)
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(last_share_text)
		_toast("Copied!")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__ptShare||''", true)
	if typeof(r) != TYPE_STRING or r == "pending" or r == "":
		return
	share_pending = false
	match r:
		"copied": _toast("Copied! Paste it anywhere")
		"shared": _toast("Shared!")
		"prompted", "cancelled": pass
		"share_failed": _toast("Couldn't share, tap again to copy")
		_: _toast("Couldn't share, try again")


func _read_url() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var r = JavaScriptBridge.eval("""(function(){var p=new URLSearchParams(location.search);
		return JSON.stringify({day:p.get('day')||p.get('d')||'',dev:p.get('dev')||'',base:location.origin+location.pathname});})()""", true)
	if typeof(r) != TYPE_STRING:
		return {}
	var d = JSON.parse_string(r)
	return d if d is Dictionary else {}


func _clean_url() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{history.replaceState(null,'',location.pathname)}catch(e){}", true)


func next_puzzle_text() -> String:
	var s := 86400 - int(Time.get_unix_time_from_system()) % 86400
	return "New plans in %dh %02dm" % [s / 3600, (s % 3600) / 60]


# ================================================================ frame loop + input

func _process(delta: float) -> void:
	_handle_actions()
	if not is_done() and modal != Modal.HELP and modal != Modal.ARCHIVE:
		st.seconds = float(st.seconds) + minf(delta, 1.0)  # big gaps = hidden tab; don't count them
		save_t += delta
		if save_t > 5.0:
			save_t = 0.0
			_save_state()
	_update_status()
	if toast_t > 0.0:
		toast_t -= delta
		toast_label.modulate.a = clampf(toast_t * 3.0, 0.0, 1.0)
		toast_label.visible = toast_t > 0.0
	if share_pending:
		_poll_share()
	rollover_t += delta
	if rollover_t > 20.0:
		rollover_t = 0.0
		check_rollover()


## Notices when the UTC day changes while the game is open.
func check_rollover(now := "") -> void:
	var t := now if now != "" else PTDaily.today()
	if t == today:
		return
	var was_today := date == today
	today = t
	if not was_today or dev_mode:
		return
	if st.guesses.is_empty() and modal == Modal.NONE:
		load_day(today)
		_toast("New plans are ready")
	else:
		new_day_ready = true
		_toast("New plans are ready")
		if modal == Modal.WIN:
			_show_win(false)


## Actions are polled (not event-driven) so real keys, tests and agents' simulated actions
## all behave the same.
func _handle_actions() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is BaseButton:
		return   # typing / keyboard focus on a control: let it take the keys
	if Input.is_action_just_pressed("dev_toggle") and dev_mode:
		_toggle_dev()
		return
	if modal != Modal.NONE:
		if Input.is_action_just_pressed("back") or (modal == Modal.WRONG and Input.is_action_just_pressed("lock_in")):
			_close_modal()
		return
	if Input.is_action_just_pressed("lock_in"):
		if is_done():
			_show_win(false)
		else:
			lock_in()
	elif Input.is_action_just_pressed("hint"):
		_ask_hint()
	else:
		for i in 8:
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				select_plan(i)


# ================================================================ UI construction

func _make_theme() -> Theme:
	# Buttons, panels, inputs, focus and type sizes come from the shared GameTests theme.
	return GTUI.make_theme(GTUI.S)


func _style(bg: Color, radius := 14, border := Color(0, 0, 0, 0), bw := 0, pad := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	# product surfaces use the shared radii; round avatars and tiny marks keep their own
	var rad := float(radius)
	if radius >= 9 and radius <= 12:
		rad = GTUI.R_CONTROL
	elif radius == 14:
		rad = GTUI.R_PANEL
	elif radius == 18:
		rad = GTUI.R_OVERLAY
	sb.set_corner_radius_all(int(rad * GTUI.S))
	sb.anti_aliasing = true
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


func icon(code: String) -> Texture2D:
	if not tex_cache.has(code):
		var path := "res://icons/%s.svg" % code
		tex_cache[code] = load(path) if ResourceLoader.exists(path) else null
	return tex_cache[code]


func _icon_rect(code: String, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(code)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(text: String, size := 15, color := C_INK, bold := false, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _rich(size := 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.fit_content = true
	r.bbcode_enabled = false
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_override("bold_font", font_bold)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	frame = VBoxContainer.new()
	frame.add_theme_constant_override("separation", 0)
	add_child(frame)

	# --- header
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", _style(C_BG, 0, Color(0, 0, 0, 0), 0, 0))
	var hm := MarginContainer.new()
	for side in ["left", "right"]:
		hm.add_theme_constant_override("margin_" + side, 16)
	hm.add_theme_constant_override("margin_top", 12)
	hm.add_theme_constant_override("margin_bottom", 8)
	head.add_child(hm)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	hm.add_child(hv)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	hv.add_child(hrow)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_STOP
	tv.gui_input.connect(_on_title_input)
	hrow.add_child(tv)
	title_label = _label("Plans Tonight?", GTUI.fs(GTUI.FS_HEADING), C_ACCENT, true)
	tv.add_child(title_label)
	sub_label = _label("", GTUI.fs(GTUI.FS_LABEL), C_MUTED)
	tv.add_child(sub_label)
	var cal := GTUI.make_icon_button("calendar", "Past days")
	cal.pressed.connect(func(): _show_archive())
	hrow.add_child(cal)
	var hb := GTUI.make_icon_button("help", "How to play")
	hb.pressed.connect(func(): _show_help())
	hrow.add_child(hb)
	goal_label = _label("Pick the one plan that works for everyone.", GTUI.fs(GTUI.FS_BODY), C_INK)
	hv.add_child(goal_label)
	frame.add_child(head)

	# --- scrolling board
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 8
	frame.add_child(scroll)
	var cm := MarginContainer.new()
	cm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		cm.add_theme_constant_override("margin_" + side, 12)
	cm.add_theme_constant_override("margin_top", 4)
	cm.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(cm)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cm.add_child(content)
	content.add_child(_section("THE GROUP"))
	friends_box = VBoxContainer.new()
	friends_box.add_theme_constant_override("separation", 8)
	content.add_child(friends_box)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	content.add_child(sp)
	content.add_child(_section("TONIGHT'S OPTIONS"))
	var help := _label("Tap a plan to pick it. Tap × to cross it off for yourself.", GTUI.fs(GTUI.FS_LABEL), C_MUTED)
	content.add_child(help)
	plans_box = VBoxContainer.new()
	plans_box.add_theme_constant_override("separation", 8)
	content.add_child(plans_box)

	# --- bottom bar
	var bar := PanelContainer.new()
	var bsb := _style(C_PANEL, 0, C_LINE, 0, 0)
	bsb.border_width_top = 1
	bar.add_theme_stylebox_override("panel", bsb)
	var bm := MarginContainer.new()
	for side in ["left", "right"]:
		bm.add_theme_constant_override("margin_" + side, 12)
	bm.add_theme_constant_override("margin_top", 8)
	bm.add_theme_constant_override("margin_bottom", 12)
	bar.add_child(bm)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)
	bm.add_child(bv)
	status_label = _label("", GTUI.fs(GTUI.FS_LABEL), C_MUTED)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(status_label)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	bv.add_child(brow)
	hint_btn = Button.new()
	hint_btn.text = "Hint"
	hint_btn.icon = icon("1f4a1")
	hint_btn.expand_icon = false
	hint_btn.add_theme_constant_override("icon_max_width", 20)
	hint_btn.custom_minimum_size = Vector2(108, GTUI.target())
	hint_btn.focus_mode = Control.FOCUS_ALL
	hint_btn.pressed.connect(_ask_hint)
	brow.add_child(hint_btn)
	lock_btn = Button.new()
	lock_btn.text = "Lock it in"
	lock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock_btn.custom_minimum_size = Vector2(0, GTUI.target())
	lock_btn.theme_type_variation = "GTPrimary"
	lock_btn.focus_mode = Control.FOCUS_ALL
	lock_btn.pressed.connect(_on_lock_pressed)
	brow.add_child(lock_btn)
	frame.add_child(bar)

	# --- toast
	toast_label = _label("", GTUI.fs(GTUI.FS_LABEL + 1), C_BG, true, true)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tsb := GTUI._sb(GTUI.S, Color(C_INK, 0.96), GTUI.R_CONTROL, Color(0, 0, 0, 0), GTUI.SP_L, GTUI.SP_M)
	toast_label.add_theme_stylebox_override("normal", tsb)
	toast_label.visible = false
	toast_label.z_index = 20
	add_child(toast_label)

	# --- modal layer
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.visible = false
	modal_layer.z_index = 10
	add_child(modal_layer)
	var dim := ColorRect.new()
	dim.color = GTUI.c("scrim")
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(dim)
	modal_panel = PanelContainer.new()
	modal_panel.theme_type_variation = "GTOverlay"
	GTUI.mark_overlay(modal_layer)
	modal_layer.add_child(modal_panel)
	modal_box = VBoxContainer.new()
	modal_box.add_theme_constant_override("separation", int(GTUI.dp(GTUI.SP_M)))
	modal_panel.add_child(modal_box)

	_build_dev_panel()


func _section(text: String) -> Label:
	var l := _label(text, GTUI.fs(GTUI.FS_CAPTION), C_MUTED, true)
	return l


func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x, MAX_W)
	# Anchored (not sized by hand) so the board always re-fits the screen, even after wrapped
	# text settles to its real height.
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -w * 0.5
	frame.offset_right = w * 0.5
	frame.offset_top = 0
	frame.offset_bottom = 0
	toast_label.size = Vector2(minf(w - 40, 340), 0)
	toast_label.reset_size()
	toast_label.size.x = minf(w - 40, 340)
	# toasts sit just above the bottom action bar
	toast_label.position = Vector2((vs.x - toast_label.size.x) * 0.5, vs.y - 128 - toast_label.size.y - GTUI.dp(GTUI.SP_M))
	_layout_modal()
	if dev_panel:
		dev_panel.position = Vector2(8, 8)


func _layout_modal() -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 24, 420)
	modal_panel.custom_minimum_size.x = w
	modal_panel.size = Vector2(w, 0)  # shrinks to the content's real height
	modal_panel.position = Vector2((vs.x - w) * 0.5, maxf(12, (vs.y - modal_panel.size.y) * 0.45))


# ---------------------------------------------------------------- board

func _build_board() -> void:
	for c in friends_box.get_children():
		c.queue_free()
	for c in plans_box.get_children():
		c.queue_free()
	friend_cards.clear()
	plan_cards.clear()
	for fi in puzzle.friends.size():
		friend_cards.append(_friend_card(fi))
	for plan in puzzle.plans:
		plan_cards.append(_plan_card(plan))
	var th: Dictionary = PTCatalog.THEMES.get(puzzle.get("theme", "night"), PTCatalog.THEMES.night)
	goal_label.text = th.line


func _friend_card(fi: int) -> Dictionary:
	var f: Dictionary = puzzle.friends[fi]
	var panel := PanelContainer.new()
	var sb := _style(C_CARD, 14, Color(0, 0, 0, 0), 2, 12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	friends_box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var av := PanelContainer.new()
	av.add_theme_stylebox_override("panel", _style(Color(f.color).darkened(0.55), 24, Color(f.color), 2, 4))
	av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(_icon_rect(f.avatar, 34))
	row.add_child(av)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var nrow := HBoxContainer.new()
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nrow)
	var name := _label(f.name, GTUI.fs(GTUI.FS_BODY), C_INK, true)
	nrow.add_child(name)
	if f.get("birthday", false):
		nrow.add_child(_icon_rect("1f382", 20))
	var tag := _label("", GTUI.fs(GTUI.FS_CAPTION), C_HINT, true, false)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.size_flags_horizontal = Control.SIZE_SHRINK_END
	tag.visible = false
	nrow.add_child(tag)
	col.add_child(_label(f.flavor, GTUI.fs(GTUI.FS_LABEL), C_MUTED))
	var rules := VBoxContainer.new()
	rules.add_theme_constant_override("separation", 2)
	rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rules)
	var rule_rows: Array = []
	for r in f.rules:
		var rt := _rich(GTUI.fs(GTUI.FS_BODY))
		rules.add_child(rt)
		rule_rows.append(rt)
	return {"panel": panel, "style": sb, "tag": tag, "rules": rule_rows}


func _plan_card(plan: Dictionary) -> Dictionary:
	var id := int(plan.id)
	var panel := PanelContainer.new()
	var sb := _style(C_CARD, 14, Color(0, 0, 0, 0), 2, 12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.gui_input.connect(_on_plan_input.bind(id))
	plans_box.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var num := _label(str(id + 1), GTUI.fs(GTUI.FS_CAPTION), C_DIM, true, false)
	num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	num.custom_minimum_size.x = 10
	top.add_child(num)
	top.add_child(_icon_rect(plan.icon, 34))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nv)
	var name := _label(plan.name, GTUI.fs(GTUI.FS_BODY), C_INK, true)
	nv.add_child(name)
	if String(plan.activity).to_lower() != String(plan.name).to_lower():
		nv.add_child(_label(plan.activity, GTUI.fs(GTUI.FS_LABEL), C_MUTED))
	var price := _label("$%d" % int(plan.price), 19, C_ACCENT, true, false)
	price.size_flags_horizontal = Control.SIZE_SHRINK_END
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(price)
	var x := PanelContainer.new()
	x.custom_minimum_size = Vector2(38, 38)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var xsb := _style(C_CARD_DIM, 10, C_LINE, 1, 0)
	x.add_theme_stylebox_override("panel", xsb)
	var xl := _label("×", 24, C_MUTED, true, false)
	xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	x.add_child(xl)
	top.add_child(x)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(chips)
	chips.add_child(_chip("1f557", PTRules.time_range(plan)))
	chips.add_child(_chip("1f6b6", "%d min away" % int(plan.travel)))
	chips.add_child(_chip("1f3e0" if plan.setting == "indoor" else "1f333", "Indoors" if plan.setting == "indoor" else "Outdoors"))
	if plan.food != "":
		chips.add_child(_chip(PTCatalog.FOOD_ICON.get(plan.food, "1f37d"), plan.food))
	else:
		chips.add_child(_chip("1f6ab", "No food"))
	var ncode := {"quiet": "1f508", "lively": "1f509", "loud": "1f50a"}
	chips.add_child(_chip(ncode.get(plan.noise, "1f509"), PTRules.noise_label(plan.noise)))
	var status := _rich(GTUI.fs(GTUI.FS_LABEL))
	status.visible = false
	col.add_child(status)
	return {"panel": panel, "style": sb, "name": name, "x": x, "xsb": xsb, "xl": xl, "status": status, "col": col}


func _chip(code: String, text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _style(Color(1, 1, 1, 0.06), 9, Color(0, 0, 0, 0), 0, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 9
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(_icon_rect(code, 16))
	var l := _label(text, GTUI.fs(GTUI.FS_LABEL), C_INK, false, false)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	h.add_child(l)
	return p


## Tap = press + release without dragging (so scrolling the board never picks a plan).
var _press_pos := Vector2.ZERO
var _press_id := -1


func _on_plan_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.global_position
			_press_id = id
		elif _press_id == id and event.global_position.distance_to(_press_pos) < 14.0:
			_press_id = -1
			var x: Control = plan_cards[id].x
			if x.get_global_rect().grow(6).has_point(event.global_position):
				toggle_cross(id)
			else:
				select_plan(id)


func _on_lock_pressed() -> void:
	if is_done():
		_show_win(false)
	else:
		lock_in()


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var now := Time.get_ticks_msec()
		title_taps.append(now)
		title_taps = title_taps.filter(func(t): return now - t < 1500)
		if title_taps.size() >= 5:
			title_taps.clear()
			if not dev_mode:
				dev_mode = true
				load_day(date)
			_toggle_dev()


# ---------------------------------------------------------------- refresh

func refresh() -> void:
	if puzzle.is_empty():
		return
	var label: String = puzzle.difficulty.label
	var th: Dictionary = PTCatalog.THEMES.get(puzzle.get("theme", "night"), PTCatalog.THEMES.night)
	var sub := "#%d · %s · %s" % [puzzle_no, PTDaily.pretty(date), label]
	if puzzle.get("theme", "night") != "night":
		sub += " · " + th.title
	if date < today:
		sub += " · past day"
	elif date > today:
		sub += " · future (dev)"
	sub_label.text = sub
	var out := ruled_out()
	var wrong := wrong_guesses()
	var hint_friend := PTHints.restrictive_friend(puzzle) if int(st.hints) >= 1 else -1
	for fi in friend_cards.size():
		var fc: Dictionary = friend_cards[fi]
		var f: Dictionary = puzzle.friends[fi]
		var hi := fi == hint_friend and not is_done()
		fc.style.border_color = Color(C_HINT, 0.85) if hi else Color(0, 0, 0, 0)
		fc.tag.visible = hi
		fc.tag.text = "Most restrictive" if hi else ""
		for ri in f.rules.size():
			var rt: RichTextLabel = fc.rules[ri]
			var r: Dictionary = f.rules[ri]
			rt.clear()
			rt.add_image(icon(_rule_icon(r)), 16, 16)
			rt.add_text("  " + PTRules.text(r))
	for plan in puzzle.plans:
		var id := int(plan.id)
		var pc: Dictionary = plan_cards[id]
		var sb: StyleBoxFlat = pc.style
		var status: RichTextLabel = pc.status
		status.clear()
		var lines := 0
		var won := is_done() and id == int(puzzle.target)
		var is_wrong := id in wrong
		var hinted := not is_wrong and id in out
		var crossed: bool = st.crossed.has(id)
		var dim := is_wrong or hinted or crossed or (is_done() and not won)
		sb.bg_color = C_CARD_DIM if dim else C_CARD
		pc.col.modulate = Color(1, 1, 1, 0.5 if dim else 1.0)
		if won:
			sb.border_color = C_GOOD
		elif id == selected:
			sb.border_color = C_ACCENT
		elif is_wrong:
			sb.border_color = Color(C_BAD, 0.55)
		elif dev_reveal and id == int(puzzle.target):
			sb.border_color = Color(C_GOOD, 0.5)
		else:
			sb.border_color = Color(0, 0, 0, 0)
		# Faded rather than hidden so the card never reflows.
		pc.x.modulate.a = 1.0 if (not is_done() and not is_wrong and not hinted) else 0.0
		pc.xsb.bg_color = Color(C_BAD, 0.25) if crossed else C_CARD_DIM
		pc.xl.add_theme_color_override("font_color", C_BAD if crossed else C_MUTED)
		if won:
			status.push_color(C_GOOD)
			status.push_font(font_bold)
			status.add_text("Everyone's in!")
			status.pop()
			status.pop()
			lines += 1
		if is_wrong:
			status.push_color(C_BAD)
			status.push_font(font_bold)
			status.add_text("Doesn't work")
			status.pop()
			status.pop()
			lines += 1
			for fi in puzzle.friends.size():
				var f: Dictionary = puzzle.friends[fi]
				for ri in PTRules.broken(plan, f):
					status.newline()
					status.push_color(C_INK)
					status.push_font(font_bold)
					status.add_text(f.name + ": ")
					status.pop()
					status.add_text(PTRules.reason(plan, f.rules[ri]))
					status.pop()
		elif hinted:
			status.add_image(icon("1f4a1"), 15, 15)
			status.push_color(C_HINT)
			if not st.hint_conflict.is_empty() and int(st.hint_conflict.plan) == id:
				var c: Dictionary = st.hint_conflict
				var f: Dictionary = puzzle.friends[int(c.friend)]
				status.add_text("  Breaks %s's rule: %s" % [f.name, PTRules.reason(plan, f.rules[int(c.rule)])])
			else:
				status.add_text("  Hint: this plan can't work")
			status.pop()
			lines += 1
		elif crossed:
			status.push_color(C_MUTED)
			status.add_text("You crossed this off")
			status.pop()
			lines += 1
		if dev_reveal and id == int(puzzle.target) and not won:
			if lines > 0:
				status.newline()
			status.push_color(C_GOOD)
			status.add_text("[dev] answer")
			status.pop()
			lines += 1
		status.visible = lines > 0
	_update_status()
	var can_hint := hint_available()
	hint_btn.disabled = not can_hint
	hint_btn.text = "Hint %d/%d" % [mini(int(st.hints) + 1, PTHints.MAX), PTHints.MAX] if can_hint else "Hint"
	if is_done():
		lock_btn.text = "See result"
		lock_btn.disabled = false
	else:
		lock_btn.text = "Lock it in"
		lock_btn.disabled = selected < 0


func _rule_icon(r: Dictionary) -> String:
	match String(r.type):
		"setting": return "1f333" if String(r.v) == "outdoor" else "1f3e0"
		"not_loud": return "1f50a"
		"not_quiet": return "1f508"
		"max_duration", "min_duration": return "23f3"
		"no_food_type": return PTCatalog.FOOD_ICON.get(String(r.v), "1f37d")
		"no_activity":
			for p in puzzle.plans:
				if p.activity == r.v and p.activity != "Dinner":
					return p.icon
			return "1f3f7"
	return TOPIC_ICON.get(PTRules.TOPIC.get(r.type, ""), "1f3f7")


func _update_status() -> void:
	if not status_label or puzzle.is_empty():
		return
	var g: int = st.guesses.size()
	var s := "Guesses %d · Time %s" % [g, PTShare.clock(int(st.seconds))]
	if int(st.hints) > 0:
		s += " · Hints %d" % int(st.hints)
	if is_done():
		s = "Solved in %d %s · %s" % [g, "guess" if g == 1 else "guesses", PTShare.clock(int(st.seconds))]
	elif selected >= 0:
		s = "Picked: %s" % puzzle.plans[selected].name
	status_label.text = s


# ---------------------------------------------------------------- animation

func _shake_card(id: int) -> void:
	var p: Control = plan_cards[id].panel
	var tw := create_tween()
	var x0 := p.position.x
	for dx in [10.0, -8.0, 6.0, -4.0, 0.0]:
		tw.tween_property(p, "position:x", x0 + dx, 0.05)


func _pop_card(id: int) -> void:
	var p: Control = plan_cards[id].panel
	p.pivot_offset = p.size * 0.5
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2(1.04, 1.04), 0.12)
	tw.tween_property(p, "scale", Vector2.ONE, 0.18)


func _toast(msg: String) -> void:
	toast_label.text = msg
	toast_t = 2.2
	toast_label.visible = true
	_layout()


# ================================================================ modals

func _open_modal(kind: Modal) -> void:
	for c in modal_box.get_children():
		modal_box.remove_child(c)
		c.queue_free()
	modal = kind
	modal_layer.visible = true
	_refit_modal()


## Wrapped text only knows its height once it has been laid out at its real width.
func _refit_modal() -> void:
	for i in 3:
		await get_tree().process_frame
		if modal == Modal.NONE:
			return
		_layout_modal()


func _close_modal() -> void:
	modal = Modal.NONE
	if modal_layer:
		modal_layer.visible = false
	refresh_buttons_only()


func refresh_buttons_only() -> void:
	if hint_btn and not puzzle.is_empty():
		hint_btn.disabled = not hint_available()


func close_modal() -> void:
	_close_modal()


func _modal_title(text: String, _code := "", color := C_INK) -> void:
	# standard overlay header: title left, close (x) right
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(GTUI.dp(GTUI.SP_S)))
	var t := _label(text, GTUI.fs(GTUI.FS_TITLE), color, true)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	var x := GTUI.make_icon_button("close", "Close")
	x.pressed.connect(_close_modal)
	h.add_child(x)
	modal_box.add_child(h)


func _modal_buttons(specs: Array) -> void:
	## specs: [[text, callable, primary?], ...] — always a full row, so buttons never move.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GTUI.dp(GTUI.SP_S)))
	for s in specs:
		var b := Button.new()
		b.text = s[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, GTUI.target())
		b.focus_mode = Control.FOCUS_ALL
		if s.size() > 2 and s[2]:
			b.theme_type_variation = "GTPrimary"
		b.pressed.connect(s[1])
		row.add_child(b)
	modal_box.add_child(row)


func _show_wrong(id: int) -> void:
	var plan: Dictionary = puzzle.plans[id]
	_open_modal(Modal.WRONG)
	_modal_title("%s doesn't work" % plan.name, "274c", C_BAD)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	modal_box.add_child(list)
	for f in puzzle.friends:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_icon_rect(f.avatar, 26))
		var ok := PTRules.friend_ok(plan, f)
		row.add_child(_icon_rect("2705" if ok else "274c", 18))
		var t := _rich(GTUI.fs(GTUI.FS_BODY))
		t.push_font(font_bold)
		t.add_text(f.name)
		t.pop()
		if ok:
			t.push_color(C_MUTED)
			t.add_text("  is fine with it")
			t.pop()
		else:
			for ri in PTRules.broken(plan, f):
				t.newline()
				t.push_color(C_BAD)
				t.add_text(PTRules.reason(plan, f.rules[ri]))
				t.pop()
		row.add_child(t)
		list.add_child(row)
	_modal_buttons([["Got it", _close_modal, true]])


func _ask_hint() -> void:
	if not hint_available() or modal != Modal.NONE:
		return
	_open_modal(Modal.HINT)
	modal_hint_used = false
	var n := int(st.hints) + 1
	_modal_title("Use hint %d of %d?" % [n, PTHints.MAX], "1f4a1", C_HINT)
	modal_box.add_child(_label(hint_preview(n), GTUI.fs(GTUI.FS_BODY)))
	modal_box.add_child(_label("Your shared result will show how many hints you used.", GTUI.fs(GTUI.FS_LABEL), C_MUTED))
	_modal_buttons([["Not yet", _close_modal], ["Use hint", _confirm_hint, true]])


func _confirm_hint() -> void:
	if not use_hint():
		_close_modal()
		return
	var n := int(st.hints)
	_open_modal(Modal.HINT)
	_modal_title("Hint %d" % n, "1f4a1", C_HINT)
	modal_box.add_child(_label(hint_text(n), GTUI.fs(GTUI.FS_BODY)))
	_modal_buttons([["Got it", _close_modal, true]])
	if n == 1:
		scroll.scroll_vertical = 0


func _show_win(_fresh: bool) -> void:
	if not is_done():
		return
	_open_modal(Modal.WIN)
	var plan: Dictionary = puzzle.plans[int(puzzle.target)]
	_modal_title("Plans locked!", "1f389", C_GOOD)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.add_child(_icon_rect(plan.icon, 40))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 0)
	hv.add_child(_label("Everyone's in for %s." % plan.name, GTUI.fs(GTUI.FS_BODY), C_INK, true))
	var rng := RandomNumberGenerator.new()
	rng.seed = PTDaily.seed_for(date)
	hv.add_child(_label(WIN_LINES[rng.randi_range(0, WIN_LINES.size() - 1)], GTUI.fs(GTUI.FS_LABEL), C_MUTED))
	h.add_child(hv)
	modal_box.add_child(h)
	# Stats + the same squares the share text uses, drawn as boxes (no emoji font needed).
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	stats.add_child(_stat("%d/%d" % [st.guesses.size(), puzzle.plans.size()], "guesses"))
	stats.add_child(_stat(PTShare.clock(int(st.seconds)), "time"))
	stats.add_child(_stat(str(int(st.hints)), "hints"))
	modal_box.add_child(stats)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	for g in st.guesses:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		for f in puzzle.friends:
			var sq := Panel.new()
			sq.custom_minimum_size = Vector2(22, 22)
			sq.add_theme_stylebox_override("panel", _style(C_GOOD if PTRules.friend_ok(puzzle.plans[int(g)], f) else C_BAD, 5, Color(0, 0, 0, 0), 0, 0))
			row.add_child(sq)
		grid.add_child(row)
	modal_box.add_child(grid)
	var nxt := _label("", GTUI.fs(GTUI.FS_LABEL), C_MUTED)
	nxt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if date != today:
		nxt.text = "Past day #%d" % puzzle_no
	elif new_day_ready:
		nxt.text = "New plans are ready."
	else:
		nxt.text = next_puzzle_text()
	modal_box.add_child(nxt)
	_modal_buttons([["Share result", share, true]])
	if new_day_ready or date != today:
		_modal_buttons([["Play today", _play_today], ["Close", _close_modal]])
	else:
		_modal_buttons([["Past days", _show_archive], ["Close", _close_modal]])


func _play_today() -> void:
	new_day_ready = false
	load_day(today)


func _stat(big: String, small: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var a := _label(big, GTUI.fs(GTUI.FS_TITLE), C_ACCENT, true)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var b := _label(small.to_upper(), GTUI.fs(GTUI.FS_CAPTION), C_MUTED, true)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	return p


func _show_help() -> void:
	_open_modal(Modal.HELP)
	_modal_title("How to play", "2753")
	var lines := [
		["1f37b", "Your friends can't agree on plans. Each one has a few rules."],
		["1f3f7", "Exactly one plan works for everybody. Find it."],
		["1f4b5", "Icons match: a rule's icon shows which part of each plan to check (price, time, distance and so on)."],
		["274c", "Wrong pick? You'll see who vetoed it and why. Try again."],
		["1f4a1", "Stuck? Hints help, but show up in your result."],
	]
	for l in lines:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(_icon_rect(l[0], 22))
		var t := _label(String(l[1]), GTUI.fs(GTUI.FS_BODY))
		h.add_child(t)
		modal_box.add_child(h)
	modal_box.add_child(_label("Every clue matters, and nothing needs outside knowledge. New plans every day at midnight UTC.", GTUI.fs(GTUI.FS_LABEL), C_MUTED))
	_modal_buttons([["Let's go", _close_modal, true]])


func archive_count() -> int:
	return maxi(1, PTDaily.day_number(today))


func archive_pages() -> int:
	return ceili(float(archive_count()) / ARCHIVE_ROWS)


## Days on one page of the picker, newest first (page 0 starts with today).
func archive_page_days(page: int) -> Array:
	var out: Array = []
	for i in range(page * ARCHIVE_ROWS, mini((page + 1) * ARCHIVE_ROWS, archive_count())):
		out.append(PTDaily.date_add(today, -i))
	return out


func _show_archive(page := -1) -> void:
	if page < 0:
		var idx := clampi(PTDaily.day_number(today) - PTDaily.day_number(date), 0, archive_count() - 1)
		page = int(idx / ARCHIVE_ROWS)
	archive_page = clampi(page, 0, archive_pages() - 1)
	_open_modal(Modal.ARCHIVE)
	_modal_title("Past days", "1f4c5")
	var results := load_results()
	var days := archive_page_days(archive_page)
	for i in ARCHIVE_ROWS:
		# Always ARCHIVE_ROWS rows tall, so the paging buttons never jump around.
		if i < days.size():
			var d: String = days[i]
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, GTUI.target())
			b.focus_mode = Control.FOCUS_ALL
			var res := String(results.get(d, ""))
			var cfg := PTDaily.config(d)
			b.text = "#%d  %s  ·  %s%s" % [PTDaily.day_number(d), PTDaily.pretty(d), cfg.label,
				("  ·  " + res) if res != "" else ""]
			if d == date:
				b.add_theme_stylebox_override("normal", _style(C_BTN_HI, 12, C_ACCENT, 2, 10))
			b.pressed.connect(func(): pick_day(d))
			modal_box.add_child(b)
		else:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(0, 44)
			modal_box.add_child(sp)
	var pg := _label("Page %d of %d" % [archive_page + 1, archive_pages()], GTUI.fs(GTUI.FS_CAPTION), C_MUTED)
	pg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_box.add_child(pg)
	_modal_buttons([["Newer", func(): _show_archive(archive_page - 1)], ["Older", func(): _show_archive(archive_page + 1)]])
	var nav: HBoxContainer = modal_box.get_child(modal_box.get_child_count() - 1)
	nav.get_child(0).disabled = archive_page == 0
	nav.get_child(1).disabled = archive_page >= archive_pages() - 1


## Opens a past (or today's) puzzle from the picker.
func pick_day(d: String) -> void:
	_close_modal()
	if not dev_mode and (d < PTDaily.EPOCH or d > today):
		return
	if d != date:
		load_day(d)


# ================================================================ dev mode

func _build_dev_panel() -> void:
	dev_panel = PanelContainer.new()
	dev_panel.add_theme_stylebox_override("panel", _style(Color(0.05, 0.04, 0.09, 0.94), 10, C_ACCENT, 1, 8))
	dev_panel.visible = false
	dev_panel.z_index = 30
	dev_panel.custom_minimum_size = Vector2(260, 0)
	add_child(dev_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	dev_panel.add_child(v)
	v.add_child(_label("DEV", GTUI.fs(GTUI.FS_CAPTION), C_ACCENT, true))
	dev_info = _label("", GTUI.fs(GTUI.FS_CAPTION), C_MUTED)
	v.add_child(dev_info)
	dev_date_edit = LineEdit.new()
	dev_date_edit.placeholder_text = "YYYY-MM-DD"
	dev_date_edit.text_submitted.connect(func(t): dev_set_day(t))
	v.add_child(dev_date_edit)
	var rows := [
		[["◀ Day", func(): dev_set_day(PTDaily.date_add(date, -1))], ["Day ▶", func(): dev_set_day(PTDaily.date_add(date, 1))], ["Go", func(): dev_set_day(dev_date_edit.text)]],
		[["Today", func(): dev_set_day(today)], ["Random", dev_random], ["Reset", dev_reset]],
		[["Reveal", dev_toggle_reveal], ["Win", dev_win], ["Worst", dev_worst]],
		[["Close", _toggle_dev]],
	]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		for spec in r:
			var b := Button.new()
			b.text = spec[0]
			b.add_theme_font_size_override("font_size", 13)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.focus_mode = Control.FOCUS_ALL
			b.pressed.connect(spec[1])
			h.add_child(b)
		v.add_child(h)


func _toggle_dev() -> void:
	if not dev_mode:
		return
	dev_panel.visible = not dev_panel.visible
	_update_dev()


func _update_dev() -> void:
	if not dev_panel or not dev_panel.visible or puzzle.is_empty():
		return
	var d: Dictionary = puzzle.difficulty
	dev_info.text = "%s  #%d  seed %d\nattempt %d · score %s (%s)\nclues %d · near misses %d · avg elim %s\nanswer: %s\nstate: %s · guesses %d · hints %d" % [
		date, puzzle_no, int(puzzle.seed), int(puzzle.attempt), str(d.score), d.label, int(d.clues), int(d.near),
		str(d.avg_elim), puzzle.plans[int(puzzle.target)].name, "won" if is_done() else "playing",
		st.guesses.size(), int(st.hints)]
	dev_date_edit.text = date


func dev_set_day(d: String) -> bool:
	if not PTDaily.is_date(d):
		_toast("Not a date: %s" % d)
		return false
	load_day(d)
	_update_dev()
	return true


func dev_random() -> void:
	var off := randi_range(-400, 400)
	dev_set_day(PTDaily.date_add(today, off))


func dev_reset() -> void:
	wipe_save()
	st = PTSave.fresh()
	selected = -1
	_close_modal()
	refresh()
	_update_dev()


func dev_toggle_reveal() -> void:
	dev_reveal = not dev_reveal
	refresh()


func dev_win() -> void:
	guess_plan(int(puzzle.target))
	_update_dev()


## Guesses every wrong plan, then the right one (the worst possible run).
func dev_worst() -> void:
	for plan in puzzle.plans:
		if int(plan.id) != int(puzzle.target) and not st.guesses.has(int(plan.id)):
			guess_plan(int(plan.id))
	_close_modal()
	dev_win()


# ================================================================ agent hooks

func get_agent_state() -> Dictionary:
	if puzzle.is_empty():
		return {}
	return {
		"day": date, "today": today, "puzzle_no": puzzle_no, "seed": int(puzzle.seed),
		"state": "won" if is_done() else "playing", "difficulty": puzzle.difficulty.label,
		"plans": puzzle.plans.map(func(p): return p.name), "friends": puzzle.friends.map(func(f): return f.name),
		"answer": int(puzzle.target), "answer_name": puzzle.plans[int(puzzle.target)].name,
		"guesses": st.guesses.duplicate(), "hints": int(st.hints), "seconds": int(st.seconds),
		"selected": selected, "crossed": st.crossed.duplicate(), "modal": Modal.keys()[modal],
		"dev_mode": dev_mode, "share_text": share_text(), "new_day_ready": new_day_ready,
	}


## Fingerprint of any day's puzzle (agents use it to check web and native builds agree).
func puzzle_signature(d: String) -> String:
	return PTSave.signature(PTGen.generate(d))


func _input(ev: InputEvent) -> void:
	# Tab / Shift+Tab move focus through the visible controls (inside the open overlay only)
	if GTUI.handle_input(ev).has("consumed"):
		get_viewport().set_input_as_handled()
