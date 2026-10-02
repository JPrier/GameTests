extends GameTest

const DAY := "2026-10-02"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.dev_sandbox = false
	main.date = d
	main.wipe_save()
	main.target_score = -1
	main.load_puzzle(d)
	main.tut_open = false
	return main


func _dot(x: int, y: int) -> Vector2i:
	return Vector2i(x * 100, y * 100)


func test_same_date_same_level():
	var a := BridgeSim.make_level(DAY)
	assert_eq(BridgeSim.make_level(DAY), a, "level is deterministic")
	var differs := false
	for i in range(1, 6):
		if BridgeSim.make_level(Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(DAY + "T00:00:00") + i * 86400)) != a:
			differs = true
	assert_true(differs, "other days give other levels")
	var main = await _fresh()
	assert_eq(main.day_number(DAY), 1, "puzzle #1 is the epoch")
	assert_eq(main.day_number("2026-10-12"), 11, "puzzle numbering")


## Upcoming days vary (gap, bank heights, anchors, ledges/pillars) and every one is solvable.
func test_days_vary_and_are_solvable():
	var gaps := {}
	var dys := {}
	var rocks := 0
	var vehicles := {}
	for i in 40:
		var d: String = Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(DAY + "T00:00:00") + i * 86400)
		var lv := BridgeSim.make_level(d)
		gaps[lv.gap] = true
		dys[lv.dy] = true
		vehicles[lv.vehicle] = true
		if not lv.rocks.is_empty():
			rocks += 1
		assert_true(int(lv.gap) <= int(BridgeSim.MAX_GAP[lv.vehicle]), d + ": gap fits the vehicle")
		var idx: int = load("res://main.gd").ideal_index_for(d)
		assert_true(idx >= 0, d + ": the precomputed table has an ideal")
		var ideal: Array = BridgeSim.candidates(lv)[idx]
		var sim := BridgeSim.new()
		sim.setup(lv, ideal)
		var r := sim.run_to_end()
		assert_true(r.crossed and r.snapped == 0, d + ": the ideal crosses cleanly")
		for a: Vector2i in lv.anchors:
			assert_false(BridgeSim.in_rock(lv, BridgeSim.wpos(a), true), d + ": anchors sit on the rock surface")
	assert_gt(gaps.size(), 4, "gap widths vary")
	assert_gt(dys.size(), 3, "bank heights vary")
	assert_gt(rocks, 4, "some days have a ledge or pillar")
	assert_eq(vehicles.size(), 3, "all vehicles appear")


## The shipped table must match a fresh search (catches physics changes without a re-run of the tool).
func test_ideal_table_matches_search():
	for d in ["2026-10-02", "2026-10-03", "2026-12-25", "2027-06-09"]:
		var s := BridgeSim.IdealSearch.new(BridgeSim.make_level(d))
		s.run()
		assert_eq(s.index(), load("res://main.gd").ideal_index_for(d), d + ": table matches the search")


func test_days_past_the_table_are_searched_in_game():
	var main = await _fresh()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://bridge_ideal_%s_2031-01-01.json" % main.IDEAL_VERSION))
	main.dev_set_day("2031-01-01")
	assert_eq(main.ideal, -1, "not in the table: searching")
	main.ensure_ideal()
	assert_gt(main.ideal, 0, "found in-game")
	main.dev_sandbox = false


func test_ideal_scores_100_and_is_cheapest():
	var main = await _fresh()
	main.ensure_ideal()
	assert_gt(main.ideal, 0, "ideal found")
	assert_true(main.simulate(main.ideal_design).crossed, "the ideal bridge crosses")
	assert_eq(BridgeSim.design_cost(main.ideal_design), main.ideal, "ideal is the bridge's material")
	for c in BridgeSim.candidates(main.level()):
		if BridgeSim.design_cost(c) < main.ideal:
			var r: Dictionary = main.simulate(c)
			assert_false(r.crossed and r.snapped == 0, "every cheaper candidate snaps or falls")
	assert_eq(main.score_for(main.ideal), 100, "ideal scores 100")
	main.load_puzzle(DAY)
	assert_eq(main.ideal_search, null, "today's ideal comes straight from the table")


func test_score_curve():
	var main = await _fresh()
	main.ensure_ideal()
	var ideal: int = main.ideal
	assert_eq(main.score_for(ideal * 2), 50, "twice the material scores 50")
	assert_lt(main.score_for(ideal * 10), 11, "heading toward 0")
	assert_gt(main.score_for(ideal - 40), 100, "beating the ideal scores over 100")


func test_build_rules():
	var main = await _fresh()
	assert_false(main.add_beam(_dot(0, 0), _dot(5, 0), BridgeSim.Mat.ROAD), "5 m is too long for one piece")
	assert_false(main.add_beam(_dot(0, 0), _dot(-1, 1), BridgeSim.Mat.WOOD), "can't build into rock")
	assert_true(main.add_beam(_dot(0, 0), _dot(2, 0), BridgeSim.Mat.ROAD), "a road panel")
	assert_eq(main.cost(), 30, "road costs 15 per metre")
	assert_false(main.add_beam(_dot(2, 0), _dot(0, 0), BridgeSim.Mat.WOOD), "no duplicate beams")
	main.undo()
	assert_eq(main.design.size(), 0, "undo")


func test_any_angle_lines():
	var main = await _fresh()
	main.set_piece_len(2)
	var plan: Dictionary = main.plan_line(_dot(0, 0), _dot(7, -3))
	assert_eq(plan.why, "", "any dot is reachable at any angle")
	assert_eq(plan.pieces.size(), 4, "7.6 m in 2 m pieces = 4 equal pieces")
	var l0 := BridgeSim.wpos(plan.pieces[0][0]).distance_to(BridgeSim.wpos(plan.pieces[0][1]))
	var l3 := BridgeSim.wpos(plan.pieces[3][0]).distance_to(BridgeSim.wpos(plan.pieces[3][1]))
	assert_near(l0, l3, 0.02, "pieces are equal")
	assert_lt(l0, 2.0 + 0.001, "no longer than the chosen length")
	assert_true(main.add_path(_dot(0, 0), _dot(7, -3), BridgeSim.Mat.WOOD), "built in one drag")
	assert_eq(main.design.size(), 4, "four beams")
	var mid: Vector2i = plan.pieces[1][1]
	assert_true(mid.x % 100 != 0 or mid.y % 100 != 0, "joints can sit between grid dots")
	main.undo()
	assert_eq(main.design.size(), 0, "one drag is one undo step")
	# a line passing over an existing joint connects through it
	main.set_piece_len(4)
	main.add_path(_dot(0, 0), _dot(2, -2), BridgeSim.Mat.WOOD)
	main.add_path(_dot(0, 0), _dot(4, -4), BridgeSim.Mat.WOOD)
	assert_eq(main.design.size(), 2, "the second line reuses the first and adds the rest")
	assert_false(main.add_path(_dot(0, 0), _dot(4, -4), BridgeSim.Mat.WOOD), "drawing over beams adds nothing")


func test_pointer_drag_tap_and_swipe_erase():
	var main = await _fresh()
	await wait_frames(2)
	var a: Vector2 = main.gpos(_dot(0, 0))
	var b: Vector2 = main.gpos(_dot(2, 0))
	var c: Vector2 = main.gpos(_dot(1, -2))
	main.set_piece_len(4)
	main._on_press(a)
	main.dragging = true
	main.drag_pos = b
	main._on_release(b + Vector2(3, -2))
	assert_eq(main.design.size(), 1, "drag builds a line")
	assert_eq(main.design[0].m, BridgeSim.Mat.ROAD, "with the current tool")
	main.set_tool(main.Tool.WOOD)
	main._on_press(c)
	main._on_release(c)
	assert_eq(main.design.size(), 2, "tap on empty space builds from the selected joint")
	main._on_press(a)
	main._on_release(a)
	assert_eq(main.design.size(), 3, "tapping a joint closes the triangle")
	main.set_tool(main.Tool.ERASE)
	main._on_press((a + b) * 0.5)
	main._on_release((a + b) * 0.5)
	assert_eq(main.design.size(), 2, "erase what you tap")
	main.undo()
	assert_eq(main.design.size(), 3, "undo the erase")


func test_zoom_and_pan():
	var main = await _fresh()
	await wait_frames(2)
	var p: Vector2 = main.view_rect.get_center() + Vector2(40, 10)
	var w: Vector2 = main.s2w(p)
	main.zoom_at(p, 2.0)
	assert_near(main.zoom, 2.0, 0.001, "zoomed in")
	assert_lt(main.s2w(p).distance_to(w), 0.01, "the point under the pointer stays put")
	var before: Vector2 = main.cam_center
	main._pan_by(Vector2(-60, 0))
	assert_gt(main.cam_center.x, before.x, "dragging left pans right")
	main.zoom_at(p, 100.0)
	assert_near(main.zoom, main.ZOOM_MAX, 0.001, "zoom is capped")
	main.zoom_reset()
	assert_near(main.zoom, 1.0, 0.001, "reset")


func test_attempt_flow_ideal_view_and_share():
	var main = await _fresh()
	main.ensure_ideal()
	# attempt 1: an unbraced deck
	main.set_piece_len(2)
	main.add_path(_dot(0, 0), Vector2i(main.gap * 100, main.dy * 100), BridgeSim.Mat.ROAD)
	main.go()
	assert_eq(main.phase, main.Phase.RUN, "running")
	await wait_frames(3)
	main.skip()
	assert_false(main.tries[0].crossed, "an unbraced deck falls")
	assert_eq(main.try_score(main.tries[0]), 0, "a fall scores 0")
	main.repair()
	assert_eq(main.phase, main.Phase.BUILD, "repairing keeps the bridge")
	# attempt 2: the ideal bridge
	main.set_design(main.ideal_design)
	main.go()
	main.skip()
	assert_true(main.tries[1].crossed, "the ideal bridge crosses")
	assert_eq(main.best_score(), 100, "and scores 100")
	main.finish()
	assert_eq(main.phase, main.Phase.FINAL, "finished")
	main.toggle_ideal()
	assert_true(main.show_ideal, "ideal view on")
	assert_eq(main.shown_design(), main.ideal_design, "the ideal bridge is shown")
	main.replay()
	assert_eq(main.phase, main.Phase.RUN, "the ideal bridge can be watched")
	main.skip()
	assert_eq(main.phase, main.Phase.FINAL, "back to the end screen")
	main.toggle_ideal()
	assert_false(main.show_ideal, "back to your bridge")
	var text: String = main.share_text()
	assert_true(text.contains("Daily Bridge #1"), "share names the puzzle")
	assert_true(text.contains("💥 ✅"), "share shows the attempts")
	assert_true(text.contains("?day=" + DAY), "share link carries the day")
	assert_false(text.contains("dev=1"), "no dev flag in share links")
	main.load_puzzle(DAY)
	assert_eq(main.tries.size(), 2, "tries saved")
	assert_eq(main.phase, main.Phase.FINAL, "reopens on the result")
	main.wipe_save()


func test_three_attempts_max():
	var main = await _fresh()
	main.add_beam(_dot(0, 0), _dot(2, 0), BridgeSim.Mat.ROAD)
	for i in 3:
		main.go()
		main.skip()
		if i < 2:
			main.repair()
	assert_eq(main.tries_left(), 0, "out of attempts")
	assert_true(main.finished, "day is over")
	main.repair()
	assert_eq(main.phase, main.Phase.RESULT, "no repair without attempts")
	main.replay()
	main.skip()
	assert_eq(main.tries.size(), 3, "replay doesn't use an attempt")
	main.wipe_save()


func test_dev_controls_dont_touch_saves():
	var main = await _fresh()
	main.dev_set_day("2027-03-15")
	assert_eq(main.date, "2027-03-15", "jump to any day, even a future one")
	assert_true(main.dev_sandbox, "dev days aren't saved")
	main.dev_win()
	assert_eq(main.phase, main.Phase.FINAL, "instant win reaches the end screen")
	assert_eq(main.best_score(), 100, "at the ideal")
	assert_false(FileAccess.file_exists(main._save_path()), "nothing written")
	main.dev_lose()
	assert_eq(main.best_score(), 0, "instant lose scores 0")
	main.dev_set_day(main.shift_date("2027-03-15", 1))
	assert_eq(main.date, "2027-03-16", "next day")
	main.dev_sandbox = false
