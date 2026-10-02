extends GameTest


func _level(g := 10, v := 0) -> Dictionary:
	return {"gap": g, "vehicle": v, "pillar_h": 0, "anchors": [Vector2i(0, 0), Vector2i(g, 0)]}


func test_stuck_vehicle_ends_early():
	# a wall of road beams standing up from the left edge blocks the vehicle
	var d: Array = [BridgeSim.beam(Vector2i(0, 0), Vector2i(0, -2), BridgeSim.Mat.ROAD)]
	var s := BridgeSim.new()
	s.setup({"gap": 10, "vehicle": 0, "pillar_h": 0, "anchors": [Vector2i(0, 0), Vector2i(0, -2), Vector2i(10, 0)]}, d)
	var r := s.run_to_end()
	assert_eq(r.outcome, "stuck", "blocked vehicle is stuck")
	assert_lt(r.time, 8.0, "and the run ends quickly")


func test_heavier_vehicle_loads_more():
	var light := BridgeSim.new()
	light.setup(_level(10, 0), BridgeSim.reference_design(_level(), 2))
	var heavy := BridgeSim.new()
	heavy.setup(_level(10, 2), BridgeSim.reference_design(_level(), 2))
	assert_gt(heavy.run_to_end().peak, light.run_to_end().peak, "a truck strains the bridge more than a hatchback")
