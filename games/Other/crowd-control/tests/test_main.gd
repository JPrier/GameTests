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
	assert_eq(int(g.telemetry.population.total), int(g.sc.spawn_schedules[0].population), "everyone from the scenario")
	g.begin_play()
	assert_eq(g.phase, g.Phase.PLAYING)


func test_people_leave_the_stadium_and_render():
	var g = await _game()
	_run(g, 30.0)
	var pop: Dictionary = g.telemetry.population
	assert_gt(int(pop.active), 50, "people are walking outside")
	assert_lt(int(pop.inside), int(pop.total), "the stadium is emptying")
	# people in camera-delayed station halls are drawn from the last snapshot, so compare with
	# perfect information on: then there is exactly one instance per person on site
	g.set_perfect_info(true)
	g.step_ticks(1)
	assert_eq(g.world.count, int(g.telemetry.population.active), "one rendered instance per person")
	assert_eq(int(pop.inside) + int(pop.active) + int(pop.completed), int(pop.total), "population is conserved")


func test_closing_a_gate_stops_its_flow_and_reopening_restores_it():
	var g = await _game()
	_run(g, 90.0)
	g.set_gate("gate_a", "closed")
	assert_eq(_gate(g, "gate_a").mode, "closed")
	_run(g, 90.0)
	assert_eq(int(_gate(g, "gate_a").flow_pm), 0, "nobody passes a closed gate")
	assert_gt(int(_gate(g, "gate_b").flow_pm), 30, "people reroute through the South Gate")
	g.set_gate("gate_a", "open")
	_run(g, 120.0)
	assert_gt(int(_gate(g, "gate_a").flow_pm), 0, "flow resumes when reopened")


func test_metering_limits_gate_throughput():
	var g = await _game()
	g.set_gate("gate_a", "metered", 0.25)
	_run(g, 150.0)
	var cap := 5 * 1.0 * 0.25 * 60.0
	assert_lt(float(_gate(g, "gate_a").flow_pm), cap + 2.0, "metered gate never exceeds its service rate")
	assert_gt(int(_gate(g, "gate_a").queue), 0, "a queue forms upstream of the metered gate")


func test_tools_are_validated_and_placed():
	var g = await _game()
	var bad = g.adapter.check_command({"type": "fence_add", "points": [[10, 10], [15, 10]]})
	assert_false(bad.ok, "fences off open ground are rejected")
	var ok = g.adapter.check_command({"type": "fence_add", "points": [[150, 90], [174, 90], [174, 100]]})
	assert_true(ok.ok, "a bent fence in the plaza is allowed: %s" % str(ok))
	assert_gt(float(ok.cost), 0.0, "the preview quotes a cost")
	var r = g.adapter.command({"type": "fence_add", "points": [[150, 90], [174, 90], [174, 100]]})
	assert_true(r.ok)
	g.step_ticks(1)
	assert_eq(g.telemetry.barriers.size(), 1)
	assert_gt(float(g.telemetry.spent), 0.0, "fences cost money")
	g.remove_barrier(int(r.id))
	assert_eq(g.telemetry.barriers.size(), 0)
	assert_near(float(g.telemetry.spent), 0.0, 0.01, "undo within the window refunds")
	# stewards hold and release; arrows mark lanes
	var s = g.adapter.command({"type": "stewards_add", "a": [262, 40], "b": [262, 59]})
	assert_true(s.ok, str(s))
	g.set_stewards(int(s.id), false)
	var st: Dictionary = {}
	for b in g.telemetry.barriers:
		if int(b.id) == int(s.id):
			st = b
	assert_eq(st.get("kind", ""), "stewards")
	assert_false(bool(st.get("hold", true)), "released")
	var a = g.adapter.command({"type": "arrow_add", "points": [[135, 175], [228, 205]], "one_way": true})
	assert_true(a.ok, str(a))


func test_drawing_a_fence_with_the_pointer():
	var g = await _game()
	g.begin_play()
	g.tutorial_step = -1
	g.paused = true
	g.set_tool("fence")
	# an L-shaped stroke: the corner survives simplification
	g._pointer(g.m_to_screen(Vector2(150, 96)), true)
	for k in 23:
		g._pointer_move(g.m_to_screen(Vector2(151 + k, 96)), Vector2.ZERO)
	for k in 10:
		g._pointer_move(g.m_to_screen(Vector2(173, 95 - k)), Vector2.ZERO)
	g._preview_t = -10.0
	g._pointer(g.m_to_screen(Vector2(173, 86)), false)
	assert_eq(g.telemetry.barriers.size(), 1, "the drawn fence was placed: %s" % g.preview_error)
	var pts: Array = g.telemetry.barriers[0].points
	assert_eq(pts.size(), 3, "a straight run and a corner: %s" % str(pts))
	assert_eq(g.tool, "fence", "the tool stays on for the next stroke")


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
	g.set_tool("fence")
	assert_eq(g.tool, "fence")
	g.ui._activate("tool:0")
	assert_eq(g.tool, "select")
	g.ui._activate("tool:2")
	assert_eq(g.tool, "stewards")
	g.ui._cancel()
	assert_eq(g.tool, "select", "Escape leaves a drawing tool")
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


func _play(g, interventions: bool) -> Dictionary:
	g.start_scenario(false)
	g.paused = true
	g.tutorial_step = -1
	var started := false
	var held := false
	var released := false
	var guard := 0
	while g.phase == g.Phase.PLAYING and guard < 5000:
		if interventions and not started:
			g.set_sign("sign_n", "waits")
			g.set_sign("sign_s", "waits")
			started = true
		g.step_ticks(20)
		guard += 1
		if not interventions:
			continue
		var delayed: bool = not g.telemetry.get("incidents", []).is_empty()
		if delayed and not held:
			# trains stopped: close the station entrances so the halls do not overfill, and hold
			# the plaza gates at half rate so the walkways do not either
			g.set_gate("station_n", "closed")
			g.set_gate("station_r", "closed")
			g.set_gate("gate_a", "metered", 0.5)
			g.set_gate("gate_b", "metered", 0.5)
			held = true
		elif held and not delayed and not released:
			for id in ["station_n", "station_r", "gate_a", "gate_b"]:
				g.set_gate(id, "open")
			released = true
	return g.report


## End-to-end: the same scenario played with gate and sign interventions through an
## incident, compared with doing nothing. The interventions must change the outcome for the better.
func test_playthrough_interventions_beat_doing_nothing():
	var g = await _game(false)
	var idle := _play(g, false)
	var played := _play(g, true)
	var cost := float(played.cost)
	assert_gt(cost, 0.0, "interventions were paid for")
	assert_lt(float(played.danger_seconds), float(idle.danger_seconds), "less dangerous crowding")
	assert_gt(int(played.score), int(idle.score) + 150, "much better score (%d vs %d)" % [int(played.score), int(idle.score)])
	assert_ne(str(idle.outcome), "won", "doing nothing does not pass (%d points)" % int(idle.score))
	assert_eq(str(played.outcome), "won", "holding the crowd passes (%d points)" % int(played.score))
	assert_true(g.log_entries.any(func(e): return e.kind == "incident"), "the train delay happened")
	assert_eq(g.phase, g.Phase.ENDED, "results screen reached")
