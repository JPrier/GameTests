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
	assert_false(main.add_beam(a + main.dot(0, 3), a + main.dot(0, 4)), "must start at an anchor or joint")
	assert_false(main.add_beam(a, a + main.dot(3, 2)), "too long (3.6 m)")
	assert_false(main.add_beam(a, a + main.dot(0, 4)), "longer than MAX_LEN as one beam")
	assert_false(main.add_beam(a + main.dot(0, 1), a + main.dot(1, 0)), "ground points must be anchors")
	assert_true(main.add_beam(a, a + main.dot(0, 1)), "post from anchor")
	assert_false(main.add_beam(a + main.dot(0, 1), a), "no duplicate beams")
	assert_true(main.add_beam(a + main.dot(0, 1), a + main.dot(0, 3)), "build up from a joint")
	assert_eq(main.design.size(), 2, "two beams")
	main.remove_beam(0)
	assert_eq(main.design.size(), 1, "removing one piece removes only that piece")
	assert_eq(main.built_height(), 0.0, "the piece left floating doesn't count as built")
	main.undo()
	assert_eq(main.design.size(), 2, "undo restores")


func test_budget_is_enforced():
	var main = await _fresh()
	main.set_mat(1)
	var a: Vector2i = main.anchors[0]
	var y := 0
	var built := 0
	while y < main.GH:
		if not main.add_beam(Vector2i(a.x, y * 100), Vector2i(a.x, (y + 1) * 100)):
			break
		built += 1
		y += 1
	assert_true(main.money_left() >= 0.0, "never overspend")
	assert_lt(main.money_left(), 3.0, "spent down to the last beam")
	assert_eq(built, int(main.budget / 3), "steel posts cost $3 each")


func test_taps_build_and_remove():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.tap_world(a, main.wpos(a))
	assert_eq(main.selected, a, "tap an anchor selects it")
	main.tap_world(a + main.dot(1, 1), main.wpos(a + main.dot(1, 1)))
	assert_eq(main.design.size(), 1, "tap a dot builds a beam")
	assert_eq(main.selected, a + main.dot(1, 1), "selection follows the new joint")
	main.tap_world(a + main.dot(1, 1), main.wpos(a + main.dot(1, 1)))
	assert_eq(main.selected, Vector2i(-1, -1), "tap again deselects")
	main.tap_world(Vector2i(-1, -1), main.wpos(a) + Vector2(0.5, 0.5))
	assert_eq(main.design.size(), 1, "tapping a beam does NOT remove it (only Erase does)")
	main._release(main.world_to_screen(main.wpos(a) + Vector2(0.5, 0.5)))
	assert_eq(main.design.size(), 1, "releasing a tap on a beam doesn't remove it either")
	main.dragging = true
	main._release(main.world_to_screen(main.wpos(a) + Vector2(0.5, 0.5)))
	main.dragging = false
	assert_eq(main.design.size(), 1, "a drag that didn't start on a joint does nothing")


func test_quake_is_deterministic():
	var main = await _fresh()
	var ab := _two_anchors(main)
	var a: Vector2i = ab[0]
	var b: Vector2i = ab[1]
	# a braced 2-level frame between the two anchors (if they're 2 apart; else a lean-to)
	main.add_beam(a, a + main.dot(0, 1))
	main.add_beam(a + main.dot(0, 1), a + main.dot(0, 2))
	main.add_beam(a + main.dot(0, 2), a + main.dot(1, 3))
	main.add_beam(a, a + main.dot(1, 2))
	main.add_beam(a + main.dot(0, 1), a + main.dot(1, 2))
	main.add_beam(a + main.dot(1, 2), a + main.dot(1, 3))
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
	var apex := Vector2i(roundi((a.x + b.x) / 200.0) * 100, 100)
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
			main.add_beam(a, a + main.dot(1, 1))
			main.add_beam(a, a + main.dot(0, 1))
			main.add_beam(a + main.dot(0, 1), a + main.dot(1, 1))
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
	main.add_beam(a, a + main.dot(0, 1))
	main.load_day(DAY)
	assert_eq(main.design.size(), 1, "design in progress survives a reload")
	main.add_beam(a, a + main.dot(1, 1))
	main.add_beam(a + main.dot(0, 1), a + main.dot(1, 1))
	main.run_instant()
	main.finish()
	assert_eq(main.phase, main.Phase.FINAL, "finish ends the day")
	main.wipe_save()


func test_live_run_advances():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.add_beam(a, a + main.dot(1, 1))
	main.add_beam(a, a + main.dot(0, 1))
	main.add_beam(a + main.dot(0, 1), a + main.dot(1, 1))
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
	main.add_beam(a, a + main.dot(0, 1))
	main.add_beam(a, a + main.dot(1, 1))
	main.add_beam(a + main.dot(0, 1), a + main.dot(1, 1))
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


func _lens(main) -> Array:
	var out: Array = []
	for b in main.design:
		out.append(snappedf(main.wpos(b.a).distance_to(main.wpos(b.b)), 0.01))
	return out


func test_drawn_line_is_cut_into_pieces():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.set_piece_len(2)
	assert_eq(main.add_chain(a, a + main.dot(0, 7)), 4, "7 m in pieces up to 2 m = 4 equal pieces")
	assert_eq(_lens(main), [1.75, 1.75, 1.75, 1.75], "equal piece lengths")
	main.undo()
	assert_eq(main.design.size(), 0, "a whole line undoes in one step")
	main.set_piece_len(3)
	assert_eq(main.add_chain(a, a + main.dot(0, 9)), 3, "9 m in 3 m pieces")
	main.set_piece_len(1)
	assert_eq(main.add_chain(a + main.dot(0, 9), a + main.dot(2, 9)), 2, "1 m pieces across the top")
	assert_true(main.is_node(a + main.dot(1, 9)), "a joint between pieces")
	main.set_piece_len(2)
	assert_eq(main.add_chain(a + main.dot(0, 9), a + main.dot(0, 4)), 0, "drawing over an existing line adds nothing")
	var n_before: int = main.design.size()
	assert_eq(main.add_chain(a, a + main.dot(0, 11)), 1, "extending a line reuses its joints: only the 2 m on top is new")
	assert_eq(main.design.size(), n_before + 1, "no overlapping beams")


func test_diagonal_lines_and_bad_angles():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.set_piece_len(2)
	assert_eq(main.add_chain(a, a + main.dot(4, 4)), 3, "5.66 m diagonal in pieces up to 2 m = 3 pieces")
	main.undo()
	main.set_piece_len(3)
	assert_eq(main.add_chain(a, a + main.dot(4, 4)), 2, "3 m pieces on 45° = two 2.83 m beams")
	main.undo()
	assert_eq(main.add_chain(a, a + main.dot(3, 5)), 2, "any angle works: a 3:5 line")
	var mid: Vector2i = main.design[0].b
	assert_true(mid.x % 100 != 0 or mid.y % 100 != 0, "the joint between pieces sits off the grid")
	assert_true(main.is_node(mid), "and you can build from it")
	assert_eq(main.add_chain(mid, mid + main.dot(2, 0)), 1, "a line from the off-grid joint")
	main.set_erasing(false)
	assert_eq(main.add_chain(a + main.dot(0, 4), a), 2, "drawing towards an anchor works too (3 m + 1 m)")


func test_existing_pieces_are_skipped_and_budget_truncates():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.set_piece_len(1)
	main.add_chain(a, a + main.dot(0, 2))
	assert_eq(main.add_chain(a, a + main.dot(0, 4)), 2, "only the new part is built")
	assert_eq(main.design.size(), 4, "no duplicates")
	main.set_mat(1)
	assert_eq(main.add_chain(a + main.dot(0, 4), a + main.dot(0, 18)), 14, "14 steel pieces")
	var left: float = main.money_left()
	var b: Vector2i = main.anchors[1]
	var n: int = main.add_chain(b, b + main.dot(0, 18))
	assert_eq(n, floori(left / 3.0), "the line stops where the budget runs out")
	assert_true(main.money_left() >= 0.0, "never overspend")


func test_long_beams_buckle_sooner():
	var Sim = load("res://quake_sim.gd")
	var s = Sim.new()
	var q = load("res://quake.gd").new()
	q.make(DAY)
	s.setup([{"a": Vector2i(0, 0), "b": Vector2i(0, 1), "m": 0}, {"a": Vector2i(1, 0), "b": Vector2i(1, 3), "m": 0}], [Vector2i(0, 0), Vector2i(1, 0)], q)
	assert_eq(s.b_cstrength[0], s.b_strength[0], "short beams: full compression strength")
	assert_lt(s.b_cstrength[1], s.b_strength[1] * 0.5, "3 m beams buckle at under half")


func test_erase_tool_removes_single_pieces():
	var main = await _fresh()
	var a: Vector2i = main.anchors[0]
	main.set_piece_len(1)
	main.add_chain(a, a + main.dot(0, 4))
	main.set_erasing(true)
	assert_true(main.erase_at(main.wpos(a) + Vector2(0.05, 2.5)), "erase the third piece")
	assert_eq(main.design.size(), 3, "only that piece goes")
	main.erase_stroke = false
	main.undo()
	assert_eq(main.design.size(), 4, "undo brings it back")
	# a swipe erases several pieces as one undo step
	main.erase_stroke = false
	main.erase_at(main.wpos(a) + Vector2(0, 1.5))
	main.erase_at(main.wpos(a) + Vector2(0, 3.5))
	assert_eq(main.design.size(), 2, "two pieces erased in one stroke")
	main.erase_stroke = false
	main.undo()
	assert_eq(main.design.size(), 4, "one undo restores the whole stroke")
	main.set_erasing(false)


func test_zoom_keeps_point_under_pointer():
	var main = await _fresh()
	await wait_frames(2)
	var p: Vector2 = main.board_rect.get_center() + Vector2(30, 40)
	var w: Vector2 = main.screen_to_world(p)
	main.zoom_at(p, 2.0)
	assert_near(main.zoom, 2.0, 0.001, "zoomed in")
	assert_lt(main.screen_to_world(p).distance_to(w), 0.01, "world point stays under the pointer")
	main.zoom_at(p, 100.0)
	assert_near(main.zoom, main.ZOOM_MAX, 0.001, "zoom is capped")
	main._pan_by(Vector2(-100000, 0))
	var right: Vector2 = main.screen_to_world(Vector2(main.board_rect.end.x, 0))
	assert_lt(right.x, main.GW + main.VIEW_PAD + 0.01, "panning stops at the edge of the site")
	main.zoom_reset()
	assert_near(main.zoom, 1.0, 0.001, "reset")


func test_auto_lock_snaps_to_nearby_joints():
	var main = await _fresh()
	await wait_frames(2)
	assert_true(main.auto_lock, "auto-lock defaults to on")
	var a: Vector2i = main.anchors[0]
	main.add_chain(a, a + main.dot(3, 5), 3)   # 5.83 m in 2 pieces: joint at (+1.5, +2.5), off the grid
	var mid: Vector2i = main.design[0].b
	assert_eq(mid, a + Vector2i(150, 250), "off-grid joint where expected")
	var w: Vector2 = main.wpos(mid) + Vector2(0.3, 0.3)     # 0.42 m from the joint, 0.28 m from dot (+2, +3)
	var sp: Vector2 = main.world_to_screen(w)
	assert_eq(main.snap(sp), mid, "lock on: the nearby joint wins")
	main.auto_lock = false
	assert_eq(main.snap(sp), a + main.dot(2, 3), "lock off: the nearest dot wins")
	main.auto_lock = true
	assert_ne(main.snap(main.world_to_screen(main.wpos(mid)), mid), mid, "the drag's own start joint is excluded")
	# a joint more than the lock reach away doesn't grab the pointer
	var far: Vector2 = main.world_to_screen(main.wpos(a) + Vector2(-1.0, 6.0))
	assert_eq(main.snap(far), a + main.dot(-1, 6), "far from joints: plain dot")


func test_lock_toggle_is_saved():
	var main = await _fresh()
	main.set_auto_lock(false)
	main.auto_lock = true
	main._load_prefs()
	assert_false(main.auto_lock, "off persists")
	main.set_auto_lock(true)
	main._load_prefs()
	assert_true(main.auto_lock, "on persists")


func test_loupe_sits_above_the_finger():
	var main = await _fresh()
	await wait_frames(2)
	var vs: Vector2 = main.get_viewport_rect().size
	main.drag_pointer = Vector2(vs.x / 2.0, vs.y * 0.8)
	var r: Rect2 = main.loupe_rect()
	assert_lt(r.end.y, main.drag_pointer.y, "above the finger")
	assert_true(Rect2(Vector2.ZERO, vs).encloses(r), "on screen")
	main.drag_pointer = Vector2(20, 30)
	r = main.loupe_rect()
	assert_true(Rect2(Vector2.ZERO, vs).encloses(r), "on screen near the top-left corner")
	assert_false(r.has_point(main.drag_pointer), "not under the finger")
	var seg: Array = main._clip_seg(Vector2(-10, 5), Vector2(10, 5), Rect2(0, 0, 4, 10))
	assert_eq(seg, [Vector2(0, 5), Vector2(4, 5)], "segment clipped to the loupe")
	assert_eq(main._clip_seg(Vector2(-10, 50), Vector2(10, 50), Rect2(0, 0, 4, 10)), [], "outside")
