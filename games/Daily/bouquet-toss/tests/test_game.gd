extends GameTest
## The game scene: real drag input, keyboard aim, throws, winning, sharing, saving, dev mode.

const Save = preload("res://core/save.gd")
const P = preload("res://core/physics.gd")
const U = preload("res://core/units.gd")

const DAY := "2026-10-19"      # a Monday


func _fresh(d := DAY, reset := true) -> Node:
	var main = await load_scene("res://main.tscn")
	for i in 30:
		if main.phase != "loading":
			break
		await wait_frames(1)
	main.dev_set_day(d)
	if reset:
		main.dev_reset()
	main.modal = ""
	await wait_frames(1)
	return main


func _mouse(main: Node, type: String, p: Vector2) -> void:
	var ev
	if type == "move":
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = type == "down"
	ev.position = p
	ev.global_position = p
	main._input(ev)
	await wait_frames(1)


## Drags from the middle of the stage so that letting go throws at (a, p).
func _drag_throw(main: Node, a: int, p: int) -> void:
	var start: Vector2 = main.to_screen(Vector2(400, 420))
	var length: float = (main.MIN_PULL + p / 100.0 * (main.MAX_PULL - main.MIN_PULL)) * main.k
	var dir := Vector2(U.ux(a), U.uy(a))
	var end := start - dir * length
	await _mouse(main, "down", start)
	for k in range(1, 6):
		await _mouse(main, "move", start.lerp(end, k / 5.0))
	await _mouse(main, "up", end)


func test_loads_into_todays_level():
	var main = await _fresh()
	var st: Dictionary = main.get_agent_state()
	assert_eq(st.phase, "aim", "ready to throw")
	assert_eq(st.day, DAY, "day set")
	assert_eq(st.archetype, "open", "Monday venue")
	assert_true(st.dev_mode, "dev mode on in debug builds")
	assert_eq(main.save.prefix, "dev_", "dev mode saves separately from the player's progress")
	assert_eq(st.share_text, "", "nothing to share yet")


func test_drag_aims_and_release_throws():
	var main = await _fresh()
	var start: Vector2 = main.to_screen(Vector2(400, 420))
	await _mouse(main, "down", start)
	await _mouse(main, "move", start + Vector2(-60, 40))
	assert_true(main.has_aim, "dragging aims")
	assert_gt(main.preview.size(), 4, "shows a short preview")
	var full := P.simulate(main.comp, main.aim_a, main.aim_p, 3)
	assert_lt(main.preview.size(), full.path.size(), "but never the whole flight")
	await _mouse(main, "move", start + Vector2(-4, 3))
	assert_false(main.has_aim, "pulling back to the start cancels")
	await _mouse(main, "up", start + Vector2(-4, 3))
	assert_eq(main.phase, "aim", "no throw")
	assert_eq(main.throws.size(), 0, "nothing counted")
	await _drag_throw(main, 60, 50)
	assert_eq(main.phase, "flight", "letting go throws")
	assert_eq([main.aim_a, main.aim_p], [60, 50], "the drag maps to exact whole-number aim")


func test_win_with_real_input_then_share():
	var main = await _fresh()
	var sol: Dictionary = main.level.solution
	await _drag_throw(main, int(sol.a), int(sol.p))
	assert_eq(main.phase, "flight", "thrown")
	for i in 400:
		if main.phase != "flight":
			break
		await wait_frames(1)
	assert_eq(main.phase, "won", "caught")
	assert_true(main.done, "day finished")
	assert_eq(int(main.result.throws), 1, "one throw")
	assert_gt(int(main.result.accuracy), 59, "accuracy recorded")
	var share: String = main.share_text()
	assert_true(share.begins_with("Bouquet Toss #%d" % int(main.level.number)), "share title")
	assert_true(share.contains("🎯 1 throw · Perfect"), "share result")
	assert_true(share.ends_with(main.DEFAULT_URL), "plain game URL")
	assert_false(share.contains("dev"), "no dev flag in the link")
	for i in 40:
		if main.modal == "end":
			break
		await wait_seconds(0.1)
	assert_eq(main.modal, "end", "end screen opens")


func test_misses_count_and_persist():
	var main = await _fresh()
	assert_true(main.throw(270, 5), "throw straight down")
	main.skip_flight()
	assert_eq(main.throws.size(), 1, "counted")
	assert_eq(main.throws[0].o, "floor", "landed on the floor")
	assert_eq(main.phase, "settle", "shows where it landed")
	assert_ne(main.status, "", "says what happened")
	assert_false(main.throw(45, 50), "can't throw while it settles")
	await _mouse(main, "down", main.to_screen(Vector2(400, 300)))
	await _mouse(main, "up", main.to_screen(Vector2(400, 300)))
	assert_eq(main.phase, "aim", "a tap skips ahead")
	main._save_now()
	main.queue_free()
	await wait_frames(2)
	var again = await _fresh(DAY, false)
	assert_eq(again.throws.size(), 1, "throws survive a reload")
	assert_eq(again.get_agent_state().aim, [270, 5], "last aim restored")


func test_keyboard_aim_and_throw():
	var main = await _fresh()
	var a0: int = main.aim_a
	var p0: int = main.aim_p
	await tap_action("aim_up")
	await wait_frames(1)
	assert_eq(main.aim_a, posmod(a0 + 1, 360), "up raises the angle")
	await tap_action("power_up")
	await wait_frames(1)
	assert_eq(main.aim_p, p0 + 1, "right adds power")
	await tap_action("throw")
	await wait_frames(1)
	assert_eq(main.phase, "flight", "space throws")


func test_practice_after_winning_keeps_the_result():
	var main = await _fresh()
	main.dev_win()
	assert_true(main.done, "won")
	var res: Dictionary = main.result.duplicate(true)
	main.modal = ""
	main.phase = "aim"
	assert_true(main.throw(270, 5), "practice throw allowed")
	main.skip_flight()
	assert_eq(main.practice_throws, 1, "counted as practice")
	assert_eq(main.result, res, "result unchanged")
	assert_eq(main.throws.size(), 1, "official throws unchanged")


func test_dev_controls_stay_out_of_real_saves():
	var real := Save.new(false)
	var before := real.load_results().duplicate()
	var main = await _fresh()
	main.dev_shift(1)
	assert_eq(main.date, "2026-10-20", "next day")
	main.dev_win()
	assert_true(main.done, "instant win")
	assert_eq(real.load_results(), before, "player's results untouched")
	main.dev_reset()
	assert_false(main.done, "reset clears the day")
	assert_eq(main.throws.size(), 0, "no throws")
	main.dev_reveal()
	assert_gt(main.ghost.size(), 10, "reveal shows the reference path")
	main.dev_set_day("2027-06-01")
	assert_eq(main.date, "2027-06-01", "any date")
	assert_eq(main.phase, "aim", "playable")
	main.dev_random_day()
	assert_eq(main.phase, "aim", "random day playable")


func test_archive_lists_past_days_only():
	var main = await _fresh()
	main.open_archive()
	assert_eq(main.modal, "archive", "opens")
	assert_eq(main.archive_count(), maxi(1, main.Daily.day_number(main.today)), "one row per day so far")
	main.pick_day("2026-10-16")
	assert_eq(main.modal, "", "closes")
