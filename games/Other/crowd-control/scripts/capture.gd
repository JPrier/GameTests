extends Node
## Screenshot checkpoints for visual review and CI baselines (needs a real display, e.g. Xvfb).
##   godot --path . -- --capture=out_dir [--capture-size=1280x720] [--capture-set=all|title|play...]
## Each checkpoint sets up a state through the same public functions the UI uses, renders a few
## frames, then saves out_dir/<name>.png. Only active when --capture is passed.

var main: Node
var out_dir := ""
var only := ""


static func requested() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			return true
	return false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--capture-size="):
			var wh := a.get_slice("=", 1).split("x")
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		elif a.begins_with("--capture-set="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if only != "" and only != "all" and not only.split(",").has(name):
		return
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captured ", name)


func _run() -> void:
	main = get_parent()
	await _frames(10)
	while main.phase == main.Phase.LOADING:
		await _frames(1)
	await _shot("title")
	main.start_scenario(true)
	await _shot("briefing")
	main.begin_play()
	main.tutorial_step = 0
	await _shot("tutorial")
	main.tutorial_step = -1
	main.paused = true
	main.step_ticks(int(70.0 / main.dt))
	await _shot("normal_ops")
	main.set_sign("sign_n", "waits")
	main.select("sign", "sign_n")
	await _shot("signage")
	main.set_tool("barrier")
	main.drag_active = true
	main.drag_from = Vector2(52, 31)
	main.drag_to = Vector2(60, 27)
	main.preview_ok = true
	await _shot("barrier_preview")
	main.drag_active = false
	main.adapter.command({"type": "barrier_add", "a": [52, 31], "b": [60, 27]})
	main.set_tool("select")
	main.select("gate", "gate_a")
	main.set_gate("gate_a", "metered", 0.5)
	main.step_ticks(int(130.0 / main.dt))
	await _shot("gate_metered")
	main.selection = {}
	main.toggle_overlay("density")
	await _shot("density_overlay")
	main.toggle_overlay("density")
	main.toggle_overlay("risk")
	main.toggle_overlay("flow")
	main.select("area", "station_north")
	await _shot("congestion_explained")
	main.toggle_overlay("risk")
	main.toggle_overlay("flow")
	main.selection = {}
	main.zoom_at(main.m_to_screen(Vector2(124, 15)), 3.2)
	await _shot("close_zoom")
	main._fit_camera()
	main.color_mode = 1
	main.toggle_overlay("routes")
	await _shot("mood_routes")
	main.color_mode = 0
	main.toggle_overlay("routes")
	var guard := 0
	while main.phase == main.Phase.PLAYING and guard < 80:
		main.step_ticks(400)
		guard += 1
	await _shot("results")
	# hands-off run until the first dangerous crowding, shown with the risk overlay
	main.start_scenario(false)
	main.paused = true
	main.tutorial_step = -1
	guard = 0
	while main.phase == main.Phase.PLAYING and float(main.telemetry.get("danger_seconds", 0.0)) < 3.0 and guard < 400:
		main.step_ticks(20)
		guard += 1
	main.toggle_overlay("risk")
	for a in main.telemetry.get("areas", []):
		if int(a.level) >= 3:
			main.select("area", a.id)
			break
	await _shot("danger")
	main.toggle_overlay("risk")
	main.selection = {}
	main.debug = true
	main.phase = main.Phase.PLAYING
	main.help_open = true
	await _shot("help")
	get_tree().quit()
