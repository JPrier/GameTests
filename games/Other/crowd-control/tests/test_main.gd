extends GameTest
## Crowd Control: game-level tests. They drive the real Rust simulation (GDExtension in headless
## runs) and check consequences in the simulation, not just that calls return.


func _game(start := true) -> Node:
	var g = await load_scene("res://main.tscn")
	for i in 30:
		if g.phase == g.Phase.TITLE:
			break
		await wait_frames(1)
	if start:
		g.start_scenario(false)
		g.paused = true
		g.tutorial_step = -1
	return g


func _run(g, seconds: float) -> void:
	var ticks := int(seconds / g.dt)
	while ticks > 0:
		var n := mini(ticks, 200)
		g.step_ticks(n)
		ticks -= n


func _gate(g, id: String) -> Dictionary:
	for x in g.telemetry.get("gates", []):
		if x.id == id:
			return x
	return {}


func test_title_screen_then_scenario_loads():
	var g = await _game(false)
	assert_eq(g.adapter.backend, "native", "headless tests use the GDExtension")
	assert_eq(g.phase, g.Phase.TITLE, "title first")
	g.start_scenario(true)
	assert_eq(g.phase, g.Phase.BRIEFING, "briefing before play")
	assert_eq(int(g.telemetry.population.total), 1000)
	g.begin_play()
	assert_eq(g.phase, g.Phase.PLAYING)


func test_people_leave_the_stadium_and_render():
	var g = await _game()
	_run(g, 30.0)
	var pop: Dictionary = g.telemetry.population
	assert_gt(int(pop.active), 50, "people are walking outside")
	assert_lt(int(pop.inside), 1000, "the stadium is emptying")
	assert_eq(g.world.count, int(pop.active), "one rendered instance per person")
	assert_eq(int(pop.inside) + int(pop.active) + int(pop.completed), int(pop.total), "population is conserved")


func test_closing_a_gate_stops_its_flow_and_reopening_restores_it():
	var g = await _game()
	_run(g, 40.0)
	g.set_gate("gate_a", "closed")
	assert_eq(_gate(g, "gate_a").mode, "closed")
	_run(g, 70.0)
	assert_eq(int(_gate(g, "gate_a").flow_pm), 0, "nobody passes a closed gate")
	assert_gt(int(_gate(g, "gate_b").flow_pm), 30, "people reroute through the South Gate")
	g.set_gate("gate_a", "open")
	_run(g, 60.0)
	assert_gt(int(_gate(g, "gate_a").flow_pm), 0, "flow resumes when reopened")


func test_metering_limits_gate_throughput():
	var g = await _game()
	g.set_gate("gate_a", "metered", 0.25)
	_run(g, 150.0)
	var cap := 5 * 1.0 * 0.25 * 60.0
	assert_lt(float(_gate(g, "gate_a").flow_pm), cap + 2.0, "metered gate never exceeds its service rate")
	assert_gt(int(_gate(g, "gate_a").queue), 0, "a queue forms upstream of the metered gate")


func test_barrier_is_validated_and_changes_geometry():
	var g = await _game()
	var bad = g.adapter.check_barrier(Vector2(10, 10), Vector2(15, 10))
	assert_false(bad.ok, "barriers outside the zones are rejected")
	var ok = g.adapter.check_barrier(Vector2(50, 30), Vector2(58, 30))
	assert_true(ok.ok, "a barrier in the plaza zone is allowed: %s" % str(ok))
	var r = g.adapter.command({"type": "barrier_add", "a": [50, 30], "b": [58, 30]})
	assert_true(r.ok)
	g.step_ticks(1)
	assert_eq(g.telemetry.barriers.size(), 1)
	assert_gt(float(g.telemetry.spent), 0.0, "barriers cost money")
	g.remove_barrier(int(r.id))
	assert_eq(g.telemetry.barriers.size(), 0)
	assert_near(float(g.telemetry.spent), 0.0, 0.01, "undo within the window refunds")


func test_sign_changes_are_read_by_people():
	var g = await _game()
	g.set_sign("sign_n", "trains_south")
	_run(g, 90.0)
	var reads := 0
	for s in g.telemetry.signs:
		if s.id == "sign_n":
			reads = int(s.reads)
			assert_eq(s.mode, "trains_south")
	assert_gt(reads, 10, "people read the sign")


func test_explanation_for_a_congested_area_names_a_cause():
	var g = await _game()
	g.set_gate("gate_a", "metered", 0.25)
	_run(g, 150.0)
	g.select("area", "plaza")
	var e: Dictionary = g.explain
	assert_eq(e.name, "Central Plaza")
	assert_true(e.has("arrivals_pm") and e.has("departures_pm"), "rates present")
	assert_true(str(e.get("limiting", "")).contains("North Gate"), "the metered gate is named as the limit: %s" % str(e.get("limiting")))


func test_full_run_ends_with_a_scored_report():
	var g = await _game()
	g.begin_play()
	g.tutorial_step = -1
	var guard := 0
	while g.phase == g.Phase.PLAYING and guard < 60:
		g.step_ticks(400)
		guard += 1
	assert_eq(g.phase, g.Phase.ENDED, "the scenario ends")
	assert_true(g.report.has("score"), "report produced")
	assert_true(g.report.components.size() >= 6, "score is broken down")
	assert_true(FileAccess.file_exists("user://last_replay.json"), "replay saved")


func test_same_seed_gives_same_checksum():
	var g = await _game()
	_run(g, 30.0)
	var a: String = g.adapter.checksum()
	g.start_scenario(false)
	g.paused = true
	_run(g, 30.0)
	assert_eq(g.adapter.checksum(), a, "reset with the same seed reproduces the state exactly")


func test_overlays_do_not_change_the_simulation():
	var g = await _game()
	_run(g, 20.0)
	var a: String = g.adapter.checksum()
	g.start_scenario(false)
	g.paused = true
	for k in ["density", "risk", "flow", "routes"]:
		g.toggle_overlay(k)
	g.color_mode = 1
	_run(g, 20.0)
	assert_eq(g.adapter.checksum(), a, "overlays are read-only")


func test_ui_tools_and_pause():
	var g = await _game()
	g.begin_play()
	g.tutorial_step = -1
	g.paused = false
	g.set_tool("barrier")
	assert_eq(g.tool, "barrier")
	g.ui._activate("tool:0")
	assert_eq(g.tool, "select")
	g.ui._activate("pause")
	assert_true(g.paused, "pause button pauses")
	g.ui._activate("speed:3")
	assert_eq(g.SPEEDS[g.speed_idx], 8)
	g.ui._activate("ov:density")
	assert_true(g.overlays.density)


func test_camera_zoom_is_clamped():
	var g = await _game()
	var z0: float = g.camera.zoom.x
	for i in 40:
		g.zoom_at(Vector2(400, 300), 1.3)
	assert_lt(g.camera.zoom.x, 5.01, "max zoom")
	for i in 80:
		g.zoom_at(Vector2(400, 300), 0.7)
	assert_gt(g.camera.zoom.x, z0 * 0.8, "min zoom keeps the map in view")
