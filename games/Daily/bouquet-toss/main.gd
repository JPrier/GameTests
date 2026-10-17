extends Node2D
## Bouquet Toss — a daily wedding bouquet trick shot.
##
## This script is the game shell: layout, input, the throw flow, drawing order, saving,
## sharing and dev mode. Physics, generation, validation, scoring, sharing text and saving
## live in core/ with no dependency on anything here; art.gd draws, audio.gd makes sounds.

const P = preload("res://core/physics.gd")
const L = preload("res://core/level.gd")
const Levels = preload("res://core/levels.gd")
const V = preload("res://core/validator.gd")
const Gen = preload("res://core/generator.gd")
const Daily = preload("res://core/daily.gd")
const Scoring = preload("res://core/scoring.gd")
const Share = preload("res://core/share.gd")
const Save = preload("res://core/save.gd")
const Art = preload("res://art.gd")
const Audio = preload("res://audio.gd")

const DEFAULT_URL := "https://jprier.github.io/GameTests/bouquet-toss/"
const GOAL := "Toss the bouquet into the glowing hands."

const HEADER_H := 66.0
const FOOTER_H := 112.0
const MAX_PULL := 180.0          # pull for 100% power (UI units: about 150 CSS px on a phone)
const MIN_PULL := 18.0           # shorter pulls are taps, not throws
const PREVIEW_STEPS := 40        # 1/3 s of predicted flight
const SETTLE_TIME := 1.0
const ARCHIVE_ROWS := 6
const SAVE_VERSION := 2
const HOLES_H := 66

const C_BG := Color("fdf3e6")
const C_PANEL := Color("fffaf2")
const C_INK := Color("2e2440")
const C_MUTED := Color("7a6f80")
const C_FAINT := Color("e7dccd")
const C_BTN := Color("f3e7d6")
const C_ACCENT := Color("e0607e")
const C_ACCENT_DARK := Color("b9435f")
const C_TEAL := Color("2fa39a")
const C_GOLD := Color("f2b84b")

# ------------------------------------------------------------------ game state
var today := ""
var date := ""
var level: Dictionary = {}
var comp: Dictionary = {}
var save = null
var base_url := DEFAULT_URL
var dev_mode := false
var dev_open := false
var phase := "loading"            # loading, aim, flight, settle, won
var pending_day := ""
var load_frames := 0

var hole := 0                     # which of the day's five throws is on stage
var holes: Array = []             # per throw: {throws: [{a, p, o, acc}], done, acc, aim}
var levels: Array = []            # level per throw, built on first visit
var throws: Array = []            # the current throw's counted attempts (same Array as in holes)
var done := false                 # all five caught (result is final)
var result: Dictionary = {}       # {throws (total attempts), accuracy, seconds, holes: [[outcomes]]}
var next_pending := -1.0
var practice_throws := 0
var elapsed := 0.0
var started := false
var aim_a := 45
var aim_p := 55
var has_aim := false              # something to preview (dragging or keyboard aim)
var last_aim := Vector2i(-1, -1)

var flight: Dictionary = {}
var flight_t := 0.0
var flight_event := 0
var flight_counted := true
var ghost: PackedFloat64Array = []
var ghost_end := Vector2(-1, -1)
var settle_t := 0.0
var won_t := 0.0
var end_pending := -1.0
var status := ""
var status_good := false

# ------------------------------------------------------------------ ui state
var font: Font
var bold: Font
var modal := ""                   # "", "help", "end", "archive"
var archive_page := 0
var archive_results: Dictionary = {}
var buttons: Array = []
var toast := ""
var toast_t := 0.0
var particles: Array = []
var shake := 0.0
var anim_t := 0.0
var title_taps := 0
var title_tap_t := -10.0
var share_pending := false
var last_share_text := ""
var sound_on := true
var show_tutorial := false
var key_repeat := 0.0
var save_t := 0.0
var preview: PackedFloat64Array = []

# layout
var vs := Vector2(720, 720)        # viewport size (logical px)
var k := 1.0                       # UI scale: bigger on phones, so text stays readable
var uvs := Vector2(720, 720)       # UI layer size in UI units (vs / k)
var world_scale := 1.0
var world_origin := Vector2.ZERO
var footer_rect := Rect2()

# pointer
var pressing := false
var press_pos := Vector2()
var cur_pos := Vector2()
var aiming := false
var press_button := ""

# layers
var venue_layer: Node2D
var actor_layer: Node2D
var ui_layer: Node2D
var audio: Node


func _ready() -> void:
	font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = font
	fv.variation_embolden = 0.7
	bold = fv
	RenderingServer.set_default_clear_color(C_BG)
	venue_layer = Node2D.new()
	actor_layer = Node2D.new()
	ui_layer = Node2D.new()
	add_child(venue_layer)
	add_child(actor_layer)
	add_child(ui_layer)
	venue_layer.draw.connect(_draw_venue)
	actor_layer.draw.connect(_draw_actors)
	ui_layer.draw.connect(_draw_ui)
	# The UI layer is pre-scaled to CSS px (see ui_scale()), so GTUI works 1:1 in dp inside it.
	GTUI.setup(ui_layer, {
		"bg": C_BG, "surface": C_PANEL, "surface_high": C_BTN, "text": C_INK, "text_muted": C_MUTED,
		"border": C_FAINT, "accent": C_ACCENT, "on_accent": Color.WHITE,
		"success": C_TEAL, "danger": C_ACCENT_DARK, "focus": C_ACCENT_DARK, "scrim": Color(0.12, 0.08, 0.16, 0.45),
	}, 1.0)
	audio = Audio.new()
	add_child(audio)
	_add_key_action("aim_up", [KEY_UP, KEY_W])
	_add_key_action("aim_down", [KEY_DOWN, KEY_S])
	_add_key_action("power_up", [KEY_RIGHT, KEY_D])
	_add_key_action("power_down", [KEY_LEFT, KEY_A])
	_add_key_action("throw", [KEY_SPACE, KEY_ENTER])
	_add_key_action("dev", [KEY_QUOTELEFT])
	get_viewport().size_changed.connect(_layout)
	today = Daily.today_local()
	var url := _read_url()
	if String(url.get("base", "")) != "":
		base_url = String(url.base)
	dev_mode = OS.is_debug_build() or String(url.get("dev", "")) == "1"
	dev_open = String(url.get("dev", "")) == "1"
	save = Save.new(dev_mode)
	_load_settings()
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


func _load_settings() -> void:
	var s: Dictionary = save.load_settings()
	sound_on = bool(s.get("sound", true))
	show_tutorial = not bool(s.get("tutorial_seen", false))
	audio.enabled = sound_on


func _save_settings() -> void:
	save.save_settings({"sound": sound_on, "tutorial_seen": not show_tutorial})


# ------------------------------------------------------------------ layout

func _layout() -> void:
	vs = get_viewport_rect().size
	k = ui_scale()
	uvs = vs / k
	ui_layer.scale = Vector2(k, k)
	var hh := (HEADER_H + HOLES_H) * k
	var fh := FOOTER_H * k
	var avail := Rect2(0, hh, vs.x, maxf(100.0, vs.y - hh - fh))
	world_scale = minf((avail.size.x - 8.0) / float(L.W), avail.size.y / float(L.H))
	var ww := float(L.W) * world_scale
	var wh := float(L.H) * world_scale
	var top := avail.position.y + maxf(0.0, (avail.size.y - wh) * 0.42)
	world_origin = Vector2((vs.x - ww) * 0.5, top)
	footer_rect = Rect2(0, uvs.y - FOOTER_H, uvs.x, FOOTER_H)
	for layer in [venue_layer, actor_layer]:
		layer.position = world_origin
		layer.scale = Vector2(world_scale, world_scale)
	_redraw_all()


## How many logical px one CSS px is (GTUI's physical scale). The UI layer is drawn in dp at this scale,
## so text and buttons keep a comfortable physical size on any screen.
func ui_scale() -> float:
	return GTUI.css_scale(self)


func _redraw_all() -> void:
	venue_layer.queue_redraw()
	actor_layer.queue_redraw()
	ui_layer.queue_redraw()


func to_world(p: Vector2) -> Vector2:
	return (p - world_origin) / world_scale


func to_screen(p: Vector2) -> Vector2:
	return world_origin + p * world_scale


# ------------------------------------------------------------------ days

## Shows the "setting up" card for a frame, then builds the day.
func request_day(d: String) -> void:
	_save_now()
	phase = "loading"
	load_frames = 0
	pending_day = d
	_redraw_all()


func load_day(d: String) -> void:
	date = d
	holes = []
	levels = []
	for i in Daily.HOLES:
		holes.append({"throws": [], "done": false, "acc": 0, "aim": []})
		levels.append({})
	done = false
	result = {}
	practice_throws = 0
	elapsed = 0.0
	started = false
	particles = []
	end_pending = -1.0
	next_pending = -1.0
	var start := _load_progress()
	enter_hole(start)
	if done:
		modal = "end"


## Puts throw `i` of the day on stage (building its level the first time).
func enter_hole(i: int) -> void:
	hole = clampi(i, 0, Daily.HOLES - 1)
	if (levels[hole] as Dictionary).is_empty():
		levels[hole] = level_for(date, hole)
	level = levels[hole]
	comp = P.compile(level)
	throws = holes[hole].throws
	flight = {}
	ghost = PackedFloat64Array()
	ghost_end = Vector2(-1, -1)
	status = ""
	status_good = false
	has_aim = false
	preview = PackedFloat64Array()
	next_pending = -1.0
	aim_a = 135 if bool(level.mirror) else 45
	aim_p = 55
	last_aim = Vector2i(-1, -1)
	var aim: Array = holes[hole].get("aim", [])
	if aim.size() == 2:
		aim_a = int(aim[0])
		aim_p = int(aim[1])
		last_aim = Vector2i(aim_a, aim_p)
	phase = "aim"
	_redraw_all()


## The first throw still to land (or the first one, once the day is done).
func next_open_hole(after := -1) -> int:
	for k in Daily.HOLES:
		var i := (after + 1 + k) % Daily.HOLES
		if not bool(holes[i].done):
			return i
	return 0


func attempts_total() -> int:
	var n := 0
	for h in holes:
		n += (h.throws as Array).size()
	return n


func holes_done() -> int:
	var n := 0
	for h in holes:
		if bool(h.done):
			n += 1
	return n


## The level for one of a date's throws: the precomputed table, then the local cache, then a
## full search.
func level_for(d: String, i: int) -> Dictionary:
	var lv := Levels.from_table(d, i)
	if not lv.is_empty():
		return lv
	var path := "user://level_v%d_%s_%d.json" % [Gen.GEN_VERSION, d, i]
	var cached = Save.read_json(path)
	if cached is Dictionary and String(cached.get("date", "")) == d:
		var c: Dictionary = L.normalize(cached)
		if c.has("solution") and P.throw(c, int(c.solution.a), int(c.solution.p)).outcome == "catch":
			return c
	lv = Levels.search(d, i)
	Save.write_json(path, lv)
	return lv


## Restores the day from the save; returns which throw to show first.
func _load_progress() -> int:
	var data: Dictionary = save.load_day(date)
	if data.is_empty():
		return 0
	if int(data.get("v", 1)) != SAVE_VERSION:
		# A save from the one-throw version of the game: start the day fresh, and drop its old
		# result from the past-days list and the home page.
		save.wipe_day(date)
		if not dev_mode and OS.has_feature("web"):
			JavaScriptBridge.eval("try{localStorage.removeItem(%s)}catch(e){}" % JSON.stringify("gametests:bouquet-toss:" + date), true)
		return 0
	var saved: Array = data.get("holes", [])
	if saved.size() != Daily.HOLES:
		return 0
	for i in Daily.HOLES:
		var h = saved[i]
		if h is Dictionary and h.get("throws", []) is Array:
			holes[i] = {"throws": h.throws, "done": bool(h.get("done", false)), "acc": int(h.get("acc", 0)), "aim": h.get("aim", [])}
	done = bool(data.get("done", false)) and holes_done() == Daily.HOLES
	result = data.get("result", {}) if done else {}
	elapsed = float(data.get("seconds", 0.0))
	practice_throws = int(data.get("practice", 0))
	started = attempts_total() > 0
	return clampi(int(data.get("hole", 0)), 0, Daily.HOLES - 1) if not done else 0


func _save_now() -> void:
	if level.is_empty() or phase == "loading" or holes.is_empty():
		return
	save.save_day(date, {"v": SAVE_VERSION, "holes": holes, "hole": hole, "done": done, "result": result,
		"seconds": elapsed, "practice": practice_throws})


# ------------------------------------------------------------------ throwing (also used by tests)

func can_throw() -> bool:
	return phase == "aim" and modal == "" and not level.is_empty()


## Sets the aim (whole degrees, power 1..100) and refreshes the preview.
func aim_to(a: int, p: int) -> void:
	started = true
	aim_a = posmod(a, 360)
	aim_p = clampi(p, 1, 100)
	has_aim = true
	_update_preview()


func throw(a: int, p: int) -> bool:
	if not can_throw():
		return false
	aim_to(a, p)
	has_aim = false
	last_aim = Vector2i(aim_a, aim_p)
	started = true
	if show_tutorial:
		show_tutorial = false
		_save_settings()
	flight = P.simulate(comp, aim_a, aim_p, 1)
	flight_t = 0.0
	flight_event = 0
	flight_counted = not bool(holes[hole].done)
	phase = "flight"
	status = ""
	audio.play("whoosh", 0.8 + aim_p / 200.0)
	_redraw_all()
	return true


## Jumps to the end of the current flight (tests, dev, and impatient taps).
func skip_flight() -> void:
	if phase == "flight":
		flight_t = float(flight.steps) * P.DT + 1.0
		_tick_flight(0.0)


func _tick_flight(delta: float) -> void:
	var steps := int(flight.steps)
	var speed := 1.0
	if String(flight.outcome) == "catch" and flight_t / P.DT > steps - 24:
		speed = 0.4                         # a little slow motion into the hands
	flight_t += delta * speed
	var idx := flight_t / P.DT
	var events: Array = flight.events
	while flight_event < events.size() and float(events[flight_event].s) <= idx:
		_impact(events[flight_event])
		flight_event += 1
	if idx >= float(steps):
		_land()


func _impact(e: Dictionary) -> void:
	var k := String(e.k)
	var v := float(e.v)
	var pos := Vector2(float(e.x), float(e.y))
	var loud := clampf(v / 700.0, 0.2, 1.0)
	match k:
		"balloon": audio.play("boing", randf_range(0.9, 1.15), linear_to_db(loud))
		"fumble":
			audio.play("boing", 0.7)
			_toast("Too fast to catch!")
			return
		"cake": pass
		"curtain", "hedge", "plant": audio.play("tap", 0.6, linear_to_db(loud * 0.7))
		"chandelier", "railing", "pillar": audio.play("tap", 1.4, linear_to_db(loud))
		_: audio.play("thunk", randf_range(0.9, 1.1), linear_to_db(loud))
	_petals(pos, int(4 + loud * 6))


func _land() -> void:
	var o := String(flight.outcome)
	var acc := Scoring.accuracy(float(flight.catch_d), float(level.target.r)) if o == "catch" else 0
	var path: PackedFloat64Array = flight.path
	ghost = path
	ghost_end = Vector2(float(flight.end_x), float(flight.end_y))
	holes[hole].aim = [aim_a, aim_p]
	if flight_counted:
		throws.append({"a": aim_a, "p": aim_p, "o": o, "acc": acc})
	else:
		practice_throws += 1
	if o == "catch":
		_catch(acc)
	else:
		if o == "splat":
			_splat(ghost_end)
		else:
			audio.play("miss", 1.0, -6.0)
		status = Scoring.outcome_text(o, flight.hits)
		status_good = false
		phase = "settle"
		settle_t = SETTLE_TIME
	_save_now()
	_redraw_all()


func _buzz(ms: int) -> void:
	if sound_on and OS.has_feature("web"):
		JavaScriptBridge.eval("try{navigator.vibrate&&navigator.vibrate(%d)}catch(e){}" % ms, true)


func _catch(acc: int) -> void:
	phase = "won"
	won_t = 0.0
	audio.play("chime")
	_buzz(40)
	_burst(Vector2(level.target.hands[0], level.target.hands[1]))
	status_good = true
	if flight_counted:
		holes[hole].done = true
		holes[hole].acc = acc
		if holes_done() == Daily.HOLES:
			done = true
			var outs: Array = []
			var acc_sum := 0
			for h in holes:
				var o: Array = []
				for t in h.throws:
					o.append(String(t.o))
				outs.append(o)
				acc_sum += int(h.acc)
			result = {"throws": attempts_total(), "accuracy": int(round(float(acc_sum) / Daily.HOLES)),
				"seconds": snappedf(elapsed, 0.1), "holes": outs}
			save.record_result(date, Scoring.label(result))
			_mark_played()
			audio.play("fanfare", 1.0, -4.0)
			status = "All five caught! %s: %d tries." % [Scoring.rating_total(int(result.throws), Daily.HOLES), int(result.throws)]
			end_pending = 1.7
			_confetti()
		else:
			var n := throws.size()
			status = "Caught it %s! %d of 5 done." % ["first try" if n == 1 else "in %d tries" % n, holes_done()]
			next_pending = 1.5
	else:
		status = "Caught it! (practice, %d%%)" % acc


func _splat(p: Vector2) -> void:
	audio.play("splat")
	_buzz(20)
	shake = 0.35
	for i in 18:
		var a := randf_range(PI, TAU)
		particles.append({"p": p, "v": Vector2(cos(a), sin(a)) * randf_range(80, 260), "life": 0.8, "max": 0.8,
			"c": [Color("fffaf3"), Color("ffd1dc"), Color("ffe9a8")][i % 3], "r": randf_range(3, 7), "world": true})


func _petals(p: Vector2, n: int) -> void:
	for i in n:
		var a := randf_range(0, TAU)
		particles.append({"p": p, "v": Vector2(cos(a), sin(a)) * randf_range(40, 160), "life": 0.6, "max": 0.6,
			"c": Art.BLOOM[i % Art.BLOOM.size()], "r": randf_range(2.5, 4.5), "world": true})


func _burst(p: Vector2) -> void:
	for i in 26:
		var a := TAU * i / 26.0
		particles.append({"p": p, "v": Vector2(cos(a), sin(a)) * randf_range(160, 320), "life": 0.9, "max": 0.9,
			"c": [C_GOLD, Color("ffffff"), C_ACCENT, Color("ff8fab")][i % 4], "r": randf_range(3, 6), "world": true, "star": true})


func _confetti() -> void:
	for i in 90:
		particles.append({"p": Vector2(randf_range(0, uvs.x), randf_range(-uvs.y * 0.4, 0)), "v": Vector2(randf_range(-40, 40), randf_range(120, 260)),
			"life": 3.2, "max": 3.2, "c": [C_ACCENT, C_GOLD, C_TEAL, Art.LILAC, Art.SKY][i % 5], "r": randf_range(4, 7),
			"world": false, "spin": randf_range(-8, 8), "rot": randf() * TAU})


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	anim_t += delta
	if phase == "loading":
		load_frames += 1
		ui_layer.queue_redraw()
		if load_frames >= 2:
			load_day(pending_day)
		return
	if share_pending:
		_poll_share()
	if toast_t > 0.0:
		toast_t -= delta
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
	if started and not done and modal == "" and phase != "won":
		elapsed += delta
	match phase:
		"flight":
			_tick_flight(delta)
		"settle":
			settle_t -= delta
			if settle_t <= 0.0:
				phase = "aim"
		"won":
			won_t += delta
			if end_pending > 0.0:
				end_pending -= delta
				if end_pending <= 0.0:
					end_pending = -1.0
					modal = "end"
			elif next_pending > 0.0:
				next_pending -= delta
				if next_pending <= 0.0:
					next_pending = -1.0
					enter_hole(next_open_hole(hole))
			elif won_t > 1.6 and modal == "":
				phase = "aim"
	_keyboard(delta)
	_tick_particles(delta)
	save_t += delta
	if save_t > 5.0:
		save_t = 0.0
		if started and not done:
			_save_now()
	actor_layer.queue_redraw()
	ui_layer.queue_redraw()


func _keyboard(delta: float) -> void:
	if Input.is_action_just_pressed("dev") and dev_mode:
		dev_open = not dev_open
	if not can_throw():
		return
	var da := 0
	var dp := 0
	var held := false
	for pair in [["aim_up", 1, 0], ["aim_down", -1, 0], ["power_up", 0, 1], ["power_down", 0, -1]]:
		if Input.is_action_just_pressed(pair[0]):
			da += pair[1]
			dp += pair[2]
			key_repeat = 0.35
		elif Input.is_action_pressed(pair[0]):
			held = true
			if key_repeat <= 0.0:
				da += pair[1]
				dp += pair[2]
	if held:
		key_repeat -= delta
		if key_repeat <= 0.0:
			key_repeat = 0.05
	if da != 0 or dp != 0:
		# Up always means "aim higher", whichever way the thrower faces.
		var face := -1 if bool(level.mirror) else 1
		aim_to(aim_a + da * face, aim_p + dp)
		audio.play("tick")
	if Input.is_action_just_pressed("throw") and GTUI.focused_id() == "":   # Enter/Space press the focused control instead
		throw(aim_a, aim_p)


func _tick_particles(delta: float) -> void:
	var keep: Array = []
	for p in particles:
		p.life -= delta
		if p.life <= 0.0:
			continue
		p.v.y += (420.0 if p.world else 60.0) * delta
		p.p += p.v * delta
		if p.has("rot"):
			p.rot += p.spin * delta
		keep.append(p)
	particles = keep


func _update_preview() -> void:
	if not has_aim or level.is_empty():
		preview = PackedFloat64Array()
		return
	var r := P.simulate(comp, aim_a, aim_p, 3, PREVIEW_STEPS, true)
	preview = r.path


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	var gt := GTUI.handle_input(ui_layer.make_input_local(event))
	if gt.has("activate"):
		for e in GTUI.tap_events(gt.pos * k):
			_input(e)
		return
	if gt.has("cancel"):
		if modal != "":
			modal = ""
			_redraw_all()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down(event.position)
		else:
			_pointer_up(event.position)
	elif event is InputEventMouseMotion and pressing:
		_pointer_move(event.position)


func _button_at(p: Vector2) -> String:
	for i in range(buttons.size() - 1, -1, -1):
		var b: Dictionary = buttons[i]
		if b.enabled and Rect2(b.rect).grow(4).has_point(p / k):
			return String(b.id)
	return ""


func _pointer_down(p: Vector2) -> void:
	pressing = true
	press_pos = p
	cur_pos = p
	aiming = false
	press_button = _button_at(p)
	if press_button != "" or modal != "":
		return
	if phase == "settle":
		phase = "aim"
		settle_t = 0.0
	if phase == "flight":
		skip_flight()
		pressing = false
		return
	if phase == "won" and end_pending < 0.0:
		if next_pending > 0.0:
			next_pending = 0.01        # a tap moves straight on to the next throw
		else:
			phase = "aim"


func _pointer_move(p: Vector2) -> void:
	cur_pos = p
	if press_button != "" or modal != "" or not can_throw():
		return
	var pull := press_pos - p
	if pull.length() >= MIN_PULL * k:
		if not aiming:
			aiming = true
		var a := int(round(rad_to_deg(atan2(-pull.y, pull.x))))
		var pw := clampi(int(round((pull.length() - MIN_PULL * k) / ((MAX_PULL - MIN_PULL) * k) * 100.0)), 1, 100)
		if a != aim_a or pw != aim_p:
			if absi(pw - aim_p) >= 5 or a != aim_a:
				audio.play("tick", 1.0 + pw / 200.0, -10.0)
		aim_to(a, pw)
	elif aiming:
		has_aim = false            # pulled back to the start: cancel
		preview = PackedFloat64Array()


func _pointer_up(p: Vector2) -> void:
	if not pressing:
		return
	pressing = false
	if press_button != "":
		if _button_at(p) == press_button:
			_press(press_button)
		press_button = ""
		return
	if modal != "":
		return
	if aiming and has_aim and (press_pos - p).length() >= MIN_PULL * k:
		throw(aim_a, aim_p)
	aiming = false


func _press(id: String) -> void:
	audio.play("tap", 1.3, -8.0)
	match id:
		"help": modal = "help"
		"sound":
			sound_on = not sound_on
			audio.enabled = sound_on
			_save_settings()
			_toast("Sound on" if sound_on else "Sound off")
		"archive": open_archive()
		"results":
			if done:
				modal = "end"
		"close", "got_it", "close_end": modal = ""
		"share": share()
		"copy": copy_result()
		"title": _title_tap()
		"arch_prev": archive_page = maxi(0, archive_page - 1)
		"arch_next": archive_page = mini(archive_pages() - 1, archive_page + 1)
		"dev_prev": dev_shift(-1)
		"dev_next": dev_shift(1)
		"dev_today": dev_set_day(today)
		"dev_random": dev_random_day()
		"dev_reset": dev_reset()
		"dev_win": dev_win()
		"dev_win_day": dev_win_day()
		"dev_reveal": dev_reveal()
		"dev_close": dev_open = false
		_:
			if id.begins_with("day:"):
				pick_day(id.substr(4))
			elif id.begins_with("hole:"):
				pick_hole(int(id.substr(5)))
	_redraw_all()


func _title_tap() -> void:
	if anim_t - title_tap_t > 1.5:
		title_taps = 0
	title_tap_t = anim_t
	title_taps += 1
	if title_taps >= 5:
		title_taps = 0
		if not dev_mode:
			dev_mode = true
			save = Save.new(true)
			_load_settings()
			request_day(date)
		dev_open = not dev_open


func _toast(msg: String) -> void:
	toast = msg
	toast_t = 2.4


# ------------------------------------------------------------------ results & sharing

func share_link() -> String:
	return base_url


func share_text() -> String:
	if not done:
		return ""
	return Share.text(int(level.number), result, share_link())


## Tells the GameTests home page this day is played (not in dev mode).
func _mark_played() -> void:
	if dev_mode or not OS.has_feature("web"):
		return
	var js := "try{localStorage.setItem(%s,%s)}catch(e){}" % [
		JSON.stringify("gametests:bouquet-toss:" + date), JSON.stringify(JSON.stringify({"result": Scoring.label(result)}))]
	JavaScriptBridge.eval(js, true)


func share() -> void:
	_send(share_text(), true)


func copy_result() -> void:
	_send(share_text(), false)


func _send(text: String, use_share_sheet: bool) -> void:
	if text == "":
		return
	last_share_text = text
	if OS.has_feature("web"):
		var js := """(function(t,s){
			window.__btShare='pending';
			var done=function(r){if(window.__btShare==='pending'){window.__btShare=r;}};
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
					setTimeout(function(){if(window.__btShare==='pending'){ask();}},2500);
					navigator.clipboard.writeText(t).then(function(){done('copied');},ask);
				}else{ask();}
			};
			if(s&&navigator.share){
				navigator.share({text:t}).then(function(){done('shared');},function(e){
					if(e&&e.name==='AbortError'){done('cancelled');}else{copy();}
				});
			}else{copy();}
		})(%s,%s)""" % [JSON.stringify(text), "true" if use_share_sheet else "false"]
		JavaScriptBridge.eval(js, true)
		share_pending = true
	else:
		DisplayServer.clipboard_set(text)
		_toast("Copied! Paste it anywhere.")


func _poll_share() -> void:
	var r = JavaScriptBridge.eval("window.__btShare||''", true)
	if typeof(r) != TYPE_STRING or r == "pending" or r == "":
		return
	share_pending = false
	match r:
		"copied": _toast("Copied! Paste it anywhere.")
		"shared": _toast("Shared!")
		"prompted", "cancelled": pass
		_: _toast("Couldn't share. Try Copy.")


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()


## Tapping a throw's chip goes to it (finished throws can be replayed as practice).
func pick_hole(i: int) -> void:
	if i == hole or phase == "flight":
		return
	end_pending = -1.0
	_save_now()
	enter_hole(i)


# ------------------------------------------------------------------ past days

func archive_count() -> int:
	return maxi(1, Daily.day_number(today))


func archive_pages() -> int:
	return ceili(float(archive_count()) / ARCHIVE_ROWS)


func open_archive() -> void:
	_save_now()
	archive_results = save.load_results()
	if not done and started and not archive_results.has(date):
		archive_results[date] = "In progress"
	var idx := clampi(Daily.day_number(today) - Daily.day_number(date), 0, archive_count() - 1)
	archive_page = idx / ARCHIVE_ROWS
	modal = "archive"


func pick_day(d: String) -> void:
	modal = ""
	if d != date and Daily.valid_date(d) and (dev_mode or (d >= Daily.EPOCH and d <= today)):
		request_day(d)


# ------------------------------------------------------------------ dev mode

func dev_set_day(d: String) -> void:
	if dev_mode and Daily.valid_date(d):
		_save_now()
		modal = ""
		load_day(d)


func dev_shift(days: int) -> void:
	dev_set_day(Daily.add_days(date, days))


func dev_random_day() -> void:
	dev_set_day(Daily.add_days(Daily.EPOCH, randi_range(-100, 700)))


func dev_reset() -> void:
	if not dev_mode:
		return
	save.wipe_day(date)
	modal = ""
	load_day(date)


## Throws the reference solution and lands it instantly.
func dev_win() -> void:
	if not dev_mode or level.is_empty():
		return
	modal = ""
	if phase != "aim":
		skip_flight()
		phase = "aim"
	var sol: Dictionary = level.get("solution", {})
	if throw(int(sol.a), int(sol.p)):
		skip_flight()


## Lands every remaining throw of the day with its reference throw.
func dev_win_day() -> void:
	if not dev_mode:
		return
	for i in Daily.HOLES:
		if not bool(holes[i].done):
			enter_hole(i)
			dev_win()


## Shows the reference throw's whole path as the ghost and sets the aim to it.
func dev_reveal() -> void:
	if not dev_mode or level.is_empty():
		return
	var sol: Dictionary = level.get("solution", {})
	var r := P.simulate(comp, int(sol.a), int(sol.p), 2)
	ghost = r.path
	ghost_end = Vector2(float(r.end_x), float(r.end_y))
	aim_to(int(sol.a), int(sol.p))


func dev_stats() -> Dictionary:
	if level.is_empty():
		return {}
	if (level.get("stats", {}) as Dictionary).is_empty():
		var st := V.evaluate(level)
		level.stats = {"rate": snappedf(float(st.rate), 0.0001), "solves": st.solves, "robust": st.robust, "routes": st.routes, "clusters": st.clusters}
	return level.stats


func _tries() -> Array:
	var out: Array = []
	for h in holes:
		out.append((h.throws as Array).size())
	return out


func get_agent_state() -> Dictionary:
	return {
		"day": date, "today": today, "number": int(level.get("number", 0)), "seed": int(level.get("seed", 0)),
		"archetype": String(level.get("archetype", "")), "attempt": int(level.get("attempt", 0)),
		"state": "loading" if phase == "loading" else ("won" if done else "playing"), "phase": phase,
		"hole": hole, "tries": _tries(), "holes_done": holes_done(),
		"throws": throws.size(), "practice_throws": practice_throws, "result": result,
		"aim": [aim_a, aim_p], "modal": modal, "dev_mode": dev_mode, "share_text": share_text(),
		"solution": level.get("solution", {}) if dev_mode else {}, "status": status,
		"elapsed": snappedf(elapsed, 0.1), "sound": sound_on, "tutorial": show_tutorial,
	}


# ------------------------------------------------------------------ drawing: venue (static)

func _world_extents() -> Array:
	var top := world_origin.y / world_scale + 10.0
	var bottom := (vs.y - world_origin.y) / world_scale - float(L.H) + 10.0
	var side := world_origin.x / world_scale + 10.0
	return [top, maxf(bottom, 0.0), side]


func _draw_venue() -> void:
	if level.is_empty():
		return
	var ex := _world_extents()
	Art.background(venue_layer, level, ex[0], ex[1], ex[2])
	Art.back_decor(venue_layer, level)
	for s in level.solids:
		Art.solid(venue_layer, s, level)
	Art.front_decor(venue_layer, level)
	# bystanders (the target and thrower are animated, so they live on the actor layer)
	var seen := {}
	for s in level.solids:
		if String(s.k) == "guest" and String(s.get("role", "")) != "target" and String(s.t) == "rect" and not seen.has(int(s.g)):
			seen[int(s.g)] = true
			Art.person(venue_layer, Vector2(float(s.x) + float(s.w) / 2.0, float(s.y) + float(s.h)), int(s.look), 0, 0.0)
	if int(level.get("wind", 0)) != 0:
		_draw_wind_sock(venue_layer)
	_draw_audience(venue_layer, ex)


## On tall phone screens there's spare room in front of the stage: fill it with the backs of
## other guests watching (purely decoration, outside the play area).
func _draw_audience(ci: CanvasItem, ex: Array) -> void:
	var spare := float(ex[1]) - float(L.H - L.FLOOR)
	if spare < 150.0:
		return
	var base_y := (vs.y - FOOTER_H * k - world_origin.y) / world_scale + 16.0
	var left := -float(ex[2])
	var right := float(L.W) + float(ex[2])
	var cols := [Color("5b4a63"), Color("6c5a52"), Color("4f5b6e"), Color("70506a")]
	for row in 2:
		var y := base_y - row * 46.0
		var x := left + 20.0 + row * 37.0
		var i := row * 7
		while x < right:
			var c: Color = cols[i % cols.size()]
			c.a = 0.30 if row == 0 else 0.18
			var hw := 30.0 + float((i * 13) % 9)
			Art.rrect(ci, Rect2(x - hw, y - 26, hw * 2, 60), c, 22)
			ci.draw_circle(Vector2(x, y - 44), 20.0 + float((i * 7) % 5), c)
			x += 74.0 + float((i * 17) % 23)
			i += 1


func _draw_wind_sock(ci: CanvasItem) -> void:
	var wind := int(level.wind)
	var x := 400.0
	var y := 120.0
	ci.draw_rect(Rect2(x - 2, y, 4, 70), Color("6b5a4e"))
	var dir := 1.0 if wind > 0 else -1.0
	var len := 30.0 + absf(wind) * 0.4
	var droop := 26.0 - absf(wind) * 0.18
	for i in 4:
		var t0 := i / 4.0
		var t1 := (i + 1) / 4.0
		var c := C_ACCENT if i % 2 == 0 else Color("ffffff")
		var w0 := 12.0 - 5.0 * t0
		var w1 := 12.0 - 5.0 * t1
		var p0 := Vector2(x + dir * len * t0, y + 6 + droop * t0 * t0)
		var p1 := Vector2(x + dir * len * t1, y + 6 + droop * t1 * t1)
		ci.draw_colored_polygon(PackedVector2Array([p0 + Vector2(0, -w0 / 2), p1 + Vector2(0, -w1 / 2), p1 + Vector2(0, w1 / 2), p0 + Vector2(0, w0 / 2)]), c)


# ------------------------------------------------------------------ drawing: actors (every frame)

func _draw_actors() -> void:
	if level.is_empty():
		return
	var ci := actor_layer
	if shake > 0.0:
		ci.draw_set_transform(Vector2(sin(anim_t * 70.0), cos(anim_t * 53.0)) * shake * 14.0)
	var tg: Dictionary = level.target
	var hands := Vector2(float(tg.hands[0]), float(tg.hands[1]))
	var caught := phase == "won"
	# Catch zone glow
	var pulse := 0.5 + 0.5 * sin(anim_t * 3.2)
	if not caught or phase != "won":
		ci.draw_circle(hands, float(tg.r), Color(1.0, 0.85, 0.35, 0.07 + 0.05 * pulse))
		ci.draw_arc(hands, float(tg.r), 0, TAU, 40, Color(1.0, 0.72, 0.2, 0.55 + 0.25 * pulse), 3.0)
		ci.draw_arc(hands, float(tg.r) + 6 + 4 * pulse, 0, TAU, 40, Color(1.0, 0.72, 0.2, 0.25 * (1.0 - pulse)), 2.0)
	# Target guest (jumps for joy after a catch)
	var jump := 0.0
	if phase == "won":
		jump = -absf(sin(won_t * 9.0)) * 18.0 * maxf(0.0, 1.0 - won_t / 1.4)
	Art.person(ci, Vector2(float(tg.x), float(tg.feet) + jump), int(tg.look), 1, anim_t)
	if not caught:
		var bob := sin(anim_t * 4.0) * 4.0
		var tip := hands + Vector2(0, -float(tg.r) - 14 + bob)
		Art.tri(ci, tip + Vector2(-9, -12), tip + Vector2(9, -12), tip, C_ACCENT)
	# Ghost of the last throw
	if ghost.size() >= 4 and phase != "flight":
		var n := ghost.size() / 2
		var stepn := maxi(1, n / 60)
		for i in range(0, n, stepn):
			ci.draw_circle(Vector2(ghost[i * 2], ghost[i * 2 + 1]), 2.6, Color(0.18, 0.14, 0.25, 0.22))
		if ghost_end.x >= 0.0 and not caught:
			var e := ghost_end
			ci.draw_line(e + Vector2(-6, -6), e + Vector2(6, 6), Color(0.18, 0.14, 0.25, 0.35), 2.5)
			ci.draw_line(e + Vector2(-6, 6), e + Vector2(6, -6), Color(0.18, 0.14, 0.25, 0.35), 2.5)
	# Thrower
	var th: Dictionary = level.thrower
	var face := int(th.face)
	var rel := Vector2(float(level.release[0]), float(level.release[1]))
	var dir := Vector2(face, -1).normalized()
	var lean := 0.0
	if has_aim and phase == "aim":
		dir = Vector2(P.Units.ux(aim_a), P.Units.uy(aim_a))
		lean = -dir.x * 4.0 * aim_p / 100.0
	elif phase == "flight" and flight_t < 0.25:
		dir = Vector2(P.Units.ux(aim_a), P.Units.uy(aim_a))
	Art.person(ci, Vector2(float(th.x), float(th.feet)), int(th.look), 2, anim_t, face, dir, lean)
	# Aim preview + power arrow
	if has_aim and phase == "aim":
		_draw_aim(ci, rel)
	# The bouquet
	match phase:
		"aim":
			Art.bouquet(ci, rel, -0.4 * face)
		"flight":
			var pos := _flight_pos()
			var spin := flight_t * 9.0 * (1.0 if float(flight.path[2]) >= float(flight.path[0]) else -1.0)
			Art.bouquet(ci, pos, spin)
		"settle":
			if settle_t > 0.3:
				Art.bouquet(ci, ghost_end, PI * 0.5)
			else:
				Art.bouquet(ci, rel, -0.4 * face, 1.0 - settle_t / 0.3)
		"won":
			Art.bouquet(ci, hands + Vector2(0, -6 + jump), sin(anim_t * 6.0) * 0.3, 1.15)
	# World-space particles
	for p in particles:
		if p.world:
			var a: float = clampf(p.life / p.max, 0.0, 1.0)
			if p.has("star"):
				_star(ci, p.p, p.r * (0.5 + a), Color(p.c, a))
			else:
				ci.draw_circle(p.p, p.r, Color(p.c, a))
	ci.draw_set_transform(Vector2.ZERO)


func _flight_pos() -> Vector2:
	var path: PackedFloat64Array = flight.path
	var n := path.size() / 2
	var f := clampf(flight_t / P.DT, 0.0, float(n - 1))
	var i := int(f)
	var j := mini(i + 1, n - 1)
	var t := f - float(i)
	return Vector2(lerpf(path[i * 2], path[j * 2], t), lerpf(path[i * 2 + 1], path[j * 2 + 1], t))


func _draw_aim(ci: CanvasItem, rel: Vector2) -> void:
	var dir := Vector2(P.Units.ux(aim_a), P.Units.uy(aim_a))
	var power := aim_p / 100.0
	var col := Color(1, 1, 1, 0.95)
	# preview dots (only the first part of the flight)
	var n := preview.size() / 2
	for i in range(1, n):
		var a := 1.0 - float(i) / float(n + 1)
		var p := Vector2(preview[i * 2], preview[i * 2 + 1])
		ci.draw_circle(p, 5.5, Color(0.18, 0.14, 0.25, 0.55 * a))
		ci.draw_circle(p, 3.8, Color(col, a))
	# power arrow
	var len := 28.0 + 70.0 * power
	var tip := rel + dir * len
	var side := Vector2(-dir.y, dir.x)
	var pc := C_TEAL.lerp(C_ACCENT, power)
	ci.draw_line(rel + dir * 16, tip, Color(0.18, 0.14, 0.25, 0.25), 9)
	ci.draw_line(rel + dir * 16, tip, pc, 5)
	Art.tri(ci, tip + dir * 12, tip + side * 8, tip - side * 8, pc)


func _star(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + PI * i / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, c)


# ------------------------------------------------------------------ drawing: UI

func _font_for(b: bool) -> Font:
	return bold if b else font


## Draws text that always fits: shrinks the font until it fits max_w (never truncates).
## align: 0 left, 1 centre, 2 right. pos is the baseline-left/centre/right point.
func _text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, align := 0, max_w := 10000.0, b := false) -> float:
	var f := _font_for(b)
	var fs := size
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > max_w and fs > 9:
		fs -= 1
		w = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := pos.x
	if align == 1:
		x -= w / 2.0
	elif align == 2:
		x -= w
	ci.draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return w


## Wraps text into lines that fit max_w at the largest size <= size that fits max_lines.
func _wrap(s: String, size: int, max_w: float, max_lines: int, b := false) -> Array:
	var f := _font_for(b)
	var fs := size
	while fs > 9:
		var lines: Array = []
		var line := ""
		for word in s.split(" "):
			var cand := word if line == "" else line + " " + word
			if f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
				line = cand
			else:
				if line != "":
					lines.append(line)
				line = word
		if line != "":
			lines.append(line)
		var fits := lines.size() <= max_lines
		for l in lines:
			if f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
				fits = false
		if fits:
			return [fs, lines]
		fs -= 1
	return [9, [s]]


func _button(ci: CanvasItem, id: String, r: Rect2, label: String, primary := false, enabled := true, size := GTUI.FS_LABEL + 2) -> void:
	buttons.append({"id": id, "rect": r, "enabled": enabled})
	GTUI.button(ci, id, r, label, "primary" if primary else "secondary", enabled, size)


func _draw_ui() -> void:
	buttons = []
	GTUI.begin()
	var ci := ui_layer
	if phase == "loading" or level.is_empty():
		ci.draw_rect(Rect2(Vector2.ZERO, uvs), C_BG)
		Art.bouquet(ci, uvs * 0.5 + Vector2(0, -30), sin(anim_t * 4.0) * 0.4, 2.4)
		GTUI.text_in(ci, Rect2(0, uvs.y * 0.5 + 24, uvs.x, GTUI.line_height(GTUI.FS_BODY)), "Setting up the reception...", GTUI.FS_BODY, C_MUTED)
		return
	# drag feedback (screen space): from where you pressed to your finger
	if aiming and has_aim and phase == "aim" and modal == "":
		var a0 := press_pos / k
		var a1 := cur_pos / k
		ci.draw_dashed_line(a0, a1, Color(C_INK, 0.35), 3, 10)
		ci.draw_circle(a0, 9, Color(C_INK, 0.25))
		ci.draw_circle(a1, 20, Color(C_ACCENT, 0.18))
		ci.draw_arc(a1, 20, -PI / 2, -PI / 2 + TAU * aim_p / 100.0, 32, C_ACCENT, 4)
	_draw_header(ci)
	_draw_footer(ci)
	if show_tutorial and phase == "aim" and modal == "" and not done:
		_draw_tutorial(ci)
	# screen-space confetti
	for p in particles:
		if not p.world:
			var a: float = clampf(p.life / p.max, 0.0, 1.0)
			ci.draw_set_transform(p.p, p.rot)
			ci.draw_rect(Rect2(-p.r, -p.r * 0.5, p.r * 2, p.r), Color(p.c, minf(1.0, a * 2.0)))
			ci.draw_set_transform(Vector2.ZERO)
	if dev_mode and dev_open:
		_draw_dev(ci)
	match modal:
		"help": _draw_help(ci)
		"end": _draw_end(ci)
		"archive": _draw_archive(ci)
	if toast_t > 0.0 and toast != "":
		GTUI.toast(ci, toast, clampf(toast_t / GTUI.T_NORMAL, 0.0, 1.0), footer_rect.position.y - GTUI.SP_M)


func _draw_header(ci: CanvasItem) -> void:
	var r := Rect2(0, 0, uvs.x, HEADER_H)
	ci.draw_rect(r, C_PANEL)
	ci.draw_rect(Rect2(0, HEADER_H - GTUI.BORDER, uvs.x, GTUI.BORDER), C_FAINT)
	var icons := GTUI.icon_row(uvs.x - GTUI.SP_M, (HEADER_H - GTUI.TARGET) / 2.0, ["sound", "archive", "help"])
	for id in ["sound", "archive", "help"]:
		buttons.append({"id": id, "rect": icons[id], "enabled": true})
	GTUI.icon_button(ci, "sound", icons["sound"], "sound_on" if sound_on else "sound_off")
	GTUI.icon_button(ci, "archive", icons["archive"], "calendar")
	GTUI.icon_button(ci, "help", icons["help"], "help")
	var rh: Rect2 = icons["sound"]
	var title_w := rh.position.x - GTUI.SP_L
	var tr := Rect2(GTUI.SP_M, 4, title_w, HEADER_H - 8)
	buttons.append({"id": "title", "rect": tr, "enabled": true})
	# the bouquet mark is the game's own logo art
	Art.bouquet(ci, Vector2(GTUI.SP_M + 18, HEADER_H / 2.0 - 4), -0.3, 1.25)
	var tx := GTUI.SP_M + 42
	var lh_t := GTUI.line_height(GTUI.FS_TITLE)
	var lh_m := GTUI.line_height(GTUI.FS_CAPTION)
	var ty := (HEADER_H - lh_t - lh_m + GTUI.SP_XS) / 2.0
	GTUI.text_in(ci, Rect2(tx, ty, title_w - 42, lh_t), "Bouquet Toss", GTUI.FS_TITLE, C_INK, -1, true)
	var sub := "#%d · %s" % [int(level.number), Daily.short_date(date)]
	if date < today:
		sub += " · past day"
	elif date > today:
		sub += " · future (dev)"
	GTUI.text_in(ci, Rect2(tx, ty + lh_t - GTUI.SP_XS, title_w - 42, lh_m), sub, GTUI.FS_CAPTION, C_MUTED, -1)
	_draw_holes(ci)


func _draw_holes(ci: CanvasItem) -> void:
	var y0 := HEADER_H
	ci.draw_rect(Rect2(0, y0, uvs.x, HOLES_H), C_PANEL)
	ci.draw_rect(Rect2(0, y0 + HOLES_H - GTUI.BORDER, uvs.x, GTUI.BORDER), C_FAINT)
	var pad := GTUI.SP_M
	var gap := GTUI.SP_XS
	var cw := (uvs.x - pad * 2 - gap * (Daily.HOLES - 1)) / Daily.HOLES
	for i in Daily.HOLES:
		var r := Rect2(pad + i * (cw + gap), y0 + GTUI.SP_S, cw, HOLES_H - GTUI.SP_S * 2)
		var h: Dictionary = holes[i] if i < holes.size() else {"throws": [], "done": false}
		var n := (h.throws as Array).size()
		var cur := i == hole
		var fill := C_BTN
		if bool(h.done):
			fill = Color("d7efe9")
		if cur:
			fill = C_ACCENT
		var id := "hole:%d" % i
		buttons.append({"id": id, "rect": r, "enabled": true})
		GTUI.register(id, r)
		if not cur and GTUI.is_pressed(id, r):
			fill = fill.darkened(0.08)
		elif not cur and GTUI.is_hover(id):
			fill = fill.darkened(0.04)
		GTUI.box(ci, r, fill, GTUI.R_CONTROL)
		var tc := Color("ffffff") if cur else C_INK
		var lh := GTUI.line_height(GTUI.FS_CAPTION)
		var top := r.position.y + (r.size.y - lh - GTUI.line_height(GTUI.FS_BODY) + GTUI.SP_XS) / 2.0
		GTUI.text_in(ci, Rect2(r.position.x, top, r.size.x, lh), "Throw %d" % (i + 1), GTUI.FS_CAPTION, Color(tc, 0.8))
		var count := "%d" % n if n > 0 else "–"
		var vr := Rect2(r.position.x, top + lh - GTUI.SP_XS, r.size.x, GTUI.line_height(GTUI.FS_BODY))
		if bool(h.done):
			var tw := GTUI.text_width(count, GTUI.FS_BODY, true)
			GTUI.text_in(ci, Rect2(vr.position + Vector2(9, 0), vr.size), count, GTUI.FS_BODY, tc, 0, true)
			Art.bouquet(ci, Vector2(vr.get_center().x + 9 - tw / 2.0 - 10, vr.get_center().y - 4), -0.2, 0.75)
		else:
			GTUI.text_in(ci, vr, count, GTUI.FS_BODY, tc, 0, true)
		GTUI.focus_ring(ci, id, r)


func _draw_footer(ci: CanvasItem) -> void:
	var r := footer_rect
	ci.draw_rect(r, C_PANEL)
	ci.draw_rect(Rect2(0, r.position.y, uvs.x, GTUI.BORDER), C_FAINT)
	var pad := GTUI.SP_L
	# right: aim readout (fixed width) and Results button (always there, enabled once done)
	var rw := clampf(uvs.x * 0.36, 140.0, 220.0)
	var aim_r := Rect2(uvs.x - pad - rw, r.position.y + GTUI.SP_M, rw, 36)
	GTUI.box(ci, aim_r, C_BTN, GTUI.R_CONTROL)
	var show_aim := has_aim or last_aim.x >= 0
	var aa := aim_a if has_aim else last_aim.x
	var ap := aim_p if has_aim else last_aim.y
	var fa := _forward_angle(aa)
	var aim_txt := "%d°  ·  %d%%" % [fa, ap] if show_aim else "Drag to aim"
	GTUI.text_in(ci, aim_r, aim_txt, GTUI.FS_LABEL, C_INK if show_aim else C_MUTED, 0, true)
	if show_aim:
		ci.draw_rect(Rect2(aim_r.position.x + GTUI.SP_S, aim_r.end.y - 5, (rw - GTUI.SP_S * 2) * ap / 100.0, 3), C_ACCENT)
	var res_r := Rect2(uvs.x - pad - rw, aim_r.end.y + GTUI.SP_S, rw, GTUI.TARGET)
	_button(ci, "results", res_r, "Results", done, done)
	# left: counter + status (two fixed lines)
	var lw := uvs.x - pad * 3 - rw
	var line1 := ""
	if done:
		line1 = "All 5 in %d tries · %d%%" % [int(result.throws), int(result.accuracy)]
	elif bool(holes[hole].done):
		line1 = "Throw %d/5 · done" % (hole + 1)
	else:
		var n := throws.size() + (0 if phase == "flight" else 1)
		line1 = "Throw %d/5 · try %d" % [hole + 1, maxi(1, n)]
		if started:
			line1 += " · " + Scoring.clock(elapsed)
	GTUI.text_in(ci, Rect2(pad, r.position.y + GTUI.SP_M, lw, GTUI.line_height(GTUI.FS_TITLE)), line1, GTUI.FS_TITLE, C_INK, -1, true)
	var msg := status
	if msg == "":
		if bool(holes[hole].done):
			msg = "Already caught: practice away, it won't change your result."
		else:
			msg = GOAL
	var y := r.position.y + GTUI.SP_M + GTUI.line_height(GTUI.FS_TITLE)
	var lines := GTUI.wrap_lines(msg, GTUI.FS_LABEL, lw)
	for i in mini(lines.size(), 2):
		GTUI.text_in(ci, Rect2(pad, y, lw, GTUI.line_height(GTUI.FS_LABEL)), lines[i], GTUI.FS_LABEL, C_TEAL.darkened(0.2) if status_good else C_MUTED, -1)
		y += GTUI.line_height(GTUI.FS_LABEL)


## Angle as the player sees it: 0 = straight ahead, 90 = straight up, whichever way you face.
func _forward_angle(a: int) -> int:
	var f := posmod(180 - a, 360) if bool(level.get("mirror", false)) else posmod(a, 360)
	return f - 360 if f > 180 else f


func _draw_tutorial(ci: CanvasItem) -> void:
	var rel := to_screen(Vector2(float(level.release[0]), float(level.release[1]))) / k
	var face := int(level.thrower.face)
	var t := fmod(anim_t, 2.2) / 2.2
	var start := rel + Vector2(face * 50, 0)
	var room := maxf(30.0, footer_rect.position.y - 24.0 - start.y)
	var pull := Vector2(-face * 100, minf(70.0, room)) * minf(1.0, t * 1.6)
	var hand := start + pull
	if t < 0.75:
		ci.draw_dashed_line(start, hand, Color(C_INK, 0.45), 3, 9)
		ci.draw_circle(start, 8, Color(C_INK, 0.3))
		ci.draw_circle(hand, 18, Color(C_ACCENT, 0.3))
		ci.draw_circle(hand, 9, C_ACCENT)
	var bw := minf(uvs.x - GTUI.SP_L * 2, 440.0)
	var lh1 := GTUI.line_height(GTUI.FS_BODY)
	var lh2 := GTUI.line_height(GTUI.FS_LABEL)
	var box := Rect2((uvs.x - bw) / 2, HEADER_H + HOLES_H + GTUI.SP_M, bw, lh1 + lh2 + GTUI.SP_M * 2)
	GTUI.box(ci, box, Color(C_PANEL, 0.97), GTUI.R_PANEL, C_FAINT)
	GTUI.text_in(ci, Rect2(box.position.x + GTUI.SP_M, box.position.y + GTUI.SP_M, bw - GTUI.SP_M * 2, lh1), "Drag back from anywhere, then let go.", GTUI.FS_BODY, C_INK, 0, true)
	GTUI.text_in(ci, Rect2(box.position.x + GTUI.SP_M, box.position.y + GTUI.SP_M + lh1, bw - GTUI.SP_M * 2, lh2), "Land the bouquet in the glowing hands.", GTUI.FS_LABEL, C_MUTED)


func _draw_help(ci: CanvasItem) -> void:
	var w := _content_w(480)
	var h := 0.0
	for l in HELP_LINES:
		h = GTUI.paragraph(ci, 0, h, w - GTUI.SP_L, l, GTUI.FS_BODY, C_INK, false, false) + GTUI.SP_S
	var card := _modal_card(ci, 480, h)
	buttons.append({"id": "close", "rect": GTUI.modal_close_rect(card), "enabled": true})
	var c := GTUI.modal(ci, card, "How to play", "close")
	var y := c.position.y
	for l in HELP_LINES:
		ci.draw_circle(Vector2(c.position.x + 4, y + GTUI.line_height(GTUI.FS_BODY) / 2.0), 3, C_ACCENT)
		y = GTUI.paragraph(ci, c.position.x + GTUI.SP_L, y, c.size.x - GTUI.SP_L, l, GTUI.FS_BODY, C_INK) + GTUI.SP_S
	_button(ci, "got_it", GTUI.modal_buttons_rect(c), "Got it", true)


func _draw_end(ci: CanvasItem) -> void:
	var th := GTUI.TARGET
	var stat_h := GTUI.line_height(GTUI.FS_TITLE) + GTUI.line_height(GTUI.FS_CAPTION)
	var content_h := GTUI.line_height(GTUI.FS_LABEL) + 96 + GTUI.line_height(GTUI.FS_TITLE) + GTUI.SP_L + stat_h + GTUI.SP_XL + th + GTUI.SP_S + th + GTUI.SP_M + GTUI.line_height(GTUI.FS_CAPTION)
	var card := _modal_card(ci, 500, content_h, false)
	buttons.append({"id": "close", "rect": GTUI.modal_close_rect(card), "enabled": true})
	var c := GTUI.modal(ci, card, "All five caught!", "close")
	var w := c.size.x
	var cx := c.get_center().x
	var y := c.position.y
	GTUI.text(ci, Vector2(c.position.x, y), "Bouquet Toss #%d · %s" % [int(level.number), Daily.short_date(date)], GTUI.FS_LABEL, C_MUTED)
	y += GTUI.line_height(GTUI.FS_LABEL)
	var t := int(result.get("throws", 0))
	var per: Array = result.get("holes", [])
	# one bouquet per throw, with how many tries it took underneath (game art)
	var slot := minf(64.0, w / Daily.HOLES)
	for i in Daily.HOLES:
		var bc := Vector2(cx - slot * Daily.HOLES / 2.0 + slot * (i + 0.5), y + 40)
		var n: int = (per[i] as Array).size() if i < per.size() else 0
		Art.bouquet(ci, bc, -0.3 + 0.15 * i, 1.4 if n == 1 else 1.1)
		GTUI.text_in(ci, Rect2(bc.x - slot / 2.0, bc.y + 30, slot, GTUI.line_height(GTUI.FS_LABEL)), "%d" % n, GTUI.FS_LABEL, C_INK if n == 1 else C_MUTED, 0, true)
	y += 96
	GTUI.text_in(ci, Rect2(c.position.x, y, w, GTUI.line_height(GTUI.FS_TITLE)), Scoring.rating_total(t, Daily.HOLES), GTUI.FS_TITLE, C_ACCENT_DARK, 0, true)
	y += GTUI.line_height(GTUI.FS_TITLE) + GTUI.SP_L
	# three stats, flat (no boxes)
	var labels := ["Tries", "Accuracy", "Time"]
	var vals := [str(t), "%d%%" % int(result.get("accuracy", 0)), Scoring.clock(float(result.get("seconds", 0)))]
	var cw := w / 3.0
	for i in 3:
		var sx := c.position.x + i * cw
		GTUI.text_in(ci, Rect2(sx, y, cw, GTUI.line_height(GTUI.FS_TITLE)), vals[i], GTUI.FS_TITLE, C_INK, 0, true)
		GTUI.text_in(ci, Rect2(sx, y + GTUI.line_height(GTUI.FS_TITLE), cw, GTUI.line_height(GTUI.FS_CAPTION)), labels[i].to_upper(), GTUI.FS_CAPTION, C_MUTED, 0, true)
	y += stat_h + GTUI.SP_XL
	var r1 := GTUI.row(Rect2(c.position.x, y, w, th), 2, [1.0, 1.4])
	_button(ci, "copy", r1[0], "Copy result")
	_button(ci, "share", r1[1], "Share", true)
	y += th + GTUI.SP_S
	var r2 := GTUI.row(Rect2(c.position.x, y, w, th), 2)
	_button(ci, "close_end", r2[0], "Keep throwing")
	_button(ci, "archive", r2[1], "Past days")
	y += th + GTUI.SP_M
	GTUI.text_in(ci, Rect2(c.position.x, y, w, GTUI.line_height(GTUI.FS_CAPTION)), "New venue in " + GTUI.countdown(), GTUI.FS_CAPTION, C_MUTED)


func _draw_archive(ci: CanvasItem) -> void:
	var rh := GTUI.TARGET + GTUI.SP_S
	var content_h := GTUI.line_height(GTUI.FS_CAPTION) + GTUI.SP_S + ARCHIVE_ROWS * rh - GTUI.SP_S
	var card := _modal_card(ci, 480, content_h)
	buttons.append({"id": "close", "rect": GTUI.modal_close_rect(card), "enabled": true})
	var c := GTUI.modal(ci, card, "Past days", "close")
	GTUI.text(ci, c.position, "Page %d of %d" % [archive_page + 1, archive_pages()], GTUI.FS_CAPTION, C_MUTED)
	var y := c.position.y + GTUI.line_height(GTUI.FS_CAPTION) + GTUI.SP_S
	var first := archive_page * ARCHIVE_ROWS
	for j in ARCHIVE_ROWS:
		var i := first + j
		if i >= archive_count():
			break
		var row := Rect2(c.position.x, y, c.size.x, GTUI.TARGET)
		var d := Daily.add_days(today, -i)
		var res := String(archive_results.get(d, ""))
		buttons.append({"id": "day:" + d, "rect": row, "enabled": true})
		GTUI.list_row(ci, "day:" + d, row, "#%d" % Daily.day_number(d), "Today" if d == today else Daily.short_date(d),
			res if res != "" else "Not played", d == date, C_TEAL.darkened(0.2) if res != "" else Color(0, 0, 0, 0))
		y += rh
	var pr := GTUI.row(GTUI.modal_buttons_rect(c), 2)
	_button(ci, "arch_prev", pr[0], "Newer", false, archive_page > 0)
	_button(ci, "arch_next", pr[1], "Older", false, archive_page < archive_pages() - 1)


func _draw_dev(ci: CanvasItem) -> void:
	var w := minf(340.0, uvs.x - 24)
	var r := Rect2(12, HEADER_H + HOLES_H + 10, w, 280)
	Art.rrect(ci, r, Color(0.1, 0.08, 0.14, 0.86), 12)
	var st := dev_stats() if level.has("stats") else {}
	var sol: Dictionary = level.get("solution", {})
	var lines := [
		"DEV  %s  #%d  throw %d %s" % [date, int(level.number), hole + 1, String(level.archetype)],
		"seed %d  attempt %d  %s" % [int(level.seed), int(level.attempt), "mirrored" if bool(level.mirror) else ""],
		"rate %.3f  robust %d  clusters %d" % [float(st.get("rate", 0)), int(st.get("robust", 0)), int(st.get("clusters", 0))],
		"routes %s" % ", ".join(st.get("routes", [])),
		"solution %d° (fwd %d°) %d%%  wind %d" % [int(sol.get("a", 0)), _forward_angle(int(sol.get("a", 0))), int(sol.get("p", 0)), int(level.get("wind", 0))],
	]
	var y := r.position.y + 22
	for l in lines:
		_text(ci, Vector2(r.position.x + 12, y), l, 14, Color(1, 1, 1, 0.92), 0, w - 24)
		y += 19
	var ids := [["dev_prev", "< Day"], ["dev_next", "Day >"], ["dev_today", "Today"], ["dev_random", "Random"],
		["dev_reset", "Reset"], ["dev_win", "Win"], ["dev_win_day", "Win all"], ["dev_reveal", "Reveal"],
		["dev_close", "Hide"]]
	var bw := (w - 24 - 9) / 4.0
	for i in ids.size():
		var br := Rect2(r.position.x + 12 + (i % 4) * (bw + 3), y + 8 + (i / 4) * 48, bw, GTUI.TARGET)
		_button(ci, ids[i][0], br, ids[i][1], false, true, GTUI.FS_LABEL)


const HELP_LINES := [
	"Drag back from anywhere on the screen, aim, and let go to throw.",
	"Five throws a day, each to a different guest. Fewest tries wins; tap a number to switch.",
	"Bounce off walls, ceilings and tables all you like. Not the cake.",
	"Everyone gets the same venue each day. Arrow keys and Space work too.",
]


func _modal_card(ci: CanvasItem, w: float, content_h: float, buttons_row := true) -> Rect2:
	return GTUI.modal_rect(ci, w, GTUI.modal_height(content_h, true, buttons_row))


func _content_w(w: float) -> float:
	return minf(w, uvs.x - GTUI.SP_L * 2) - GTUI.SP_XL * 2