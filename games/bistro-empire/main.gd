extends Node2D
## Bistro Empire: an incremental restaurant tycoon. Mobile-first, portrait, drawn immediate-mode.
## Economy rules live in econ.gd; this file is input, layout, drawing and saving.

## Away longer than this (tab hidden, phone locked, app switched) counts as offline time.
const AWAY_OFFLINE := 60.0
## Gaps shorter than this are just slow frames.
const AWAY_MIN := 2.0
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
	"business": Color("ffcf6e"), "grit": Color("ff8a5c"),
}
const CAT_LABEL := {
	"demand": "Demand", "seating": "Seating", "kitchen": "Kitchen", "ticket": "Menu", "global": "Ambience",
	"cost": "Savings", "tap": "Serving", "ceiling": "Brand", "auto": "Manager", "offline": "Night shift",
	"royalty": "Franchise", "city": "City", "venture": "Venture", "concept": "Signature", "cross": "Crossroads",
	"business": "Business",
}
const TABS := ["build", "upgrades", "business", "franchise", "legacy", "more"]
const TAB_LABEL := {"build": "Build", "upgrades": "Upgrades", "business": "Business", "franchise": "Franchise", "legacy": "Legacy", "more": "More"}
const BUY_MODES := [1, 10, 100, -1]
const UPG_FILTERS := ["all", "afford", "stats", "business", "growth", "cross"]
const UPG_FILTER_LABEL := {"all": "All", "afford": "Can buy", "stats": "Stats", "business": "Business", "growth": "Growth", "cross": "Crossroads"}
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
var em_cache := {}
var biz_page := -1               # which business's page is open on the Business tab (-1 = the list)
var glob_vis: Array = []         # visible upgrades outside any one business
var biz_vis: Array = []          # visible upgrades per business
var biz_afford_count := 0
var truck_x := -1.0
var price_hist: Array = []
var price_hist_t := 0.0
const C_GRIT := Color("ff8a5c")
var info_cache := {}
var afford_count := 0
var last_saved_unix := 0
var loaded_offline := false
var store := SaveStore.new()
var save_ready := false          # never write before the existing save has been read
var life_floor := 0.0            # lifetime earnings of the loaded save; a save below it is refused
var last_frame_unix := 0.0
var _js_cbs: Array = []          # keep JS callbacks alive
var import_text := ""


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
	store.request_persistence()
	if not load_game():
		E.new_game()
	save_ready = true
	last_frame_unix = Time.get_unix_time_from_system()
	_hook_page_events()
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
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		if E != null:
			_catch_up()


## The browser stops running the game while the tab is hidden, so save the moment it hides.
## pagehide/visibilitychange fire even on mobile when switching apps or locking the phone.
func _hook_page_events() -> void:
	if not OS.has_feature("web"):
		return
	var cb := JavaScriptBridge.create_callback(_on_page_hidden)
	_js_cbs.append(cb)
	var win = JavaScriptBridge.get_interface("window")
	win.__beHidden = cb
	JavaScriptBridge.eval("""(function(){
		document.addEventListener('visibilitychange',function(){if(document.visibilityState==='hidden'){window.__beHidden();}});
		window.addEventListener('pagehide',function(){window.__beHidden();});
		window.addEventListener('blur',function(){window.__beHidden();});
	})()""", true)


func _on_page_hidden(_args: Array) -> void:
	if E != null and save_ready:
		save_game()


## Credits time that passed while the game wasn't running (hidden tab, locked phone).
func _catch_up() -> void:
	var now := Time.get_unix_time_from_system()
	var gap := now - last_frame_unix
	last_frame_unix = now
	if gap < AWAY_MIN or not save_ready or not E.concept_chosen or modal == "concept":
		return
	if gap <= AWAY_OFFLINE:
		E.tick(gap, false)
		_refresh_cache(false)
		return
	var g := E.offline_gain(gap)
	if g > 0.0:
		_credit_away(gap, g)
	save_game()


func _credit_away(away: float, g: float) -> void:
	E.cash = minf(E.cash + g, Econ.MAX_MONEY)
	E.run_earned += g
	E.life_earned += g
	if modal == "welcome":
		modal_data = {"away": float(modal_data.get("away", 0.0)) + away, "gain": float(modal_data.get("gain", 0.0)) + g}
	elif modal == "":
		open_modal("welcome", {"away": away, "gain": g})
	else:
		_toast("Away %s: +%s" % [Econ.fmt_time(away), Econ.fmt_money(g)])
	_refresh_cache(true)


func _process(delta: float) -> void:
	_catch_up()
	delta = minf(delta, 1.0)
	anim_t += delta
	if E.concept_chosen and modal != "concept":
		E.events_on = modal == ""
		E.tick(delta)
	if not E.last_bankrupt.is_empty():
		var lb: Dictionary = E.last_bankrupt
		E.last_bankrupt = {}
		for t in TABS:
			scroll[t] = 0.0
		tab = "build"
		open_modal("bankrupt", lb)
		_refresh_cache(true)
		save_game()
	while not E.notes.is_empty():
		_toast(String(E.notes.pop_front()))
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
	price_hist_t += delta
	if price_hist_t >= 1.0:
		price_hist_t = 0.0
		for i in Biz.N:
			if String(Biz.DEFS[i].id) == "wholesale" and bool(E.biz[i].open):
				price_hist.append(float(E.biz[i].mprice))
				if price_hist.size() > 90:
					price_hist.pop_front()
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
	em_cache = E.empire()
	inc_cache = float(em_cache.net)
	vis_cache = E.visible_upgrades()
	glob_vis = []
	biz_vis = []
	for i in Biz.N:
		biz_vis.append([])
	afford_count = 0
	biz_afford_count = 0
	for u in vis_cache:
		if u.has("biz"):
			(biz_vis[int(u.biz)] as Array).append(u)
			if E.upgrade_cost(u) <= E.cash:
				biz_afford_count += 1
			continue
		glob_vis.append(u)
		if E.upgrade_cost(u) <= E.cash:
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
	var cur := _profit(E.income_info(a))
	var nxt := _profit(E.income_info(E.copy_with(a, u.eff)))
	var g := nxt / maxf(cur, 1e-300) - 1.0 if cur > 0.0 else 0.0
	gain_cache[key] = g
	return g


func rep_gain(r: String, k: int) -> float:
	var a := E.agg()
	var cur := _profit(E.income_info(a))
	var nxt := _profit(E.income_info(a, {r: int(E.reps[r]) + k}))
	return nxt / maxf(cur, 1e-300) - 1.0 if cur > 0.0 else 0.0


## Restaurant profit, ignoring temporary closures so previews stay meaningful.
func _profit(inf: Dictionary) -> float:
	return float(inf.net)


func biz_buy_count(i: int, w: String) -> int:
	var m: int = BUY_MODES[buy_mode]
	if m > 0:
		return m
	return maxi(1, E.biz_max_affordable(i, w))


func biz_gain(i: int, w: String, k: int) -> float:
	var s: Dictionary = E.biz[i]
	var cur: Dictionary = Biz.estimate(i, s, E)
	var s2 := s.duplicate(true)
	s2[w] = int(s2[w]) + k
	var nxt: Dictionary = Biz.estimate(i, s2, E)
	return (float(nxt.rev) - float(nxt.cost)) - (float(cur.rev) - float(cur.cost))


func buy_count(r: String) -> int:
	var m: int = BUY_MODES[buy_mode]
	if m > 0:
		return m
	return maxi(1, E.rep_max_affordable(r))


# =================================================================== saving

func _state() -> Dictionary:
	var d := E.to_dict()
	d["ui"] = {"tab": tab, "buy_mode": buy_mode}
	return d


func save_game() -> void:
	save_t = 0.0
	if not save_ready:
		return
	# safety net: never let a bug overwrite a richer save with a poorer one
	if E.life_earned < life_floor * 0.999:
		push_error("refusing to save: lifetime earnings went down (%s < %s)" % [E.life_earned, life_floor])
		return
	var t := int(Time.get_unix_time_from_system())
	store.write(_state(), t, _now())
	life_floor = maxf(life_floor, E.life_earned)
	last_saved_unix = t


func load_game() -> bool:
	var pick := store.best()
	if pick.is_empty():
		if store.all_corrupt():
			store.quarantine(int(Time.get_unix_time_from_system()))
			_toast("Save unreadable: kept a copy, starting fresh")
		return false
	_apply_state(pick.state)
	var away := float(int(Time.get_unix_time_from_system()) - int(pick.t))
	if away > AWAY_OFFLINE and E.concept_chosen:
		var g := E.offline_gain(away)
		if g > 0.0:
			_credit_away(away, g)
			loaded_offline = true
	return true


func _apply_state(d: Dictionary) -> void:
	E.from_dict(d)
	life_floor = E.life_earned
	var ui: Dictionary = d.get("ui", {})
	if TABS.has(String(ui.get("tab", "build"))):
		tab = String(ui.get("tab", "build"))
	buy_mode = clampi(int(ui.get("buy_mode", 0)), 0, BUY_MODES.size() - 1)


func wipe_save() -> void:
	store.erase_all()
	life_floor = 0.0


# ------------------------------------------------------------------ backups

func export_code() -> String:
	return SaveStore.encode_code(SaveStore.pack(_state(), int(Time.get_unix_time_from_system())))


func copy_save_code() -> void:
	save_game()
	var code := export_code()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(function(t){
			var legacy=function(){try{var ta=document.createElement('textarea');ta.value=t;ta.setAttribute('readonly','');
				ta.style.cssText='position:fixed;top:0;left:0;opacity:0;';document.body.appendChild(ta);ta.select();
				var ok=document.execCommand('copy');document.body.removeChild(ta);var c=document.querySelector('canvas');if(c){c.focus();}return ok;}catch(e){return false;}};
			var ask=function(){try{window.prompt('Copy your save code and keep it somewhere safe:',t);}catch(e){}};
			if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).then(function(){},function(){if(!legacy()){ask();}});}
			else if(!legacy()){ask();}
		})(%s)""" % JSON.stringify(code), true)
	else:
		DisplayServer.clipboard_set(code)
	_toast("Save code copied")


func download_backup() -> void:
	save_game()
	var code := export_code()
	var name := "bistro-empire-%s.txt" % Time.get_date_string_from_system()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(code.to_utf8_buffer(), name, "text/plain")
	else:
		var f := FileAccess.open("user://" + name, FileAccess.WRITE)
		if f:
			f.store_string(code)
			f.close()
	_toast("Backup file saved")


func ask_import() -> void:
	var code := ""
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("(function(){try{return window.prompt('Paste a Bistro Empire save code:','')||'';}catch(e){return '';}})()", true)
		code = r if r is String else ""
	else:
		code = DisplayServer.clipboard_get()
	if code.strip_edges() == "":
		return
	preview_import(code)


## Validates a code and asks for confirmation. Returns false if the code is unusable.
func preview_import(code: String) -> bool:
	var text := SaveStore.decode_code(code)
	var u := SaveStore.unpack(text)
	if u.is_empty():
		_toast("That save code isn't valid")
		return false
	import_text = text
	var st: Dictionary = u.state
	open_modal("import", {"stars": float(st.get("stars", 0.0)), "life": float(st.get("life_earned", 0.0)),
		"cash": float(st.get("cash", 0.0)), "t": int(u.t)})
	return true


func confirm_import() -> void:
	var u := SaveStore.unpack(import_text)
	if u.is_empty():
		return
	store.keep_before_import(SaveStore.pack(_state(), int(Time.get_unix_time_from_system())))
	_apply_state(u.state)
	life_floor = E.life_earned
	import_text = ""
	modal = ""
	if not E.concept_chosen:
		open_modal("concept")
	_refresh_cache(true)
	save_game()
	_toast("Save imported")


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
		if t == "business" and tab == "business" and biz_page >= 0:
			biz_page = -1
			scroll["business"] = 0.0
		tab = t
		scroll_vel = 0.0


func _on_biz_page() -> bool:
	return tab == "business" and biz_page >= 0 and biz_page < Biz.N and bool(E.biz[biz_page].open)


func open_biz_page(i: int) -> void:
	tab = "business"
	biz_page = i
	scroll["business"] = 0.0
	scroll_vel = 0.0
	truck_x = -1.0
	price_hist = []


## Tapping a business's scene sells by hand: half a second of its sales, at least a quarter of a restaurant tap.
func biz_tap(i: int, at: Vector2 = Vector2.ZERO) -> void:
	if not E.concept_chosen or not bool(E.biz[i].open):
		return
	var v := E.biz_tap(i)
	serve_bump = 1.0
	if at == Vector2.ZERO:
		at = scene_r.get_center()
	floaters.append({"pos": at + Vector2(randf_range(-20, 20), -10), "text": "+" + Econ.fmt_money(v), "t": 0.0, "color": Color(String(Biz.DEFS[i].color))})


func _toast(s: String) -> void:
	toast = s
	toast_t = 2.2 + minf(2.0, s.length() / 30.0)


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
				if u.cat != "cross" and not u.has("biz") and E.upgrade_cost(u) <= E.cash and E.buy_upgrade(int(u.id)):
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
		"copy_code": copy_save_code()
		"download": download_backup()
		"import": ask_import()
		"import_yes": confirm_import()
		"save_now":
			save_game()
			_toast("Saved")
		"reset_yes":
			wipe_save()
			E.new_game()
			tab = "build"
			for t in TABS:
				scroll[t] = 0.0
			open_modal("concept")
			_refresh_cache(true)
		"help": open_modal("help")
		"event":
			var ev_title := String(E.event.get("title", ""))
			var line := E.answer_event(int(parts[1]))
			if line != "":
				_toast("%s: %s" % [ev_title, line])
			_refresh_cache(true)
		"borrow":
			var amt := E.credit_available() * float(parts[1])
			var got := E.borrow(amt)
			if got > 0.0:
				_toast("Borrowed %s" % Econ.fmt_money(got))
			_refresh_cache(true)
		"rescue":
			var got := E.borrow(-E.cash * 1.05 + 1.0)
			if got > 0.0:
				_toast("Emergency loan: %s" % Econ.fmt_money(got))
			_refresh_cache(true)
		"repay":
			var amt := E.debt * float(parts[1])
			var paid := E.repay(amt)
			if paid > 0.0:
				_toast("Repaid %s" % Econ.fmt_money(paid))
			_refresh_cache(true)
		"biz_open":
			if E.open_biz(int(parts[1])):
				_toast("%s is open!" % Biz.DEFS[int(parts[1])].name)
				open_biz_page(int(parts[1]))
				_refresh_cache(true)
		"biz_page": open_biz_page(int(parts[1]))
		"biz_back":
			biz_page = -1
			scroll["business"] = 0.0
		"auto_biz":
			var key := "auto_" + String(Biz.DEFS[int(parts[1])].id)
			E.auto_on[key] = not E.automation_active(key)
		"biz":
			var i := int(parts[1])
			var w: String = parts[2]
			if E.buy_biz(i, w, biz_buy_count(i, w)):
				_refresh_cache(true)
		"bizupg":
			var n := 0
			for u in _biz_upgrades(int(parts[1])):
				if E.upgrade_cost(u) <= E.cash and E.buy_upgrade(int(u.id)):
					n += 1
			if n > 0:
				_toast("Bought %d upgrade%s" % [n, "" if n == 1 else "s"])
			_refresh_cache(true)
		"spot":
			if Biz.move_truck(E.biz[int(parts[1])], int(parts[2])):
				_toast("Driving to %s..." % Biz.SPOTS[int(parts[2])])
		"accept":
			if Biz.accept(E.biz[int(parts[1])], int(parts[2])):
				_toast("Contract accepted")
			else:
				_toast("Not enough free crew or vans")
		"happy":
			var s2: Dictionary = E.biz[int(parts[1])]
			s2.happy = not bool(s2.happy)
			_toast("Happy hour ON: more drinks, rowdier crowd" if s2.happy else "Happy hour OFF")
			_refresh_cache(false)
		"rate":
			var hs: Dictionary = E.biz[int(parts[1])]
			match String(parts[2]):
				"up": hs.rate = minf(20.0, float(hs.rate) * 1.1); hs.rate_auto = false
				"down": hs.rate = maxf(0.2, float(hs.rate) / 1.1); hs.rate_auto = false
				"auto": hs.rate_auto = not bool(hs.rate_auto)
			_refresh_cache(false)
		"ws_sell":
			var i := int(parts[1])
			var v := Biz.sell_stock(i, E.biz[i], E)
			E.cash += v
			E.run_earned += v
			E.life_earned += v
			E.biz[i].earned = float(E.biz[i].earned) + v
			_toast("Sold for %s" % Econ.fmt_money(v))
		"ws_auto":
			var ws: Dictionary = E.biz[int(parts[1])]
			ws.auto_sell = not bool(ws.auto_sell)
		"sell_loc":
			var v := E.sell_location()
			if v > 0.0:
				_toast("Sold a franchise: +%s" % Econ.fmt_money(v))
			_refresh_cache(true)
		"sell_biz": open_modal("sell_biz", {"i": int(parts[1])})
		"sell_biz_yes":
			var i := int(modal_data.get("i", -1))
			modal = ""
			if i >= 0:
				var v := E.sell_biz(i)
				_toast("Sold the %s: +%s" % [Biz.DEFS[i].name, Econ.fmt_money(v)])
			_refresh_cache(true)
		"file": open_modal("file")
		"file_yes":
			modal = ""
			E.go_bankrupt()
		"after_bankrupt":
			modal = ""
			open_modal("concept", {"grit": float(modal_data.get("grit", 0.0))})
		"noop": pass


# =================================================================== input

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("serve") and modal == "":
		serve()
	elif ev.is_action_pressed("back"):
		if modal != "" and modal != "concept":
			modal = ""
		elif _on_biz_page():
			biz_page = -1
			scroll["business"] = 0.0
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
		if _on_biz_page():
			biz_tap(biz_page, p)
		else:
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
	if _on_biz_page():
		_draw_biz_scene(biz_page)
		_draw_biz_strip(biz_page)
	else:
		_draw_scene()
		_draw_strip()
	_draw_nav()


func _draw_header() -> void:
	var r := header_r
	var cc: Dictionary = Econ.CONCEPT[E.concept]
	var ccol := Color(String(cc.color))
	_text(Vector2(r.position.x, r.position.y + 14), ("BISTRO EMPIRE  ·  " + String(cc.name).to_upper()) if E.concept_chosen else "BISTRO EMPIRE", 12, ccol)
	var cash_s := Econ.fmt_money(E.cash)
	var red := E.in_red()
	_text(Vector2(r.position.x, r.position.y + 46), cash_s, 32, C_RED if red else C_INK)
	var net_s := ("+" if inc_cache >= 0.0 else "") + Econ.fmt_money(inc_cache) + "/s"
	_text(Vector2(r.position.x, r.position.y + 66), net_s, 16, C_GREEN if inc_cache >= 0.0 else C_RED)
	if E.debt > 0.0:
		var nx := r.position.x + _tw(net_s, 16) + 12
		_text(Vector2(nx, r.position.y + 66), "debt " + Econ.fmt_money(E.debt), 13, C_ORANGE)
	# stars badge
	var bw := 92.0
	var br := Rect2(r.end.x - bw, r.position.y + 4, bw, 40)
	_rr(br, C_CARD, 20)
	_star(br.position + Vector2(22, 20), 11, C_ACCENT)
	_text(br.position + Vector2(38, 27), Econ.fmt_num(E.stars), 18, C_ACCENT)
	_btn("tab:legacy", br)
	var pend := E.stars_pending()
	if E.grit > 0.0 or E.bankruptcies > 0:
		_text_r(r.end.x, r.position.y + 62, "%s grit" % Econ.fmt_num(E.grit), 13, C_GRIT)
	elif pend >= 1.0:
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
	# closed sign
	if bool(inf.get("closed", false)):
		var cs := Rect2(rr.get_center().x - 50, rr.position.y + rr.size.y * 0.42, 100, 30)
		_rr(cs, Color("2a0904"), 6, C_RED, 2)
		_text_c(cs, cs.position.y + 21, "CLOSED", 16, C_RED)
	# active event effects
	var fx_y := rr.position.y + 22
	for f in E.effects:
		var lab := _effect_label(f)
		var fw := _tw(lab, 11) + 14
		var fr2 := Rect2(rr.position.x + 8, fx_y, fw, 17)
		var good := _effect_good(f)
		_rr(fr2, Color(0, 0, 0, 0.6), 8, C_GREEN if good else C_RED, 1)
		_text(fr2.position + Vector2(7, 13), lab, 11, C_GREEN if good else Color("ffb0a6"))
		fx_y += 20
	# tap hint
	var tv := Econ.fmt_money(E.tap_value())
	var hint := "TAP TO SERVE  +" + tv
	var hw := _tw(hint, 13) + 18
	var hr := Rect2(rr.end.x - hw - 8, rr.end.y - 26, hw, 20)
	_rr(hr, Color(0, 0, 0, 0.45), 10)
	_text_c(hr, hr.position.y + 15, hint, 13, Color(C_ACCENT, 0.8 + 0.2 * sin(anim_t * 3.0)))


func _effect_good(f: Dictionary) -> bool:
	match String(f.kind):
		"food", "wages": return float(f.mult) < (0.0 if String(f.kind) == "food" else 1.0)
		"closed": return false
	return float(f.mult) >= 1.0


func _effect_label(f: Dictionary) -> String:
	var t := Econ.fmt_time(float(f.t))
	match String(f.kind):
		"closed": return "Closed %s" % t
		"food": return "Food +%d pts %s" % [int(f.mult), t]
		"wages": return "Upkeep x%s %s" % [Econ.fmt_mult(float(f.mult)), t]
		"income": return "Income x%s %s" % [Econ.fmt_mult(float(f.mult)), t]
	return "%s x%s %s" % [String(f.kind).capitalize().replace("Demand", "Guests"), Econ.fmt_mult(float(f.mult)), t]


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
		var locked := (t == "franchise" and not E.franchise_unlocked()) or (t == "business" and not E.biz_unlocked(0))
		var c := C_ACCENT if on else (C_DIM if locked else C_MUTED)
		_nav_icon(t, Vector2(br.get_center().x, br.position.y + 24), c, locked)
		_text_c(br, br.position.y + 52, TAB_LABEL[t], 12, c)
		if on:
			cv.draw_rect(Rect2(br.get_center().x - 16, r.position.y, 32, 3), C_ACCENT)
		var badge := 0
		if t == "upgrades":
			badge = afford_count
		elif t == "business":
			badge = biz_afford_count
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
		"business":
			cv.draw_rect(Rect2(c + Vector2(-11, -6), Vector2(22, 16)), col_, false, 2)
			cv.draw_rect(Rect2(c + Vector2(-5, -11), Vector2(10, 5)), col_, false, 2)
			cv.draw_line(c + Vector2(-11, 1), c + Vector2(11, 1), col_, 2)
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
	var y := _draw_alerts(y0)
	match tab:
		"build": y = _draw_build(y)
		"upgrades": y = _draw_upgrades(y)
		"business": y = _draw_business(y)
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
	y = _draw_pnl(y + 4)
	# a nudge when selling would be worth it
	var pend := E.stars_pending()
	if pend >= maxf(10.0, (E.stars + _legacy_spent()) * 0.5) and E.run_time > 1200.0:
		var hr := _row_rect(y + 4, 64)
		_rr(hr, Color(C_ACCENT, 0.12), 12, C_ACCENT, 1)
		_star(hr.position + Vector2(24, 32), 12, C_ACCENT)
		_text(hr.position + Vector2(44, 27), "Selling now: +%s" % _stars_label(pend), 16, C_ACCENT)
		var after := 1.0 + (E.stars + pend) * (Econ.STAR_BASE + float(a.starpow))
		_text(hr.position + Vector2(44, 48), _fit("Stars would multiply income by %s. Tap to sell." % Econ.fmt_mult(snappedf(after, 0.01)), 13, hr.size.x - 56), 13, C_MUTED)
		_btn("tab:legacy", hr, "content")
		y = hr.end.y + 8
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


func _legacy_spent() -> float:
	var n := 0.0
	for id in E.legacy:
		var u: Dictionary = E.upgrades[id]
		if E.currency(u) == "star":
			n += float(u.star)
	return n


func _draw_pnl(y: float) -> float:
	var em := em_cache
	if em.is_empty():
		return y
	var inf := info_cache
	var rows: Array = [
		["Restaurant sales", float(em.rest_rev), C_INK],
		["Food (%d%% of each plate)" % int(round(E.food_cost_pct())), -float(em.food), C_MUTED],
		["Rent on empty seats", -float(inf.get("rent", 0.0)), C_MUTED],
		["Wages for idle cooks", -float(inf.get("wages", 0.0)), C_MUTED],
		["Ads for guests turned away", -float(inf.get("marketing", 0.0)), C_MUTED],
	]
	if E.biz_open_count() > 0:
		rows.append(["Side businesses", float(em.biz_rev) - float(em.biz_cost), C_INK])
	if E.debt > 0.0:
		rows.append(["Loan interest", -float(em.interest), C_ORANGE])
	var h := 44 + rows.size() * 22 + 30
	var r := _row_rect(y, h)
	if not _visible(r):
		return r.end.y + 8
	_rr(r, C_CARD, 12)
	_text(r.position + Vector2(14, 26), "Profit & loss", 17)
	var pct := 100.0 * float(em.costs) / maxf(float(em.gross), 1e-300)
	_text_r(r.end.x - 14, r.position.y + 26, "costs %d%% of sales" % int(round(pct)), 12, C_DIM)
	var yy := r.position.y + 50
	for row in rows:
		var v := float(row[1])
		_text(Vector2(r.position.x + 14, yy), String(row[0]), 13, C_MUTED)
		_text_r(r.end.x - 14, yy, ("" if v >= 0.0 else "-") + Econ.fmt_money(absf(v)) + "/s", 13, row[2] if v >= 0.0 else Color("e99a8f"))
		yy += 22
	cv.draw_line(Vector2(r.position.x + 14, yy - 12), Vector2(r.end.x - 14, yy - 12), C_LINE, 1)
	_text(Vector2(r.position.x + 14, yy + 8), "Profit", 15, C_INK)
	var net := float(em.net)
	_text_r(r.end.x - 14, yy + 8, ("+" if net >= 0.0 else "-") + Econ.fmt_money(absf(net)) + "/s", 15, C_GREEN if net >= 0.0 else C_RED)
	return r.end.y + 8


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
	_text(r.position + Vector2(14 + _tw("Menu prices", 17) + 8, 25), "x" + Econ.fmt_mult(snappedf(p, 0.01)), 17, C_ACCENT)
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
	for u in glob_vis:
		match upg_filter:
			"afford":
				if E.upgrade_cost(u) > E.cash:
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
	var can := E.upgrade_cost(u) <= E.cash
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
	_button("upg:%d" % int(u.id), br, Econ.fmt_money(E.upgrade_cost(u)), "buy" if can else "", "content", false, can, 16)


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
		_text(r.position + Vector2(20 + _tw(nm, 17), 26), "x%d" % n, 15, C_PURPLE)
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
		_text(r.position + Vector2(20 + _tw(String(v.name), 17), 26), "Lv %d" % n, 15, Color("6ad1c0"))
	if not unlocked:
		_text(r.position + Vector2(14, 50), "Unlock: earn %s this run" % Econ.fmt_money(Econ.cp(float(E.vent_cost[i])) * 0.05), 13, C_DIM)
		return
	var sname: String = Econ.STAT_NAME[v.stat]
	_text(r.position + Vector2(14, 50), _fit("%s x%s" % [sname, Econ.fmt_mult(snappedf(E.vent_effect(i, a), 0.01))], 13, r.size.x - 150), 13, C_MUTED)
	var cost := E.vent_next_cost(i)
	var can := cost <= E.cash
	var br := Rect2(r.end.x - 124, r.position.y + 10, 114, r.size.y - 20)
	_button("vent:%d" % i, br, "Level up\n" + Econ.fmt_money(cost), "buy" if can else "", "content", true, can, 16)


# ------------------------------------------------------------------ alerts (every tab)

func _draw_alerts(y: float) -> float:
	if E.in_red():
		y = _draw_red(y)
	if not E.event.is_empty():
		y = _draw_event(y)
	return y


func _draw_red(y: float) -> float:
	var left := maxf(0.0, E.deadline() - E.red_t)
	var opts: Array = []
	var need := -E.cash
	if E.credit_available() > 0.0:
		opts.append(["rescue", "Emergency loan\n" + Econ.fmt_money(minf(E.credit_available(), need * 1.05)), "accent"])
	if E.locations() > 0:
		opts.append(["sell_loc", "Sell a franchise\n+" + Econ.fmt_money(_loc_refund()), ""])
	var bi := _biggest_biz()
	if bi >= 0:
		opts.append(["sell_biz:%d" % bi, "Sell %s\n+%s" % [Biz.DEFS[bi].name, Econ.fmt_money(Biz.invested(bi, E.biz[bi], E) * E.refund_rate())], ""])
	opts.append(["file", "File for bankruptcy\n+%s grit" % Econ.fmt_num(E.grit_pending()), "red"])
	var rows := int(ceil(opts.size() / 2.0))
	var r := _row_rect(y, 92 + rows * 58)
	var pulse := 0.6 + 0.4 * sin(anim_t * 5.0)
	_rr(r, Color("2a0b07"), 12, Color(C_RED, pulse), 2)
	_text(r.position + Vector2(14, 28), "IN THE RED", 18, C_RED)
	_text_r(r.end.x - 14, r.position.y + 28, "Bankrupt in " + Econ.fmt_time(left), 16, C_RED)
	var lines := _wrap("You're %s short. Get back above $0 before the deadline or the whole empire goes under." % Econ.fmt_money(need), 13, r.size.x - 28)
	for i in mini(lines.size(), 2):
		_text(r.position + Vector2(14, 50 + i * 17), lines[i], 13, Color("ffb0a6"))
	var bar := Rect2(r.position.x + 14, r.position.y + 80, r.size.x - 28, 5)
	cv.draw_rect(bar, Color(1, 1, 1, 0.08))
	cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * left / maxf(E.deadline(), 1.0), 5)), C_RED)
	var bw := (r.size.x - 28 - 8) * 0.5
	for k in opts.size():
		var o: Array = opts[k]
		var br := Rect2(r.position.x + 14 + (k % 2) * (bw + 8), r.position.y + 92 + (k / 2) * 58, bw, 50)
		_button(String(o[0]), br, String(o[1]), String(o[2]), "content", false, true, 14)
	return r.end.y + 10


func _loc_refund() -> float:
	for i in range(E.NC - 1, -1, -1):
		if int(E.cities[i]) > 0:
			return Econ.cp(float(E.city_cost[i]) * pow(Econ.CITY_GROWTH, int(E.cities[i]) - 1)) * float(E.agg().citycost) * E.refund_rate()
	return 0.0


func _biggest_biz() -> int:
	var best := -1
	var bv := 0.0
	for i in Biz.N:
		if E.biz[i].open:
			var v := Biz.invested(i, E.biz[i], E)
			if v > bv:
				bv = v
				best = i
	return best


func _draw_event(y: float) -> float:
	var ev := E.event
	var w := content_r.size.x - 24
	var lines := _wrap(String(ev.text), 14, w - 28)
	var choices: Array = ev.choices
	# measure each choice: label line plus wrapped details, nothing cut off
	var blocks: Array = []
	var ch_h := 0.0
	for k in choices.size():
		var ch: Dictionary = choices[k]
		var cost := Events.upfront(ev, ch, E.cash)
		var parts: Array = []
		if cost > 0.0:
			parts.append("Costs " + Econ.fmt_money(cost) + " now")
		if String(ch.get("note", "")) != "":
			parts.append(String(ch.note))
		if parts.is_empty():
			parts.append("No cost")
		var detail := _wrap(". ".join(parts) + ".", 13, w - 52)
		var h := 30.0 + detail.size() * 17.0 + 10.0
		blocks.append({"detail": detail, "h": h})
		ch_h += h + 8.0
	var r := _row_rect(y, 58 + lines.size() * 19 + 14 + ch_h + 22)
	var good := bool(ev.good)
	var col := C_GREEN if good else C_ORANGE
	_rr(r, C_CARD_HI, 12, col, 2)
	_text(r.position + Vector2(14, 28), _fit(String(ev.title), 18, r.size.x - 90), 18, col)
	_text_r(r.end.x - 14, r.position.y + 28, Econ.fmt_time(float(ev.t)), 15, C_MUTED)
	for i in lines.size():
		_text(r.position + Vector2(14, 52 + i * 19), lines[i], 14, C_MUTED)
	var bar := Rect2(r.position.x + 14, r.position.y + 60 + lines.size() * 19, r.size.x - 28, 3)
	cv.draw_rect(bar, Color(1, 1, 1, 0.08))
	cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(ev.t) / Events.TIMEOUT, 3)), col)
	var by := bar.end.y + 10
	for k in choices.size():
		var ch: Dictionary = choices[k]
		var b: Dictionary = blocks[k]
		var br := Rect2(r.position.x + 14, by, r.size.x - 28, float(b.h))
		var is_def := k == int(ev.default) and choices.size() > 1
		var pressed: bool = not press.is_empty() and String(press.id) == "event:%d" % k and not press.moved
		var bg := Color(col, 0.22) if k == 0 else Color(1, 1, 1, 0.06)
		_rr(br.grow(-1.5) if pressed else br, bg, 10, Color(col, 0.7) if k == 0 else C_LINE, 1)
		_text(br.position + Vector2(12, 22), _fit(String(ch.label), 16, br.size.x - 24), 16, C_INK)
		var dl: PackedStringArray = b.detail
		for i in dl.size():
			_text(br.position + Vector2(12, 42 + i * 17), dl[i], 13, C_MUTED)
		_btn("event:%d" % k, br, "content")
		by += float(b.h) + 8.0
	var dflt := choices.size() > 1
	_text(Vector2(r.position.x + 14, r.end.y - 9), "If you don't choose in time: " + String((choices[int(ev.default)] as Dictionary).label).to_lower() if dflt else "Tap to continue", 12, C_DIM)
	return r.end.y + 10


# ------------------------------------------------------------------ business tab

func _draw_business(y: float) -> float:
	if _on_biz_page():
		return _draw_biz_page(y, biz_page)
	biz_page = -1
	y = _draw_bank(y)
	y = _section(y, "Your businesses", "%d / %d open" % [E.biz_open_count(), Biz.N])
	var shown_locked := false
	for i in Biz.N:
		var s: Dictionary = E.biz[i]
		if s.open:
			y = _draw_biz_tile(y, i)
		elif E.biz_unlocked(i):
			y = _draw_biz_offer(y, i)
		elif not shown_locked:
			shown_locked = true
			y = _draw_biz_locked(y, i)
	return y


## One row in the list of businesses: tap it to open that business's page.
func _draw_biz_tile(y: float, i: int) -> float:
	var d: Dictionary = Biz.DEFS[i]
	var s: Dictionary = E.biz[i]
	var col := Color(String(d.color))
	var r := _row_rect(y, 92)
	if not _visible(r):
		return r.end.y + 8
	var pressed: bool = not press.is_empty() and String(press.id) == "biz_page:%d" % i and not press.moved
	_rr(r.grow(-1.5) if pressed else r, C_CARD, 12, Color(col, 0.6), 1)
	_biz_icon(i, r.position + Vector2(30, 34), col, 1.0)
	_text(r.position + Vector2(58, 28), String(d.name), 18, col)
	var est: Dictionary = Biz.estimate(i, s, E)
	var net := float(est.rev) - float(est.cost)
	_text(r.position + Vector2(58, 50), "%d %s · %d %s" % [int(s.a), String(d.as).to_lower(), int(s.b), String(d.bs).to_lower()], 13, C_MUTED)
	_text_r(r.end.x - 34, r.position.y + 28, ("+" if net >= 0.0 else "-") + Econ.fmt_money(absf(net)) + "/s", 16, C_GREEN if net >= 0.0 else C_RED)
	var sat := float(est.get("sat", 0.0))
	var bar := Rect2(r.position.x + 58, r.end.y - 22, r.size.x - 130, 6)
	cv.draw_rect(bar, Color(1, 1, 1, 0.08))
	cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * sat, 6)), col)
	_text(Vector2(bar.end.x + 8, bar.end.y + 1), "market %d%%" % int(round(sat * 100.0)), 11, C_DIM)
	var ups: Array = biz_vis[i] if biz_vis.size() > i else []
	var ready := 0
	for u in ups:
		if E.upgrade_cost(u) <= E.cash:
			ready += 1
	if ready > 0:
		var bt := str(mini(ready, 99))
		var bc := Vector2(r.end.x - 34, r.position.y + 50)
		_rr(Rect2(bc - Vector2(4, 12), Vector2(_tw(bt, 12) + 26, 18)), C_RED, 9)
		_text(bc + Vector2(4, 2), bt + " up", 11, Color.WHITE)
	# chevron
	var cx := r.end.x - 16
	cv.draw_polyline(PackedVector2Array([Vector2(cx - 5, r.get_center().y - 8), Vector2(cx + 2, r.get_center().y), Vector2(cx - 5, r.get_center().y + 8)]), C_MUTED, 2.5)
	_btn("biz_page:%d" % i, r, "content")
	return r.end.y + 8


func _biz_icon(i: int, c: Vector2, col: Color, k: float) -> void:
	cv.draw_circle(c, 20 * k, Color(col, 0.15))
	match String(Biz.DEFS[i].id):
		"truck":
			cv.draw_rect(Rect2(c + Vector2(-13, -7) * k, Vector2(20, 12) * k), col)
			cv.draw_rect(Rect2(c + Vector2(7, -3) * k, Vector2(6, 8) * k), col)
			cv.draw_circle(c + Vector2(-8, 7) * k, 3 * k, col)
			cv.draw_circle(c + Vector2(7, 7) * k, 3 * k, col)
		"bakery":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 4) * k, c + Vector2(-8, -8) * k, c + Vector2(8, -8) * k, c + Vector2(13, 4) * k]), col)
			for q in 3:
				cv.draw_line(c + Vector2(-6 + q * 6, -6) * k, c + Vector2(-4 + q * 6, 2) * k, C_CARD, 1.5)
		"catering":
			cv.draw_arc(c + Vector2(0, 4) * k, 12 * k, PI, TAU, 16, col, 3)
			cv.draw_rect(Rect2(c + Vector2(-14, 4) * k, Vector2(28, 3) * k), col)
			cv.draw_circle(c + Vector2(0, -9) * k, 2 * k, col)
		"bar":
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-10, -10) * k, c + Vector2(10, -10) * k, c + Vector2(1, 2) * k, c + Vector2(-1, 2) * k]), col)
			cv.draw_rect(Rect2(c + Vector2(-1, 2) * k, Vector2(2, 8) * k), col)
			cv.draw_rect(Rect2(c + Vector2(-6, 10) * k, Vector2(12, 2) * k), col)
		"hotel":
			cv.draw_rect(Rect2(c + Vector2(-10, -12) * k, Vector2(20, 24) * k), col)
			for q in 6:
				cv.draw_rect(Rect2(c + Vector2(-7 + (q % 2) * 8, -9 + (q / 2) * 7) * k, Vector2(5, 4) * k), C_CARD)
		"wholesale":
			for q in 3:
				cv.draw_rect(Rect2(c + Vector2(-13 + q * 9, 0) * k, Vector2(8, 8) * k), col)
			cv.draw_rect(Rect2(c + Vector2(-8, -9) * k, Vector2(8, 8) * k), col)
			cv.draw_rect(Rect2(c + Vector2(1, -9) * k, Vector2(8, 8) * k), col)


# ------------------------------------------------------------------ one business's page

func _draw_biz_page(y: float, i: int) -> float:
	var d: Dictionary = Biz.DEFS[i]
	var s: Dictionary = E.biz[i]
	var col := Color(String(d.color))
	# back row
	var br := _row_rect(y, 40)
	_button("biz_back", Rect2(br.position.x, y, 120, 40), "‹  All businesses", "ghost", "content", false, true, 14)
	_text_r(br.end.x, y + 26, String(d.name), 17, col)
	y += 48
	# the twist
	var tw_h := _twist_height(i)
	var tr := _row_rect(y, tw_h + 34)
	_rr(tr, C_CARD, 12)
	_text(tr.position + Vector2(14, 22), _twist_title(i), 14, col)
	_draw_twist(i, s, Rect2(tr.position.x + 8, tr.position.y + 30, tr.size.x - 16, tw_h))
	y = tr.end.y + 8
	# market
	y = _draw_market(y, i, s, col)
	# builds
	var r := _row_rect(y, 32)
	var labels := ["x1", "x10", "x100", "Max"]
	var cw := (r.size.x - 3 * 6) / 4.0
	for k in 4:
		_button("mode:%d" % k, Rect2(r.position.x + k * (cw + 6), y, cw, 32), labels[k], "on" if buy_mode == k else "ghost", "content", false, true, 14)
	y += 40
	for w in ["a", "b"]:
		var rr := _row_rect(y, 72)
		if _visible(rr):
			_draw_biz_build(i, s, w, rr, col)
		y += 78
	# automation
	y = _draw_biz_automation(y, i, s, col)
	# this business's upgrades
	y = _draw_biz_upgrades(y, i, col)
	# sell
	var sr := _row_rect(y + 6, 44)
	_button("sell_biz:%d" % i, sr, "Sell the %s (+%s)" % [String(d.name), Econ.fmt_money(Biz.invested(i, s, E) * E.refund_rate())], "ghost", "content", false, true, 13)
	return sr.end.y + 8


func _twist_title(i: int) -> String:
	match String(Biz.DEFS[i].id):
		"truck": return "WHERE TO PARK"
		"bakery": return "OVENS, SHELF AND COUNTERS"
		"catering": return "CONTRACTS"
		"bar": return "THE CROWD"
		"hotel": return "SEASON AND ROOM RATE"
		"wholesale": return "THE MARKET"
	return ""


func _draw_market(y: float, i: int, s: Dictionary, col: Color) -> float:
	var est: Dictionary = Biz.estimate(i, s, E)
	var sat := float(est.get("sat", 0.0))
	var mk := Biz.market(i, E) * E.biz_ref()
	var lines := _wrap("Sales level off as you fill this market, while running costs keep rising. The market grows with your restaurant's income and with company-wide upgrades.", 12, content_r.size.x - 52)
	var r := _row_rect(y, 76 + lines.size() * 16)
	if not _visible(r):
		return r.end.y + 8
	_rr(r, C_CARD, 12)
	_text(r.position + Vector2(14, 24), "Market captured", 15)
	_text_r(r.end.x - 14, r.position.y + 24, "%d%%" % int(round(sat * 100.0)), 16, C_ORANGE if sat > 0.6 else col)
	var bar := Rect2(r.position.x + 14, r.position.y + 34, r.size.x - 28, 8)
	_rr(bar, Color(1, 1, 1, 0.08), 4)
	_rr(Rect2(bar.position, Vector2(maxf(8.0, bar.size.x * sat), 8)), C_ORANGE if sat > 0.6 else col, 4)
	_text(r.position + Vector2(14, 60), "Sales %s/s of a market worth up to %s/s" % [Econ.fmt_money(float(est.rev)), Econ.fmt_money(mk)], 12, C_MUTED)
	for k in lines.size():
		_text(r.position + Vector2(14, 78 + k * 16), lines[k], 12, C_DIM)
	return r.end.y + 8


func _draw_biz_automation(y: float, i: int, s: Dictionary, col: Color) -> float:
	var id: String = Biz.DEFS[i].id
	var a := E.agg()
	var rows: Array = []
	if a.flags.has("mgr_" + id):
		rows.append(["mgr", Econ.FLAG_TEXT.get("mgr_" + id, "Manager")])
	if a.flags.has("auto_" + id):
		rows.append(["auto", Econ.FLAG_TEXT.get("auto_" + id, "Auto-buyer")])
	y = _section(y, "Automation")
	if rows.is_empty():
		var r := _row_rect(y, 46)
		_rr(r, Color(C_CARD, 0.5), 12)
		_text(r.position + Vector2(14, 28), _fit("Hire a manager below to run this business for you.", 13, r.size.x - 28), 13, C_DIM)
		return r.end.y + 8
	for row in rows:
		var r := _row_rect(y, 50)
		_rr(r, C_CARD, 12)
		_text(r.position + Vector2(14, 30), _fit(String(row[1]), 14, r.size.x - 110), 14)
		var on := true
		var bid := ""
		if row[0] == "auto":
			on = E.automation_active("auto_" + id)
			bid = "auto_biz:%d" % i
		elif id == "hotel":
			on = bool(s.rate_auto)
			bid = "rate:%d:auto" % i
		elif id == "wholesale":
			on = bool(s.auto_sell)
			bid = "ws_auto:%d" % i
		if bid != "":
			_button(bid, Rect2(r.end.x - 74, r.position.y + 8, 64, 34), "ON" if on else "OFF", "buy" if on else "ghost", "content", false, true, 14)
		else:
			_text_r(r.end.x - 14, r.position.y + 30, "always on", 12, C_GREEN)
		y = r.end.y + 6
	return y + 2


func _draw_biz_upgrades(y: float, i: int, col: Color) -> float:
	var ups: Array = biz_vis[i] if biz_vis.size() > i else []
	var owned := 0
	var total := 0
	for u in E.upgrades:
		if u.has("biz") and int(u.biz) == i:
			total += 1
			if E.owned.has(int(u.id)):
				owned += 1
	y = _section(y + 4, "Upgrades", "%d / %d owned" % [owned, total])
	if not ups.is_empty():
		var cost := 0.0
		var n := 0
		for u in ups:
			if cost + E.upgrade_cost(u) <= E.cash:
				cost += E.upgrade_cost(u)
				n += 1
		if n > 1:
			_button("bizupg:%d" % i, _row_rect(y, 40), "Buy %d affordable (%s)" % [n, Econ.fmt_money(cost)], "accent", "content", false, true, 15)
			y += 48
	for u in ups:
		var rr := _row_rect(y, 76)
		if _visible(rr):
			_draw_upgrade_row(rr, u)
		y += 82
	# what unlocks next
	var next: Array = []
	for u in E.upgrades:
		if u.has("biz") and int(u.biz) == i and not E.owned.has(int(u.id)) and not E.req_met(u):
			next.append(u)
	next.sort_custom(func(x, z): return E.upgrade_cost(x) < E.upgrade_cost(z))
	for k in mini(3, next.size()):
		var u: Dictionary = next[k]
		var rr := _row_rect(y, 56)
		if _visible(rr):
			_rr(rr, Color(C_CARD, 0.5), 12)
			cv.draw_rect(Rect2(rr.position.x, rr.position.y + 10, 4, rr.size.y - 20), Color(col, 0.4))
			_text(rr.position + Vector2(14, 22), _fit(String(u.name).split(": ")[-1] + " · " + E.effect_text(u.eff), 14, rr.size.x - 28), 14, C_DIM)
			_text(rr.position + Vector2(14, 43), _fit("Unlocks at: " + E.req_text(u), 12, rr.size.x - 28), 12, C_DIM)
		y += 62
	return y


# ------------------------------------------------------------------ business scenes (top of the screen)

func _draw_biz_strip(i: int) -> void:
	var r := strip_r
	var s: Dictionary = E.biz[i]
	var est: Dictionary = Biz.estimate(i, s, E)
	var col := Color(String(Biz.DEFS[i].color))
	var vals := [["Sales", Econ.fmt_money(float(est.rev)) + "/s", C_GREEN], ["Costs", Econ.fmt_money(float(est.cost)) + "/s", Color("e99a8f")],
		["Market", "%d%%" % int(round(float(est.get("sat", 0.0)) * 100.0)), col]]
	var gap := 6.0
	var w := (r.size.x - gap * 2) / 3.0
	for k in 3:
		var cr := Rect2(r.position.x + k * (w + gap), r.position.y, w, r.size.y)
		_rr(cr, C_CARD, 10)
		_text(cr.position + Vector2(9, 17), String(vals[k][0]), 12, C_MUTED)
		_text(cr.position + Vector2(9, 39), _fit(String(vals[k][1]), 16, cr.size.x - 14), 16, vals[k][2])


func _draw_biz_scene(i: int) -> void:
	var r := scene_r.grow(serve_bump * serve_bump * 3.0)
	var s: Dictionary = E.biz[i]
	var col := Color(String(Biz.DEFS[i].color))
	match String(Biz.DEFS[i].id):
		"truck": _scene_truck(r, s, col)
		"bakery": _scene_bakery(r, s, col)
		"catering": _scene_catering(r, s, col)
		"bar": _scene_bar(r, s, col)
		"hotel": _scene_hotel(r, s, col)
		"wholesale": _scene_wholesale(r, s, col)
	var hint := "TAP TO SELL  +" + Econ.fmt_money(maxf(float(Biz.estimate(i, s, E).rev) * 0.5, E.tap_value() * 0.25))
	var hw := _tw(hint, 12) + 16
	var hr := Rect2(r.end.x - hw - 8, r.end.y - 24, hw, 18)
	_rr(hr, Color(0, 0, 0, 0.5), 9)
	_text_c(hr, hr.position.y + 13, hint, 12, Color(col, 0.8 + 0.2 * sin(anim_t * 3.0)))


func _person(p: Vector2, c: Color, bob := 0.0) -> void:
	cv.draw_circle(p + Vector2(0, -9 + bob), 4, Color("e8c4a0"))
	cv.draw_rect(Rect2(p + Vector2(-4, -5 + bob), Vector2(8, 9)), c)


func _scene_truck(r: Rect2, s: Dictionary, col: Color) -> void:
	_rr(r, Color("27405e"), 14)
	# skyline
	var bx := r.position.x + 6
	var k := 0
	while bx < r.end.x - 6:
		var bw := 22.0 + float((k * 37) % 19)
		var bh := 28.0 + float((k * 53) % 34)
		cv.draw_rect(Rect2(bx, r.position.y + r.size.y * 0.55 - bh, bw, bh), Color("1d2f46"))
		for wy in int(bh / 9):
			if (k + wy) % 3 != 0:
				cv.draw_rect(Rect2(bx + 4, r.position.y + r.size.y * 0.55 - bh + 4 + wy * 9, 4, 3), Color(1, 0.85, 0.5, 0.35))
		bx += bw + 3
		k += 1
	# street
	var road := Rect2(r.position.x, r.position.y + r.size.y * 0.55, r.size.x, r.size.y * 0.45)
	_rr(road, Color("2b2b30"), 14)
	cv.draw_rect(Rect2(road.position.x, road.position.y, road.size.x, 6), Color("4a4a52"))
	for d in int(road.size.x / 28):
		cv.draw_rect(Rect2(road.position.x + 8 + d * 28 + fmod(anim_t * 0.0, 28.0), road.position.y + road.size.y * 0.62, 14, 3), Color(1, 1, 1, 0.35))
	# spots with crowds
	var n := Biz.SPOTS.size()
	for q in n:
		var x := r.position.x + (q + 0.5) * r.size.x / n
		var m := float(s.spots[q])
		var c := C_GREEN if m >= 1.5 else (C_ACCENT if m >= 0.9 else C_RED)
		_text_c(Rect2(x - 40, 0, 80, 0), road.position.y - 4 - 18, Biz.SPOTS[q], 10, Color(c, 0.9))
		var crowd := clampi(int(round(m * 3.0)), 1, 8)
		for p in crowd:
			var px := x - 18 + (p % 4) * 12
			var py := road.position.y - 2 - (p / 4) * 6
			_person(Vector2(px, py), Color.from_hsv(fmod(q * 0.23 + p * 0.11, 1.0), 0.45, 0.9), sin(anim_t * 4.0 + p + q) * 1.0)
	# the truck drives to its spot
	var target := (int(s.spot) + 0.5) / float(n)
	if truck_x < 0.0:
		truck_x = target
	truck_x = move_toward(truck_x, target, 0.6 * get_process_delta_time())
	var tx := r.position.x + truck_x * r.size.x
	var ty := road.position.y + road.size.y * 0.42
	var moving := absf(truck_x - target) > 0.002 or float(s.move_t) > 0.0
	var bump := sin(anim_t * 20.0) * (1.2 if moving else 0.0)
	cv.draw_rect(Rect2(tx - 30, ty - 20 + bump, 48, 24), col)
	cv.draw_rect(Rect2(tx + 18, ty - 12 + bump, 14, 16), col.darkened(0.15))
	cv.draw_rect(Rect2(tx + 21, ty - 9 + bump, 8, 6), Color("bfe3ff"))
	cv.draw_rect(Rect2(tx - 26, ty - 16 + bump, 26, 10), Color("2a1e16"))
	for st in 4:
		cv.draw_rect(Rect2(tx - 30 + st * 12, ty - 24 + bump, 12, 5), Color.WHITE if st % 2 == 0 else C_RED)
	cv.draw_circle(Vector2(tx - 20, ty + 5), 6, Color("1a1a1a"))
	cv.draw_circle(Vector2(tx + 22, ty + 5), 6, Color("1a1a1a"))
	cv.draw_circle(Vector2(tx - 20, ty + 5), 2.5, Color("888888"))
	cv.draw_circle(Vector2(tx + 22, ty + 5), 2.5, Color("888888"))
	if int(s.a) > 1:
		_text(Vector2(tx - 30, ty - 30), "x%d" % int(s.a), 11, Color.WHITE)


func _scene_bakery(r: Rect2, s: Dictionary, col: Color) -> void:
	var rush := fmod(float(s.rush_t), Biz.RUSH_PERIOD) < Biz.RUSH_LEN
	_rr(r, Color("4a3424") if not rush else Color("5a3d22"), 14)
	cv.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.7, r.size.x, r.size.y * 0.3), Color("3a2a1f"))
	# ovens
	var ovens := clampi(1 + int(s.a) / 15, 1, 4)
	for o in ovens:
		var orr := Rect2(r.position.x + 12 + o * 44, r.position.y + 18, 38, 44)
		_rr(orr, Color("2a2a2a"), 6)
		var glow := 0.55 + 0.25 * sin(anim_t * 5.0 + o)
		_rr(Rect2(orr.position + Vector2(6, 14), Vector2(26, 18)), Color(1.0, 0.45, 0.1, glow), 4)
		cv.draw_line(orr.position + Vector2(6, 8), orr.position + Vector2(32, 8), Color("555555"), 2)
	# shelf with loaves
	var shelf := Rect2(r.position.x + r.size.x * 0.52, r.position.y + 22, r.size.x * 0.44, 46)
	cv.draw_rect(Rect2(shelf.position.x, shelf.position.y + 20, shelf.size.x, 3), Color("8a5a3b"))
	cv.draw_rect(Rect2(shelf.position.x, shelf.end.y, shelf.size.x, 3), Color("8a5a3b"))
	var cap := Biz.bakery_sell_cap(s, E) * (180.0 if Biz.has_mgr(1, E) else 60.0)
	var fill := clampf(float(s.stock) / maxf(cap, 1e-9), 0.0, 1.0)
	var loaves := int(round(fill * 16.0))
	for l in loaves:
		var lx := shelf.position.x + 6 + (l % 8) * (shelf.size.x - 12) / 8.0
		var ly := shelf.position.y + 14 + (l / 8) * 26
		cv.draw_colored_polygon(PackedVector2Array([Vector2(lx, ly + 4), Vector2(lx + 3, ly - 3), Vector2(lx + 13, ly - 3), Vector2(lx + 16, ly + 4)]), col)
	# counter with customers
	var counter := Rect2(r.position.x + 10, r.position.y + r.size.y * 0.62, r.size.x - 20, 10)
	cv.draw_rect(counter, Color("8a5a3b"))
	var people := clampi(int(Biz.bakery_sell_cap(s, E) / 4.0) + (6 if rush else 0), 1, 12)
	for p in people:
		var px := r.position.x + 24 + fmod(p * 37.0 + anim_t * (30.0 if rush else 12.0), r.size.x - 48)
		_person(Vector2(px, r.end.y - 14), Color.from_hsv(fmod(p * 0.17, 1.0), 0.4, 0.9), sin(anim_t * 6.0 + p) * 1.0)
	if rush:
		var b := Rect2(r.get_center().x - 60, r.position.y + 6, 120, 18)
		_rr(b, Color(C_ACCENT, 0.9), 9)
		_text_c(b, b.position.y + 13, "MORNING RUSH!", 12, Color("241703"))


func _scene_catering(r: Rect2, s: Dictionary, col: Color) -> void:
	_rr(r, Color("2c3a2c"), 14)
	cv.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.62, r.size.x, r.size.y * 0.38), Color("223022"))
	# chandelier
	var cc := Vector2(r.get_center().x, r.position.y + 14)
	cv.draw_line(Vector2(cc.x, r.position.y), cc, Color("caa85a"), 1.5)
	cv.draw_arc(cc + Vector2(0, 4), 16, 0, PI, 12, Color("caa85a"), 2)
	for q in 5:
		cv.draw_circle(cc + Vector2(-16 + q * 8, 6 + absf(q - 2) * -1.5), 2.2, Color(1, 0.9, 0.5, 0.6 + 0.4 * sin(anim_t * 3.0 + q)))
	# one banquet table per job in progress, guests fill as it nears the end
	var jobs: Array = s.jobs
	var slots := maxi(1, Biz.catering_max_jobs(s))
	for q in mini(slots, 5):
		var tx := r.position.x + (q + 0.5) * r.size.x / mini(slots, 5)
		var ty := r.position.y + r.size.y * 0.5
		var active := q < jobs.size()
		cv.draw_circle(Vector2(tx, ty), 16, Color("f3e3cc") if active else Color(1, 1, 1, 0.12))
		if active:
			var j: Dictionary = jobs[q]
			var prog := 1.0 - float(j.t) / maxf(float(j.dur), 1.0)
			for g in 8:
				var a := g * TAU / 8.0
				if g < int(prog * 8.0) + 2:
					_person(Vector2(tx, ty) + Vector2(cos(a), sin(a)) * 24 + Vector2(0, 6), Color.from_hsv(fmod(g * 0.13 + q * 0.3, 1.0), 0.4, 0.9))
			cv.draw_circle(Vector2(tx, ty), 5, col)
			_text_c(Rect2(tx - 40, 0, 80, 0), ty + 38, _fit(String(j.name), 10, 76), 10, C_INK)
	# vans
	for v in mini(int(s.b), 4):
		var vx := r.position.x + fmod(v * 90.0 + anim_t * 40.0, r.size.x + 60.0) - 30.0
		var vy := r.end.y - 18
		cv.draw_rect(Rect2(vx, vy - 12, 30, 14), Color.WHITE)
		cv.draw_rect(Rect2(vx + 2, vy - 8, 16, 4), col)
		cv.draw_circle(Vector2(vx + 7, vy + 2), 3, Color("1a1a1a"))
		cv.draw_circle(Vector2(vx + 23, vy + 2), 3, Color("1a1a1a"))


func _scene_bar(r: Rect2, s: Dictionary, col: Color) -> void:
	var happy: bool = s.happy
	_rr(r, Color("221630"), 14)
	var rowdy := clampf(float(s.rowdy) / 100.0, 0.0, 1.0)
	# neon sign
	var neon := Color("ff5fd2") if happy else col
	var flick := 0.75 + 0.25 * sin(anim_t * (9.0 if happy else 3.0))
	_text(Vector2(r.position.x + 16, r.position.y + 28), "COCKTAILS" if not happy else "HAPPY HOUR", 18, Color(neon, flick))
	# bottles on the back wall
	for b in 12:
		var bx := r.position.x + r.size.x * 0.45 + b * 15
		if bx > r.end.x - 10:
			break
		cv.draw_rect(Rect2(bx, r.position.y + 18, 7, 18), Color.from_hsv(fmod(b * 0.19, 1.0), 0.5, 0.7, 0.8))
		cv.draw_rect(Rect2(bx + 2, r.position.y + 13, 3, 6), Color.from_hsv(fmod(b * 0.19, 1.0), 0.5, 0.7, 0.8))
	# bar counter + bartenders
	var counter := Rect2(r.position.x + 10, r.position.y + r.size.y * 0.45, r.size.x - 20, 12)
	cv.draw_rect(counter, Color("5b3a2a"))
	for t in clampi(1 + int(s.a) / 15, 1, 5):
		_person(Vector2(r.position.x + 40 + t * 50, counter.position.y - 1), Color("1d1d1d"), sin(anim_t * 5.0 + t) * 1.0)
	# the crowd: more shaking as it gets rowdier
	var crowd := clampi(4 + int(s.a) / 6, 4, 18)
	if float(s.closed_t) > 0.0:
		crowd = 0
	for p in crowd:
		var px := r.position.x + 20 + fmod(p * 29.0, r.size.x - 40)
		var shake := sin(anim_t * (8.0 + rowdy * 25.0) + p * 1.7) * (1.0 + rowdy * 4.0)
		_person(Vector2(px + shake, r.end.y - 10 - (p % 2) * 8), Color.from_hsv(fmod(p * 0.13, 1.0), 0.5, 0.95), shake * 0.5)
	# bouncers by the door
	for b in mini(int(s.b), 3):
		cv.draw_circle(Vector2(r.end.x - 18 - b * 14, r.end.y - 30), 5, Color("e8c4a0"))
		cv.draw_rect(Rect2(r.end.x - 24 - b * 14, r.end.y - 26, 12, 14), Color("101010"))
	if float(s.closed_t) > 0.0:
		var cs := Rect2(r.get_center().x - 70, r.get_center().y - 12, 140, 28)
		_rr(cs, Color("2a0904"), 6, C_RED, 2)
		_text_c(cs, cs.position.y + 20, "FIGHT! CLOSED", 15, C_RED)


func _scene_hotel(r: Rect2, s: Dictionary, col: Color) -> void:
	var sea := Biz.season(s)
	var sky: Color = [Color("4d9be0"), Color("6a8fb0"), Color("6d7480"), Color("8a7fb0")][sea]
	_rr(r, sky, 14)
	if sea == 0:
		cv.draw_circle(r.position + Vector2(r.size.x - 34, 26), 13, Color("ffd65a"))
	elif sea == 2:
		for f in 24:
			var fx := r.position.x + fmod(f * 41.0 + anim_t * 6.0 * (1 + f % 3), r.size.x)
			var fy := r.position.y + fmod(f * 23.0 + anim_t * 25.0 * (1 + f % 2), r.size.y)
			cv.draw_circle(Vector2(fx, fy), 1.6, Color(1, 1, 1, 0.8))
	# the building
	var b := Rect2(r.position.x + r.size.x * 0.18, r.position.y + 12, r.size.x * 0.5, r.size.y - 12)
	cv.draw_rect(b, Color("d8c7a8"))
	cv.draw_rect(Rect2(b.position.x - 4, b.position.y - 4, b.size.x + 8, 8), col)
	var h := Biz.hotel_rev(4, s, E, sea, float(s.rate))
	var occ := float(h.occ)
	var rooms := clampi(int(s.a), 4, 40)
	var cols := 5
	var rows := int(ceil(rooms / float(cols)))
	var cw := (b.size.x - 12) / cols
	var ch := minf(14.0, (b.size.y - 30) / maxf(1, rows))
	for q in rooms:
		var wx := b.position.x + 6 + (q % cols) * cw
		var wy := b.position.y + 10 + (q / cols) * ch
		var lit := float((q * 7919) % 100) / 100.0 < occ
		cv.draw_rect(Rect2(wx + 2, wy + 2, cw - 4, ch - 4), Color("ffd98a") if lit else Color("3a4250"))
	cv.draw_rect(Rect2(b.get_center().x - 10, b.end.y - 16, 20, 16), Color("5b3a2a"))
	# the season sign
	var sign := Rect2(r.end.x - r.size.x * 0.28, r.end.y - 46, r.size.x * 0.25, 36)
	_rr(sign, Color(0, 0, 0, 0.45), 8)
	_text_c(sign, sign.position.y + 15, Biz.SEASONS[sea], 12, Color.WHITE)
	_text_c(sign, sign.position.y + 30, "%d%% full" % int(round(occ * 100.0)), 11, Color("ffd98a"))


func _scene_wholesale(r: Rect2, s: Dictionary, col: Color) -> void:
	_rr(r, Color("2a3436"), 14)
	cv.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.75, r.size.x, r.size.y * 0.25), Color("23292b"))
	# crate stacks fill with stock
	var fill := clampf(float(s.stock) / maxf(Biz.wholesale_cap(s), 1.0), 0.0, 1.0)
	var stacks := 6
	for q in stacks:
		var h := int(round(fill * 5.0 + (0.5 if q % 2 == 0 else 0.0)))
		for c2 in mini(h, 5):
			var cx := r.position.x + 10 + q * 24
			var cy := r.end.y - 22 - c2 * 16
			cv.draw_rect(Rect2(cx, cy, 20, 15), Color("a0703f"))
			cv.draw_rect(Rect2(cx, cy, 20, 15), Color("6e4a28"), false, 1.5)
	# market price chart
	var chart := Rect2(r.position.x + r.size.x * 0.48, r.position.y + 14, r.size.x * 0.48, r.size.y * 0.62)
	_rr(chart, Color(0, 0, 0, 0.35), 8)
	cv.draw_line(Vector2(chart.position.x, chart.end.y - chart.size.y * (1.0 - 0.4) / 2.2), Vector2(chart.end.x, chart.end.y - chart.size.y * (1.0 - 0.4) / 2.2), Color(1, 1, 1, 0.15), 1)
	if price_hist.size() > 1:
		var pts := PackedVector2Array()
		for k in price_hist.size():
			var v := float(price_hist[k])
			pts.append(Vector2(chart.position.x + 4 + k * (chart.size.x - 8) / 89.0, chart.end.y - 4 - (v - 0.4) / 2.2 * (chart.size.y - 8)))
		cv.draw_polyline(pts, C_GREEN if float(s.mprice) >= 1.3 else (C_ACCENT if float(s.mprice) >= 0.8 else C_RED), 2.0)
	_text(chart.position + Vector2(6, 14), "PRICE x" + Econ.fmt_mult(snappedf(float(s.mprice), 0.01)), 11, Color.WHITE)
	# forklift
	var fx := r.position.x + 20 + fmod(anim_t * 30.0, r.size.x * 0.4)
	cv.draw_rect(Rect2(fx, r.end.y - 30, 18, 12), col)
	cv.draw_line(Vector2(fx + 20, r.end.y - 34), Vector2(fx + 20, r.end.y - 14), Color("cccccc"), 2)
	cv.draw_circle(Vector2(fx + 4, r.end.y - 16), 3, Color("111111"))
	cv.draw_circle(Vector2(fx + 14, r.end.y - 16), 3, Color("111111"))


func _draw_bank(y: float) -> float:
	var lim := E.credit_limit()
	var r := _row_rect(y, 128 if E.debt > 0.0 else 104)
	if not _visible(r):
		return r.end.y + 10
	_rr(r, C_CARD, 12)
	_text(r.position + Vector2(14, 26), "Bank", 17)
	var rate := E.interest_rate() * 60.0 * 100.0
	if E.debt > 0.0:
		_text_r(r.end.x - 14, r.position.y + 26, "Debt " + Econ.fmt_money(E.debt), 15, C_ORANGE)
		_text(r.position + Vector2(14, 48), "Interest %s/s (%s%%/min, rises as you max out)" % [Econ.fmt_money(E.interest_per_s()), Econ.fmt_mult(snappedf(rate, 0.01))], 12, C_MUTED)
		var bar := Rect2(r.position.x + 14, r.position.y + 58, r.size.x - 28, 5)
		cv.draw_rect(bar, Color(1, 1, 1, 0.08))
		cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(E.debt / maxf(lim, 1e-9), 0.0, 1.0), 5)), C_ORANGE)
	else:
		_text_r(r.end.x - 14, r.position.y + 26, "No debt", 13, C_GREEN)
		_text(r.position + Vector2(14, 48), _fit("Borrow up to %s at %s%%/min to expand faster." % [Econ.fmt_money(lim), Econ.fmt_mult(snappedf(rate, 0.01))], 12, r.size.x - 28), 12, C_MUTED)
	var by := r.end.y - 46
	var avail := E.credit_available()
	var w := (r.size.x - 28 - 18) / 4.0
	var x := r.position.x + 14
	_button("borrow:0.25", Rect2(x, by, w, 36), "+" + Econ.fmt_money(avail * 0.25), "", "content", false, avail > 1.0, 13)
	_button("borrow:1.0", Rect2(x + (w + 6), by, w, 36), "Max", "", "content", false, avail > 1.0, 13)
	_button("repay:0.5", Rect2(x + 2 * (w + 6), by, w, 36), "Repay half", "", "content", false, E.debt > 0.0 and E.cash > 0.0, 12)
	_button("repay:1.0", Rect2(x + 3 * (w + 6), by, w, 36), "Repay all", "buy" if E.debt > 0.0 and E.cash >= E.debt else "", "content", false, E.debt > 0.0 and E.cash > 0.0, 12)
	return r.end.y + 10


func _draw_biz_locked(y: float, i: int) -> float:
	var d: Dictionary = Biz.DEFS[i]
	var r := _row_rect(y, 84)
	_rr(r, Color(C_CARD, 0.5), 12)
	_text(r.position + Vector2(14, 26), String(d.name), 17, C_DIM)
	_text_r(r.end.x - 14, r.position.y + 26, "LOCKED", 11, C_DIM)
	var need := Biz.unlock_at(i)
	_text(r.position + Vector2(14, 48), _fit("Earn %s this run to unlock" % Econ.fmt_money(need), 13, r.size.x - 28), 13, C_DIM)
	var bar := Rect2(r.position.x + 14, r.end.y - 18, r.size.x - 28, 5)
	cv.draw_rect(bar, Color(1, 1, 1, 0.08))
	cv.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(E.run_earned / need, 0.0, 1.0), 5)), Color(String(d.color)))
	return r.end.y + 10


func _draw_biz_offer(y: float, i: int) -> float:
	var d: Dictionary = Biz.DEFS[i]
	var col := Color(String(d.color))
	var lines := _wrap(String(d.blurb), 13, content_r.size.x - 48)
	var r := _row_rect(y, 96 + lines.size() * 17)
	if not _visible(r):
		return r.end.y + 10
	_rr(r, C_CARD, 12, col, 2)
	_text(r.position + Vector2(14, 28), String(d.name), 19, col)
	_text_r(r.end.x - 14, r.position.y + 28, "NEW", 12, col)
	for k in lines.size():
		_text(r.position + Vector2(14, 50 + k * 17), lines[k], 13, C_MUTED)
	var cost := Biz.open_cost(i, E)
	_button("biz_open:%d" % i, Rect2(r.position.x + 14, r.end.y - 46, r.size.x - 28, 36), "Open for " + Econ.fmt_money(cost), "buy" if E.cash >= cost else "", "content", false, E.cash >= cost, 15)
	return r.end.y + 10


## This business's upgrades that can be bought right now.
func _biz_upgrades(i: int) -> Array:
	return (biz_vis[i] as Array).duplicate() if biz_vis.size() > i else []


func _draw_biz_build(i: int, s: Dictionary, w: String, r: Rect2, col: Color) -> void:
	var d: Dictionary = Biz.DEFS[i]
	_rr(r, C_CARD, 12)
	cv.draw_rect(Rect2(r.position.x, r.position.y + 12, 4, r.size.y - 24), col)
	var tw := r.size.x - 146.0
	var nm: String = d[w]
	_text(r.position + Vector2(14, 22), _fit(nm, 16, tw - 50), 16)
	_text(r.position + Vector2(20 + _tw(_fit(nm, 16, tw - 50), 16), 22), "x%d" % int(s[w]), 13, C_MUTED)
	var nm_next := E.biz_next_milestone(i, w)
	var desc := String(d[w + "_desc"])
	if nm_next > 0:
		desc += " · bonus at %d" % nm_next
	_text(r.position + Vector2(14, 42), _fit(desc, 12, tw), 12, C_MUTED)
	var k := biz_buy_count(i, w)
	var cost := E.biz_cost(i, w, k)
	var can := cost <= E.cash
	var g := biz_gain(i, w, k)
	if g > 0.0:
		var pb := cost / g
		var pc := C_GREEN if pb < 600.0 else (C_ACCENT if pb < 3600.0 else C_ORANGE)
		_text(r.position + Vector2(14, 62), _fit("+%s/s · pays back in %s" % [Econ.fmt_money(g), Econ.fmt_time(pb)], 12, tw), 12, pc)
	elif g < 0.0:
		_text(r.position + Vector2(14, 62), _fit("-%s/s (not needed now)" % Econ.fmt_money(-g), 12, tw), 12, C_ORANGE)
	_button("biz:%d:%s" % [i, w], Rect2(r.end.x - 124, r.position.y + 8, 116, r.size.y - 16), "Buy %d\n%s" % [k, Econ.fmt_money(cost)], "buy" if can else "", "content", true, can, 15)


func _twist_height(i: int) -> float:
	match String(Biz.DEFS[i].id):
		"truck": return 80.0
		"bakery": return 62.0
		"catering": return 146.0
		"bar": return 62.0
		"hotel": return 72.0
		"wholesale": return 72.0
	return 60.0


func _draw_twist(i: int, s: Dictionary, r: Rect2) -> void:
	var id: String = Biz.DEFS[i].id
	var col := Color(String(Biz.DEFS[i].color))
	_rr(r, Color(0, 0, 0, 0.25), 10)
	var mgr := Biz.has_mgr(i, E)
	match id:
		"truck":
			var moving := float(s.move_t) > 0.0
			var sub := "Driving to %s... %s" % [Biz.SPOTS[int(s.spot)], Econ.fmt_time(float(s.move_t))] if moving else "Crowds change in %s" % Econ.fmt_time(float(s.spot_t))
			if mgr:
				sub += " · Route Planner on"
			_text(r.position + Vector2(10, 18), sub, 12, C_MUTED)
			var n := Biz.SPOTS.size()
			var bw := (r.size.x - 20 - 6 * (n - 1)) / n
			for k in n:
				var m := float(s.spots[k])
				var here := k == int(s.spot)
				var br := Rect2(r.position.x + 10 + k * (bw + 6), r.position.y + 26, bw, 46)
				var c := C_GREEN if m >= 1.5 else (C_ACCENT if m >= 0.9 else C_RED)
				_rr(br, Color(c, 0.25 if here else 0.1), 8, c if here else Color(0, 0, 0, 0), 2 if here else 0)
				_text_c(br, br.position.y + 18, _fit(Biz.SPOTS[k], 11, bw - 4), 11, C_INK if here else C_MUTED)
				_text_c(br, br.position.y + 38, "x" + Econ.fmt_mult(m), 15, c)
				if not here:
					_btn("spot:%d:%d" % [i, k], br, "content")
		"bakery":
			var rush := fmod(float(s.rush_t), Biz.RUSH_PERIOD) < Biz.RUSH_LEN
			var cap := Biz.bakery_sell_cap(s, E)
			var shelf := cap * (180.0 if mgr else 60.0)
			_text(r.position + Vector2(10, 18), "Baking %s/s · selling up to %s/s" % [Econ.fmt_num(float(int(s.a))), Econ.fmt_num(cap * (3.0 if rush else 1.0))], 12, C_MUTED)
			var rt := "MORNING RUSH! %s" % Econ.fmt_time(Biz.RUSH_LEN - float(s.rush_t)) if rush else "Rush in %s" % Econ.fmt_time(Biz.RUSH_PERIOD - float(s.rush_t))
			_text_r(r.end.x - 10, r.position.y + 18, rt, 12, C_ACCENT if rush else C_DIM)
			var bar := Rect2(r.position.x + 10, r.position.y + 30, r.size.x - 20, 10)
			_rr(bar, Color(1, 1, 1, 0.08), 5)
			var f := clampf(float(s.stock) / maxf(shelf, 1e-9), 0.0, 1.0)
			_rr(Rect2(bar.position, Vector2(maxf(10.0, bar.size.x * f), 10)), col, 5)
			var stale := "Shelf full: extra bread goes stale" if f > 0.98 else ("Stock %s loaves" % Econ.fmt_num(float(s.stock)))
			if int(s.a) < cap * 0.8:
				stale = "Counters idle: more ovens would sell"
			_text(r.position + Vector2(10, 56), stale, 12, C_ORANGE if f > 0.98 else C_MUTED)
		"catering":
			var free := int(s.a) - Biz.busy_crew(s)
			_text(r.position + Vector2(10, 18), "Crew free %d/%d · jobs %d/%d · new offers in %s" % [free, int(s.a), (s.jobs as Array).size(), Biz.catering_max_jobs(s), Econ.fmt_time(float(s.offer_t))], 12, C_MUTED)
			var offers: Array = s.offers
			var oy := r.position.y + 26
			for k in 3:
				var orr := Rect2(r.position.x + 10, oy, r.size.x - 20, 34)
				if k < offers.size():
					var o: Dictionary = offers[k]
					var ok := Biz.can_accept(s, k)
					_rr(orr, Color(1, 1, 1, 0.05), 8)
					_text(orr.position + Vector2(8, 15), _fit(String(o.name), 13, orr.size.x - 120), 13, C_INK if ok else C_DIM)
					_text(orr.position + Vector2(8, 29), "%d crew · %s" % [int(o.crew), Econ.fmt_time(float(o.dur))], 11, C_MUTED)
					var pay := float(o.pay) * float(E.agg().twist.catering) * Biz.mult(i, E)
					_button("accept:%d:%d" % [i, k], Rect2(orr.end.x - 104, orr.position.y + 3, 100, 28), "Take " + Econ.fmt_money(pay), "buy" if ok else "", "content", false, ok, 12)
				oy += 38
			var jobs: Array = s.jobs
			var jy := r.end.y - 6
			var jw := (r.size.x - 20) / maxf(1.0, float(Biz.catering_max_jobs(s)))
			for k in jobs.size():
				var j: Dictionary = jobs[k]
				var jr := Rect2(r.position.x + 10 + k * jw, jy - 6, jw - 4, 6)
				cv.draw_rect(jr, Color(1, 1, 1, 0.08))
				cv.draw_rect(Rect2(jr.position, Vector2(jr.size.x * (1.0 - float(j.t) / maxf(float(j.dur), 1.0)), 6)), col)
		"bar":
			var m := Biz.bar_mix(s)
			_text(r.position + Vector2(10, 18), "Rowdiness" + ("   CLOSED %s" % Econ.fmt_time(float(s.closed_t)) if float(s.closed_t) > 0.0 else ""), 12, C_RED if float(s.closed_t) > 0.0 else C_MUTED)
			var bar := Rect2(r.position.x + 10, r.position.y + 28, r.size.x - 130, 10)
			_rr(bar, Color(1, 1, 1, 0.08), 5)
			var f := clampf(float(s.rowdy) / 100.0, 0.0, 1.0)
			_rr(Rect2(bar.position, Vector2(maxf(10.0, bar.size.x * f), 10)), C_RED.lerp(C_ACCENT, 1.0 - f), 5)
			var per_min := Biz.bar_incident_rate(s, E) * 60.0
			_text(r.position + Vector2(10, 56), "~%s incidents/min · %d so far" % [Econ.fmt_mult(snappedf(per_min, 0.01)), int(s.incidents)], 12, C_MUTED)
			_button("happy:%d" % i, Rect2(r.end.x - 112, r.position.y + 8, 102, 46), "Happy hour\n" + ("ON" if s.happy else "OFF"), "accent" if s.happy else "", "content", false, true, 14)
		"hotel":
			var sea := Biz.season(s)
			var left := Biz.SEASON_LEN - fmod(float(s.season_t), Biz.SEASON_LEN)
			var h := Biz.hotel_rev(i, s, E, sea, float(s.rate))
			var best := Biz.hotel_best_rate(i, s, E, sea)
			_text(r.position + Vector2(10, 18), "%s season (%s left) · occupancy %d%%" % [Biz.SEASONS[sea], Econ.fmt_time(left), int(round(float(h.occ) * 100.0))], 12, C_MUTED)
			_text(r.position + Vector2(10, 42), "Room rate x" + Econ.fmt_mult(snappedf(float(s.rate), 0.01)), 15, col)
			_text(r.position + Vector2(10, 62), "Fills every room at x%s" % Econ.fmt_mult(snappedf(best, 0.01)), 11, C_DIM)
			var auto: bool = mgr and bool(s.rate_auto)
			_button("rate:%d:down" % i, Rect2(r.end.x - 150, r.position.y + 24, 40, 40), "-", "", "content", true, not auto, 20)
			_button("rate:%d:up" % i, Rect2(r.end.x - 106, r.position.y + 24, 40, 40), "+", "", "content", true, not auto, 20)
			if mgr:
				_button("rate:%d:auto" % i, Rect2(r.end.x - 62, r.position.y + 24, 52, 40), "Auto", "on" if auto else "ghost", "content", false, true, 12)
		"wholesale":
			var mp := float(s.mprice)
			var cap := Biz.wholesale_cap(s)
			var mc := C_GREEN if mp >= 1.3 else (C_ACCENT if mp >= 0.8 else C_RED)
			_text(r.position + Vector2(10, 18), "Market price", 12, C_MUTED)
			_text(r.position + Vector2(10 + _tw("Market price ", 12), 18), "x" + Econ.fmt_mult(snappedf(mp, 0.01)), 14, mc)
			var bar := Rect2(r.position.x + 10, r.position.y + 28, r.size.x - 130, 10)
			_rr(bar, Color(1, 1, 1, 0.08), 5)
			_rr(Rect2(bar.position, Vector2(maxf(10.0, bar.size.x * clampf(float(s.stock) / maxf(cap, 1.0), 0.0, 1.0)), 10)), col, 5)
			_text(r.position + Vector2(10, 56), "Food costs -%s pts empire-wide" % Econ.fmt_mult(snappedf(Biz.food_cut(s), 0.1)), 12, C_MUTED)
			var v := float(s.stock) * Biz.wholesale_price(i, s, E) * 0.9
			_button("ws_sell:%d" % i, Rect2(r.end.x - 112, r.position.y + 8, 102, 46), "Sell stock\n" + Econ.fmt_money(v), "accent" if mp >= 1.3 else "", "content", false, float(s.stock) > 0.0, 14)


# ------------------------------------------------------------------ legacy tab

func _draw_legacy(y: float) -> float:
	var a := E.agg()
	var r := _row_rect(y, 196)
	_rr(r, C_CARD_HI, 14)
	_star(r.position + Vector2(34, 38), 20, C_ACCENT)
	_text(r.position + Vector2(64, 34), _stars_label(E.stars), 22, C_ACCENT)
	_text(r.position + Vector2(64, 54), "Income x%s from stars" % Econ.fmt_num(E.star_mult(a)), 14, C_MUTED)
	var pend := E.stars_pending()
	var lines := _wrap("Sell the company to an investor for stars. You restart from a single diner, keeping your stars, Grit and perks. Each star adds +%s%% income." % Econ.fmt_mult(snappedf((Econ.STAR_BASE + float(a.starpow)) * 100.0, 0.01)), 13, r.size.x - 32)
	for i in lines.size():
		_text(r.position + Vector2(16, 82 + i * 18), lines[i], 13, C_MUTED)
	var br := Rect2(r.position.x + 16, r.end.y - 62, r.size.x - 32, 48)
	if pend >= 1.0:
		_button("sell", br, "Sell company: +" + _stars_label(pend), "accent", "content", false, true, 17)
	else:
		var next := 1.0 + E.stars_earned
		var need := pow(pow(next / Econ.STAR_COEF, 5.0) * 1.0e10, Econ.COST_POW)
		_button("noop", br, "Earn %s in total for the next star" % Econ.fmt_money(need), "", "content", false, false, 14)
	y = r.end.y + 12
	y = _perk_list(y, "star")
	# ---- grit
	var gr := _row_rect(y + 6, 150)
	_rr(gr, Color("2a1710"), 14, Color(C_GRIT, 0.5), 1)
	_grit_icon(gr.position + Vector2(34, 38), C_GRIT)
	_text(gr.position + Vector2(64, 34), "%s Grit" % Econ.fmt_num(E.grit), 22, C_GRIT)
	_text(gr.position + Vector2(64, 54), "Income x%s from Grit" % Econ.fmt_mult(snappedf(E.grit_mult(), 0.01)), 14, C_MUTED)
	var gl := _wrap("Going bankrupt hurts, but you learn. Each bankruptcy pays Grit based on how much this run earned (now: %s). Grit adds +1%% income each and buys perks that make risk safer." % Econ.fmt_num(E.grit_pending()), 13, gr.size.x - 32)
	for i in gl.size():
		_text(gr.position + Vector2(16, 82 + i * 18), gl[i], 13, C_MUTED)
	y = gr.end.y + 12
	y = _perk_list(y, "grit")
	return y


func _grit_icon(c: Vector2, col_: Color) -> void:
	# a clenched fist, roughly: a rounded block with knuckle lines
	_rr(Rect2(c - Vector2(14, 12), Vector2(28, 24)), col_, 8)
	for k in 3:
		cv.draw_line(c + Vector2(-7 + k * 7, -12), c + Vector2(-7 + k * 7, -2), Color("2a1710"), 2)
	cv.draw_rect(Rect2(c + Vector2(-10, 10), Vector2(20, 8)), col_)


func _perk_list(y: float, cur: String) -> float:
	var total := 0
	var owned := 0
	for u in E.upgrades:
		if u.legacy and E.currency(u) == cur:
			total += 1
			if E.legacy.has(int(u.id)):
				owned += 1
	y = _section(y, "Legacy perks" if cur == "star" else "Grit perks", "%d / %d owned" % [owned, total])
	var shown := {}
	var col := C_ACCENT if cur == "star" else C_GRIT
	for u in E.upgrades:
		if not u.legacy or E.currency(u) != cur:
			continue
		var kind := String(u.req[1])
		if shown.has(kind) or E.legacy.has(int(u.id)):
			continue
		shown[kind] = true
		var rr := _row_rect(y, 70)
		if _visible(rr):
			var can := E.legacy_available(u) and float(u.star) <= E.wallet(cur)
			_rr(rr, C_CARD, 12)
			cv.draw_rect(Rect2(rr.position.x, rr.position.y + 10, 4, rr.size.y - 20), col)
			_text(rr.position + Vector2(14, 28), _fit(String(u.name), 16, rr.size.x - 150), 16)
			_text(rr.position + Vector2(14, 50), _fit(E.effect_text(u.eff), 13, rr.size.x - 150), 13, C_MUTED)
			var b := Rect2(rr.end.x - 124, rr.position.y + 12, 114, rr.size.y - 24)
			var lab := _stars_label(float(u.star)) if cur == "star" else "%s grit" % Econ.fmt_num(float(u.star))
			_button("legacy:%d" % int(u.id), b, lab, ("accent" if cur == "star" else "red") if can else "", "content", false, can, 15)
		y += 76
	if shown.is_empty():
		var rr := _row_rect(y, 50)
		_text_c(rr, rr.position.y + 30, "Every perk owned. Legendary.", 15, col)
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
	y = _draw_backup(y + 6)
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
		["Bankruptcies", str(E.bankruptcies)],
		["Grit", Econ.fmt_num(E.grit)],
		["Debt", Econ.fmt_money(E.debt)],
		["Businesses running", "%d / %d" % [E.biz_open_count(), Biz.N]],
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


func _draw_backup(y: float) -> float:
	y = _section(y, "Your save")
	var r := _row_rect(y, 84)
	_rr(r, C_CARD, 12)
	var ago := int(Time.get_unix_time_from_system()) - last_saved_unix
	var ok := store.last_write_ok
	var where := "browser storage x%d + backups" % store.last_places if ok else "not saved yet"
	_text(r.position + Vector2(14, 26), "Saved %s ago" % Econ.fmt_time(float(maxi(ago, 1))) if last_saved_unix > 0 else "Not saved yet", 16, C_GREEN if ok else C_ORANGE)
	_text(r.position + Vector2(14, 48), _fit(where, 13, r.size.x - 120), 13, C_MUTED)
	_text(r.position + Vector2(14, 68), _fit("Auto-saves every %ds and when you leave" % int(AUTOSAVE), 12, r.size.x - 120), 12, C_DIM)
	_button("save_now", Rect2(r.end.x - 96, r.position.y + 20, 86, 44), "Save now", "", "content", false, true, 14)
	y = r.end.y + 8
	var tip := _wrap("Browsers can wipe site data (clearing history, low storage, or Safari after ~7 days without a visit). Keep a backup code somewhere safe, like your notes app.", 13, content_r.size.x - 40)
	for l in tip:
		_text(Vector2(content_r.position.x + 18, y + 14), l, 13, C_DIM)
		y += 17
	y += 8
	var w := (content_r.size.x - 24 - 8) * 0.5
	var x := content_r.position.x + 12
	_button("copy_code", Rect2(x, y, w, 44), "Copy save code", "accent", "content", false, true, 14)
	_button("download", Rect2(x + w + 8, y, w, 44), "Download backup", "", "content", false, true, 14)
	y += 52
	_button("import", _row_rect(y, 44), "Restore from a save code", "", "content", false, true, 14)
	return y + 52


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
		"bankrupt": _modal_bankrupt(vs)
		"file": _modal_file(vs)
		"sell_biz": _modal_sell_biz(vs)
		"import": _modal_import(vs)


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
	var gg := float(modal_data.get("grit", 0.0))
	var title := "Sold! +" + _stars_label(g) if g > 0.0 else ("Back on your feet" if modal_data.has("grit") else "Open your first restaurant")
	_text_c(r, r.position.y + 36, title, 22, C_ACCENT if g > 0.0 else (C_GRIT if gg > 0.0 else C_INK))
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


func _modal_import(vs: Vector2) -> void:
	var r := _modal_card(vs, 290)
	_rr(r, C_BG, 16, C_LINE, 1)
	_text_c(r, r.position.y + 40, "Restore this save?", 22)
	var t := int(modal_data.get("t", 0))
	var when := Time.get_datetime_string_from_unix_time(t, true) if t > 0 else "unknown time"
	var rows := [
		["Saved", when],
		["Stars", Econ.fmt_num(float(modal_data.get("stars", 0.0)))],
		["Cash", Econ.fmt_money(float(modal_data.get("cash", 0.0)))],
		["Earned all time", Econ.fmt_money(float(modal_data.get("life", 0.0)))],
	]
	for i in rows.size():
		var yy := r.position.y + 78 + i * 24
		_text(Vector2(r.position.x + 24, yy), String(rows[i][0]), 14, C_MUTED)
		_text_r(r.end.x - 24, yy, String(rows[i][1]), 14, C_INK)
	_text_c(r, r.position.y + 190, "Your current game is kept as a backup first.", 13, C_DIM)
	var bw := (r.size.x - 44) * 0.5
	_button("close", Rect2(r.position.x + 16, r.end.y - 64, bw, 48), "Cancel", "", "modal", false, true, 16)
	_button("import_yes", Rect2(r.position.x + 28 + bw, r.end.y - 64, bw, 48), "Restore", "accent", "modal", false, true, 16)


func _modal_bankrupt(vs: Vector2) -> void:
	var r := _modal_card(vs, 330)
	_rr(r, Color("1c0906"), 16, C_RED, 2)
	_text_c(r, r.position.y + 46, "BANKRUPT", 30, C_RED)
	_text_c(r, r.position.y + 76, "The bank took everything.", 15, C_MUTED)
	_grit_icon(Vector2(r.get_center().x, r.position.y + 118), C_GRIT)
	_text_c(r, r.position.y + 166, "+%s Grit" % Econ.fmt_num(float(modal_data.get("grit", 0.0))), 24, C_GRIT)
	var lost := float(modal_data.get("lost_stars", 0.0))
	var t := "Grit gives +1% income each and buys perks in the Legacy tab."
	if lost >= 1.0:
		t = "You lost the %s this run would have paid. " % _stars_label(lost) + t
	var lines := _wrap(t, 13, r.size.x - 40)
	for i in lines.size():
		_text_c(r, r.position.y + 196 + i * 18, lines[i], 13, C_MUTED)
	_button("after_bankrupt", Rect2(r.position.x + 16, r.end.y - 64, r.size.x - 32, 48), "Start over", "red", "modal", false, true, 17)


func _modal_file(vs: Vector2) -> void:
	var r := _modal_card(vs, 280)
	_rr(r, C_BG, 16, C_RED, 1)
	_text_c(r, r.position.y + 42, "File for bankruptcy?", 22, C_RED)
	var lines := _wrap("Everything resets like selling the company, but you get %s Grit instead of stars, and this run's stars (%s) are lost. Debt is wiped." % [Econ.fmt_num(E.grit_pending()), Econ.fmt_num(E.stars_pending())], 14, r.size.x - 40)
	for i in lines.size():
		_text_c(r, r.position.y + 78 + i * 19, lines[i], 14, C_MUTED)
	var bw := (r.size.x - 44) * 0.5
	_button("close", Rect2(r.position.x + 16, r.end.y - 64, bw, 48), "Keep fighting", "", "modal", false, true, 15)
	_button("file_yes", Rect2(r.position.x + 28 + bw, r.end.y - 64, bw, 48), "File", "red", "modal", false, true, 16)


func _modal_sell_biz(vs: Vector2) -> void:
	var i := int(modal_data.get("i", 0))
	var r := _modal_card(vs, 230)
	_rr(r, C_BG, 16, C_LINE, 1)
	_text_c(r, r.position.y + 42, "Sell the %s?" % Biz.DEFS[i].name, 21)
	var v := Biz.invested(i, E.biz[i], E) * E.refund_rate()
	_text_c(r, r.position.y + 80, "+" + Econ.fmt_money(v), 24, C_GREEN)
	_text_c(r, r.position.y + 108, "%d%% of what you put in. You can reopen it later." % int(round(E.refund_rate() * 100.0)), 13, C_MUTED)
	var bw := (r.size.x - 44) * 0.5
	_button("close", Rect2(r.position.x + 16, r.end.y - 64, bw, 48), "Keep it", "", "modal", false, true, 15)
	_button("sell_biz_yes", Rect2(r.position.x + 28 + bw, r.end.y - 64, bw, 48), "Sell", "accent", "modal", false, true, 16)


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
		"net": float(em_cache.get("net", 0.0)), "debt": E.debt, "grit": E.grit, "bankruptcies": E.bankruptcies,
		"in_red": E.in_red(), "event": String(E.event.get("id", "")), "biz_open": E.biz_open_count(),
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


## Shows an event card now (for testing). Pass an id from events.gd to pick one.
func dev_event(id := "") -> void:
	var ev := Events.make(E.rng, maxf(float(em_cache.get("gross", 1.0)), 1.0), 0.0, float(E.agg().event_cost), E.cash > 0.0)
	if id != "":
		for src in Events.LIST:
			if String(src.id) == id:
				ev = (src as Dictionary).duplicate(true)
				ev.r = maxf(float(em_cache.get("gross", 1.0)), 1.0)
				ev.cost_mult = float(E.agg().event_cost)
				ev.t = Events.TIMEOUT
	E.event = ev
