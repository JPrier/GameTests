extends GameTest
## The full loop through real input, the end screen, sharing and dev controls.

const DAY := "2030-05-10"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.dev_mode = true
	main.load_day(d)
	main.wipe_save()
	main.load_day(d)
	return main


func test_board_builds():
	var main = await _fresh()
	await wait_frames(2)
	assert_eq(main.friend_cards.size(), main.puzzle.friends.size())
	assert_eq(main.plan_cards.size(), main.puzzle.plans.size())
	assert_eq(main.get_agent_state().state, "playing")
	assert_true(main.lock_btn.disabled, "nothing to lock in yet")
	assert_false(main.goal_label.text.is_empty(), "goal is on screen")


func test_full_loop_with_keys():
	var main = await _fresh()
	await wait_frames(2)
	var target: int = main.puzzle.target
	var wrong: int = PTValidate.decoys(main.puzzle)[0]
	# Pick a wrong plan with its number key, lock it in with Enter.
	await tap_action("pick_%d" % (wrong + 1))
	await wait_frames(2)
	assert_eq(main.selected, wrong)
	assert_false(main.lock_btn.disabled)
	await tap_action("lock_in")
	await wait_frames(2)
	assert_eq(main.st.guesses, [wrong])
	assert_eq(main.modal, main.Modal.WRONG, "shows who vetoed it")
	assert_eq(main.get_agent_state().state, "playing", "a wrong guess doesn't end the game")
	await tap_action("lock_in")  # Enter closes the feedback
	await wait_frames(2)
	assert_eq(main.modal, main.Modal.NONE)
	# The wrong plan can't be picked again.
	main.select_plan(wrong)
	assert_eq(main.selected, -1)
	# Now the right one.
	await tap_action("pick_%d" % (target + 1))
	await wait_frames(1)
	await tap_action("lock_in")
	await wait_seconds(0.7)
	assert_eq(main.get_agent_state().state, "won")
	assert_eq(main.modal, main.Modal.WIN, "end screen shows")
	var s: String = main.get_agent_state().share_text
	assert_true(s.contains("Plans Tonight? #%d" % main.puzzle_no))
	assert_true(s.contains("🍻 2/%d" % main.puzzle.plans.size()))
	assert_true(s.contains(PTShare.URL) or s.contains("http"), "has the play link")
	assert_false(s.contains("day="), "link has no day")
	assert_false(s.contains("dev=1"), "link has no dev flag")
	main.wipe_save()


func test_tap_selects_and_cross_toggles():
	var main = await _fresh()
	await wait_frames(3)
	main.select_plan(2)
	assert_eq(main.selected, 2)
	main.toggle_cross(2)
	assert_true(main.st.crossed.has(2))
	assert_eq(main.selected, -1, "crossing off a picked plan unpicks it")
	main.toggle_cross(2)
	assert_false(main.st.crossed.has(2))
	assert_eq(main.st.guesses.size(), 0, "crossing off is not a guess")
	main.wipe_save()


func test_hint_button_asks_first():
	var main = await _fresh()
	await wait_frames(2)
	await tap_action("hint")
	await wait_frames(2)
	assert_eq(main.modal, main.Modal.HINT, "confirm dialog")
	assert_eq(main.st.hints, 0, "nothing used until confirmed")
	main.close_modal()
	assert_eq(main.st.hints, 0, "cancel costs nothing")
	main._ask_hint()
	main._confirm_hint()
	assert_eq(main.st.hints, 1)
	main.wipe_save()


func test_dev_controls_dont_touch_real_saves():
	var main = await load_scene("res://main.tscn")
	# A real (non-dev) result on disk.
	main.dev_mode = false
	main.load_day(DAY)
	main.wipe_save()
	main.load_day(DAY)
	var wrong: int = PTValidate.decoys(main.puzzle)[0]
	main.guess_plan(wrong)
	main.close_modal()
	var real_path: String = main._save_path()
	var before := FileAccess.get_file_as_string(real_path)
	# Dev mode: set day, win, reset, worst run.
	main.dev_mode = true
	main.load_day(DAY)
	assert_eq(main.st.guesses, [], "dev mode has its own progress")
	main.dev_win()
	await wait_seconds(0.6)
	assert_eq(main.get_agent_state().state, "won")
	main.dev_reset()
	assert_eq(main.get_agent_state().state, "playing")
	main.dev_worst()
	await wait_seconds(0.6)
	assert_eq(main.st.guesses.size(), main.puzzle.plans.size(), "worst run tries every plan")
	assert_true(main.dev_set_day(PTDaily.date_add(DAY, 3)))
	assert_eq(main.date, PTDaily.date_add(DAY, 3))
	assert_false(main.dev_set_day("nope"))
	assert_eq(FileAccess.get_file_as_string(real_path), before, "real save untouched by dev actions")
	assert_false(main.share_text().contains("dev"), "dev share links stay clean")
	main.dev_reset()
	main.dev_set_day(DAY)
	main.dev_reset()
	main.dev_mode = false
	main.load_day(DAY)
	main.wipe_save()


func test_archive_pages():
	var main = await _fresh()
	main.today = PTDaily.date_add(PTDaily.EPOCH, 20)
	assert_eq(main.archive_count(), 21)
	assert_eq(main.archive_pages(), 3)
	assert_eq(main.archive_page_days(0)[0], main.today, "newest first")
	assert_eq(main.archive_page_days(2).size(), 7)
	main.pick_day(PTDaily.date_add(PTDaily.EPOCH, 5))
	assert_eq(main.date, PTDaily.date_add(PTDaily.EPOCH, 5))
	main.wipe_save()
	main.load_day(DAY)
	main.wipe_save()
