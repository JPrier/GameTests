extends GameTest
## The game scene: real taps on the on-screen keyboard, search, winning, losing, sharing,
## saving, dev controls, date rollover, past days and text that always fits.

const Save = preload("res://core/save.gd")
const DB = preload("res://core/db.gd")
const Daily = preload("res://core/daily.gd")
const Schema = preload("res://core/schema.gd")

const DAY := "2026-10-20"      # a Tuesday


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	await wait_frames(1)
	main.dev_set_day(d)
	main.dev_reset()
	main.modal = ""
	main._layout()
	await wait_frames(1)
	return main


func _mouse(main, type: String, p: Vector2) -> void:
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = type == "down"
	ev.position = p
	ev.global_position = p
	main._input(ev)
	await wait_frames(1)


func _tap(main, p: Vector2) -> void:
	await _mouse(main, "down", p)
	await _mouse(main, "up", p)


func _tap_button(main, id: String) -> void:
	var c: Vector2 = main.button_center(id)
	assert_true(c.x >= 0, "button %s exists" % id)
	await _tap(main, c)


func _type_by_taps(main, text: String) -> void:
	for ch in text.to_upper():
		await _tap_button(main, "k_SPACE" if ch == " " else "k_" + ch)


func _a_wrong_drink(main, n := 0) -> String:
	var k := 0
	for d in DB.all():
		if d.id != main.game.target.id and not main.game.guesses.has(d.id):
			if k == n:
				return d.id
			k += 1
	return ""


func test_loads_into_todays_game():
	var main = await load_scene("res://main.tscn")
	await wait_frames(2)
	var st: Dictionary = main.get_agent_state()
	assert_eq(st.state, "playing", "playing")
	assert_eq(st.day, Daily.today_local(), "opens today")
	assert_true(st.dev_mode, "dev mode on in debug builds")
	assert_eq(main.save.prefix, "dev_", "dev mode saves separately")
	assert_eq(st.guesses_left, 6, "six guesses")


func test_type_select_and_guess_with_taps():
	var main = await _fresh()
	await _type_by_taps(main, "marg")
	assert_eq(main.query, "marg", "typed with the on-screen keyboard")
	assert_true(main.panel_open, "suggestions open while typing")
	assert_eq(main.suggestions[0], "margarita", "margarita suggested first")
	await _tap(main, main.suggestion_center(0))
	assert_eq(main.selected_id, "margarita", "tap a suggestion to pick it")
	assert_false(main.panel_open, "picking closes the list")
	await _tap_button(main, "guess")
	assert_eq(main.game.guesses, ["margarita"] if main.game.target.id != "margarita" else ["margarita"], "guessed")
	assert_eq(main.query, "", "input cleared")
	await _tap_button(main, "k_G")
	await _tap_button(main, "k_DEL")
	assert_eq(main.query, "", "delete key erases")


func test_enter_submits_exact_alias_and_rejects_repeats():
	var main = await _fresh()
	if main.game.target.id == "gin_tonic":
		return
	main.type_text("g&t")
	var r: Dictionary = main.submit()
	assert_true(r.ok, "an exact alias submits without picking from the list")
	assert_eq(main.game.guesses[-1], "gin_tonic", "G&T resolved")
	main.type_text("gin and tonic")
	r = main.submit()
	assert_false(r.ok, "repeat refused")
	assert_eq(main.game.guesses.size(), 1, "repeat costs nothing")
	main.clear_query()
	r = main.submit()
	assert_false(r.ok, "empty input refused")
	assert_true(main.panel_open, "and the browse list opens instead")


func test_browse_lists_every_drink():
	var main = await _fresh()
	await _tap(main, main.field_rect.get_center())
	assert_true(main.panel_open, "tapping the box opens the list")
	assert_eq(main.suggestions.size(), DB.size(), "every drink, A to Z")


func test_win_shows_end_screen_and_share():
	var main = await _fresh()
	main.guess_drink(_a_wrong_drink(main))
	main.guess_drink(main.game.target.id)
	assert_eq(main.get_agent_state().state, "won", "won")
	await wait_seconds(1.6)
	assert_eq(main.modal, "end", "end screen after the reveal")
	var s: String = main.share_text()
	assert_true(s.begins_with("Mystery Drink #%d" % Daily.day_number(DAY)), "share header: " + s)
	assert_true(s.contains("2/6"), "score")
	assert_true(s.ends_with(main.base_url), "plain game link")
	assert_false(s.contains("dev=1"), "no dev flag")
	assert_false(s.contains("day="), "no day in the link (past days are picked in-game)")
	assert_false(s.to_lower().contains(String(main.game.target.name).to_lower()), "no spoiler")
	assert_eq(s.split("\n").size(), 5, "header, 2 rows, score, link")
	main.share()       # native: copies to the clipboard
	assert_eq(main.last_share_text, s, "share uses the share text")


func test_lose_after_six():
	var main = await _fresh()
	for i in 6:
		main.guess_drink(_a_wrong_drink(main))
	assert_eq(main.get_agent_state().state, "lost", "lost")
	await wait_seconds(1.6)
	assert_eq(main.modal, "end", "end screen")
	assert_true(main.share_text().contains("X/6"), "loss in the share text")
	assert_false(main.guess_drink(main.game.target.id).ok, "no more guesses")


func test_hints_and_clues_show_in_the_message_bar():
	var main = await _fresh()
	main.guess_drink(_a_wrong_drink(main))
	var h: Dictionary = main.use_hint()
	assert_eq(h.level, 1, "hint 1")
	assert_true(String(main.message).begins_with("Hint 1"), "shown")
	for i in 3:
		main.guess_drink(_a_wrong_drink(main))
	assert_true(String(main.message).begins_with("Clue:"), "free clue after guess 4: " + main.message)


func test_progress_is_saved_and_restored():
	var main = await _fresh()
	var g1 := _a_wrong_drink(main)
	main.guess_drink(g1)
	main.use_hint()
	main.dev_set_day("2026-10-21")
	main.dev_set_day(DAY)
	assert_eq(main.game.guesses, [g1], "guess restored")
	assert_eq(main.game.hints_used, 1, "hint restored")
	assert_eq(main.save.load_results().get(DAY, ""), "In progress", "listed as in progress")


func test_dev_controls_never_touch_real_saves():
	var real = Save.new(false)
	var before: Dictionary = real.load_results()
	var main = await _fresh()
	main.dev_win()
	await wait_frames(2)
	assert_eq(main.get_agent_state().state, "won", "dev win")
	main.dev_reset()
	assert_eq(main.get_agent_state().state, "playing", "dev reset")
	main.dev_lose()
	assert_eq(main.get_agent_state().state, "lost", "dev lose")
	main.dev_shift(1)
	assert_eq(main.date, Daily.add_days(DAY, 1), "next day")
	main.dev_shift(-7)
	assert_eq(main.date, Daily.add_days(DAY, -6), "back a week")
	main.dev_random_day()
	assert_true(Daily.valid_date(main.date), "random day")
	assert_eq(real.load_results(), before, "the player's real results are untouched")
	assert_false(FileAccess.file_exists("user://day_%s.json" % DAY), "no real day file written")


func test_date_rollover():
	var main = await _fresh(Daily.today_local())
	main.today_override = ""
	var tomorrow := Daily.add_days(main.today, 1)
	main.dev_set_today(tomorrow)
	assert_eq(main.date, tomorrow, "an untouched game moves to the new day")
	main.guess_drink(_a_wrong_drink(main))
	main.dev_set_today(Daily.add_days(tomorrow, 1))
	assert_eq(main.date, tomorrow, "a game in progress stays put")
	assert_true(String(main.toast).contains("new mystery drink"), "and a toast says a new one is ready")
	main.today_override = ""


func test_past_days_from_the_calendar():
	var main = await _fresh(Daily.today_local())
	main.today_override = "2026-10-30"
	main.today = "2026-10-30"
	main.open_archive()
	assert_eq(main.modal, "archive", "calendar open")
	main.archive_page = 0
	main._build_buttons()
	assert_true(main.archive_page_days(0).has("2026-10-29"), "yesterday listed")
	await _tap_button(main, "day_2026-10-29")
	assert_eq(main.date, "2026-10-29", "picked a past day")
	assert_eq(main.number, 14, "its puzzle number")
	main.today_override = ""


func test_help_and_first_run():
	var main = await _fresh()
	main.open_help()
	assert_eq(main.modal, "help", "help")
	await _tap_button(main, "close")
	assert_eq(main.modal, "", "closed")
	assert_true(bool(main.save.load_meta().get("tutorial", false)), "remembered")


func test_every_label_fits_its_cell():
	# no truncation, no overlap: every value label fits a cell in two lines at the smallest
	# cell width any layout produces (landscape left column 520 wide).
	var main = await _fresh()
	var cell_w := (520.0 - 6 * 5) / 6.0 - 10.0
	for id in Schema.ids():
		for v in Schema.values(id):
			var label := Schema.value_label(id, v)
			assert_true(main.text_fits(label, cell_w, 20, 12, 2, main.bold), "%s fits a cell" % label)
	for d in DB.all():
		assert_true(main.text_fits(d.name, 520.0 - 40, 22, 14, 1, main.bold), d.name + " fits a guess row")
	for l in main.COL_LABELS:
		assert_true(main.text_fits(l, cell_w + 10, 18, 13, 1, main.bold), l + " header fits")


func test_layouts_do_not_overlap():
	var main = await _fresh()
	for size in [Vector2(720, 1560), Vector2(720, 1280), Vector2(720, 1100), Vector2(1280, 720), Vector2(978, 720)]:
		main.layout_for(size)
		var parts := [main.head_rect, main.known_rect, main.msg_rect, main.rows_rect, main.input_rect, main.kb_rect]
		for i in parts.size():
			for j in range(i + 1, parts.size()):
				var a: Rect2 = parts[i]
				var b: Rect2 = parts[j]
				assert_false(a.grow(-1).intersects(b.grow(-1)), "%s: parts %d and %d overlap" % [str(size), i, j])
		assert_true(main.kb_rect.end.y <= size.y + 0.5, "keyboard on screen at " + str(size))
		assert_true(main.slot_h >= 60.0, "guess rows stay readable at %s (%.0f)" % [str(size), main.slot_h])
