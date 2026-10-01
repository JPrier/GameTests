extends Node2D
## Kitchen Crawl — a restaurant-sim roguelike.
## Survive 10 days: cook, plate and serve orders, pay rising rent every night,
## and pick one upgrade between days. Lose all reputation or miss rent and the run ends.
## Controls: keyboard (WASD/arrows + E/Space) or touch (left-thumb joystick, right-thumb action).

const Data = preload("res://data.gd")

const VIEW := Vector2(960, 540)
const FLOOR := Rect2(72, 176, 816, 292)  # where the chef's centre may go
const CHEF_RADIUS := 16.0
const STATION_SIZE := Vector2(56, 56)
const DAY_LENGTH := 80.0
const FINAL_DAY := 10
const PLATE_CAP := 4
const SERVE_Y := 205.0     # chef must be this close to the pass to serve
const SEAT_SPACING := 150.0
const CUSTOMER_Y := 108.0
const JOY_RADIUS := 60.0
const JOY_HOME := Vector2(120, 400)
const BTN_HOME := Vector2(850, 400)
const KIND_COLOR := {"unlock": Color("e0a43a"), "station": Color("4fa3d9"), "perk": Color("7cc06a")}

enum Phase { TITLE, DAY, SHOP, GAMEOVER, VICTORY }

var rng := RandomNumberGenerator.new()
var phase: int = Phase.TITLE
var day := 0
var money := 0
var hearts := 3
var max_hearts := 3
var seats := 3
var day_time := 0.0
var day_earned := 0
var served_today := 0
var lost_today := 0
var total_earned := 0
var served_total := 0
var last_rent := 0
var spawn_timer := 0.0
var vip_spawned := false
var event: Dictionary = {}
var last_event_id := ""
var upgrades := {}        # id -> stacks
var unlocks := {}         # "tomato" / "cheese" / "fryer" -> true
var stations: Array = []  # Array[Dictionary]
var customers: Array = [] # Array[Dictionary]
var held: Variant = null  # null, an item String, or a plate (Array of item Strings)
var chef_pos := Vector2(300, 330)
var chef_facing := Vector2.DOWN
var chef_walk := 0.0
var target: Dictionary = {}
var target_seat := -1
var offers: Array = []
var card_rects: Array = []
var popups: Array = []
var banner_t := 0.0
var end_t := 0.0
var game_over_reason := ""
var anim_t := 0.0

# touch controls
var touch_mode := false
var joy_index := -1
var joy_origin := JOY_HOME
var joy_dir := Vector2.ZERO
var btn_index := -1
var btn_down := false
var btn_just := false


func _ready() -> void:
	_ensure_input()
	rng.randomize()
	touch_mode = DisplayServer.is_touchscreen_available()
	_build_stations()


static func _ensure_input() -> void:
	var binds := {
		"interact": [KEY_E, KEY_SPACE, KEY_J],
		"confirm": [KEY_ENTER, KEY_KP_ENTER],
		"pick_1": [KEY_1, KEY_KP_1],
		"pick_2": [KEY_2, KEY_KP_2],
		"pick_3": [KEY_3, KEY_KP_3],
	}
	for action: String in binds:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k: Key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


# =====================================================================  run flow

func start_run(run_seed := -1) -> void:
	if run_seed >= 0:
		rng.seed = run_seed
	else:
		rng.randomize()
	money = 0
	hearts = 3
	max_hearts = 3
	seats = 3
	upgrades = {}
	unlocks = {}
	total_earned = 0
	served_total = 0
	last_event_id = ""
	popups.clear()
	_build_stations()
	start_day(1)


func start_day(n: int) -> void:
	day = n
	day_time = 0.0
	day_earned = 0
	served_today = 0
	lost_today = 0
	customers.clear()
	held = null
	chef_pos = Vector2(300, 330)
	spawn_timer = 1.5
	vip_spawned = false
	_reset_station_items()
	event = _roll_event(n)
	last_event_id = event.id
	banner_t = 3.5
	phase = Phase.DAY


func end_day() -> void:
	last_rent = rent_for(day)
	money -= last_rent
	held = null
	customers.clear()
	_reset_station_items()
	_release_touch()
	if money < 0:
		_game_over("You couldn't make rent on day %d." % day)
		return
	if day >= FINAL_DAY:
		phase = Phase.VICTORY
		end_t = 0.0
		return
	offers = _roll_offers()
	end_t = 0.0
	phase = Phase.SHOP


func choose_offer(i: int) -> void:
	if phase != Phase.SHOP or i < 0 or i >= offers.size():
		return
	apply_upgrade(offers[i].id)
	start_day(day + 1)


func _game_over(reason: String) -> void:
	game_over_reason = reason
	phase = Phase.GAMEOVER
	end_t = 0.0
	_release_touch()


func _roll_event(n: int) -> Dictionary:
	if n == 1:
		return Data.OPENING
	if n == FINAL_DAY:
		return Data.GALA
	var pool: Array = []
	for e in Data.EVENTS:
		if e.id != last_event_id:
			pool.append(e)
	return pool[rng.randi_range(0, pool.size() - 1)]


func _roll_offers() -> Array:
	var eligible: Array = []
	for u in Data.UPGRADES:
		if _lvl(u.id) < int(u.max):
			eligible.append(u)
	for i in range(eligible.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = tmp
	var picks: Array = eligible.slice(0, 3)
	# Early on, always offer at least one new ingredient so the menu grows.
	if day <= 4:
		var has_unlock := false
		for p in picks:
			has_unlock = has_unlock or p.kind == "unlock"
		if not has_unlock:
			for u in eligible:
				if u.kind == "unlock":
					picks[0] = u
					break
	return picks


# =====================================================================  stats

func _lvl(id: String) -> int:
	return int(upgrades.get(id, 0))


func _ev(id: String) -> bool:
	if event.is_empty():
		return false
	if event.id == id:
		return true
	return event.id == "gala" and (id == "rush" or id == "critic")


func speed() -> float:
	return 250.0 * (1.0 + 0.2 * _lvl("clogs"))


func cook_time() -> float:
	return 6.0 * pow(0.75, _lvl("hot_grill")) * (0.85 if _ev("heat") else 1.0)


func burn_time() -> float:
	return 8.0 * (1.0 + _lvl("bell")) * (0.5 if _ev("heat") else 1.0)


func chop_time() -> float:
	return 1.5 * pow(0.6, _lvl("sharp_knife"))


func patience_mult() -> float:
	return (1.0 + 0.25 * _lvl("breadsticks")) * pow(0.9, _lvl("fancy")) * (0.75 if _ev("picky") else 1.0)


func price_mult() -> float:
	return 1.0 + 0.25 * _lvl("fancy") + (0.25 if _ev("picky") else 0.0)


func tip_mult() -> float:
	return (1.0 + 0.4 * _lvl("smile")) * (1.25 if _ev("rush") else 1.0) * (2.0 if _ev("payday") else 1.0)


func spawn_interval() -> float:
	var base := maxf(2.6, 8.5 - 0.6 * (day - 1))
	return base * (0.7 if _ev("rush") else 1.0) * (1.4 if _ev("rain") else 1.0)


func rent_for(d: int) -> int:
	var k := d - 1
	var base := 25.0 + 20.0 * k + 3.0 * k * k
	return int(round(base * pow(0.8, _lvl("landlord")) * (0.8 if _ev("rain") else 1.0)))


func _patience_for(recipe: Dictionary) -> float:
	var base: float = 34.0 + 7.0 * recipe.items.size()
	return base * maxf(0.6, 1.0 - 0.035 * (day - 1)) * patience_mult()


# =====================================================================  stations

func _build_stations() -> void:
	stations.clear()
	_add_station("crate", Vector2(40, 220), "bun")
	_add_station("crate", Vector2(40, 300), "patty_raw")
	_add_station("crate", Vector2(40, 380), "lettuce_raw")
	_add_station("grill", Vector2(200, 500))
	_add_station("board", Vector2(360, 500))
	_add_station("counter", Vector2(600, 500))
	_add_station("counter", Vector2(680, 500))
	_add_station("trash", Vector2(880, 500))
	_add_station("plate", Vector2(440, 330), "", true)
	_add_station("plate", Vector2(520, 330), "", true)


func _add_station(type: String, pos: Vector2, ingredient := "", island := false) -> Dictionary:
	var s := {
		"type": type, "pos": pos, "ingredient": ingredient, "island": island,
		"item": [] if type == "plate" else null, "progress": 0.0,
	}
	stations.append(s)
	return s


func _reset_station_items() -> void:
	for s in stations:
		s.item = [] if s.type == "plate" else null
		s.progress = 0.0


func _station_rect(s: Dictionary) -> Rect2:
	return Rect2(s.pos - STATION_SIZE / 2.0, STATION_SIZE)


func stations_of(type: String) -> Array:
	return stations.filter(func(s): return s.type == type)


func apply_upgrade(id: String) -> void:
	upgrades[id] = _lvl(id) + 1
	match id:
		"tomato":
			unlocks.tomato = true
			_add_station("crate", Vector2(920, 220), "tomato_raw")
		"cheese":
			unlocks.cheese = true
			_add_station("crate", Vector2(920, 300), "cheese")
		"fryer":
			unlocks.fryer = true
			_add_station("fryer", Vector2(280, 500))
			_add_station("crate", Vector2(920, 380), "potato")
		"grill2":
			_add_station("grill", Vector2(120, 500))
		"board2":
			_add_station("board", Vector2(440, 500))
		"plate3":
			_add_station("plate", Vector2(600, 330), "", true)
		"stool":
			seats = mini(seats + 1, 5)
		"review":
			max_hearts += 1
			hearts = max_hearts


func tick_stations(dt: float) -> void:
	for s in stations:
		if not Data.COOK.has(s.type) or s.item == null:
			continue
		var stages: Array = Data.COOK[s.type]
		s.progress += dt
		if s.item == stages[0] and s.progress >= cook_time():
			s.item = stages[1]
			s.progress = 0.0
		elif s.item == stages[1] and s.progress >= burn_time():
			s.item = stages[2]
			s.progress = 0.0
			_popup("Burnt!", s.pos + Vector2(0, -40), Color("ff6a4d"))


func chop(dt: float, s: Dictionary) -> void:
	if s.type != "board" or not (s.item is String) or not Data.CHOP.has(s.item):
		return
	s.progress += dt / chop_time()
	if s.progress >= 1.0:
		s.item = Data.CHOP[s.item]
		s.progress = 0.0


# =====================================================================  interaction

func _str(v: Variant) -> String:
	return v if v is String else ""


func _is_plate(v: Variant) -> bool:
	return v is Array


func _plateable(v: Variant) -> bool:
	return v is String and v in Data.PLATEABLE


func update_target() -> void:
	target = {}
	target_seat = -1
	if chef_pos.y <= SERVE_Y:
		var best := 1e9
		for c in customers:
			var dx := absf(seat_x(c.seat) - chef_pos.x)
			if dx < 75.0 and dx < best:
				best = dx
				target_seat = c.seat
		if target_seat >= 0:
			return
	var best_d := CHEF_RADIUS + 30.0
	for s in stations:
		var r := _station_rect(s)
		var p := chef_pos.clamp(r.position, r.end)
		var d := chef_pos.distance_to(p)
		# prefer the station we're facing when two are equally close
		d -= 4.0 * chef_facing.dot((s.pos - chef_pos).normalized())
		if d < best_d:
			best_d = d
			target = s


func interact() -> void:
	if phase != Phase.DAY:
		return
	if target_seat >= 0:
		serve(target_seat)
		return
	if target.is_empty():
		return
	var s := target
	match s.type:
		"crate":
			if held == null:
				held = s.ingredient
			elif _is_plate(held) and _plateable(s.ingredient):
				_add_to_plate(held, s.ingredient, s.pos)
		"trash":
			if held != null:
				held = null
				_popup("Tossed", s.pos + Vector2(0, -40), Color(0.8, 0.8, 0.8))
		"grill", "fryer":
			var stages: Array = Data.COOK[s.type]
			if s.item == null:
				if _str(held) == stages[0]:
					s.item = held
					s.progress = 0.0
					held = null
				elif held is String:
					_popup("Can't cook that here", s.pos + Vector2(0, -40), Color("ffd27a"))
			elif held == null:
				held = s.item
				s.item = null
				s.progress = 0.0
			elif _is_plate(held) and _plateable(s.item):
				if _add_to_plate(held, s.item, s.pos):
					s.item = null
					s.progress = 0.0
		"board":
			if s.item == null:
				if held is String and Data.CHOP.has(held):
					s.item = held
					s.progress = 0.0
					held = null
				elif held is String:
					_popup("Nothing to chop", s.pos + Vector2(0, -40), Color("ffd27a"))
			elif not Data.CHOP.has(s.item):  # chopped and ready
				if held == null:
					held = s.item
					s.item = null
				elif _is_plate(held):
					if _add_to_plate(held, s.item, s.pos):
						s.item = null
		"plate":
			if _plateable(held):
				if _add_to_plate(s.item, held, s.pos):
					held = null
			elif held is String:
				_popup("Cook or chop it first!", s.pos + Vector2(0, -40), Color("ffd27a"))
			elif held == null and not s.item.is_empty():
				held = s.item
				s.item = []
			elif _is_plate(held) and s.item.is_empty():
				s.item = held
				held = null
		"counter":
			if s.item == null:
				if held != null:
					s.item = held
					held = null
			elif held == null:
				held = s.item
				s.item = null
			elif _is_plate(s.item) and _plateable(held):
				if _add_to_plate(s.item, held, s.pos):
					held = null
			elif _is_plate(held) and _plateable(s.item):
				if _add_to_plate(held, s.item, s.pos):
					s.item = null


func _add_to_plate(plate: Array, item: String, at: Vector2) -> bool:
	if plate.size() >= PLATE_CAP:
		_popup("Plate's full", at + Vector2(0, -40), Color("ffd27a"))
		return false
	plate.append(item)
	return true


# =====================================================================  customers

func seat_x(i: int) -> float:
	return VIEW.x / 2.0 + (i - (seats - 1) / 2.0) * SEAT_SPACING


func customer_at(seat: int) -> Dictionary:
	for c in customers:
		if c.seat == seat:
			return c
	return {}


func _free_seats() -> Array:
	var free: Array = []
	for i in seats:
		if customer_at(i).is_empty():
			free.append(i)
	return free


func recipe_pool() -> Array:
	var pool: Array = []
	for r in Data.RECIPES:
		var ok := true
		for need in r.needs:
			ok = ok and unlocks.has(need)
		if ok:
			pool.append(r)
	return pool


func spawn_customer(recipe_name := "", vip := false) -> Dictionary:
	var free := _free_seats()
	if free.is_empty():
		return {}
	var recipe: Dictionary = Data.recipe(recipe_name) if recipe_name != "" else _pick_recipe()
	var pat := _patience_for(recipe) * (0.85 if vip else 1.0)
	var c := {
		"seat": free[rng.randi_range(0, free.size() - 1)], "recipe": recipe,
		"patience": pat, "max_patience": pat, "vip": vip,
		"color": Color.from_hsv(rng.randf(), 0.45, 0.85), "bob": rng.randf() * TAU,
	}
	customers.append(c)
	return c


func _pick_recipe() -> Dictionary:
	var pool := recipe_pool()
	var weights: Array = []
	var total := 0.0
	for r in pool:
		# newly unlocked dishes show up more, and bigger dishes get likelier as days pass
		var w: float = 1.0 + (1.0 if not r.needs.is_empty() else 0.0) + 0.08 * day * (r.items.size() - 1)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[-1]


static func plate_matches(plate: Array, items: Array) -> bool:
	var a := plate.duplicate()
	var b := items.duplicate()
	a.sort()
	b.sort()
	return a == b


func order_value(c: Dictionary) -> int:
	var base := 0.0
	for it in c.recipe.items:
		base += Data.ITEM_PRICE[it]
	base *= price_mult()
	var tip := base * 0.6 * clampf(c.patience / c.max_patience, 0.0, 1.0) * tip_mult()
	return int(round((base + tip) * (4.0 if c.vip else 1.0)))


func serve(seat: int) -> void:
	var c := customer_at(seat)
	if c.is_empty():
		return
	var at := Vector2(seat_x(seat), CUSTOMER_Y - 40)
	if not _is_plate(held) or held.is_empty():
		_popup("Bring me a plate!", at, Color("ffd27a"))
		return
	if not plate_matches(held, c.recipe.items):
		c.patience -= 4.0
		_popup("That's not my order!", at, Color("ff6a4d"))
		return
	var paid := order_value(c)
	money += paid
	day_earned += paid
	total_earned += paid
	served_today += 1
	served_total += 1
	held = null
	customers.erase(c)
	_popup("+$%d" % paid, at, Color("8be38b"))


func _customer_lost(c: Dictionary) -> void:
	var dmg := 2 if c.vip else 1
	hearts -= dmg
	lost_today += 1
	_popup("Left angry! -%d rep" % dmg, Vector2(seat_x(c.seat), CUSTOMER_Y - 40), Color("ff6a4d"))
	if hearts <= 0:
		_game_over("Your reputation is ruined. Nobody eats here anymore.")


func tick_customers(dt: float) -> void:
	for c in customers.duplicate():
		c.patience -= dt
		if c.patience <= 0.0:
			customers.erase(c)
			_customer_lost(c)
			if phase != Phase.DAY:
				return


func _tick_spawning(dt: float) -> void:
	if day_time >= DAY_LENGTH:
		return
	if _ev("critic") and not vip_spawned and day_time > 15.0 and not _free_seats().is_empty():
		vip_spawned = true
		spawn_customer("", true)
		_popup("A food critic arrives!", Vector2(480, 200), Color("ffd700"))
		return
	spawn_timer -= dt
	if spawn_timer > 0.0:
		return
	if _free_seats().is_empty():
		spawn_timer = 0.5
		return
	spawn_customer()
	spawn_timer = spawn_interval() * rng.randf_range(0.75, 1.25)


# =====================================================================  main loop

func _physics_process(delta: float) -> void:
	anim_t += delta
	var confirm := Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("interact")
	match phase:
		Phase.TITLE:
			if confirm:
				start_run()
		Phase.DAY:
			_day_step(delta)
		Phase.SHOP:
			end_t += delta
			for i in 3:
				if Input.is_action_just_pressed("pick_%d" % (i + 1)):
					choose_offer(i)
		Phase.GAMEOVER, Phase.VICTORY:
			end_t += delta
			if end_t > 1.0 and confirm:
				start_run()
	btn_just = false
	for p in popups.duplicate():
		p.t += delta
		p.pos.y -= 28.0 * delta
		if p.t > 1.4:
			popups.erase(p)


func _process(_delta: float) -> void:
	queue_redraw()


func _day_step(delta: float) -> void:
	day_time += delta
	banner_t = maxf(0.0, banner_t - delta)
	_move_chef(delta)
	update_target()
	if Input.is_action_just_pressed("interact") or btn_just:
		interact()
	if (Input.is_action_pressed("interact") or btn_down) and not target.is_empty():
		chop(delta, target)
	tick_stations(delta)
	tick_customers(delta)
	if phase != Phase.DAY:
		return
	_tick_spawning(delta)
	if day_time >= DAY_LENGTH and customers.is_empty():
		end_day()


func _move_chef(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		dir = joy_dir
	if dir != Vector2.ZERO:
		chef_facing = dir.normalized()
		chef_walk += delta * 12.0
	var step := dir * speed() * delta
	var p := chef_pos
	p.x = clampf(p.x + step.x, FLOOR.position.x, FLOOR.end.x)
	if _blocked(p):
		p.x = chef_pos.x
	p.y = clampf(p.y + step.y, FLOOR.position.y, FLOOR.end.y)
	if _blocked(p):
		p.y = chef_pos.y
	chef_pos = p


func _blocked(p: Vector2) -> bool:
	for s in stations:
		if s.island and _station_rect(s).grow(CHEF_RADIUS).has_point(p):
			return true
	return false


# ---------------------------------------------------------------- pointer / touch

func _release_touch() -> void:
	joy_index = -1
	joy_dir = Vector2.ZERO
	btn_index = -1
	btn_down = false


func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		touch_mode = true
		_handle_touch(make_input_local(ev))
	elif ev is InputEventKey and ev.pressed:
		touch_mode = false


func _handle_touch(ev: InputEvent) -> void:
	if phase != Phase.DAY:
		if ev is InputEventScreenTouch and ev.pressed:
			_tap(ev.position)
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if ev.position.x < VIEW.x * 0.5 and joy_index < 0:
				joy_index = ev.index
				joy_origin = ev.position.clamp(Vector2(JOY_RADIUS + 8, 200), Vector2(VIEW.x * 0.5, VIEW.y - JOY_RADIUS - 8))
				joy_dir = Vector2.ZERO
			elif ev.position.x >= VIEW.x * 0.5 and btn_index < 0:
				btn_index = ev.index
				btn_down = true
				btn_just = true
		else:
			if ev.index == joy_index:
				joy_index = -1
				joy_dir = Vector2.ZERO
			elif ev.index == btn_index:
				btn_index = -1
				btn_down = false
	elif ev is InputEventScreenDrag and ev.index == joy_index:
		var v: Vector2 = ev.position - joy_origin
		# let the stick follow the thumb if it drifts too far
		if v.length() > JOY_RADIUS:
			joy_origin = (ev.position - v.limit_length(JOY_RADIUS)).clamp(Vector2(JOY_RADIUS + 8, 200), Vector2(VIEW.x * 0.5, VIEW.y - JOY_RADIUS - 8))
			v = ev.position - joy_origin
		joy_dir = v / JOY_RADIUS if v.length() > 8.0 else Vector2.ZERO


func _unhandled_input(ev: InputEvent) -> void:
	# Real mouse clicks (desktop). Touch taps arrive via _handle_touch instead.
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if touch_mode:
		return  # the emulated mouse event from a touch was already handled
	_tap(get_global_mouse_position())


func _tap(pos: Vector2) -> void:
	match phase:
		Phase.TITLE:
			start_run()
		Phase.SHOP:
			if end_t < 0.4:
				return  # don't let a held finger from the day pick a card by accident
			for i in card_rects.size():
				if card_rects[i].has_point(pos):
					choose_offer(i)
					return
		Phase.GAMEOVER, Phase.VICTORY:
			if end_t > 1.0:
				start_run()


func _popup(text: String, pos: Vector2, color: Color) -> void:
	popups.append({"text": text, "pos": pos, "t": 0.0, "color": color})


func get_agent_state() -> Dictionary:
	var cs: Array = []
	for c in customers:
		cs.append({"seat": c.seat, "order": c.recipe.name, "items": c.recipe.items,
			"patience": snappedf(c.patience, 0.1), "vip": c.vip})
	var ss: Array = []
	for s in stations:
		ss.append({"type": s.type, "pos": s.pos, "item": s.item if s.ingredient == "" else s.ingredient,
			"progress": snappedf(s.progress, 0.01)})
	return {
		"phase": Phase.keys()[phase], "day": day, "money": money, "hearts": hearts,
		"time_left": snappedf(maxf(0.0, DAY_LENGTH - day_time), 0.1), "event": event.get("id", ""),
		"rent_tonight": rent_for(day), "held": held, "chef": chef_pos,
		"target": target.get("type", "") if target_seat < 0 else "seat %d" % target_seat,
		"customers": cs, "stations": ss, "upgrades": upgrades, "touch": touch_mode,
		"offers": offers.map(func(o): return o.id),
	}


# =====================================================================  drawing

func _font() -> Font:
	return ThemeDB.fallback_font


func _text(center: Vector2, text: String, size: int, color: Color, outline := true) -> void:
	var f := _font()
	var w := 940.0
	var pos := Vector2(center.x - w / 2.0, center.y)
	if outline:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 4, Color(0, 0, 0, 0.7 * color.a))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, color)


func _text_left(pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string_outline(_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.6))
	draw_string(_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


func _heart(c: Vector2, r: float, color: Color) -> void:
	draw_circle(c + Vector2(-r * 0.5, -r * 0.2), r * 0.55, color)
	draw_circle(c + Vector2(r * 0.5, -r * 0.2), r * 0.55, color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, 0), c + Vector2(r * 1.02, 0), c + Vector2(0, r * 1.1)]), color)


func _draw() -> void:
	_draw_room()
	for s in stations:
		_draw_station(s)
	_draw_customers()
	_draw_chef()
	for p in popups:
		var a := clampf(1.6 - p.t, 0.0, 1.0)
		_text(p.pos, p.text, 20, Color(p.color, a))
	if phase != Phase.TITLE:
		_draw_hud()
	match phase:
		Phase.TITLE:
			_draw_title()
		Phase.DAY:
			if touch_mode:
				_draw_touch_controls()
			if banner_t > 0.0:
				_draw_banner()
		Phase.SHOP:
			_draw_shop()
		Phase.GAMEOVER:
			_draw_end(false)
		Phase.VICTORY:
			_draw_end(true)


func _draw_room() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("2a1c1b"))
	draw_rect(Rect2(0, 36, VIEW.x, 100), Color("5b3a35"))
	for i in 24:
		draw_rect(Rect2(i * 40 + 2, 36, 2, 100), Color("4f322e"))
	var tile := 40.0
	for y in range(0, 10):
		for x in range(0, 24):
			var r := Rect2(x * tile, 160 + y * tile, tile, tile)
			draw_rect(r, Color("e9ddc5") if (x + y) % 2 == 0 else Color("d6c6a8"))
	draw_rect(Rect2(0, 160, 12, 380), Color("3a2a28"))
	draw_rect(Rect2(VIEW.x - 12, 160, 12, 380), Color("3a2a28"))
	# the pass (serving counter)
	draw_rect(Rect2(0, 132, VIEW.x, 30), Color("8b5a2b"))
	draw_rect(Rect2(0, 132, VIEW.x, 6), Color("a8743f"))
	draw_rect(Rect2(0, 160, VIEW.x, 4), Color("5e3a1a"))


func _draw_station(s: Dictionary) -> void:
	var r := _station_rect(s)
	var hot: bool = target == s and target_seat < 0 and phase == Phase.DAY
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.25))
	var base := Color("9aa3ab")
	match s.type:
		"crate": base = Color("a8743f")
		"grill": base = Color("3d3f44")
		"fryer": base = Color("6d7178")
		"board": base = Color("c9a46b")
		"trash": base = Color("4a5a4a")
		"plate": base = Color("b9c2c9")
	draw_rect(r, base)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), base.lightened(0.18))
	match s.type:
		"crate":
			draw_rect(r.grow(-4), base.darkened(0.15), false, 2.0)
			draw_line(r.position + Vector2(4, 4), r.end - Vector2(4, 4), base.darkened(0.2), 2.0)
			_draw_item(s.ingredient, s.pos, 0.9)
		"grill":
			for i in 4:
				var y := r.position.y + 12 + i * 11
				draw_line(Vector2(r.position.x + 6, y), Vector2(r.end.x - 6, y), Color("1f2023"), 3.0)
			if s.item != null:
				draw_circle(s.pos, 22, Color(1.0, 0.45, 0.1, 0.18 + 0.08 * sin(anim_t * 8)))
		"fryer":
			draw_rect(r.grow(-7), Color("d9a531"))
			for i in 3:
				draw_circle(s.pos + Vector2(-12 + i * 12, sin(anim_t * 5 + i) * 6), 2.5, Color("f5d27a"))
		"board":
			draw_rect(r.grow(-8), Color("e6c690"))
		"trash":
			draw_rect(Rect2(r.position + Vector2(10, 14), r.size - Vector2(20, 18)), Color("2f3a2f"))
			draw_rect(Rect2(r.position + Vector2(6, 8), Vector2(r.size.x - 12, 7)), Color("6b7d6b"))
			_text(s.pos + Vector2(0, 8), "TRASH", 11, Color(0.8, 0.85, 0.8), false)
		"plate":
			if (s.item as Array).is_empty():
				_draw_plate([], s.pos, 1.0)
	if s.item != null and s.type != "crate":
		if s.item is Array:
			if not (s.item as Array).is_empty():
				_draw_plate(s.item, s.pos, 1.0)
		else:
			_draw_item(s.item, s.pos, 1.0)
	if Data.COOK.has(s.type) and s.item != null:
		var stages: Array = Data.COOK[s.type]
		if s.item == stages[0]:
			_bar(r, s.progress / cook_time(), Color("6fd16f"))
		elif s.item == stages[1]:
			var f: float = s.progress / burn_time()
			var col := Color("ffb347") if f < 0.6 else (Color("ff4d4d") if int(anim_t * 8) % 2 == 0 else Color("ffb347"))
			_bar(r, f, col)
	if s.type == "board" and s.item is String and Data.CHOP.has(s.item):
		_bar(r, s.progress, Color("6fb8ff"))
	if hot:
		draw_rect(r.grow(3), Color(1, 1, 1, 0.9), false, 3.0)


func _bar(r: Rect2, f: float, color: Color) -> void:
	var bg := Rect2(r.position.x, r.position.y - 12, r.size.x, 7)
	draw_rect(bg, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bg.position + Vector2(1, 1), Vector2((bg.size.x - 2) * clampf(f, 0, 1), bg.size.y - 2)), color)


func _draw_plate(items: Array, c: Vector2, s: float) -> void:
	_ellipse(c + Vector2(0, 3 * s), 21 * s, 17 * s, Color(0, 0, 0, 0.2))
	_ellipse(c, 21 * s, 17 * s, Color("f4f4f0"))
	_ellipse(c, 15 * s, 12 * s, Color("e2e2dc"))
	var offs := [Vector2(-7, -5), Vector2(7, -5), Vector2(-7, 6), Vector2(7, 6)]
	if items.size() == 1:
		offs = [Vector2.ZERO]
	elif items.size() == 2:
		offs = [Vector2(-7, 0), Vector2(7, 0)]
	for i in items.size():
		_draw_item(items[i], c + offs[i] * s, 0.55 * s)


func _draw_item(item: String, c: Vector2, s: float) -> void:
	match item:
		"bun":
			_ellipse(c, 15 * s, 11 * s, Color("d18b3c"))
			_ellipse(c + Vector2(0, -2 * s), 12 * s, 7 * s, Color("e6a75a"))
			for o in [Vector2(-5, -4), Vector2(2, -6), Vector2(5, -2)]:
				_ellipse(c + o * s, 1.6 * s, 1.0 * s, Color("fff2d0"))
		"patty_raw":
			_ellipse(c, 14 * s, 11 * s, Color("e67d8a"))
			_ellipse(c + Vector2(-3, -3) * s, 4 * s, 3 * s, Color("f7b1ba"))
		"patty":
			_ellipse(c, 14 * s, 11 * s, Color("6b3a1e"))
			for i in 3:
				draw_line(c + Vector2(-8, -5 + i * 5) * s, c + Vector2(8, -5 + i * 5) * s, Color("3d1f0e"), 2.0 * s)
		"patty_burnt":
			_ellipse(c, 14 * s, 11 * s, Color("1d1716"))
			draw_circle(c + Vector2(4, -14 + sin(anim_t * 3) * 2) * s, 4 * s, Color(0.5, 0.5, 0.5, 0.5))
		"lettuce_raw":
			draw_circle(c, 13 * s, Color("4fa64a"))
			draw_circle(c + Vector2(-3, -3) * s, 8 * s, Color("7ccc6a"))
		"lettuce":
			for o in [Vector2(-6, 2), Vector2(5, 3), Vector2(0, -5)]:
				draw_circle(c + o * s, 6 * s, Color("69bf58"))
				draw_circle(c + o * s, 3 * s, Color("a5e08f"))
		"tomato_raw":
			draw_circle(c, 13 * s, Color("e0402f"))
			draw_circle(c + Vector2(-4, -4) * s, 4 * s, Color("f27a68"))
			draw_circle(c + Vector2(0, -12) * s, 3 * s, Color("3f8f3a"))
		"tomato":
			for o in [Vector2(-5, 0), Vector2(5, 1)]:
				draw_circle(c + o * s, 8 * s, Color("e0402f"))
				draw_circle(c + o * s, 5 * s, Color("f58a73"))
		"cheese":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 8) * s, c + Vector2(12, 8) * s, c + Vector2(6, -10) * s]), Color("f2c230"))
			draw_circle(c + Vector2(2, 2) * s, 2.5 * s, Color("d9a51c"))
		"potato":
			_ellipse(c, 14 * s, 10 * s, Color("b38652"))
			draw_circle(c + Vector2(-4, -2) * s, 1.5 * s, Color("7a5631"))
			draw_circle(c + Vector2(5, 3) * s, 1.5 * s, Color("7a5631"))
		"fries", "fries_burnt":
			var col := Color("f5c542") if item == "fries" else Color("2b2320")
			for i in 5:
				draw_rect(Rect2(c + Vector2(-9 + i * 4, -12 + (i % 2) * 3) * s, Vector2(3, 14) * s), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-11, 0) * s, c + Vector2(11, 0) * s, c + Vector2(8, 12) * s, c + Vector2(-8, 12) * s]), Color("d63a2f"))


func _draw_customers() -> void:
	for i in seats:
		draw_rect(Rect2(seat_x(i) - 22, 146, 44, 8), Color("6b4422"))
	for c in customers:
		var x := seat_x(c.seat)
		var frac: float = clampf(c.patience / c.max_patience, 0.0, 1.0)
		var bob := sin(anim_t * 2.0 + c.bob) * 2.0
		var body: Color = Color("ffd700") if c.vip else c.color
		if frac < 0.25:
			body = body.lerp(Color("ff4d4d"), 0.4 + 0.2 * sin(anim_t * 10))
		var head := Vector2(x, CUSTOMER_Y + bob)
		_ellipse(head + Vector2(0, 26), 26, 14, body.darkened(0.25))
		draw_circle(head, 18, Color("f1c9a5"))
		draw_arc(head + Vector2(0, -4), 18, PI, TAU, 16, body, 8.0)
		draw_circle(head + Vector2(-6, -1), 2.2, Color("2a1c1b"))
		draw_circle(head + Vector2(6, -1), 2.2, Color("2a1c1b"))
		if frac > 0.5:
			draw_arc(head + Vector2(0, 4), 6, 0.2, PI - 0.2, 8, Color("2a1c1b"), 2.0)
		elif frac > 0.25:
			draw_line(head + Vector2(-5, 8), head + Vector2(5, 8), Color("2a1c1b"), 2.0)
		else:
			draw_arc(head + Vector2(0, 11), 6, PI + 0.3, TAU - 0.3, 8, Color("2a1c1b"), 2.0)
		if c.vip:
			draw_colored_polygon(PackedVector2Array([head + Vector2(-10, -18), head + Vector2(-10, -30), head + Vector2(-4, -24),
				head + Vector2(0, -32), head + Vector2(4, -24), head + Vector2(10, -30), head + Vector2(10, -18)]), Color("ffd700"))
		# order bubble
		var items: Array = c.recipe.items
		var w := 22.0 + items.size() * 24.0
		var bub := Rect2(x + 22, 44 + bob, w, 34)
		draw_rect(bub, Color(1, 1, 1, 0.95))
		draw_colored_polygon(PackedVector2Array([Vector2(x + 22, 66 + bob), Vector2(x + 34, 78 + bob), Vector2(x + 14, 84 + bob)]), Color(1, 1, 1, 0.95))
		for k in items.size():
			_draw_item(items[k], Vector2(bub.position.x + 23 + k * 24, bub.position.y + 17), 0.7)
		# patience bar
		var pb := Rect2(x - 26, 132, 52, 6)
		draw_rect(pb, Color(0, 0, 0, 0.6))
		var pc := Color("6fd16f") if frac > 0.5 else (Color("ffb347") if frac > 0.25 else Color("ff4d4d"))
		draw_rect(Rect2(pb.position + Vector2(1, 1), Vector2(50 * frac, 4)), pc)
		if target_seat == c.seat and phase == Phase.DAY:
			draw_arc(head, 25, 0, TAU, 24, Color.WHITE, 3.0)


func _draw_chef() -> void:
	if phase == Phase.TITLE:
		return
	var p := chef_pos
	var bob := absf(sin(chef_walk)) * 2.0
	_ellipse(p + Vector2(0, 14), 16, 6, Color(0, 0, 0, 0.25))
	draw_circle(p + Vector2(0, -bob), CHEF_RADIUS, Color("f7f7f7"))
	draw_arc(p + Vector2(0, -bob), CHEF_RADIUS, 0, TAU, 24, Color("c9c9c9"), 2.0)
	draw_circle(p + Vector2(0, -bob) + chef_facing * 6, 9, Color("f1c9a5"))
	var h := p + Vector2(0, -bob - 6)
	draw_circle(h + Vector2(-5, -8), 6, Color.WHITE)
	draw_circle(h + Vector2(5, -8), 6, Color.WHITE)
	draw_circle(h + Vector2(0, -11), 6, Color.WHITE)
	if held != null:
		var hp := p + chef_facing * 20 + Vector2(0, -bob - 4)
		if held is Array:
			_draw_plate(held, hp, 0.8)
		else:
			_draw_item(held, hp, 0.8)


func _draw_touch_controls() -> void:
	# joystick: shows at the thumb when held, ghosted at its home spot otherwise
	var base := joy_origin if joy_index >= 0 else JOY_HOME
	var a := 0.45 if joy_index >= 0 else 0.22
	draw_circle(base, JOY_RADIUS, Color(0, 0, 0, a * 0.6))
	draw_arc(base, JOY_RADIUS, 0, TAU, 32, Color(1, 1, 1, a), 3.0)
	draw_circle(base + joy_dir * JOY_RADIUS, 26, Color(1, 1, 1, a + 0.15))
	# action button — the whole right half of the screen works, this just shows it
	var bc := Color("8be38b") if btn_down else Color(1, 1, 1, 1)
	draw_circle(BTN_HOME, 52, Color(0, 0, 0, 0.3 if btn_down else 0.18))
	draw_arc(BTN_HOME, 52, 0, TAU, 32, Color(bc, 0.45), 3.0)
	var label := "USE"
	if target_seat >= 0:
		label = "SERVE"
	elif not target.is_empty():
		match target.type:
			"board":
				label = "CHOP" if target.item is String and Data.CHOP.has(target.item) else "USE"
			"crate":
				label = "GRAB"
			"trash":
				label = "TOSS"
	_text(BTN_HOME + Vector2(0, 7), label, 20, Color(bc, 0.75))


func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, VIEW.x, 36), Color(0, 0, 0, 0.55))
	_text_left(Vector2(12, 26), "Day %d/%d" % [day, FINAL_DAY], 21, Color.WHITE)
	_text_left(Vector2(122, 25), event.get("name", ""), 16, Color("ffd27a"))
	for i in max_hearts:
		_heart(Vector2(330 + i * 24, 18), 9, Color("ff5a6a") if i < hearts else Color(1, 1, 1, 0.2))
	_text_left(Vector2(460, 26), "$%d" % money, 23, Color("8be38b"))
	_text_left(Vector2(560, 25), "Rent: $%d" % rent_for(day), 17, Color("e8d6c0"))
	var f := clampf(day_time / DAY_LENGTH, 0.0, 1.0)
	var cr := Rect2(700, 9, 246, 18)
	draw_rect(cr, Color(1, 1, 1, 0.15))
	draw_rect(Rect2(cr.position, Vector2(cr.size.x * f, cr.size.y)), Color("f2a33a"))
	var label := "Closing — serve the last guests" if day_time >= DAY_LENGTH else "%ds left" % ceili(DAY_LENGTH - day_time)
	_text(Vector2(cr.get_center().x, 24), label, 14, Color.WHITE)
	if phase == Phase.DAY and day == 1 and not touch_mode:
		_text(Vector2(480, 456), "WASD/Arrows move  ·  E/Space interact  ·  hold E at the board to chop  ·  serve at the counter", 13, Color(0.2, 0.15, 0.1, 0.75), false)


func _dim(a := 0.72) -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.06, 0.04, 0.04, a))


func _draw_banner() -> void:
	var a := clampf(banner_t, 0.0, 1.0)
	var r := Rect2(150, 200, 660, 110)
	draw_rect(r, Color(0.1, 0.07, 0.06, 0.85 * a))
	draw_rect(r, Color(1, 0.84, 0.48, a), false, 2.0)
	_text(Vector2(480, 242), "Day %d — %s" % [day, event.name], 30, Color(1, 0.85, 0.5, a))
	draw_multiline_string(_font(), Vector2(170, 276), event.desc, HORIZONTAL_ALIGNMENT_CENTER, 620, 18, 2, Color(1, 1, 1, a))


func _draw_title() -> void:
	_dim(0.8)
	_text(Vector2(480, 160), "KITCHEN CRAWL", 66, Color("ffcf6b"))
	_text(Vector2(480, 200), "a restaurant roguelike", 22, Color("e8d6c0"))
	for i in 3:
		_draw_item(["bun", "patty", "lettuce_raw"][i], Vector2(420 + i * 60, 250), 1.4)
	_text(Vector2(480, 314), "Survive 10 days. Every night the rent goes up.", 20, Color.WHITE)
	_text(Vector2(480, 342), "Angry customers cost reputation. Pick an upgrade after each day.", 20, Color.WHITE)
	if touch_mode:
		_text(Vector2(480, 382), "Left thumb: move  ·  Right thumb: grab / place / serve (hold to chop)", 17, Color("cccccc"))
	else:
		_text(Vector2(480, 382), "WASD / Arrows to move  ·  E / Space to grab, place, serve  ·  hold E to chop", 16, Color("cccccc"))
	if int(anim_t * 2) % 2 == 0:
		_text(Vector2(480, 440), "Tap to open your doors" if touch_mode else "Press Enter to open your doors", 26, Color("8be38b"))


func _draw_shop() -> void:
	_dim()
	_text(Vector2(480, 66), "Day %d complete" % day, 34, Color("ffcf6b"))
	_text(Vector2(480, 100), "Served %d  ·  Lost %d  ·  Earned $%d  ·  Rent $%d  ·  Cash $%d" % [served_today, lost_today, day_earned, last_rent, money], 18, Color.WHITE)
	_text(Vector2(480, 128), "Tomorrow's rent: $%d" % rent_for(day + 1), 17, Color("e8d6c0"))
	_text(Vector2(480, 174), "Choose an upgrade", 24, Color.WHITE)
	card_rects.clear()
	var cw := 270.0
	var gap := 22.0
	var x0 := (VIEW.x - (cw * 3 + gap * 2)) / 2.0
	var mouse := get_global_mouse_position()
	for i in offers.size():
		var u: Dictionary = offers[i]
		var r := Rect2(x0 + i * (cw + gap), 192, cw, 250)
		card_rects.append(r)
		var kc: Color = KIND_COLOR[u.kind]
		var hover := r.has_point(mouse) and not touch_mode
		draw_rect(Rect2(r.position + Vector2(4, 6), r.size), Color(0, 0, 0, 0.4))
		draw_rect(r, Color("2e2220") if not hover else Color("3d2d2a"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 34)), kc)
		draw_rect(r, kc if not hover else Color.WHITE, false, 3.0)
		_text(Vector2(r.get_center().x, r.position.y + 23), u.kind.to_upper(), 15, Color(0.1, 0.08, 0.06), false)
		_text(Vector2(r.get_center().x, r.position.y + 76), u.name, 24, Color.WHITE)
		draw_multiline_string(_font(), r.position + Vector2(16, 114), u.desc, HORIZONTAL_ALIGNMENT_CENTER, cw - 32, 18, 5, Color("e0d4c4"))
		if int(u.max) > 1:
			_text(Vector2(r.get_center().x, r.end.y - 38), "Level %d / %d" % [_lvl(u.id) + 1, int(u.max)], 14, Color("aaaaaa"), false)
		_text(Vector2(r.get_center().x, r.end.y - 12), "TAP" if touch_mode else "[%d]" % (i + 1), 18, kc)
	_text(Vector2(480, 484), "Tap a card" if touch_mode else "Press 1, 2 or 3 — or click a card", 17, Color("cccccc"))


func _draw_end(won: bool) -> void:
	_dim(0.82)
	if won:
		_text(Vector2(480, 170), "★ YOU MADE IT ★", 54, Color("ffd700"))
		_text(Vector2(480, 214), "Ten days, every rent paid. The critics are calling it a gem.", 20, Color.WHITE)
	else:
		_text(Vector2(480, 170), "CLOSED FOR GOOD", 54, Color("ff6a5a"))
		_text(Vector2(480, 214), game_over_reason, 20, Color.WHITE)
	_text(Vector2(480, 280), "Days: %d   ·   Customers served: %d   ·   Total earned: $%d" % [day, served_total, total_earned], 20, Color("e8d6c0"))
	var owned: Array = []
	for id in upgrades:
		var u := Data.upgrade(id)
		owned.append(u.name + ("" if upgrades[id] == 1 else " x%d" % upgrades[id]))
	if not owned.is_empty():
		draw_multiline_string(_font(), Vector2(130, 320), "Upgrades: " + ", ".join(owned), HORIZONTAL_ALIGNMENT_CENTER, 700, 16, 3, Color("aaaaaa"))
	if end_t > 1.0 and int(anim_t * 2) % 2 == 0:
		_text(Vector2(480, 430), "Tap to start a new run" if touch_mode else "Press Enter to start a new run", 24, Color("8be38b"))
