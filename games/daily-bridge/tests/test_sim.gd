extends GameTest


func _level(g := 10, v := 0) -> Dictionary:
	return {"gap": g, "dy": 0, "vehicle": v, "rocks": [], "anchors": [Vector2i(0, 0), Vector2i(g * 100, 0)]}


func test_stuck_vehicle_ends_early():
	# a road post standing up at the left edge blocks the vehicle
	var lv := _level()
	lv.anchors.append(Vector2i(0, -200))
	var s := BridgeSim.new()
	s.setup(lv, [BridgeSim.beam(Vector2i(0, 0), Vector2i(0, -200), BridgeSim.Mat.ROAD)])
	var r := s.run_to_end()
	assert_eq(r.outcome, "stuck", "blocked vehicle is stuck")
	assert_lt(r.time, 8.0, "and the run ends quickly")


func test_heavier_vehicle_loads_more():
	var light := BridgeSim.new()
	light.setup(_level(10, 0), BridgeSim.double_design(_level(), 2.0, 2.0))
	var heavy := BridgeSim.new()
	heavy.setup(_level(10, 2), BridgeSim.double_design(_level(), 2.0, 2.0))
	assert_gt(heavy.run_to_end().peak, light.run_to_end().peak, "a truck strains the bridge more than a hatchback")


func test_long_pieces_buckle():
	var s := BridgeSim.new()
	s.setup(_level(), [BridgeSim.beam(Vector2i(0, 0), Vector2i(200, -100), 1), BridgeSim.beam(Vector2i(0, 0), Vector2i(400, 0), 1)])
	assert_eq(s.str_t[0], s.str_t[1], "tension strength doesn't depend on length")
	assert_eq(s.str_c[0], s.str_t[0], "short pieces are as strong squeezed as stretched")
	assert_lt(s.str_c[1], s.str_c[0] * 0.5, "a 4 m piece buckles at under half the load")


func test_uneven_banks():
	var lv := _level(9, 1)
	lv.dy = -2
	lv.anchors = [Vector2i(0, 0), Vector2i(900, -200)]
	var s := BridgeSim.new()
	s.setup(lv, BridgeSim.double_design(lv, 2.0, 2.0))
	assert_true(s.run_to_end().crossed, "a van drives uphill across a sturdy bridge")
	assert_true(BridgeSim.in_rock(lv, Vector2(10, -1)), "the right bank is 2 m higher")
	assert_false(BridgeSim.in_rock(lv, Vector2(10, -3)), "and open sky above it")
