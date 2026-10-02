extends GameTest

const DAY := "2026-10-02"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.date = d
	main.wipe_save()
	main.target_score = -1
	main.load_puzzle(d)
	main.tut_open = false
	return main


func _cheapest_crossing(main) -> Array:
	var best: Array = []
	for c in BridgeSim.candidates(main.level()):
		if main.simulate(c).crossed and (best.is_empty() or BridgeSim.design_cost(c) < BridgeSim.design_cost(best)):
			best = c
	return best


func test_same_date_same_level():
	var main = await _fresh()
	var a: Dictionary = main.level()
	var ideal_a: int = main.ideal
	main.generate(DAY)
	assert_eq(main.level(), a, "level is deterministic")
	assert_eq(main.ideal, ideal_a, "ideal is deterministic")
	assert_eq(main.day_number(DAY), 1, "puzzle #1 is the epoch")
	assert_eq(main.day_number("2026-10-12"), 11, "puzzle numbering")
	var seen := {}
	for i in 60:
		var d := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(DAY + "T00:00:00") + i * 86400)
		main.generate(d)
		var key := "%d-%d-%d" % [main.pillar_h, main.gap, main.vehicle_i]
		assert_true(main.BEST_KNOWN.has(key), "every generated level has a known budget: " + key)
		assert_eq(main.ideal, int(main.BEST_KNOWN[key]), "ideal is the best known bridge")
		seen[key] = true
	assert_gt(seen.size(), 6, "levels vary from day to day")


## The budget table must match the physics: the listed cost crosses, nothing cheaper in the family does.
func test_budget_table_is_honest():
	var main = await _fresh()
	for key: String in main.BEST_KNOWN:
		var parts := key.split("-")
		main.pillar_h = int(parts[0])
		main.gap = int(parts[1])
		main.vehicle_i = int(parts[2])
		main.anchors = [Vector2i(0, 0), Vector2i(main.gap, 0)]
		if main.pillar_h > 0:
			main.anchors.append(Vector2i(main.gap / 2, main.pillar_h))
		var best := _cheapest_crossing(main)
		assert_false(best.is_empty(), key + ": some reference bridge crosses")
		assert_eq(BridgeSim.design_cost(best), int(main.BEST_KNOWN[key]), key + ": table matches the cheapest crossing")


func test_physics_is_deterministic():
	var main = await _fresh()
	var d := BridgeSim.reference_design(main.level(), 1)
	var a: Dictionary = main.simulate(d)
	var b: Dictionary = main.simulate(d)
	assert_eq(a, b, "same bridge, same run")


func test_flat_deck_falls():
	var main = await _fresh()
	var d: Array = []
	for x in range(0, main.gap, 2):
		d.append(BridgeSim.beam(Vector2i(x, 0), Vector2i(x + 2, 0), BridgeSim.Mat.ROAD))
	var r: Dictionary = main.simulate(d)
	assert_false(r.crossed, "an unbraced deck can't carry the vehicle")
	assert_gt(r.snapped, 0, "beams snap")
	assert_eq(r.outcome, "splash")
	var nothing: Dictionary = main.simulate([])
	assert_eq(nothing.outcome, "splash", "no bridge, straight into the water")


func test_build_rules():
	var main = await _fresh()
	assert_false(main.add_beam(Vector2i(0, 0), Vector2i(3, 0), BridgeSim.Mat.ROAD), "3 m is too long")
	assert_false(main.add_beam(Vector2i(0, 0), Vector2i(-1, 1), BridgeSim.Mat.WOOD), "can't build into rock")
	assert_false(main.add_beam(Vector2i(0, 0), Vector2i(0, 0), BridgeSim.Mat.WOOD), "zero-length beam")
	assert_true(main.add_beam(Vector2i(0, 0), Vector2i(2, 0), BridgeSim.Mat.ROAD), "a road panel")
	assert_eq(main.cost(), 30, "road costs 15 per metre")
	assert_false(main.add_beam(Vector2i(2, 0), Vector2i(0, 0), BridgeSim.Mat.WOOD), "no duplicate beams")
	assert_true(main.add_beam(Vector2i(0, 0), Vector2i(1, -2), BridgeSim.Mat.WOOD), "a knight's-move brace fits")
	assert_eq(main.cost(), 30 + 22, "wood costs 10 per metre")
	assert_true(main.is_joint(Vector2i(1, -2)), "new joint created")
	main.undo()
	assert_eq(main.design.size(), 1, "undo removes the last beam")
	assert_false(main.is_joint(Vector2i(1, -2)), "orphan joint disappears")
	main.remove_beam(0)
	assert_eq(main.design.size(), 0, "erase")
	main.undo()
	assert_eq(main.design.size(), 1, "undo restores an erased beam")


func test_pointer_drag_and_tap():
	var main = await _fresh()
	await wait_frames(2)
	var a: Vector2 = main.w2s(Vector2(0, 0))
	var b: Vector2 = main.w2s(Vector2(2, 0))
	var c: Vector2 = main.w2s(Vector2(1, -2))
	# drag from the anchor to an empty grid point
	main._on_press(a)
	main.drag_pos = b
	main._on_release(b + Vector2(3, -2))
	assert_eq(main.design.size(), 1, "drag builds a beam")
	assert_eq(main.design[0].m, BridgeSim.Mat.ROAD, "with the current tool")
	# tap-tap: the new end is selected, tapping a point builds from it
	main.set_tool(BridgeSim.Mat.WOOD)
	main._on_press(c)
	main._on_release(c)
	assert_eq(main.design.size(), 2, "tap after a beam chains from its end")
	main._on_press(a)
	main._on_release(a)
	assert_eq(main.design.size(), 3, "tapping a joint closes the triangle")
	# erase tool removes the tapped beam
	main.set_tool(main.Tool.ERASE)
	main._on_press((a + b) * 0.5)
	main._on_release((a + b) * 0.5)
	assert_eq(main.design.size(), 2, "erase by tapping a beam")


func test_score_curve():
	var main = await _fresh()
	var ideal: int = main.ideal
	assert_eq(main.score_for(ideal), 100, "ideal scores 100")
	assert_eq(main.score_for(ideal * 2), 50, "twice the material scores 50")
	assert_lt(main.score_for(ideal * 10), 11, "heading toward 0")
	assert_gt(main.score_for(ideal - 40), 100, "beating the ideal scores over 100")
	assert_gt(main.score_for(ideal + 10), main.score_for(ideal + 80), "less material always scores more")


func test_no_hard_material_cap():
	var main = await _fresh()
	var x := 0
	var y := 0
	while main.cost() <= main.ideal * 2:
		main.add_beam(Vector2i(x, y), Vector2i(x + 2, y), BridgeSim.Mat.ROAD)
		x += 2
		if x >= main.gap:
			x = 0
			y -= 1
	assert_true(main.can_go(), "a heavy bridge can still be tried")
	main.go()
	assert_eq(main.phase, main.Phase.RUN, "running")
	main.skip()
	main.wipe_save()


func test_attempt_flow_and_share():
	var main = await _fresh()
	# attempt 1: a deck with no bracing
	for x in range(0, main.gap, 2):
		main.add_beam(Vector2i(x, 0), Vector2i(x + 2, 0), BridgeSim.Mat.ROAD)
	main.go()
	assert_eq(main.phase, main.Phase.RUN, "running")
	await wait_frames(5)
	main.skip()
	assert_eq(main.phase, main.Phase.RESULT, "result")
	assert_false(main.tries[0].crossed, "it fell")
	assert_false(main.last_loads.is_empty(), "snapped beams are remembered for the repair")
	main.repair()
	assert_eq(main.phase, main.Phase.BUILD, "repairing")
	assert_eq(main.design.size(), main.gap / 2, "the bridge is kept for repair")
	# attempt 2: the cheapest reference bridge
	var best := _cheapest_crossing(main)
	main.set_design(best)
	main.go()
	main.skip()
	assert_true(main.tries[1].crossed, "reference bridge crosses")
	assert_eq(main.tries[0].score, 0, "a fall scores 0")
	assert_eq(main.best_score(), 100, "the ideal bridge scores 100")
	main.finish()
	assert_eq(main.phase, main.Phase.FINAL, "finished for the day")
	var text: String = main.share_text()
	assert_true(text.contains("Daily Bridge #1"), "share text names the puzzle")
	assert_true(text.contains("💥 ✅"), "share text shows the attempts")
	assert_true(text.contains("Score 100"), "share text shows the score")
	assert_true(main.share_link().contains("d=%s&s=%d" % [DAY, main.best_score()]), "share link carries date + score")
	# progress survives a reload
	main.load_puzzle(DAY)
	assert_eq(main.tries.size(), 2, "tries saved")
	assert_true(main.finished, "finished saved")
	assert_eq(main.phase, main.Phase.FINAL, "reopens on the result")
	main.wipe_save()


func test_three_attempts_max():
	var main = await _fresh()
	main.add_beam(Vector2i(0, 0), Vector2i(2, 0), BridgeSim.Mat.ROAD)
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
	assert_eq(main.phase, main.Phase.RUN, "replay still works")
	main.skip()
	assert_eq(main.tries.size(), 3, "replay doesn't use an attempt")
	main.wipe_save()

