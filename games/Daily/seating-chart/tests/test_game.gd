extends GameTest
## The game scene: loading, real drag/tap input, winning, sharing, saving, dev controls.

const Save = preload("res://core/save.gd")

const DAY := "2026-10-20"      # a Tuesday


var _scene: Node


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	_scene = main
	for i in 60:
		if not main.loading:
			break
		await wait_frames(1)
	main.dev_set_day(d)
	main.dev_reset()
	main.modal = ""
	main._build_buttons()
	await wait_frames(1)
	return main


func _mouse(type: String, p: Vector2) -> void:
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
	_scene._input(ev)       # feed the event to the game's own input handler
	await wait_frames(1)


func _drag(a: Vector2, b: Vector2) -> void:
	await _mouse("down", a)
	for k in range(1, 6):
		await _mouse("move", a.lerp(b + Vector2(0, 34), k / 5.0))
	await _mouse("up", b + Vector2(0, 34))


func _tap(p: Vector2) -> void:
	await _mouse("down", p)
	await _mouse("up", p)


func test_loads_into_a_puzzle():
	var main = await _fresh()
	var st: Dictionary = main.get_agent_state()
	assert_eq(st.state, "playing", "playing")
	assert_eq(st.day, DAY, "day set")
	assert_true(int(st.clues) >= 6, "has clues")
	assert_true(st.dev_mode, "dev mode on in debug builds")
	assert_eq(main.save.prefix, "dev_", "dev mode saves separately from the player's progress")


func test_drag_and_tap_to_seat():
	var main = await _fresh()
	await _drag(main.card_center(0), main.seat_center(2))
	assert_eq(main.board.seat_of[0], 2, "dragged onto a seat")
	await _tap(main.card_center(1))
	assert_eq(main.selected, 1, "tap selects")
	await _tap(main.seat_center(7))
	assert_eq(main.board.seat_of[1], 7, "tap a seat to place the selected guest")
	await _drag(main.seat_center(7), main.card_center(1) - Vector2(0, 34))
	assert_eq(main.board.seat_of[1], -1, "drag back to the list unseats")
	await _drag(main.card_center(1), main.seat_center(2))
	assert_eq(main.board.seat_of[1], 2, "dropping on a taken seat swaps...")
	assert_eq(main.board.seat_of[0], -1, "...and the old guest returns to the list")
	main.undo()
	assert_eq(main.board.seat_of[0], 2, "undo")


func test_highlights():
	var main = await _fresh()
	var row: Dictionary = main.clue_rows[0]
	await _tap(main._clue_rect(row).get_center())
	assert_eq(main.focus_clue, int(row.i), "tapping a clue focuses it")
	var hl: Dictionary = main._highlight_guests()
	assert_eq(hl.size(), main.C.guests_of(main.model.clues[row.i]).size(), "its guests light up")
	await _tap(main.card_center(3))
	assert_eq(main.selected, 3, "tapping a guest selects them (their clues light up)")
	assert_eq(main.focus_clue, -1, "clue focus cleared")


func test_solve_with_input_wins_and_shares():
	var main = await _fresh()
	var m = main.model
	for g in 10:
		await _drag(main.card_center(g), main.seat_center(m.solution[g]))
	assert_true(main.finished, "solving by dragging wins")
	assert_eq(main.get_agent_state().state, "won", "state won")
	await wait_seconds(1.2)
	assert_eq(main.modal, "end", "end screen shows")
	var t: String = main.share_text()
	assert_true(t.contains("Seating Chart #"), "share title")
	assert_true(t.contains(main.share_link()), "share link")
	assert_false(t.contains("dev=1"), "no dev flag in the link")
	assert_true(t.contains("✨ Flawless"), "flawless run")
	main.share()
	assert_eq(main.last_share_text, t, "share uses the share text")
	assert_false(main.place_guest(0, 3), "no moves after winning")


func test_check_and_hint_counters():
	var main = await _fresh()
	var m = main.model
	# put guest 0 at the wrong table
	var wrong_seat: int = m.seat(1 - m.table_of(m.solution[0]), 0)
	main.place_guest(0, wrong_seat)
	var r: Dictionary = main.check_board()
	assert_eq(r.wrong, [0], "check flags the misplaced guest")
	assert_eq(main.mistakes, 1, "a wrong check counts")
	main.undo()
	main.place_guest(0, m.solution[0])
	main.check_board()
	assert_eq(main.mistakes, 1, "a clean check is free")
	var h1: Dictionary = main.use_hint()
	assert_eq(main.hint_level, 1, "hint level 1")
	assert_false((h1.clues as Array).is_empty(), "highlights clues")
	main.use_hint()
	assert_eq(main.hint_level, 2, "hint level 2 explains")
	var before: int = main.board.seated_count()
	main.use_hint()
	assert_eq(main.board.seated_count(), before + 1, "hint level 3 seats someone")
	assert_eq(main.hints_used, 3, "three hint presses counted")
	assert_eq(main.board.wrong_guests(), [], "the hinted seat is right")


func test_progress_is_saved_and_restored():
	var main = await _fresh()
	main.place_guest(2, 5)
	main.place_guest(4, 6)
	main.mistakes = 2
	main.elapsed = 77.0
	main._save_now()
	main.dev_set_day("2026-10-21")
	assert_eq(main.board.seated_count(), 0, "another day starts fresh")
	main.dev_set_day(DAY)
	assert_eq(main.board.seat_of[2], 5, "board restored")
	assert_eq(main.board.seat_of[4], 6, "board restored")
	assert_eq(main.mistakes, 2, "counters restored")
	assert_eq(int(main.elapsed), 77, "timer restored")
	assert_false(FileAccess.file_exists("user://day_%s.json" % DAY) and not FileAccess.file_exists("user://dev_day_%s.json" % DAY), "dev progress goes to dev files")
	assert_true(FileAccess.file_exists("user://dev_day_%s.json" % DAY), "dev save written")


func test_dev_controls():
	var main = await _fresh()
	main.dev_shift(1)
	assert_eq(main.date, "2026-10-21", "next day")
	main.dev_shift(-7)
	assert_eq(main.date, "2026-10-14", "back a week")
	main.dev_set_day(DAY)
	main.place_guest(0, 0)
	main.dev_reset()
	assert_eq(main.board.seated_count(), 0, "reset wipes the day")
	main.dev_win()
	assert_true(main.finished, "instant win")
	main.dev_set_day("2026-10-23")
	main.dev_reveal()
	assert_true(main.revealed and main.finished, "reveal ends the day as revealed")
	assert_true(main.share_text().contains("revealed"), "share says so")
	main.dev_random_day()
	assert_eq(main.get_agent_state().state, "playing", "random day loads")


func test_puzzle_cache_matches_generator():
	var main = await _fresh()
	var cached = Save.load_cached_puzzle(DAY)
	assert_not_null(cached, "today's puzzle is cached after loading")
	var fresh = load("res://core/generator.gd").for_date(DAY)
	var back = load("res://core/model.gd").from_dict(cached)
	assert_eq(back.to_dict(), fresh.to_dict(), "cache equals a fresh generation")
