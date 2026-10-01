extends GameTest
## Kitchen Crawl gameplay tests.


func _game() -> Node:
	var g = await load_scene("res://main.tscn")
	g.start_run(1234)
	g.spawn_timer = 9999.0  # tests spawn customers by hand
	g.banner_t = 0.0
	return g


func _station(g, type: String, ingredient := "") -> Dictionary:
	for s in g.stations:
		if s.type == type and (ingredient == "" or s.ingredient == ingredient):
			return s
	return {}


func _use(g, s: Dictionary) -> void:
	g.target = s
	g.target_seat = -1
	g.interact()


func test_title_then_run_starts():
	var g = await load_scene("res://main.tscn")
	assert_eq(g.phase, g.Phase.TITLE, "starts on title")
	g.start_run(1)
	assert_eq(g.phase, g.Phase.DAY, "run starts a day")
	assert_eq(g.day, 1)
	assert_eq(g.money, 0)
	assert_eq(g.hearts, 3)


func test_grill_cooks_then_burns():
	var g = await _game()
	var grill := _station(g, "grill")
	_use(g, _station(g, "crate", "patty_raw"))
	assert_eq(g.held, "patty_raw", "grabbed raw patty")
	_use(g, grill)
	assert_eq(grill.item, "patty_raw", "patty on grill")
	assert_eq(g.held, null)
	g.tick_stations(g.cook_time() + 0.01)
	assert_eq(grill.item, "patty", "cooked")
	g.tick_stations(g.burn_time() + 0.01)
	assert_eq(grill.item, "patty_burnt", "burnt")


func test_chopping_needs_time():
	var g = await _game()
	var board := _station(g, "board")
	_use(g, _station(g, "crate", "lettuce_raw"))
	_use(g, board)
	assert_eq(board.item, "lettuce_raw")
	g.chop(g.chop_time() * 0.5, board)
	assert_eq(board.item, "lettuce_raw", "half chopped")
	g.chop(g.chop_time() * 0.6, board)
	assert_eq(board.item, "lettuce", "chopped")


func test_assemble_and_serve_burger():
	var g = await _game()
	var plate := _station(g, "plate")
	var grill := _station(g, "grill")
	_use(g, _station(g, "crate", "bun"))
	_use(g, plate)
	assert_eq(plate.item, ["bun"], "bun on plate")
	_use(g, _station(g, "crate", "patty_raw"))
	_use(g, plate)
	assert_eq(plate.item, ["bun"], "raw patty refused by plate")
	_use(g, grill)
	g.tick_stations(g.cook_time() + 0.01)
	_use(g, grill)
	_use(g, plate)
	assert_eq(plate.item.size(), 2, "burger assembled")
	_use(g, plate)
	assert_true(g.held is Array, "carrying plate")
	var c: Dictionary = g.spawn_customer("Burger")
	g.serve(c.seat)
	assert_gt(g.money, 9.0, "paid with tip")
	assert_eq(g.customers.size(), 0, "customer left happy")
	assert_eq(g.held, null)


func test_wrong_order_rejected():
	var g = await _game()
	var c: Dictionary = g.spawn_customer("Burger")
	g.held = ["lettuce"]
	var p: float = c.patience
	g.serve(c.seat)
	assert_eq(g.money, 0)
	assert_lt(c.patience, p, "wrong order costs patience")
	assert_eq(g.customers.size(), 1)


func test_impatient_customer_costs_heart():
	var g = await _game()
	var c: Dictionary = g.spawn_customer("Burger")
	g.tick_customers(c.patience + 1.0)
	assert_eq(g.hearts, 2)
	assert_eq(g.customers.size(), 0)


func test_reputation_zero_ends_run():
	var g = await _game()
	g.hearts = 1
	var c: Dictionary = g.spawn_customer("Burger")
	g.tick_customers(c.patience + 1.0)
	assert_eq(g.phase, g.Phase.GAMEOVER)


func test_end_day_pays_rent_and_offers_upgrades():
	var g = await _game()
	g.money = 100
	g.end_day()
	assert_eq(g.money, 100 - g.rent_for(1))
	assert_eq(g.phase, g.Phase.SHOP)
	assert_eq(g.offers.size(), 3)
	var has_unlock := false
	for o in g.offers:
		has_unlock = has_unlock or o.kind == "unlock"
	assert_true(has_unlock, "early shop offers an ingredient unlock")
	g.choose_offer(0)
	assert_eq(g.phase, g.Phase.DAY)
	assert_eq(g.day, 2)


func test_missing_rent_is_game_over():
	var g = await _game()
	g.money = 5
	g.end_day()
	assert_eq(g.phase, g.Phase.GAMEOVER)


func test_unlocks_add_stations_and_recipes():
	var g = await _game()
	var before: int = g.recipe_pool().size()
	g.apply_upgrade("fryer")
	assert_gt(g.recipe_pool().size(), before, "more recipes")
	assert_eq(g.stations_of("fryer").size(), 1)
	g.apply_upgrade("stool")
	assert_eq(g.seats, 4)


func test_surviving_final_day_wins():
	var g = await _game()
	g.start_day(g.FINAL_DAY)
	g.money = 10000
	g.end_day()
	assert_eq(g.phase, g.Phase.VICTORY)


func test_keyboard_moves_chef():
	var g = await _game()
	var x: float = g.chef_pos.x
	await hold_action("move_left", 15)
	assert_lt(g.chef_pos.x, x - 30.0, "moved left")


func test_touch_joystick_moves_chef():
	var g = await _game()
	var y: float = g.chef_pos.y
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(150, 400)
	g._handle_touch(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(150, 460)
	g._handle_touch(drag)
	await wait_physics_frames(15)
	assert_gt(g.chef_pos.y, y + 30.0, "joystick moved chef down")
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	g._handle_touch(up)
	assert_eq(g.joy_dir, Vector2.ZERO, "released")


func test_touch_button_interacts():
	var g = await _game()
	g.chef_pos = Vector2(90, 220)  # next to the bun crate
	var tap := InputEventScreenTouch.new()
	tap.index = 1
	tap.pressed = true
	tap.position = Vector2(800, 400)
	g._handle_touch(tap)
	await wait_physics_frames(2)
	assert_eq(g.held, "bun", "right-side tap grabbed a bun")


func test_tap_picks_shop_card():
	var g = await _game()
	g.money = 100
	g.end_day()
	g.queue_redraw()
	await wait_frames(2)
	g.end_t = 1.0
	assert_eq(g.card_rects.size(), 3)
	g._tap(g.card_rects[1].get_center())
	assert_eq(g.day, 2, "card tapped, next day")
