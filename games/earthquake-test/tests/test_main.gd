extends GameTest

const DAY := "2026-10-02"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.date = d
	main.wipe_save()
	main.target_score = 0
	main.load_day(d)
	main.tut_open = false
	return main


func _two_anchors(main) -> Array:
	var a: Vector2i = main.anchors[main.anchors.size() - 2]
	var b: Vector2i = main.anchors[main.anchors.size() - 1]
	return [a, b]


func test_same_date_same_day():
	var main = await _fresh()
	var anchors_a: Array = main.anchors.duplicate()
	var budget_a: int = main.budget
	var trace_a: PackedFloat32Array = main.quake.trace.duplicate()
	main.generate(DAY)
	assert_eq(main.anchors, anchors_a, "anchors are deterministic")
	assert_eq(main.budget, budget_a, "budget is deterministic")
	assert_eq(main.quake.trace, trace_a, "quake is deterministic")
	main.generate("2026-10-03")
	assert_ne(main.quake.trace, trace_a, "a different day gives a different quake")
	assert_eq(main.day_number("2026-10-03"), 2, "quake numbering")


func test_site_is_sane():
	var main = await _fresh()
	assert_true(main.anchors.size() >= 2 and main.anchors.size() <= 3, "2-3 anchors")
	assert_true(main.budget >= 40 and main.budget <= 65, "budget range")
	for i in range(1, main.anchors.size()):
		assert_true(main.anchors[i].x - main.anchors[i - 1].x >= 2, "anchors spaced apart")
	assert_true(main.quake.magnitude >= 6.0 and main.quake.magnitude <= 7.6, "magnitude range")


func test_build_rules():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	assert_false(main.add_beam(a + Vector2i(0, 3), a + Vector2i(0, 4)), "must start at an anchor or joint")
	assert_false(main.add_beam(a, a + Vector2i(3, 1)), "too long")
	assert_false(main.add_beam(a + Vector2i(0, 1), a + Vector2i(1, 0)), "ground points must be anchors")
	assert_true(main.add_beam(a, a + Vector2i(0, 1)), "post from anchor")
	assert_false(main.add_beam(a + Vector2i(0, 1), a), "no duplicate beams")
	assert_true(main.add_beam(a + Vector2i(0, 1), a + Vector2i(0, 3)), "build up from a joint")
	assert_eq(main.design.size(), 2, "two beams")
	main.remove_beam(0)
	assert_eq(main.design.size(), 0, "removing the base prunes what hung off it")
	main.undo()
	assert_eq(main.design.size(), 2, "undo restores")


func test_budget_is_enforced():
	var main = await _fresh()
	main.set_mat(1)
	var a: Vector2i = main.anchors[0]
	var y := 0
	var built := 0
	while y < main.GH:
		if not main.add_beam(Vector2i(a.x, y), Vector2i(a.x, y + 1)):
			break
		built += 1
		y += 1
	assert_true(main.money_left() >= 0.0, "never overspend")
	assert_lt(main.money_left(), 3.0, "spent down to the last beam")
	assert_eq(built, int(main.budget / 3), "steel posts cost $3 each")


func test_taps_build_and_remove():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.tap_world(a, Vector2(a))
	assert_eq(main.selected, a, "tap an anchor selects it")
	main.tap_world(a + Vector2i(1, 1), Vector2(a + Vector2i(1, 1)))
	assert_eq(main.design.size(), 1, "tap a dot builds a beam")
	assert_eq(main.selected, a + Vector2i(1, 1), "selection follows the new joint")
	main.tap_world(a + Vector2i(1, 1), Vector2(a + Vector2i(1, 1)))
	assert_eq(main.selected, Vector2i(-1, -1), "tap again deselects")
	main.tap_world(Vector2i(-1, -1), Vector2(a) + Vector2(0.5, 0.5))
	assert_eq(main.design.size(), 0, "tap a beam removes it")


func test_quake_is_deterministic():
	var main = await _fresh()
	var ab := _two_anchors(main)
	var a: Vector2i = ab[0]
	var b: Vector2i = ab[1]
	# a braced 2-level frame between the two anchors (if they're 2 apart; else a lean-to)
	main.add_beam(a, a + Vector2i(0, 1))
	main.add_beam(a + Vector2i(0, 1), a + Vector2i(0, 2))
	main.add_beam(a + Vector2i(0, 2), a + Vector2i(1, 3))
	main.add_beam(a, a + Vector2i(1, 2))
	main.add_beam(a + Vector2i(0, 1), a + Vector2i(1, 2))
	main.add_beam(a + Vector2i(1, 2), a + Vector2i(1, 3))
	var design: Array = main.design.duplicate(true)
	var r1: Dictionary = main.run_instant()
	assert_eq(main.phase, main.Phase.RESULT, "one try used")
	main.back_to_build()
	main.design = design
	var r2: Dictionary = main.run_instant()
	assert_eq(int(r1.score), int(r2.score), "same build, same quake, same score")
	assert_eq(r1.end_x, r2.end_x, "identical final positions")


func test_triangle_survives():
	var main = await _fresh()
	var ab := _two_anchors(main)
	var a: Vector2i = ab[0]
	var b: Vector2i = ab[1]
	var apex := Vector2i((a.x + b.x) / 2, 1)
	assert_true(main.add_beam(a, apex), "left leg")
	assert_true(main.add_beam(b, apex), "right leg")
	var r: Dictionary = main.run_instant()
	assert_gt(int(r.score), 50, "a triangle across two anchors stays up")
	assert_eq(int(r.broken), 0, "nothing snaps")


func test_tries_final_share_and_save():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	for k in main.MAX_TRIES:
		if main.phase == main.Phase.RESULT:
			main.back_to_build()
		if main.design.is_empty():
			main.add_beam(a, a + Vector2i(1, 1))
			main.add_beam(a, a + Vector2i(0, 1))
			main.add_beam(a + Vector2i(0, 1), a + Vector2i(1, 1))
		main.run_instant()
	assert_eq(main.phase, main.Phase.FINAL, "final after the last try")
	assert_eq(main.tries.size(), main.MAX_TRIES, "three tries")
	var txt: String = main.share_text()
	assert_true(txt.contains("Earthquake Test #1"), "share text has the quake number")
	assert_true(txt.contains("?d=" + DAY), "share link pins the day")
	# reload keeps everything
	main.load_day(DAY)
	assert_eq(main.tries.size(), main.MAX_TRIES, "tries persist")
	assert_eq(main.phase, main.Phase.FINAL, "still final after reload")
	main.wipe_save()


func test_finish_early_and_resume_design():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.add_beam(a, a + Vector2i(0, 1))
	main.load_day(DAY)
	assert_eq(main.design.size(), 1, "design in progress survives a reload")
	main.add_beam(a, a + Vector2i(1, 1))
	main.add_beam(a + Vector2i(0, 1), a + Vector2i(1, 1))
	main.run_instant()
	main.finish()
	assert_eq(main.phase, main.Phase.FINAL, "finish ends the day")
	main.wipe_save()


func test_live_run_advances():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.add_beam(a, a + Vector2i(1, 1))
	main.add_beam(a, a + Vector2i(0, 1))
	main.add_beam(a + Vector2i(0, 1), a + Vector2i(1, 1))
	main.run()
	assert_eq(main.phase, main.Phase.RUN, "running")
	main.skip()
	var guard := 0
	while main.phase == main.Phase.RUN and guard < 2000:
		await wait_frames(1)
		guard += 1
	assert_eq(main.phase, main.Phase.RESULT, "fast-forward reaches the result")
	main.wipe_save()


func test_dev_menu_from_title_taps():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.add_beam(a, a + Vector2i(0, 1))
	main.add_beam(a, a + Vector2i(1, 1))
	main.add_beam(a + Vector2i(0, 1), a + Vector2i(1, 1))
	main.run_instant()
	assert_eq(main.tries.size(), 1, "one try used")
	for k in 4:
		main._dev_tap()
	assert_false(main.dev_open, "four taps don't open it")
	main._dev_tap()
	assert_true(main.dev_open, "the fifth quick tap opens the dev menu")
	main.dev_reset_today()
	assert_false(main.dev_open, "menu closes after resetting")
	assert_eq(main.tries.size(), 0, "today's tries are gone")
	assert_eq(main.design.size(), 0, "today's design is gone")
	assert_eq(main.phase, main.Phase.BUILD, "back to building")
	main.load_day(main.date)
	assert_eq(main.tries.size(), 0, "the reset persists across a reload")


func test_slow_title_taps_do_nothing():
	var main = await _fresh()
	for k in 5:
		main._dev_tap()
		main.anim_t += 1.0
	assert_false(main.dev_open, "taps spaced out by a second don't count")
