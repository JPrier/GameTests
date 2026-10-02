extends GameTest

const DAY := "2026-10-01"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.date = d
	main.wipe_save()
	main.target_score = 0
	main.load_puzzle(d)
	main.tut_open = false
	return main


func _plant(main, offsets: Array) -> void:
	var z: Rect2i = main.zone
	var o := z.position + Vector2i(2, 2)
	for off in offsets:
		var p: Vector2i = o + off
		main.toggle(p.y * main.W + p.x)


func test_same_date_same_map():
	var main = await _fresh()
	var a: PackedByteArray = main.tiles.duplicate()
	var zone_a: Rect2i = main.zone
	var budget_a: int = main.budget
	main.generate(DAY)
	assert_eq(main.tiles, a, "tiles are deterministic")
	assert_eq(main.zone, zone_a, "zone is deterministic")
	assert_eq(main.budget, budget_a, "budget is deterministic")
	main.generate("2026-10-02")
	assert_ne(main.tiles, a, "a different day gives a different map")
	assert_eq(main.day_number("2026-10-02"), 2, "puzzle numbering")


func test_map_is_sane():
	var main = await _fresh()
	assert_true(main.budget >= 16 and main.budget <= 28, "budget range")
	assert_gt(main.star_total, 5, "stars placed")
	var z: Rect2i = main.zone
	for y in range(z.position.y, z.end.y):
		for x in range(z.position.x, z.end.x):
			assert_eq(main.tiles[y * main.W + x], 0, "zone has no walls or stars")


func test_placement_rules():
	var main = await _fresh()
	assert_false(main.toggle(0), "corner is outside the zone")
	var z: Rect2i = main.zone
	var placed := 0
	for y in range(z.position.y, z.end.y):
		for x in range(z.position.x, z.end.x):
			if main.toggle(y * main.W + x):
				placed += 1
	assert_eq(placed, main.budget, "cannot exceed the seed budget")
	var first: int = main.seeds.keys()[0]
	assert_true(main.toggle(first), "tapping a seed removes it")
	assert_eq(main.seeds.size(), main.budget - 1, "one seed removed")


func test_life_rules():
	var main = await _fresh()
	main.tiles.fill(0)
	var W: int = main.W
	# blinker oscillates with period 2
	main._start_sim([5 * W + 4, 5 * W + 5, 5 * W + 6])
	main.step()
	assert_eq(main.alive[4 * W + 5] + main.alive[5 * W + 5] + main.alive[6 * W + 5], 3, "blinker turns vertical")
	assert_eq(main.alive.count(1), 3, "blinker keeps 3 cells")
	main.step()
	assert_eq(main.alive[5 * W + 4], 1, "blinker returns")
	# block is still
	main._start_sim([10 * W + 10, 10 * W + 11, 11 * W + 10, 11 * W + 11])
	main.step()
	assert_eq(main.alive.count(1), 4, "block is stable")
	# walls never come alive
	main.tiles[5 * W + 5] = 1
	main._start_sim([5 * W + 4, 4 * W + 5, 6 * W + 5])
	main.step()
	assert_eq(main.alive[5 * W + 5], 0, "wall cell stays dead")


func test_scoring_counts_touched_and_stars():
	var main = await _fresh()
	main.tiles.fill(0)
	var W: int = main.W
	main.tiles[10 * W + 10] = 2  # star under a block
	var r: Dictionary = main.simulate([10 * W + 10, 10 * W + 11, 11 * W + 10, 11 * W + 11])
	assert_eq(r.touched, 4, "block touches 4 cells")
	assert_eq(r.stars, 1, "one star reached")
	assert_eq(r.score, 4 + main.STAR_BONUS, "score formula")


func test_three_tries_then_share():
	var main = await _fresh()
	_plant(main, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)])  # R-pentomino
	main.run()
	assert_eq(main.phase, main.Phase.RUN, "running")
	await wait_seconds(0.3)
	assert_gt(main.gen, 0, "generations advance over time")
	main.skip()
	assert_eq(main.phase, main.Phase.RESULT, "result after first try")
	assert_eq(main.tries.size(), 1, "one try recorded")
	assert_gt(main.tries[0].score, 5, "pentomino spreads")
	main.try_again()
	assert_eq(main.seeds.size(), 5, "seeds kept for editing")
	main.run()
	main.skip()
	main.try_again()
	main.toggle(main.seeds.keys()[0])
	main.run()
	main.skip()
	assert_eq(main.phase, main.Phase.FINAL, "final after 3 tries")
	assert_eq(main.tries.size(), 3, "three tries")
	var text: String = main.share_text()
	assert_true(text.contains("Bloom #1"), "share has puzzle number")
	assert_true(text.contains("Impact %d" % main.best_score()), "share has best score")
	assert_true(text.contains("?d=2026-10-01&s=%d" % main.best_score()), "share has a link to this map")
	main.share()  # headless -> clipboard, must not crash
	main.wipe_save()


func test_progress_is_saved():
	var main = await _fresh()
	_plant(main, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	main.run()
	main.skip()
	var score: int = main.tries[0].score
	main.finish()
	main.load_puzzle(DAY)
	assert_eq(main.phase, main.Phase.FINAL, "finished day reloads as final")
	assert_eq(main.best_score(), score, "score restored")
	main.wipe_save()


func test_target_from_link_in_share():
	var main = await _fresh()
	main.target_score = 99999
	_plant(main, [Vector2i(0, 0), Vector2i(1, 0)])
	main.run()
	main.skip()
	main.finish()
	assert_true(main.share_text().contains("Couldn't beat 99999"), "challenge line")
	main.wipe_save()


func test_plant_view_zooms_on_zone():
	var main = await _fresh()
	await wait_frames(2)
	var r: Rect2i = main.plant_region()
	assert_eq(r.size.x, r.size.y, "zoom region is square")
	assert_true(r.encloses(main.zone), "zoom region covers the whole zone")
	assert_true(main.zoomed, "plant phase starts zoomed")
	assert_eq(main.main_region, r, "main board shows the zoomed region")
	var zoomed_px: float = main.cell_px
	main.toggle_zoom()
	await wait_frames(1)
	assert_gt(zoomed_px, main.cell_px * 2.5, "zoomed cells are much bigger than map cells")
	assert_eq(main.main_region, Rect2i(0, 0, main.W, main.H), "map view shows the whole board")
	main.toggle_zoom()
	_plant(main, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	main.run()
	await wait_frames(1)
	assert_eq(main.main_region, Rect2i(0, 0, main.W, main.H), "the run is shown on the full map")
	main.skip()
	main.wipe_save()


func test_dev_menu_resets_saves():
	var main = await _fresh()
	_plant(main, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	main.run()
	main.skip()
	main.finish()
	assert_eq(main.phase, main.Phase.FINAL, "day finished")
	for i in 5:
		main._dev_tap()
	assert_true(main.dev_open, "five quick title taps open the dev menu")
	main.dev_reset_today()
	assert_false(main.dev_open, "menu closes after reset")
	assert_eq(main.phase, main.Phase.PLAN, "fresh day after reset")
	assert_eq(main.tries.size(), 0, "tries cleared")
	main.run()
	_plant(main, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	main.run()
	main.skip()
	main.dev_reset_all()
	assert_eq(main.tries.size(), 0, "reset all clears saves")
	assert_false(FileAccess.file_exists("user://bloom_%s.json" % main.date), "save file removed")


func test_tutorial_on_first_visit():
	var flag := "user://bloom_tutorial_seen"
	if FileAccess.file_exists(flag):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(flag))
	var main = await load_scene("res://main.tscn")
	await wait_frames(2)
	assert_true(main.tut_open, "tutorial opens on first visit")
	assert_eq(main.tut_page, 0, "starts on the board page")
	main.tut_next()
	main.tut_next()
	assert_eq(main.tut_page, 2, "third page has the animations")
	var g: int = main.demo_gen
	await wait_seconds(1.6)
	assert_gt(main.demo_gen, g, "demos animate")
	main.tut_back()
	assert_eq(main.tut_page, 1, "back works")
	for i in main.TUT_PAGES:
		main.tut_next()
	assert_false(main.tut_open, "last Next closes it")
	assert_true(main.tutorial_seen(), "seen flag saved")
	var again = await load_scene("res://main.tscn")
	await wait_frames(1)
	assert_false(again.tut_open, "not shown again after it was seen")
	again.open_tutorial()
	assert_true(again.tut_open, "? button reopens it")
	again.close_tutorial()


func test_demo_boards():
	var main = await _fresh()
	main._demo_reset()
	var glider_start: PackedByteArray = main.demos[2]
	var block_start: PackedByteArray = main.demos[0]
	var blinker_start: PackedByteArray = main.demos[1]
	for i in 4:
		main._demo_step()
	assert_eq(main.demos[0], block_start, "block stays still")
	assert_eq(main.demos[1], blinker_start, "blinker returns after an even number of steps")
	assert_eq(main.demos[2].count(1), 5, "glider keeps 5 cells")
	assert_ne(main.demos[2], glider_start, "glider has moved")


func test_shape_library():
	var main = await _fresh()
	for i in main.SHAPES.size():
		assert_gt(main.shape_cells(i).size(), 0, "shape %s has cells" % main.SHAPES[i].name)
		var sz: Vector2i = main.shape_size(i)
		assert_true(sz.x <= main.PG_N and sz.y <= main.PG_N, "shape %s fits the playground" % main.SHAPES[i].name)
		assert_true(main.KIND_COL.has(main.SHAPES[i].kind), "shape kind has a colour")
	assert_eq(main.shape_cells(main._shape_index("Glider")).size(), 5, "glider is 5 cells")
	assert_eq(main.shape_cells(main._shape_index("Glider gun")).size(), 36, "gosper gun is 36 cells")


func test_playground():
	var main = await _fresh()
	main.open_playground()
	await wait_frames(1)
	assert_true(main.pg_open, "playground opens")
	main.pg_clear()
	main.pg_stamp(main._shape_index("Glider"), Vector2i(10, 10))
	assert_eq(main.pg_cells.count(1), 5, "glider stamped")
	var before: PackedByteArray = main.pg_cells.duplicate()
	for i in 4:
		main.pg_step()
	assert_eq(main.pg_cells.count(1), 5, "glider survives")
	assert_ne(main.pg_cells, before, "glider moved")
	assert_eq(main.pg_gen, 4, "step counter")
	main.pg_reset()
	assert_eq(main.pg_cells, before, "reset restores the starting board")
	assert_eq(main.pg_gen, 0, "reset zeroes steps")
	main.pg_clear()
	main.pg_stamp(main._shape_index("Glider gun"), Vector2i(20, 12))
	var n0: int = main.pg_cells.count(1)
	for i in 60:
		main.pg_step()
	assert_gt(main.pg_cells.count(1), n0, "gun has fired gliders")
	main.pg_toggle_play()
	assert_true(main.pg_running, "play starts")
	var g: int = main.pg_gen
	await wait_seconds(0.5)
	assert_gt(main.pg_gen, g, "playing advances steps")
	main.close_playground()
	assert_false(main.pg_open, "back to the puzzle")
	assert_false(main.pg_running, "closing pauses it")
