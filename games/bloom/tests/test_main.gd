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


func test_five_tries_then_share():
	var main = await _fresh()
	assert_eq(main.MAX_TRIES, 5, "five tries a day")
	_plant(main, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)])  # R-pentomino
	main.run()
	assert_eq(main.phase, main.Phase.RUN, "running")
	await wait_seconds(0.3)
	assert_gt(main.gen, 0, "generations advance over time")
	main.skip()
	assert_eq(main.phase, main.Phase.RESULT, "result after first try")
	assert_gt(main.tries[0].score, 5, "pentomino spreads")
	main.try_again()
	assert_eq(main.seeds.size(), 5, "seeds kept for editing")
	for i in 4:
		main.run()
		main.skip()
		if i < 3:
			assert_eq(main.phase, main.Phase.RESULT, "still has tries left")
			main.try_again()
	assert_eq(main.phase, main.Phase.FINAL, "final after 5 tries")
	assert_eq(main.tries.size(), 5, "five tries recorded")
	var text: String = main.share_text()
	assert_true(text.contains("Bloom #1"), "share has puzzle number")
	assert_true(text.contains("Impact %d" % main.best_score()), "share has best score")
	assert_true(text.ends_with(main.base_url), "share links to the game itself")
	assert_false(text.contains("?d=") or text.contains("&s="), "share link has no day or score in it")
	assert_eq(String(main._load_results().get(DAY, "")), "Impact %d" % main.best_score(), "result remembered for the picker")
	await wait_frames(2)
	var ids: Array = []
	for b in main.buttons:
		ids.append(String(b.id))
	assert_true(ids.has("today") and ids.has("share"), "past day end offers today's puzzle")
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


func test_maps_are_open_and_reachable():
	var main = await _fresh()
	for d in ["2026-10-01", "2026-10-02", "2026-11-15", "2027-03-09", "2027-07-21"]:
		main.generate(d)
		assert_true(main.all_reachable(), "%s: every open square is reachable from the zone" % d)
		var frac: float = float(main.tiles.count(main.Cell.WALL)) / (main.W * main.H)
		assert_true(frac > 0.05 and frac < 0.45, "%s: wall share %.2f is sensible" % [d, frac])
		assert_gt(main.star_total, 10, "%s: stars placed" % d)


func test_shape_tools_in_daily_play():
	var main = await _fresh()
	main.tool = main._shape_index("Glider")
	var z: Rect2i = main.zone
	var centre := z.position + z.size / 2
	assert_true(main.stamp(main.tool, centre), "glider fits in the zone")
	assert_eq(main.seeds.size(), 5, "a glider uses 5 seeds")
	var before: Dictionary = main.seeds.duplicate()
	assert_false(main.stamp(main.tool, z.position - Vector2i(3, 3)), "can't place outside the zone")
	assert_eq(main.seeds, before, "failed stamp changes nothing")
	main.clear_seeds()
	main.tool_rot = 1
	var cells: Array = main.rotated_cells(main.tool, 1)
	assert_eq(cells.size(), 5, "rotated glider keeps 5 cells")
	assert_ne(cells, main.shape_cells(main.tool), "rotation changes the layout")
	assert_eq(main.rotated_cells(main.tool, 4), main.shape_cells(main.tool), "four turns is a full circle")
	# budget is enforced
	main.clear_seeds()
	main.tool = main._shape_index("Blinker")
	main.tool_rot = 0
	var placed := 0
	for y in range(z.position.y + 1, z.end.y - 1, 2):
		for x in range(z.position.x + 2, z.end.x - 2, 4):
			if main.stamp(main.tool, Vector2i(x, y)):
				placed += 1
	assert_true(main.seeds.size() <= main.budget, "never more seeds than the budget")
	assert_gt(placed, 2, "several blinkers placed")
	var names: Array = main._chip_defs().map(func(c): return c.label)
	assert_true(names.has("Glider") and names.has("Blinker") and names.has("Rotate"), "daily chips")
	assert_false(names.has("Glider gun"), "big shapes are playground-only")


func test_playground_practice_map():
	var main = await _fresh()
	var daily: PackedByteArray = main.tiles.duplicate()
	main.open_playground()
	assert_true(main.practice, "playground opens")
	var p1: PackedByteArray = main.tiles.duplicate()
	assert_ne(p1, daily, "practice map differs from the daily map")
	assert_true(main.all_reachable(), "practice map is reachable")
	main.close_playground()
	main.date = "2026-10-02"
	main.open_playground()   # this saves the daily progress first...
	main.wipe_save()         # ...so clear it to check practice itself writes nothing
	assert_eq(main.tiles, p1, "practice map is the same every day")
	assert_true(main._chip_defs().size() > main.SHAPES.size(), "all shapes available in the playground")
	# unlimited tries, nothing saved
	main.tool = -1
	var z: Rect2i = main.zone
	for i in 3:
		main.toggle((z.position.y + 2) * main.W + z.position.x + 2 + i)
	for i in 8:
		main.run()
		main.skip()
		assert_eq(main.phase, main.Phase.RESULT, "practice never runs out of tries")
		main.try_again()
	assert_false(FileAccess.file_exists("user://bloom3_2026-10-02.json"), "practice saves nothing")
	# no limits: place outside the zone and beyond the budget
	main.no_limits = true
	main.clear_seeds()
	var outside := -1
	for i in main.W * main.H:
		if not main.in_zone(i) and main.tiles[i] == 0:
			outside = i
			break
	assert_true(main.toggle(outside), "no limits allows planting outside the zone")
	main.clear_seeds()
	main.tool = main._shape_index("Glider gun")
	main.tool_rot = 0
	var placed := false
	for y in range(5, main.H - 5):
		for x in range(18, main.W - 18):
			if main.stamp(main.tool, Vector2i(x, y)):
				placed = true
				break
		if placed:
			break
	assert_true(placed, "the glider gun fits somewhere on the practice map")
	assert_eq(main.seeds.size(), 36, "gun placed with No limits")
	main.close_playground()
	assert_false(main.practice, "back to the daily puzzle")
	assert_eq(main.tool, -1, "playground-only tool is reset")
	main.date = "2026-10-01"
	main.wipe_save()


## Dates spread from next year out to 2100, plus leap days and the 2038 rollover.
func _far_future_days() -> Array:
	var out: Array = ["2028-02-29", "2038-01-19", "2038-01-20", "2096-02-29", "2100-03-01"]
	var t := Time.get_unix_time_from_datetime_string("2027-01-01T00:00:00")
	var end := Time.get_unix_time_from_datetime_string("2100-12-31T00:00:00")
	while t <= end:
		out.append(Time.get_date_string_from_unix_time(t))
		t += 449 * 86400   # an odd stride so the samples land on every weekday and month
	return out


func test_far_future_days_generate():
	var main = await _fresh()
	var seen := {}
	for d in _far_future_days():
		main.generate(d)
		var open := 0
		for t in main.tiles:
			if t == main.Cell.OPEN:
				open += 1
		assert_true(main.budget >= 16 and main.budget <= 28, d + ": seed budget in range")
		assert_gt(open, 300, d + ": enough open ground to grow into")
		assert_gt(main.puzzle_no, 0, d + ": has a puzzle number")
		seen[hash(main.tiles)] = true
	assert_eq(seen.size(), _far_future_days().size(), "every sampled day has its own map")


func test_past_days_picker():
	var main = await _fresh(DAY)
	main.load_puzzle(main.today)
	main.open_archive()
	await wait_frames(2)
	assert_true(main.archive_open, "picker opens")
	var first: Array = main.archive_page_days(0)
	assert_eq(String(first[0]), main.today, "newest day first")
	assert_true(first.size() <= main.ARCHIVE_ROWS, "one page of rows")
	var ids: Array = []
	for b in main.buttons:
		ids.append(String(b.id))
	assert_true(ids.has("day_" + main.today), "today is a row")
	assert_true(ids.has("arch_close"), "picker has a close button")
	var row: Rect2
	for b in main.buttons:
		if String(b.id) == "day_" + main.EPOCH:
			row = b.rect
	if row.has_area():
		main._press_button(row.get_center())
	else:
		main.pick_day(main.EPOCH)
	assert_false(main.archive_open, "picking closes the picker")
	assert_eq(main.date, main.EPOCH, "picked day loads")
	assert_eq(main.puzzle_no, 1, "puzzle #1")
	main.pick_day("2099-01-01")
	assert_eq(main.date, main.EPOCH, "future days can't be picked")
	main.play_today()
	assert_eq(main.date, main.today, "back to today")
