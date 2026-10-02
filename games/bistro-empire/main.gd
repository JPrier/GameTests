extends Node2D
## Bistro Empire: an incremental restaurant tycoon. Mobile-first, portrait, drawn immediate-mode.
## Economy rules live in econ.gd; this file is input, layout, drawing and saving.

const SAVE_PATH := "user://bistro_empire.json"
const AUTOSAVE := 5.0
const AUTO_TICK := 0.25
const DRAG_SLOP := 10.0
const HOLD_DELAY := 0.38
const HOLD_RATE := 0.085

const C_BG := Color("17120e")
const C_CARD := Color("241c16")
const C_CARD_HI := Color("30251c")
const C_LINE := Color(1, 1, 1, 0.07)
const C_INK := Color("f6ede1")
const C_MUTED := Color("a8957f")
const C_DIM := Color("6f604f")
const C_ACCENT := Color("f5b942")
const C_RED := Color("e5533d")
const C_GREEN := Color("6cc56b")
const C_BLUE := Color("5aa9e6")
const C_PURPLE := Color("b58cff")
const C_ORANGE := Color("ff8a3d")
const C_BTN := Color("3a2e24")
const C_BUY := Color("4d9a4c")
const C_BUY_TXT := Color("0d1f0c")

const CAT_COLOR := {
	"demand": Color("5aa9e6"), "seating": Color("f5b942"), "kitchen": Color("e5533d"), "ticket": Color("6cc56b"),
	"global": Color("f6ede1"), "cost": Color("a8957f"), "tap": Color("ff8a3d"), "ceiling": Color("e0c27a"),
	"auto": Color("9ad1ff"), "offline": Color("7a8cff"), "royalty": Color("b58cff"), "city": Color("c58bff"),
	"venture": Color("6ad1c0"), "concept": Color("ffb3c1"), "cross": Color("ff6f91"), "legacy": Color("f5b942"),
}
const CAT_LABEL := {
	"demand": "Demand", "seating": "Seating", "kitchen": "Kitchen", "ticket": "Menu", "global": "Ambience",
	"cost": "Savings", "tap": "Serving", "ceiling": "Brand", "auto": "Manager", "offline": "Night shift",
	"royalty": "Franchise", "city": "City", "venture": "Venture", "concept": "Signature", "cross": "Crossroads",
}
const TABS := ["build", "upgrades", "franchise", "legacy", "more"]
const TAB_LABEL := {"build": "Build", "upgrades": "Upgrades", "franchise": "Franchise", "legacy": "Legacy", "more": "More"}
const BUY_MODES := [1, 10, 100, -1]
const UPG_FILTERS := ["all", "afford", "stats", "growth", "cross"]
const UPG_FILTER_LABEL := {"all": "All", "afford": "Can buy", "stats": "Stats", "growth": "Growth", "cross": "Crossroads"}
const REP_ICON := {"ads": "megaphone", "tables": "table", "cooks": "hat", "recipes": "book"}
const REP_BLURB := {"ads": "+0.5 guest demand", "tables": "+0.4 seats", "cooks": "+0.4 kitchen speed", "recipes": "+$0.50 per bill"}

var E: Econ
var font: Font
var cv: CanvasItem
var content: Control
var overlay: Control

var tab := "build"
var buy_mode := 0
var upg_filter := "all"
var scroll := {}
var scroll_max := {}
var scroll_vel := 0.0

var buttons: Array = []           # {id, rect, layer, hold}
var press := {}                   # active press: {pos, t, id, moved, hold_next, layer}
var last_pos := Vector2.ZERO
var modal := ""                   # "", "concept", "sell", "welcome", "reset", "help"
var modal_data := {}

var col := Rect2()
var header_r := Rect2()
var scene_r := Rect2()
var strip_r := Rect2()
var content_r := Rect2()
var nav_r := Rect2()

var floaters: Array = []          # {pos, text, t, color}
var toast := ""
var toast_t := 0.0
var anim_t := 0.0
var serve_bump := 0.0
var save_t := 0.0
var auto_t := 0.0
var cache_t := 0.0
var vis_cache: Array = []
var upcoming_cache: Array = []
var gain_cache := {}
var inc_cache := 0.0
var info_cache := {}
var afford_count := 0
var last_saved_unix := 0
var loaded_offline := false


# =================================================================== lifecycle

func _ready() -> void:
	font = ThemeDB.fallback_font
	E = Econ.new()
	_add_key_action("serve", [KEY_SPACE, KEY_ENTER])
	for i in TABS.size():
		_add_key_action("tab_%d" % (i + 1), [KEY_1 + i])
	_add_key_action("back", [KEY_ESCAPE])
	content = Control.new()
	content.clip_contents = true
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.draw.connect(_draw_content)
	add_child(content)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	for t in TABS:
		scroll[t] = 0.0
		scroll_max[t] = 0.0
	if not load_game():
		E.new_game()
	if not E.concept_chosen and modal == "":
		open_modal("concept")
	_refresh_cache(true)


func _add_key_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if E != null:
			save_game()


func _process(delta: float) -> void:
	delta = minf(delta, 1.0)
	anim_t += delta
	if E.concept_chosen and modal != "concept":
		E.tick(delta)
	auto_t += delta
	if auto_t >= AUTO_TICK:
		auto_t = 0.0
		if E.concept_chosen:
			var before := E.owned.size()
			E.run_automation()
			if E.owned.size() != before:
				_refresh_cache(true)
	cache_t += delta
	if cache_t >= 0.25:
		_refresh_cache(false)
	save_t += delta
	if save_t >= AUTOSAVE:
		save_game()
	serve_bump = maxf(0.0, serve_bump - delta * 5.0)
	toast_t = maxf(0.0, toast_t - delta)
	for f in floaters:
		f.t += delta
	floaters = floaters.filter(func(f): return f.t < 1.1)
	# kinetic scroll
	if press.is_empty() and absf(scroll_vel) > 1.0:
		_scroll_by(scroll_vel * delta)
		scroll_vel *= pow(0.02, delta)
	# hold-to-repeat
	if not press.is_empty() and press.get("hold", false) and not press.moved:
		var now := _now()
		if now - float(press.t) >= HOLD_DELAY and now >= float(press.hold_next):
			press.hold_next = now + HOLD_RATE
			press.held = true
			_do(String(press.id))
	_layout()
	queue_redraw()
	content.queue_redraw()
	overlay.queue_redraw()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _refresh_cache(full: bool) -> void:
	cache_t = 0.0
	info_cache = E.income_info(E.agg())
	inc_cache = float(info_cache.total)
	vis_cache = E.visible_upgrades()
	afford_count = 0
	for u in vis_cache:
		if float(u.cost) <= E.cash:
			afford_count += 1
	if full or gain_cache.size() > 400:
		gain_cache.clear()
		upcoming_cache = E.upcoming_upgrades(3)


## Income gain ratio from buying an upgrade (cached until something changes).
func upgrade_gain(u: Dictionary) -> float:
	var key := "u%d" % int(u.id)
	if gain_cache.has(key):
		return float(gain_cache[key])
	var a := E.agg()
	var cur := float(E.income_info(a).total)
	var nxt := float(E.income_info(E.copy_with(a, u.eff)).total)
	var g := nxt / maxf(cur, 1e-300) - 1.0 if cur > 0.0 else 0.0
	gain_cache[key] = g
	return g


func rep_gain(r: String, k: int) -> float:
	var a := E.agg()
	var cur := float(E.income_info(a).total)
	var nxt := float(E.income_info(a, {r: int(E.reps[r]) + k}).total)
	return nxt / maxf(cur, 1e-300) - 1.0 if cur > 0.0 else 0.0


func buy_count(r: String) -> int:
	var m: int = BUY_MODES[buy_mode]
	if m > 0:
		return m
	return maxi(1, E.rep_max_affordable(r))


# =================================================================== saving

func save_game() -> void:
	save_t = 0.0
	var d := E.to_dict()
	d["t"] = int(Time.get_unix_time_from_system())
	d["ui"] = {"tab": tab, "buy_mode": buy_mode}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()
	# touching a second file nudges the web build to flush storage to IndexedDB
	var s := FileAccess.open("user://.sync", FileAccess.WRITE)
	if s:
		s.store_string(str(d.t))
		s.close()
	last_saved_unix = int(d.t)


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not d is Dictionary:
		return false
	E.from_dict(d)
	var ui: Dictionary = d.get("ui", {})
	if TABS.has(String(ui.get("tab", "build"))):
		tab = String(ui.get("tab", "build"))
	buy_mode = clampi(int(ui.get("buy_mode", 0)), 0, BUY_MODES.size() - 1)
	var away := float(int(Time.get_unix_time_from_system()) - int(d.get("t", 0)))
	if away > 60.0 and E.concept_chosen:
		var g := E.offline_gain(away)
		if g > 0.0:
			E.cash = minf(E.cash + g, Econ.MAX_MONEY)
			E.run_earned += g
			E.life_earned += g
			open_modal("welcome", {"away": away, "gain": g})
			loaded_offline = true
	return true


func wipe_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# =================================================================== actions

func open_modal(m: String, data: Dictionary = {}) -> void:
	modal = m
	modal_data = data
	press = {}


func serve(at: Vector2 = Vector2.ZERO) -> void:
	if not E.concept_chosen:
		return
	var v := E.tap()
	serve_bump = 1.0
	if at == Vector2.ZERO:
		at = scene_r.get_center()
	floaters.append({"pos": at + Vector2(randf_range(-20, 20), -10), "text": "+" + Econ.fmt_money(v), "t": 0.0, "color": C_ACCENT})


func set_tab(t: String) -> void:
	if TABS.has(t):
		tab = t
		scroll_vel = 0.0


func _toast(s: String) -> void:
	toast = s
	toast_t = 2.2


func _do(id: String) -> void:
	var parts := id.split(":")
	var a: String = parts[0]
	match a:
		"tab": set_tab(parts[1])
		"serve": serve(last_pos)
		"mode": buy_mode = int(parts[1])
		"filter":
			upg_filter = parts[1]
			scroll["upgrades"] = 0.0
		"rep":
			var r: String = parts[1]
			if E.buy_rep(r, buy_count(r)):
				_refresh_cache(true)
		"upg":
			if E.buy_upgrade(int(parts[1])):
				_refresh_cache(true)
		"buyall":
			var n := 0
			for u in E.visible_upgrades():
				if u.cat != "cross" and float(u.cost) <= E.cash and E.buy_upgrade(int(u.id)):
					n += 1
			if n > 0:
				_toast("Bought %d upgrades" % n)
			_refresh_cache(true)
		"city":
			if E.buy_city(int(parts[1])):
				_refresh_cache(true)
		"vent":
			if E.buy_vent(int(parts[1])):
				_refresh_cache(true)
		"legacy":
			if E.buy_legacy(int(parts[1])):
				_refresh_cache(true)
				_toast("Legacy perk unlocked")
		"price_down":
			E.price = maxf(Econ.PRICE_MIN, E.effective_price(E.agg()) / 1.06)
			E.price_auto = false
			_refresh_cache(false)
		"price_up":
			E.price = minf(E.ceiling(E.agg()), E.effective_price(E.agg()) * 1.06)
			E.price_auto = false
			_refresh_cache(false)
		"price_auto":
			E.price_auto = not E.price_auto
			if not E.price_auto:
				E.price = E.effective_price(E.agg(), {}, true)
			_refresh_cache(false)
		"auto":
			E.auto_on[parts[1]] = not E.automation_active(parts[1])
		"sell": open_modal("sell")
		"sell_yes":
			var g := E.prestige()
			modal = ""
			if g > 0.0:
				for t in TABS:
					scroll[t] = 0.0
				tab = "build"
				open_modal("concept", {"stars": g})
				save_game()
		"concept":
			if E.choose_concept(parts[1]):
				modal = ""
				E.mark_dirty()
				_refresh_cache(true)
				save_game()
		"close": modal = ""
		"reset": open_modal("reset")
		"reset_yes":
			wipe_save()
			E.new_game()
			tab = "build"
			for t in TABS:
				scroll[t] = 0.0
			open_modal("concept")
			_refresh_cache(true)
		"help": open_modal("help")
		"noop": pass


# =================================================================== input

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("serve") and modal == "":
		serve()
	elif ev.is_action_pressed("back"):
		if modal != "" and modal != "concept":
			modal = ""
	else:
		for i in TABS.size():
			if ev.is_action_pressed("tab_%d" % (i + 1)) and modal == "":
				set_tab(TABS[i])


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var p: Vector2 = make_input_local(ev).position
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_on_press(p)
			else:
				_on_release(p)
		elif ev.pressed and modal == "" and content_r.has_point(p):
			if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_by(-60.0)
			elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_by(60.0)
	elif ev is InputEventMouseMotion and not press.is_empty():
		var p: Vector2 = make_input_local(ev).position
		var dy := p.y - last_pos.y
		if not press.moved and p.distance_to(press.pos) > DRAG_SLOP:
			press.moved = true
		if press.moved and press.scrolls:
			_scroll_by(-dy)
			var dt := maxf(0.008, _now() - float(press.get("mt", press.t)))
			scroll_vel = lerpf(scroll_vel, -dy / dt, 0.4)
		press.mt = _now()
		last_pos = p


func _hit(p: Vector2) -> Dictionary:
	# buttons are appended back-to-front; search from the top
	for i in range(buttons.size() - 1, -1, -1):
		var b: Dictionary = buttons[i]
		if modal != "" and b.layer != "modal":
			continue
		if b.layer == "content" and not content_r.has_point(p):
			continue
		if b.rect.has_point(p):
			return b
	return {}


func _on_press(p: Vector2) -> void:
	last_pos = p
	scroll_vel = 0.0
	var b := _hit(p)
	var scrolls := modal == "" and content_r.has_point(p)
	press = {"pos": p, "t": _now(), "id": String(b.get("id", "")), "moved": false, "scrolls": scrolls,
		"hold": bool(b.get("hold", false)), "hold_next": 0.0, "held": false}
	if b.is_empty() and modal == "" and scene_r.has_point(p):
		serve(p)
		press = {}
	elif String(b.get("id", "")) == "serve":
		serve(p)
		press = {}


func _on_release(p: Vector2) -> void:
	if press.is_empty():
		return
	var id := String(press.id)
	var was_moved: bool = press.moved
	var held: bool = press.held
	press = {}
	if id == "" or was_moved or held:
		return
	var b := _hit(p)
	if String(b.get("id", "")) == id:
		_do(id)


func _scroll_by(dy: float) -> void:
	var s := float(scroll[tab]) + dy
	var mx := float(scroll_max.get(tab, 0.0))
	scroll[tab] = clampf(s, 0.0, mx)
	if s < 0.0 or s > mx:
		scroll_vel = 0.0


# =================================================================== layout

func _btn(id: String, r: Rect2, layer := "chrome", hold := false) -> void:
	buttons.append({"id": id, "rect": r, "layer": layer, "hold": hold})


func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x, 520.0)
	col = Rect2((vs.x - w) * 0.5, 0, w, vs.y)
	var x := col.position.x + 12.0
	var cw := w - 24.0
	header_r = Rect2(x, 8, cw, 70)
	scene_r = Rect2(x, 82, cw, clampf(vs.y * 0.17, 110.0, 150.0))
	strip_r = Rect2(x, scene_r.end.y + 6, cw, 52)
	nav_r = Rect2(col.position.x, vs.y - 66, w, 66)
	content_r = Rect2(col.position.x, strip_r.end.y + 6, w, nav_r.position.y - strip_r.end.y - 6)
	content.position = content_r.position
	content.size = content_r.size
	overlay.position = Vector2.ZERO
	overlay.size = vs


# =================================================================== drawing helpers

func _text(pos: Vector2, s: String, size: int, color := C_INK, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	cv.draw_string(font, pos, s, align, width, size, color)


func _text_c(r: Rect2, y: float, s: String, size: int, color := C_INK) -> void:
	cv.draw_string(font, Vector2(r.position.x, y), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, color)


func _text_r(right: float, y: float, s: String, size: int, color := C_INK) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	cv.draw_string(font, Vector2(right - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _tw(s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _fit(s: String, size: int, width: float) -> String:
	if _tw(s, size) <= width:
		return s
	while s.length() > 1 and _tw(s + "...", size) > width:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + "..."


func _wrap(s: String, size: int, width: float) -> PackedStringArray:
	var out: PackedStringArray = []
	var line := ""
	for word in s.split(" "):
		var t := word if line == "" else line + " " + word
		if _tw(t, size) > width and line != "":
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out


var _sb_cache := {}


func _rr(r: Rect2, color: Color, radius := 12.0, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var key := "%s|%d|%s|%d" % [color.to_html(), int(radius), border.to_html() if bw > 0 else "", bw]
	var sb: StyleBoxFlat = _sb_cache.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(int(radius))
		sb.anti_aliasing = true
		if bw > 0:
			sb.border_color = border
			sb.set_border_width_all(bw)
		if _sb_cache.size() > 400:
			_sb_cache.clear()
		_sb_cache[key] = sb
	cv.draw_style_box(sb, r)


func _star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	cv.draw_colored_polygon(pts, color)


func _button(id: String, r: Rect2, label: String, style := "", layer := "chrome", hold := false, enabled := true, size := 16) -> void:
	var bg := C_BTN
	var fg := C_INK
	match style:
		"buy": bg = C_BUY; fg = C_BUY_TXT
		"accent": bg = C_ACCENT; fg = Color("241703")
		"red": bg = C_RED; fg = Color("2a0904")
		"purple": bg = C_PURPLE; fg = Color("1d0f33")
		"on": bg = Color("5b4636")
		"ghost": bg = Color(1, 1, 1, 0.05); fg = C_MUTED
	if not enabled:
		bg = Color("2c241d")
		fg = C_DIM
	var pressed: bool = not press.is_empty() and String(press.id) == id and not press.moved
	var rr := r.grow(-1.5) if pressed else r
	_rr(rr, bg, 10)
	var lines := label.split("\n")
	if lines.size() == 1:
		_text_c(rr, rr.get_center().y + size * 0.36, _fit(label, size, rr.size.x - 8), size, fg)
	else:
		_text_c(rr, rr.get_center().y - 2, _fit(lines[0], size - 3, rr.size.x - 8), size - 3, Color(fg, 0.85))
		_text_c(rr, rr.get_center().y + size - 1, _fit(lines[1], size, rr.size.x - 8), size, fg)
	_btn(id, r, layer, hold)


# =================================================================== draw: chrome

func _draw() -> void:
	cv = self
	buttons.clear()
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	_draw_header()
	_draw_scene()
	_draw_strip()
	_draw_nav()


func _draw_header() -> void:
	var r := header_r
	var cc: Dictionary = Econ.CONCEPT[E.concept]
	var ccol := Color(String(cc.color))
	_text(Vector2(r.position.x, r.position.y + 14), ("BISTRO EMPIRE  ·  " + String(cc.name).to_upper()) if E.concept_chosen else "BISTRO EMPIRE", 12, ccol)
	var cash_s := Econ.fmt_money(E.cash)
	_text(Vector2(r.position.x, r.position.y + 46), cash_s, 32, C_INK)
	_text(Vector2(r.position.x, r.position.y + 66), "+%s/s" % Econ.fmt_money(inc_cache), 16, C_GREEN)
	# stars badge
	var bw := 92.0
	var br := Rect2(r.end.x - bw, r.position.y + 4, bw, 40)
	_rr(br, C_CARD, 20)
	_star(br.position + Vector2(22, 20), 11, C_ACCENT)
	_text(br.position + Vector2(38, 27), Econ.fmt_num(E.stars), 18, C_ACCENT)
	_btn("tab:legacy", br)
	var pend := E.stars_pending()
	if pend >= 1.0:
		_text_r(r.end.x, r.position.y + 62, "+%s on sale" % Econ.fmt_num(pend), 13, C_ACCENT)
	elif E.prestiges == 0:
		_text_r(r.end.x, r.position.y + 62, "stars", 13, C_DIM)


func _draw_scene() -> void:
	var r := scene_r
	var inf := info_cache
	if inf.is_empty():
		return
	var bump := serve_bump * serve_bump
	var rr := r.grow(bump * 3.0)
	# wall + floor
	_rr(rr, Color("3a2a1f"), 14)
	var floor_r := Rect2(rr.position.x, rr.position.y + rr.size.y * 0.42, rr.size.x, rr.size.y * 0.58)
	var tile := 18.0
	var cols := int(ceil(floor_r.size.x / tile))
	var rows := int(ceil(floor_r.size.y / tile))
	for iy in rows:
		for ix in cols:
			if (ix + iy) % 2 == 0:
				var tr := Rect2(floor_r.position + Vector2(ix * tile, iy * tile), Vector2(tile, tile)).intersection(floor_r.grow_individual(0, 0, 0, -6))
				if tr.size.x > 0 and tr.size.y > 0:
					cv.draw_rect(tr, Color("2c2019"))
	# awning
	var aw_h := 14.0
	var stripes := 14
	var sw := rr.size.x / stripes
	for i in stripes:
		var c := C_RED if i % 2 == 0 else Color("f3e3cc")
		var sr := Rect2(rr.position.x + i * sw, rr.position.y, sw + 0.5, aw_h)
		if i == 0:
			_rr(Rect2(sr.position, Vector2(sw + 12, aw_h)), c, 12)
		elif i == stripes - 1:
			_rr(Rect2(sr.position - Vector2(12, 0), Vector2(sw + 12, aw_h)), c, 12)
		else:
			cv.draw_rect(sr, c)
		cv.draw_circle(Vector2(sr.position.x + sw * 0.5, rr.position.y + aw_h), sw * 0.5, c)
	# window glow
	var win := Rect2(rr.position.x + 14, rr.position.y + 26, rr.size.x * 0.22, rr.size.y * 0.24)
	_rr(win, Color("f5b942", 0.18), 6)
	cv.draw_line(Vector2(win.get_center().x, win.position.y), Vector2(win.get_center().x, win.end.y), Color("3a2a1f"), 2)
	# kitchen pass on the right
	var kx := rr.end.x - rr.size.x * 0.27
	var kr := Rect2(kx, rr.position.y + 24, rr.end.x - kx - 10, rr.size.y * 0.32)
	_rr(kr, Color("2a1e16"), 6)
	cv.draw_rect(Rect2(kr.position.x, kr.end.y - 6, kr.size.x, 6), Color("8c8c8c"))
	var chefs := clampi(1 + int(E.reps.cooks) / 8, 1, 5)
	for i in chefs:
		var cx := kr.position.x + 12 + i * (kr.size.x - 24) / maxf(1, chefs - 1) if chefs > 1 else kr.get_center().x
		var cy := kr.end.y - 14 + sin(anim_t * 6.0 + i * 1.7) * 1.5
		cv.draw_circle(Vector2(cx, cy), 6, Color("e8c4a0"))
		cv.draw_rect(Rect2(cx - 5, cy - 14, 10, 8), Color.WHITE)
		cv.draw_circle(Vector2(cx, cy - 14), 6, Color.WHITE)
	for i in 3:
		var sx := kr.position.x + 10 + i * 12
		var phase := fmod(anim_t * 0.8 + i * 0.33, 1.0)
		cv.draw_circle(Vector2(sx + sin(phase * 6.0) * 3, kr.position.y - 2 - phase * 10), 3.0 * (1.0 - phase), Color(1, 1, 1, 0.25 * (1.0 - phase)))
	# tables
	var occ := clampf(float(inf.served) / maxf(float(inf.cap), 1e-9), 0.0, 1.0)
	var ntab := clampi(2 + int(E.reps.tables) / 6, 2, 14)
	var area := Rect2(rr.position.x + 20, floor_r.position.y + 6, kx - rr.position.x - 34, floor_r.size.y - 18)
	var per_row := clampi(int(ceil(ntab / 2.0)), 1, 7)
	var nrows := int(ceil(float(ntab) / per_row))
	var filled := int(round(occ * ntab))
	for i in ntab:
		var ix := i % per_row
		var iy := i / per_row
		var tx := area.position.x + (ix + 0.5) * area.size.x / per_row
		var ty := area.position.y + (iy + 0.5) * area.size.y / maxf(1, nrows)
		var tc := Vector2(tx, ty)
		var guest := i < filled
		if guest:
			var hue := fmod(i * 0.137 + 0.05, 1.0)
			var gc := Color.from_hsv(hue, 0.45, 0.95)
			var b := sin(anim_t * 4.0 + i) * 1.2
			cv.draw_circle(tc + Vector2(-11, -2 + b), 5, gc)
			cv.draw_circle(tc + Vector2(11, -2 - b), 5, gc.darkened(0.2))
		else:
			cv.draw_rect(Rect2(tc + Vector2(-15, -4), Vector2(6, 7)), Color("6b4a33"))
			cv.draw_rect(Rect2(tc + Vector2(9, -4), Vector2(6, 7)), Color("6b4a33"))
		cv.draw_circle(tc, 8, Color("a8774f"))
		cv.draw_circle(tc, 8, Color("7a5236"), false, 1.5)
		if guest:
			cv.draw_circle(tc + Vector2(0, -1), 3.5, Color("f6ede1"))
	# queue outside when demand exceeds capacity
	var over := float(inf.want) / maxf(float(inf.cap), 1e-9)
	var q := clampi(int(round((over - 1.0) * 3.0)), 0, 5) if over > 1.02 else 0
	for i in q:
		var qx := rr.position.x + 8.0 + (i % 2) * 2.0
		var qy := rr.end.y - 12.0 - i * 9.0
		cv.draw_circle(Vector2(qx + sin(anim_t * 3.0 + i) * 1.0, qy), 4, Color.from_hsv(fmod(i * 0.21, 1.0), 0.4, 0.9))
	# tap hint
	var tv := Econ.fmt_money(E.tap_value())
	var hint := "TAP TO SERVE  +" + tv
	var hw := _tw(hint, 13) + 18
	var hr := Rect2(rr.end.x - hw - 8, rr.end.y - 26, hw, 20)
	_rr(hr, Color(0, 0, 0, 0.45), 10)
	_text_c(hr, hr.position.y + 15, hint, 13, Color(C_ACCENT, 0.8 + 0.2 * sin(anim_t * 3.0)))


func _draw_strip() -> void:
	var r := strip_r
	var inf := info_cache
	if inf.is_empty():
		return
	var vals := [["Guests", float(inf.want), "demand", C_BLUE], ["Seats", float(inf.seating), "seating", C_ACCENT], ["Kitchen", float(inf.kitchen), "kitchen", C_RED]]
	var mx := 0.0
	for v in vals:
		mx = maxf(mx, float(v[1]))
	var gap := 6.0
	var w := (r.size.x - gap * 2) / 3.0
	for i in 3:
		var v: Array = vals[i]
		var cr := Rect2(r.position.x + i * (w + gap), r.position.y, w, r.size.y)
		var lim := String(inf.limit) == String(v[2])
		_rr(cr, C_CARD, 10, Color(C_RED, 0.9), 2 if lim else 0)
		_text(cr.position + Vector2(9, 17), String(v[0]), 12, C_MUTED)
		_text_r(cr.end.x - 8, cr.position.y + 17, "LIMIT" if lim else "", 11, C_RED)
		_text(cr.position + Vector2(9, 37), Econ.fmt_num(float(v[1])) + "/s", 16, C_INK)
		var bar := Rect2(cr.position.x + 9, cr.end.y - 9, cr.size.x - 18, 4)
		cv.draw_rect(bar, Color(1, 1, 1, 0.08))
		var f := clampf(float(v[1]) / maxf(mx, 1e-9), 0.0, 1.0)
		cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(v[3]))
		_btn("help", cr)


func _draw_nav() -> void:
	var r := nav_r
	cv.draw_rect(r, Color("120e0b"))
	cv.draw_line(r.position, Vector2(r.end.x, r.position.y), C_LINE, 1)
	var w := r.size.x / TABS.size()
	for i in TABS.size():
		var t: String = TABS[i]
		var br := Rect2(r.position.x + i * w, r.position.y, w, r.size.y)
		var on := t == tab
		var locked := t == "franchise" and not E.franchise_unlocked()
		var c := C_ACCENT if on else (C_DIM if locked else C_MUTED)
		_nav_icon(t, Vector2(br.get_center().x, br.position.y + 24), c, locked)
		_text_c(br, br.position.y + 52, TAB_LABEL[t], 12, c)
		if on:
			cv.draw_rect(Rect2(br.get_center().x - 16, r.position.y, 32, 3), C_ACCENT)
		var badge := 0
		if t == "upgrades":
			badge = afford_count
		if badge > 0:
			var bt := str(mini(badge, 99))
			var bwid := maxf(18.0, _tw(bt, 11) + 10)
			var bc := Vector2(br.get_center().x + 14, br.position.y + 12)
			_rr(Rect2(bc - Vector2(bwid * 0.5 - 6, 0), Vector2(bwid, 16)), C_RED, 8)
			_text(bc + Vector2(-bwid * 0.5 + 6 + (bwid - _tw(bt, 11)) * 0.5, 12), bt, 11, Color.WHITE)
		if t == "legacy" and E.can_prestige():
			cv.draw_circle(Vector2(br.get_center().x + 14, br.position.y + 14), 5, C_ACCENT)
		_btn("tab:" + t, br)


func _nav_icon(t: String, c: Vector2, col_: Color, locked: bool) -> void:
	match t:
		"build":
			cv.draw_rect(Rect2(c + Vector2(-10, -2), Vector2(20, 12)), col_, false, 2)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-13, -2), c + Vector2(0, -12), c + Vector2(13, -2)]), col_)
		"upgrades":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(10, 0), c + Vector2(4, 0), c + Vector2(4, 10), c + Vector2(-4, 10), c + Vector2(-4, 0), c + Vector2(-10, 0)]), col_)
		"franchise":
			for i in 3:
				var h := 8.0 + i * 5.0
				cv.draw_rect(Rect2(c + Vector2(-12 + i * 8, 10 - h), Vector2(6, h)), col_)
		"legacy":
			_star(c, 11, col_)
		"more":
			for i in 3:
				cv.draw_rect(Rect2(c + Vector2(-10, -8 + i * 7), Vector2(20, 3)), col_)
	if locked:
		cv.draw_circle(c + Vector2(11, 7), 6, C_BG)
		cv.draw_rect(Rect2(c + Vector2(7, 6), Vector2(8, 6)), col_)
		cv.draw_arc(c + Vector2(11, 6), 3, PI, TAU, 8, col_, 1.5)


# =================================================================== draw: content

func _draw_content() -> void:
	cv = content
	content.draw_set_transform(-content_r.position)
	var y0 := content_r.position.y + 6.0 - float(scroll[tab])
	var y := y0
	match tab:
		"build": y = _draw_build(y)
		"upgrades": y = _draw_upgrades(y)
		"franchise": y = _draw_franchise(y)
		"legacy": y = _draw_legacy(y)
		"more": y = _draw_more(y)
	var total := y - y0 + 12.0
	scroll_max[tab] = maxf(0.0, total - content_r.size.y)
	if float(scroll[tab]) > float(scroll_max[tab]):
		scroll[tab] = scroll_max[tab]
	# scroll fade hints
	if float(scroll[tab]) > 2.0:
		_fade(content_r.position.y, true)
	if float(scroll[tab]) < float(scroll_max[tab]) - 2.0:
		_fade(content_r.end.y - 18, false)
	content.draw_set_transform(Vector2.ZERO)


func _fade(y: float, top: bool) -> void:
	for i in 6:
		var a := (1.0 - i / 6.0) * 0.5
		var yy := y + (i * 3.0 if top else 15.0 - i * 3.0)
		cv.draw_rect(Rect2(content_r.position.x, yy, content_r.size.x, 3), Color(C_BG, a))


func _row_rect(y: float, h: float) -> Rect2:
	return Rect2(content_r.position.x + 12, y, content_r.size.x - 24, h)


func _visible(r: Rect2) -> bool:
	return r.end.y >= content_r.position.y - 4 and r.position.y <= content_r.end.y + 4


func _section(y: float, title: String, sub := "") -> float:
	var r := _row_rect(y, 26)
	_text(Vector2(r.position.x + 2, y + 18), title.to_upper(), 13, C_MUTED)
	if sub != "":
		_text_r(r.end.x - 2, y + 18, sub, 13, C_DIM)
	return y + 28


func _draw_build(y: float) -> float:
	var a := E.agg()
	# buy mode chips
	var r := _row_rect(y, 36)
	var labels := ["x1", "x10", "x100", "Max"]
	var cw := (r.size.x - 3 * 6) / 4.0
	for i in 4:
		var br := Rect2(r.position.x + i * (cw + 6), r.position.y, cw, r.size.y)
		_button("mode:%d" % i, br, labels[i], "on" if buy_mode == i else "ghost", "content", false, true, 15)
	y += 44
	# the four builds
	for rep in Econ.REPS:
		var rr := _row_rect(y, 84)
		if _visible(rr):
			_draw_rep_row(rr, rep, a)
		y += 90
	# price
	y = _draw_price(y + 4, a)
	# strategy tip
	var tip := _tip()
	if tip != "":
		var lines := _wrap(tip, 14, content_r.size.x - 48)
		var tr := _row_rect(y + 4, 20 + lines.size() * 19)
		_rr(tr, Color(C_ACCENT, 0.08), 10)
		for i in lines.size():
			_text(Vector2(tr.position.x + 12, tr.position.y + 24 + i * 19), lines[i], 14, C_ACCENT if i == 0 else C_MUTED)
		y = tr.end.y + 6
	return y


func _tip() -> String:
	var inf := info_cache
	if inf.is_empty():
		return ""
	match String(inf.limit):
		"demand":
			if E.price_unlocked(E.agg()) and not E.automation_active("auto_price") and float(inf.want) > float(inf.cap) * 0.0:
				return "Tip: Guests are the limit. Ads bring more people in, or lower your price."
			return "Tip: Guests are the limit. Run Ad Campaigns to bring more people in."
		"seating":
			return "Tip: You're out of seats. Tables add capacity; a higher price turns the queue into profit."
		"kitchen":
			return "Tip: The kitchen can't keep up. Hire Line Cooks, or raise prices to serve fewer, richer guests."
	return ""


func _draw_rep_row(r: Rect2, rep: String, a: Dictionary) -> void:
	var stat: String = Econ.REP_STAT[rep]
	var lim := String(info_cache.get("limit", "")) == stat
	_rr(r, C_CARD, 12, Color(C_RED, 0.7), 2 if lim else 0)
	var ic := Vector2(r.position.x + 26, r.position.y + 30)
	_rep_icon(rep, ic, Color(CAT_COLOR[stat]))
	_text(Vector2(r.position.x + 52, r.position.y + 24), Econ.REP_NAME[rep], 17)
	var cnt := "x%d" % int(E.reps[rep])
	_text(Vector2(r.position.x + 58 + _tw(Econ.REP_NAME[rep], 17), r.position.y + 24), cnt, 15, C_MUTED)
	if lim:
		_text(Vector2(r.position.x + 64 + _tw(Econ.REP_NAME[rep], 17) + _tw(cnt, 15), r.position.y + 24), "LIMIT", 11, C_RED)
	# milestone progress
	var nm := E.next_milestone(rep)
	var desc: String = REP_BLURB[rep]
	_text(Vector2(r.position.x + 52, r.position.y + 44), _fit(desc, 13, r.size.x - 190), 13, C_MUTED)
	if nm > 0:
		var prev := 0
		for m in Econ.MILESTONES:
			if m < nm:
				prev = m
		var f := clampf(float(int(E.reps[rep]) - prev) / float(nm - prev), 0.0, 1.0)
		var bar := Rect2(r.position.x + 52, r.position.y + 56, r.size.x - 190, 5)
		cv.draw_rect(bar, Color(1, 1, 1, 0.08))
		cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(CAT_COLOR[stat]))
		_text(Vector2(r.position.x + 52, r.position.y + 76), "%d: unlocks a %s upgrade" % [nm, String(Econ.STAT_NAME[stat]).to_lower()], 12, C_DIM)
	# buy button
	var k := buy_count(rep)
	var cost := E.rep_cost(rep, k)
	var can := cost <= E.cash
	var g := rep_gain(rep, k)
	var br := Rect2(r.end.x - 128, r.position.y + 10, 118, r.size.y - 20)
	var label := "+%d   %s" % [k, Econ.fmt_money(cost)]
	_button("rep:" + rep, br, "%s\n%s" % ["Buy %d" % k, Econ.fmt_money(cost)], "buy" if can else "", "content", true, can, 17)
	if g > 0.0005:
		_text_r(br.position.x - 8, r.end.y - 10, "+" + _pct(g), 13, C_GREEN)
	elif label == "":
		pass


func _rep_icon(rep: String, c: Vector2, color: Color) -> void:
	cv.draw_circle(c, 18, Color(color, 0.15))
	match rep:
		"ads":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -4), c + Vector2(4, -10), c + Vector2(4, 10), c + Vector2(-9, 4)]), color)
			cv.draw_rect(Rect2(c + Vector2(-12, -4), Vector2(4, 8)), color)
			cv.draw_arc(c + Vector2(6, 0), 6, -0.8, 0.8, 8, color, 2)
		"tables":
			cv.draw_rect(Rect2(c + Vector2(-11, -4), Vector2(22, 4)), color)
			cv.draw_rect(Rect2(c + Vector2(-9, 0), Vector2(3, 10)), color)
			cv.draw_rect(Rect2(c + Vector2(6, 0), Vector2(3, 10)), color)
		"cooks":
			cv.draw_circle(c + Vector2(-5, -5), 6, color)
			cv.draw_circle(c + Vector2(5, -5), 6, color)
			cv.draw_circle(c + Vector2(0, -8), 6, color)
			cv.draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 11)), color)
		"recipes":
			cv.draw_rect(Rect2(c + Vector2(-10, -9), Vector2(9, 18)), color)
			cv.draw_rect(Rect2(c + Vector2(1, -9), Vector2(9, 18)), color)
			cv.draw_line(c + Vector2(0, -9), c + Vector2(0, 9), C_CARD, 2)


func _pct(g: float) -> String:
	if g >= 10.0:
		return "x" + Econ.fmt_mult(snappedf(1.0 + g, 0.1))
	if g >= 0.995:
		return "%d%%" % int(round(g * 100.0))
	if g >= 0.1:
		return "%d%%" % int(round(g * 100.0))
	return "%.1f%%" % (g * 100.0)


func _draw_price(y: float, a: Dictionary) -> float:
	var r := _row_rect(y, 76)
	_rr(r, C_CARD, 12)
	if not E.price_unlocked(a):
		_text(r.position + Vector2(14, 28), "Menu prices", 17, C_DIM)
		_text(r.position + Vector2(14, 52), "Locked: buy \"Price Tags\" in Upgrades", 14, C_DIM)
		return r.end.y + 8
	var p := E.effective_price(a)
	var cap := E.ceiling(a)
	var auto_owned: bool = a.flags.has("auto_price")
	var auto: bool = auto_owned and E.price_auto
	_text(r.position + Vector2(14, 25), "Menu prices", 17)
	_text(r.position + Vector2(14 + _tw("Menu prices", 17) + 8, r.position.y + 25), "x" + Econ.fmt_mult(snappedf(p, 0.01)), 17, C_ACCENT)
	var sub := "Floor Manager sets the best price" if auto else "Higher prices scare guests away (max x%s)" % Econ.fmt_mult(snappedf(cap, 0.01))
	_text(r.position + Vector2(14, 46), _fit(sub, 13, r.size.x - 150), 13, C_MUTED)
	# gauge
	var bar := Rect2(r.position.x + 14, r.position.y + 58, r.size.x - 160, 6)
	cv.draw_rect(bar, Color(1, 1, 1, 0.08))
	var f := clampf(log(p / Econ.PRICE_MIN) / log(cap / Econ.PRICE_MIN), 0.0, 1.0)
	cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), C_ACCENT)
	var bx := r.end.x - 136
	_button("price_down", Rect2(bx, r.position.y + 12, 40, 52), "-", "", "content", true, not auto, 22)
	_button("price_up", Rect2(bx + 44, r.position.y + 12, 40, 52), "+", "", "content", true, not auto, 22)
	if auto_owned:
		_button("price_auto", Rect2(bx + 88, r.position.y + 12, 40, 52), "Auto", "on" if auto else "ghost", "content", false, true, 12)
	return r.end.y + 8


# ------------------------------------------------------------------ upgrades tab

func _filtered() -> Array:
	var out: Array = []
	for u in vis_cache:
		match upg_filter:
			"afford":
				if float(u.cost) > E.cash:
					continue
			"stats":
				if not ["demand", "seating", "kitchen", "ticket", "global", "ceiling", "concept"].has(String(u.cat)):
					continue
			"growth":
				if not ["cost", "tap", "auto", "offline", "royalty", "city", "venture"].has(String(u.cat)):
					continue
			"cross":
				if String(u.cat) != "cross":
					continue
		out.append(u)
	return out


func _draw_upgrades(y: float) -> float:
	# filter chips
	var r := _row_rect(y, 32)
	var x := r.position.x
	for f in UPG_FILTERS:
		var lab: String = UPG_FILTER_LABEL[f]
		var w := _tw(lab, 13) + 22
		var br := Rect2(x, y, w, 32)
		_button("filter:" + f, br, lab, "on" if upg_filter == f else "ghost", "content", false, true, 13)
		x += w + 6
	y += 40
	var owned_run := E.owned.size()
	var total_run := E.run_upgrade_count
	var list := _filtered()
	y = _section(y, "%d available" % list.size(), "owned %d / %d" % [owned_run, total_run])
	if afford_count > 1:
		var br := _row_rect(y, 40)
		_button("buyall", br, "Buy all affordable (skips Crossroads)", "accent", "content", false, true, 15)
		y += 48
	if list.is_empty():
		var er := _row_rect(y, 60)
		_rr(er, C_CARD, 12)
		_text_c(er, er.position.y + 36, "Nothing here yet. Keep earning!", 15, C_MUTED)
		y += 68
	for u in list:
		var h := 92.0 if u.cat == "cross" else 76.0
		var rr := _row_rect(y, h)
		if _visible(rr):
			_draw_upgrade_row(rr, u)
		y += h + 6
	if upg_filter == "all" and not upcoming_cache.is_empty():
		y = _section(y + 6, "Coming up")
		for u in upcoming_cache:
			var rr := _row_rect(y, 56)
			if _visible(rr):
				_rr(rr, Color(C_CARD, 0.5), 12)
				cv.draw_rect(Rect2(rr.position.x, rr.position.y + 10, 4, rr.size.y - 20), Color(CAT_COLOR.get(u.cat, C_MUTED), 0.4))
				_text(rr.position + Vector2(14, 22), _fit(String(u.name), 15, rr.size.x - 28), 15, C_DIM)
				_text(rr.position + Vector2(14, 43), _fit("Unlocks at: " + E.req_text(u), 13, rr.size.x - 28), 13, C_DIM)
			y += 62
	return y


func _draw_upgrade_row(r: Rect2, u: Dictionary) -> void:
	var cc: Color = CAT_COLOR.get(u.cat, C_MUTED)
	var can := float(u.cost) <= E.cash
	_rr(r, C_CARD, 12)
	cv.draw_rect(Rect2(r.position.x, r.position.y + 10, 4, r.size.y - 20), cc)
	var tw := r.size.x - 150
	_text(r.position + Vector2(14, 16), String(CAT_LABEL.get(u.cat, u.cat)).to_upper(), 10, Color(cc, 0.85))
	_text(r.position + Vector2(14, 36), _fit(String(u.name), 16, tw), 16)
	_text(r.position + Vector2(14, 56), _fit(E.effect_text(u.eff), 13, tw), 13, C_MUTED)
	var g := upgrade_gain(u)
	if g > 0.0005:
		_text(r.position + Vector2(14, 72), "+" + _pct(g) + " income", 12, C_GREEN)
	elif g < -0.0005:
		_text(r.position + Vector2(14, 72), _pct(g) + " income now", 12, C_ORANGE)
	if u.cat == "cross" and int(u.excl) >= 0:
		var other: Dictionary = E.upgrades[int(u.excl)]
		_text(r.position + Vector2(14, 88 - 2), _fit("Locks out: " + String(other.name) + " (this run)", 12, tw), 12, C_ORANGE)
	var br := Rect2(r.end.x - 124, r.position.y + 12, 114, r.size.y - 24)
	_button("upg:%d" % int(u.id), br, Econ.fmt_money(float(u.cost)), "buy" if can else "", "content", false, can, 16)


# ------------------------------------------------------------------ franchise tab

func _draw_franchise(y: float) -> float:
	var a := E.agg()
	if not E.franchise_unlocked():
		var r := _row_rect(y, 120)
		_rr(r, C_CARD, 12)
		_text(r.position + Vector2(16, 34), "Franchising", 20)
		var need := Econ.cp(1.0e7)
		var lines := _wrap("Earn %s this run to start selling franchises. Each location pays royalties that multiply ALL your income." % Econ.fmt_money(need), 14, r.size.x - 32)
		for i in lines.size():
			_text(r.position + Vector2(16, 60 + i * 19), lines[i], 14, C_MUTED)
		var bar := Rect2(r.position.x + 16, r.end.y - 16, r.size.x - 32, 6)
		cv.draw_rect(bar, Color(1, 1, 1, 0.08))
		cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(E.run_earned / need, 0.0, 1.0), 6)), C_PURPLE)
		return r.end.y + 8
	var fr := E.franchise_mult(a)
	var head := _row_rect(y, 62)
	_rr(head, C_CARD_HI, 12)
	_text(head.position + Vector2(16, 26), "%d locations" % E.locations(), 18)
	_text(head.position + Vector2(16, 48), "Royalties multiply all income (1 + total %)", 13, C_MUTED)
	_text_r(head.end.x - 16, head.position.y + 38, "x" + Econ.fmt_num(fr), 24, C_PURPLE)
	y = head.end.y + 10
	y = _section(y, "Cities", "royalty x%s" % Econ.fmt_num(E.royalty_mult(a)))
	var shown_locked := false
	for i in E.NC:
		var unlocked := E.city_unlocked(i)
		if not unlocked and int(E.cities[i]) == 0:
			if shown_locked:
				break
			shown_locked = true
		var r := _row_rect(y, 70)
		if _visible(r):
			_draw_city_row(r, i, unlocked, a)
		y += 76
	# ventures
	y = _section(y + 6, "Ventures", "")
	if not E.ventures_unlocked():
		var r := _row_rect(y, 64)
		_rr(r, Color(C_CARD, 0.6), 12)
		_text(r.position + Vector2(16, 26), "Side businesses", 17, C_DIM)
		_text(r.position + Vector2(16, 48), "Own 15 franchise locations to unlock (%d/15)" % E.locations(), 13, C_DIM)
		return r.end.y + 8
	var shown_v := false
	for i in E.NV:
		var unlocked := E.vent_unlocked(i)
		if not unlocked and int(E.vents[i]) == 0:
			if shown_v:
				break
			shown_v = true
		var r := _row_rect(y, 70)
		if _visible(r):
			_draw_vent_row(r, i, unlocked, a)
		y += 76
	return y


func _draw_city_row(r: Rect2, i: int, unlocked: bool, a: Dictionary) -> void:
	var n := int(E.cities[i])
	_rr(r, C_CARD if unlocked else Color(C_CARD, 0.5), 12)
	var nm: String = Econ.CITY_NAMES[i]
	_text(r.position + Vector2(14, 26), nm, 17, C_INK if unlocked else C_DIM)
	if n > 0:
		_text(r.position + Vector2(20 + _tw(nm, 17), r.position.y + 26), "x%d" % n, 15, C_PURPLE)
	if not unlocked:
		_text(r.position + Vector2(14, 50), "Scout it: earn %s this run" % Econ.fmt_money(Econ.cp(float(E.city_cost[i])) * 0.05), 13, C_DIM)
		return
	var each := 0.1 * E.royalty_mult(a) * float(E.city_yield[i]) * float(a.city[i])
	var nxt := -1
	for m in Econ.CITY_MILESTONES:
		if n < m:
			nxt = m
			break
	var sub := "+%s%% royalties each" % Econ.fmt_num(each * 100.0)
	if nxt > 0:
		sub += " · %d: bonus" % nxt
	_text(r.position + Vector2(14, 50), _fit(sub, 13, r.size.x - 150), 13, C_MUTED)
	var cost := E.city_next_cost(i)
	var can := cost <= E.cash
	var co: Array = E.cities.duplicate()
	co[i] = n + 1
	var g := float(E.income_info(a, {}, co).total) / maxf(inc_cache, 1e-300) - 1.0
	if g > 0.0005:
		_text(r.position + Vector2(14, 66), "+" + _pct(g) + " income", 11, C_GREEN)
	var br := Rect2(r.end.x - 124, r.position.y + 10, 114, r.size.y - 20)
	_button("city:%d" % i, br, "Open\n" + Econ.fmt_money(cost), "buy" if can else "", "content", true, can, 16)


func _draw_vent_row(r: Rect2, i: int, unlocked: bool, a: Dictionary) -> void:
	var v: Dictionary = Econ.VENTURES[i]
	var n := int(E.vents[i])
	_rr(r, C_CARD if unlocked else Color(C_CARD, 0.5), 12)
	_text(r.position + Vector2(14, 26), String(v.name), 17, C_INK if unlocked else C_DIM)
	if n > 0:
		_text(r.position + Vector2(20 + _tw(String(v.name), 17), r.position.y + 26), "Lv %d" % n, 15, Color("6ad1c0"))
	if not unlocked:
		_text(r.position + Vector2(14, 50), "Unlock: earn %s this run" % Econ.fmt_money(Econ.cp(float(E.vent_cost[i])) * 0.05), 13, C_DIM)
		return
	var sname: String = Econ.STAT_NAME[v.stat]
	_text(r.position + Vector2(14, 50), _fit("%s x%s" % [sname, Econ.fmt_mult(snappedf(E.vent_effect(i, a), 0.01))], 13, r.size.x - 150), 13, C_MUTED)
	var cost := E.vent_next_cost(i)
	var can := cost <= E.cash
	var br := Rect2(r.end.x - 124, r.position.y + 10, 114, r.size.y - 20)
	_button("vent:%d" % i, br, "Level up\n" + Econ.fmt_money(cost), "buy" if can else "", "content", true, can, 16)


# ------------------------------------------------------------------ legacy tab

func _draw_legacy(y: float) -> float:
	var a := E.agg()
	var r := _row_rect(y, 196)
	_rr(r, C_CARD_HI, 14)
	_star(r.position + Vector2(34, 38), 20, C_ACCENT)
	_text(r.position + Vector2(64, 34), _stars_label(E.stars), 22, C_ACCENT)
	_text(r.position + Vector2(64, 54), "Income x%s from stars" % Econ.fmt_num(E.star_mult(a)), 14, C_MUTED)
	var pend := E.stars_pending()
	var lines := _wrap("Sell the company to an investor for stars. You restart from a single diner, keeping your stars and Legacy perks. Each star adds +%s%% income." % Econ.fmt_mult(snappedf((Econ.STAR_BASE + float(a.starpow)) * 100.0, 0.01)), 13, r.size.x - 32)
	for i in lines.size():
		_text(r.position + Vector2(16, 82 + i * 18), lines[i], 13, C_MUTED)
	var br := Rect2(r.position.x + 16, r.end.y - 62, r.size.x - 32, 48)
	if pend >= 1.0:
		_button("sell", br, "Sell company: +" + _stars_label(pend), "accent", "content", false, true, 17)
	else:
		var next := 1.0 + E.stars_earned
		var need := pow(pow(next / 10.0, 5.0) * 1.0e10, Econ.COST_POW)
		_button("noop", br, "Earn %s total for your first star" % Econ.fmt_money(need) if E.stars_earned < 1 else "Earn more to sell", "", "content", false, false, 15)
	y = r.end.y + 12
	y = _section(y, "Legacy perks", "%d / 80 owned" % E.legacy.size())
	# next tier of each legacy line
	var shown := {}
	for u in E.upgrades:
		if not u.legacy:
			continue
		var kind := String(u.req[1])
		if shown.has(kind) or E.legacy.has(int(u.id)):
			continue
		shown[kind] = true
		var rr := _row_rect(y, 70)
		if _visible(rr):
			var can := E.legacy_available(u) and float(u.star) <= E.stars
			_rr(rr, C_CARD, 12)
			cv.draw_rect(Rect2(rr.position.x, rr.position.y + 10, 4, rr.size.y - 20), C_ACCENT)
			_text(rr.position + Vector2(14, 28), _fit(String(u.name), 16, rr.size.x - 150), 16)
			_text(rr.position + Vector2(14, 50), _fit(E.effect_text(u.eff), 13, rr.size.x - 150), 13, C_MUTED)
			var b := Rect2(rr.end.x - 124, rr.position.y + 12, 114, rr.size.y - 24)
			_button("legacy:%d" % int(u.id), b, _stars_label(float(u.star)), "accent" if can else "", "content", false, can, 15)
		y += 76
	if shown.is_empty():
		var rr := _row_rect(y, 50)
		_text_c(rr, rr.position.y + 30, "Every perk owned. Legendary.", 15, C_ACCENT)
		y += 56
	return y


func _stars_label(n: float) -> String:
	return "%s star%s" % [Econ.fmt_num(n), "" if n == 1.0 else "s"]


# ------------------------------------------------------------------ more tab

func _draw_more(y: float) -> float:
	var a := E.agg()
	y = _section(y, "Managers")
	var any := false
	for k in ["auto_price", "auto_ads", "auto_tables", "auto_cooks", "auto_recipes", "auto_upg"]:
		if not a.flags.has(k):
			continue
		any = true
		var r := _row_rect(y, 52)
		if _visible(r):
			_rr(r, C_CARD, 12)
			var on: bool = E.automation_active(k) if k != "auto_price" else E.price_auto
			_text(r.position + Vector2(14, 32), Econ.FLAG_TEXT[k], 15, C_INK)
			var id: String = "price_auto" if k == "auto_price" else "auto:" + k
			_button(id, Rect2(r.end.x - 74, r.position.y + 9, 64, 34), "ON" if on else "OFF", "buy" if on else "ghost", "content", false, true, 14)
		y += 58
	if not any:
		var r := _row_rect(y, 48)
		_rr(r, Color(C_CARD, 0.5), 12)
		_text(r.position + Vector2(14, 30), "Hire managers in Upgrades to automate.", 14, C_DIM)
		y += 54
	y = _section(y + 6, "Stats")
	var cc: Dictionary = Econ.CONCEPT[E.concept]
	var stats := [
		["Concept", String(cc.name)],
		["Income", Econ.fmt_money(inc_cache) + "/s"],
		["Ticket per guest", Econ.fmt_money(float(info_cache.get("ticket", 0.0)) * float(info_cache.get("price", 1.0)))],
		["Served per second", Econ.fmt_num(float(info_cache.get("served", 0.0)))],
		["Earned this run", Econ.fmt_money(E.run_earned)],
		["Earned all time", Econ.fmt_money(E.life_earned)],
		["Best income", Econ.fmt_money(E.best_income) + "/s"],
		["Upgrades owned", "%d (+%d legacy)" % [E.owned.size(), E.legacy.size()]],
		["Companies sold", str(E.prestiges)],
		["Serves tapped", str(E.taps)],
		["Run time", Econ.fmt_time(E.run_time)],
		["Play time", Econ.fmt_time(E.play_time)],
		["Offline earnings", "%d%% for up to %dh" % [int(round(float(a.offline) * 100.0)), int(a.offhours)]],
	]
	var sr := _row_rect(y, 14 + stats.size() * 26)
	_rr(sr, C_CARD, 12)
	for i in stats.size():
		var yy := sr.position.y + 28 + i * 26
		_text(Vector2(sr.position.x + 14, yy), String(stats[i][0]), 14, C_MUTED)
		_text_r(sr.end.x - 14, yy, String(stats[i][1]), 14, C_INK)
	y = sr.end.y + 12
	y = _section(y, "How to play")
	var help := [
		"Income = guests served x bill x price. Guests come from Ads, are seated at Tables and fed by Line Cooks. The smallest of those is your bottleneck (red LIMIT).",
		"Recipes raise every bill. Prices turn a long queue into profit, but too high and guests leave.",
		"Crossroads upgrades come in pairs: picking one locks the other until you sell.",
		"Franchises multiply everything. Sell the company for stars to restart stronger, and try a new concept.",
	]
	for h in help:
		var lines := _wrap(h, 14, content_r.size.x - 48)
		for l in lines:
			_text(Vector2(content_r.position.x + 18, y + 16), l, 14, C_MUTED)
			y += 19
		y += 8
	var rb := _row_rect(y + 8, 44)
	_button("reset", rb, "Erase save and start over", "ghost", "content", false, true, 14)
	return rb.end.y + 8


# =================================================================== draw: overlay

func _draw_overlay() -> void:
	cv = overlay
	var vs := get_viewport_rect().size
	for f in floaters:
		var t: float = f.t
		var a := clampf(1.3 - t * 1.2, 0.0, 1.0)
		var p: Vector2 = f.pos + Vector2(0, -t * 46.0)
		var s: String = f.text
		_text(p - Vector2(_tw(s, 18) * 0.5, 0) + Vector2(1, 1), s, 18, Color(0, 0, 0, a * 0.6))
		_text(p - Vector2(_tw(s, 18) * 0.5, 0), s, 18, Color(f.color, a))
	if toast_t > 0.0 and toast != "":
		var a := clampf(toast_t / 0.3, 0.0, 1.0)
		var tw := _tw(toast, 16) + 36
		var tr := Rect2((vs.x - tw) * 0.5, nav_r.position.y - 56, tw, 40)
		_rr(tr, Color(0.07, 0.05, 0.04, 0.94 * a), 20)
		_text_c(tr, tr.position.y + 26, toast, 16, Color(C_INK, a))
	if modal == "":
		return
	cv.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.72))
	_btn("noop", Rect2(Vector2.ZERO, vs), "modal")
	match modal:
		"concept": _modal_concept(vs)
		"sell": _modal_sell(vs)
		"welcome": _modal_welcome(vs)
		"reset": _modal_reset(vs)
		"help": _modal_help(vs)


func _modal_card(vs: Vector2, h: float) -> Rect2:
	var w := minf(vs.x - 24, 480)
	return Rect2((vs.x - w) * 0.5, maxf(12.0, (vs.y - h) * 0.5), w, h)


func _modal_concept(vs: Vector2) -> void:
	var n := Econ.CONCEPTS.size()
	var ch := 92.0
	var h := 96.0 + n * (ch + 8)
	var r := _modal_card(vs, h)
	_rr(r, C_BG, 16, C_LINE, 1)
	var g := float(modal_data.get("stars", 0.0))
	var title := "Sold! +" + _stars_label(g) if g > 0.0 else "Open your first restaurant"
	_text_c(r, r.position.y + 36, title, 22, C_ACCENT if g > 0.0 else C_INK)
	_text_c(r, r.position.y + 62, "Choose a concept for this run", 14, C_MUTED)
	var y := r.position.y + 80
	for c in Econ.CONCEPTS:
		var cc: Dictionary = Econ.CONCEPT[c]
		var cr := Rect2(r.position.x + 12, y, r.size.x - 24, ch)
		var ok := E.concept_unlocked(c)
		var col_c := Color(String(cc.color))
		_rr(cr, C_CARD if ok else Color(C_CARD, 0.5), 12, col_c if ok else C_LINE, 2 if ok else 1)
		_text(cr.position + Vector2(16, 28), String(cc.name), 19, col_c if ok else C_DIM)
		if not ok:
			var need := int(cc.unlock)
			_text_r(cr.end.x - 14, cr.position.y + 28, "Sell %d time%s to unlock" % [need, "" if need == 1 else "s"], 12, C_DIM)
		var lines := _wrap(String(cc.blurb), 13, cr.size.x - 32)
		for i in mini(lines.size(), 2):
			_text(cr.position + Vector2(16, 50 + i * 18), lines[i], 13, C_MUTED if ok else C_DIM)
		var tags := "Price limit x%s · Price sensitivity %s" % [Econ.fmt_mult(float(cc.ceiling)), "low" if float(cc.elastic) < 1.9 else ("high" if float(cc.elastic) > 2.1 else "normal")]
		_text(cr.position + Vector2(16, cr.size.y - 8), tags, 11, C_DIM)
		if ok:
			_btn("concept:" + c, cr, "modal")
		y += ch + 8


func _modal_sell(vs: Vector2) -> void:
	var r := _modal_card(vs, 300)
	_rr(r, C_BG, 16, C_LINE, 1)
	var g := E.stars_pending()
	_star(Vector2(r.get_center().x, r.position.y + 44), 22, C_ACCENT)
	_text_c(r, r.position.y + 96, "Sell the company?", 22)
	_text_c(r, r.position.y + 126, "+" + _stars_label(g), 20, C_ACCENT)
	var after := 1.0 + (E.stars + g) * (Econ.STAR_BASE + float(E.agg().starpow))
	var lines := _wrap("Your restaurant, builds, upgrades, franchises and ventures reset. You keep stars and Legacy perks. Star bonus becomes x%s." % Econ.fmt_num(after), 14, r.size.x - 40)
	for i in lines.size():
		_text_c(r, r.position.y + 156 + i * 19, lines[i], 14, C_MUTED)
	var bw := (r.size.x - 44) * 0.5
	_button("close", Rect2(r.position.x + 16, r.end.y - 64, bw, 48), "Keep going", "", "modal", false, true, 16)
	_button("sell_yes", Rect2(r.position.x + 28 + bw, r.end.y - 64, bw, 48), "Sell", "accent", "modal", false, true, 17)


func _modal_welcome(vs: Vector2) -> void:
	var r := _modal_card(vs, 220)
	_rr(r, C_BG, 16, C_LINE, 1)
	_text_c(r, r.position.y + 42, "Welcome back!", 22)
	_text_c(r, r.position.y + 72, "Away for %s" % Econ.fmt_time(float(modal_data.get("away", 0.0))), 14, C_MUTED)
	_text_c(r, r.position.y + 112, "+" + Econ.fmt_money(float(modal_data.get("gain", 0.0))), 28, C_GREEN)
	_text_c(r, r.position.y + 136, "earned by the night shift", 13, C_MUTED)
	_button("close", Rect2(r.position.x + 16, r.end.y - 62, r.size.x - 32, 46), "Collect", "buy", "modal", false, true, 17)


func _modal_reset(vs: Vector2) -> void:
	var r := _modal_card(vs, 210)
	_rr(r, C_BG, 16, C_LINE, 1)
	_text_c(r, r.position.y + 44, "Erase everything?", 22, C_RED)
	var lines := _wrap("This deletes your save, including stars and Legacy perks. It can't be undone.", 14, r.size.x - 40)
	for i in lines.size():
		_text_c(r, r.position.y + 76 + i * 19, lines[i], 14, C_MUTED)
	var bw := (r.size.x - 44) * 0.5
	_button("close", Rect2(r.position.x + 16, r.end.y - 64, bw, 48), "Cancel", "", "modal", false, true, 16)
	_button("reset_yes", Rect2(r.position.x + 28 + bw, r.end.y - 64, bw, 48), "Erase", "red", "modal", false, true, 16)


func _modal_help(vs: Vector2) -> void:
	var inf := info_cache
	var r := _modal_card(vs, 360)
	_rr(r, C_BG, 16, C_LINE, 1)
	_text_c(r, r.position.y + 38, "Your bottleneck", 21)
	var txt := [
		"Guests %s/s want a table (Ads bring more; higher prices drive some away)." % Econ.fmt_num(float(inf.get("want", 0.0))),
		"Seats %s/s and Kitchen %s/s cap how many you can serve." % [Econ.fmt_num(float(inf.get("seating", 0.0))), Econ.fmt_num(float(inf.get("kitchen", 0.0)))],
		"You serve %s/s. Each pays %s." % [Econ.fmt_num(float(inf.get("served", 0.0))), Econ.fmt_money(float(inf.get("ticket", 0.0)) * float(inf.get("price", 1.0)))],
		"Spend on whatever says LIMIT. Spending elsewhere is mostly wasted until the limit moves.",
	]
	var y := r.position.y + 70
	for t in txt:
		for l in _wrap(t, 14, r.size.x - 40):
			_text(Vector2(r.position.x + 20, y), l, 14, C_MUTED)
			y += 19
		y += 8
	_button("close", Rect2(r.position.x + 16, r.end.y - 62, r.size.x - 32, 46), "Got it", "", "modal", false, true, 16)


# =================================================================== agent hooks

func get_agent_state() -> Dictionary:
	return {
		"cash": E.cash, "income": inc_cache, "tab": tab, "modal": modal, "concept": E.concept,
		"reps": E.reps.duplicate(), "owned": E.owned.size(), "legacy": E.legacy.size(), "upgrades_total": E.upgrades.size(),
		"available": vis_cache.size(), "affordable": afford_count, "locations": E.locations(), "stars": E.stars,
		"pending_stars": E.stars_pending(), "prestiges": E.prestiges, "limit": String(info_cache.get("limit", "")),
		"price": float(info_cache.get("price", 1.0)), "scroll": scroll[tab], "scroll_max": scroll_max.get(tab, 0.0),
	}


func dev_add_cash(v: float) -> void:
	E.cash += v
	E.run_earned += v
	E.life_earned += v
	_refresh_cache(true)


func dev_skip(seconds: float) -> void:
	var step := maxf(1.0, seconds / 200.0)
	var t := 0.0
	while t < seconds:
		E.tick(step)
		E.run_automation()
		t += step
	_refresh_cache(true)


## Press a button by id, as a tap would.
func press_button(id: String) -> void:
	_do(id)
