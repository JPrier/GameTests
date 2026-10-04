extends GameTest

const DAY := "2026-10-03"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.dev_mode = true
	main.dev_open = false
	main.anim_speed = 1000.0
	main.load_day(d)
	main.wipe_save()
	main.load_day(d)
	return main


func _days(n: int) -> Array:
	var out: Array = []
	var t0 := Time.get_unix_time_from_datetime_string(DAY + "T00:00:00")
	for i in n:
		out.append(Time.get_date_string_from_unix_time(t0 + i * 86400))
	return out


func _wait_phase(main, phase: int) -> void:
	for i in 60:
		if main.phase == phase or main.screen != main.Screen.PLAY:
			return
		await wait_frames(1)


func test_catalog():
	var main = await _fresh()
	for id in main.BAD_IDS:
		assert_true(main.CAT.has(id), id + " exists")
		assert_true(main.CAT[id].bad, id + " is contraband")
		assert_true(main.CAT.has(main.LOOKALIKE[id]), id + " lookalike exists")
		assert_false(main.CAT[main.LOOKALIKE[id]].bad, id + " lookalike is allowed")
		assert_true(main.LEGEND_NOTE.has(id), id + " has a legend note")
	for id in main.SMALL_OK + main.BIG_IDS:
		assert_false(main.CAT[id].bad, id + " is allowed")


func test_same_date_same_shift():
	var main = await _fresh()
	var a: Array = main.generate(DAY)
	assert_eq(main.generate(DAY), a, "same day, same bags")
	assert_ne(main.generate("2026-10-04"), a, "next day differs")
	assert_eq(main.day_number(DAY), 1, "shift #1 is the epoch")
	assert_eq(main.day_number("2026-10-13"), 11, "numbering")


func test_next_30_days_are_fair():
	var main = await _fresh()
	for d in _days(30):
		var bs: Array = main.generate(d)
		assert_true(main.bags_valid(bs), d + ": valid")
		var bad := 0
		for b in bs:
			assert_true(b.items.size() >= 3 and b.items.size() <= 9, d + ": item count fits the open grid")
			for k in b.bad:
				assert_true(main.CAT[b.items[k].id].bad, d + ": bad index points at contraband")
			bad += b.bad.size()
		assert_true(bad >= 5, d + ": enough contraband")


func test_perfect_run_scripted():
	var main = await _fresh()
	main.start_shift()
	assert_eq(main.screen, main.Screen.PLAY, "playing")
	for i in main.BAGS:
		await _wait_phase(main, main.Phase.SCAN)
		assert_eq(main.bag_i, i, "on bag %d" % i)
		var bad: Array = main.bags[i].bad
		if bad.is_empty():
			main.clear_bag()
		else:
			main.flag_bag()
			await _wait_phase(main, main.Phase.OPEN)
			for k in bad:
				main.tap_item(k)
		await wait_frames(2)
	for f in 60:
		if main.screen == main.Screen.END:
			break
		await wait_frames(1)
	assert_eq(main.screen, main.Screen.END, "end screen reached")
	assert_eq(main.found_total(), main.contraband_total(), "found everything")
	assert_eq(main.false_alarms(), 0, "no false alarms")
	assert_eq(main.base_score(), main.contraband_total() * main.FIND_PTS, "base score")
	assert_gt(main.time_bonus(), 0, "fast run earns a time bonus")
	var st: String = main.share_text()
	assert_false(st.contains("?day=") or st.contains("&day="), "share link has no day in it")
	assert_true(st.ends_with(main.base_url), "share links to the game itself")
	assert_false(st.contains("dev=1"), "share link has no dev flag")
	assert_true(st.contains("🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩"), "all bags green")
	assert_true(st.contains("X-Ray Shift #1"), "game name and number")


func _play_correct(main) -> void:
	await _wait_phase(main, main.Phase.SCAN)
	var bad: Array = main.bags[main.bag_i].bad
	if bad.is_empty():
		main.clear_bag()
	else:
		main.flag_bag()
		await _wait_phase(main, main.Phase.OPEN)
		for k in bad:
			main.tap_item(k)
	for f in 30:
		if main.phase == main.Phase.ENTER or main.phase == main.Phase.SCAN:
			break
		await wait_frames(1)


func test_false_alarm_and_wrong_tap():
	var main = await _fresh()
	main.start_shift()
	var clean := -1
	for i in main.BAGS:
		if main.bags[i].bad.is_empty():
			clean = i
			break
	while main.bag_i < clean:
		await _play_correct(main)
	await _wait_phase(main, main.Phase.SCAN)
	assert_eq(main.bag_i, clean, "reached the clean bag")
	main.flag_bag()
	await _wait_phase(main, main.Phase.OPEN)
	main.tap_item(0)
	main.tap_item(0)
	assert_eq(main.bag_points(clean), main.WRONG_PTS, "wrong tap costs points, once")
	main.done_bag()
	assert_eq(main.bag_points(clean), main.WRONG_PTS + main.FALSE_ALARM_PTS, "false alarm costs points")
	assert_eq(main.bag_mark(clean), 2, "false alarm is a red bag")
	assert_eq(main.false_alarms(), 1, "counted")


func test_partial_find_is_yellow():
	var main = await _fresh()
	main.start_shift()
	while main.bags[main.bag_i].bad.is_empty():
		await _play_correct(main)
	await _wait_phase(main, main.Phase.SCAN)
	var i: int = main.bag_i
	main.flag_bag()
	await _wait_phase(main, main.Phase.OPEN)
	main.done_bag()
	assert_eq(main.bag_points(i), 0, "found nothing, no points")
	assert_eq(main.bag_mark(i), 1, "flagged but missed items is yellow")
	assert_eq(main.missed_flash, main.bags[i].bad, "missed items are shown")


func test_clearing_contraband_is_a_miss():
	var main = await _fresh()
	main.start_shift()
	while main.bags[main.bag_i].bad.is_empty():
		await _play_correct(main)
	await _wait_phase(main, main.Phase.SCAN)
	var i: int = main.bag_i
	main.clear_bag()
	assert_eq(main.bag_points(i), 0, "no points")
	assert_eq(main.bag_mark(i), 2, "red bag")
	assert_eq(main.missed_flash, main.bags[i].bad, "missed items flash")


func test_flag_and_clear_only_while_scanning():
	var main = await _fresh()
	main.flag_bag()
	assert_eq(main.results.size(), 0, "no flag from the menu")
	main.start_shift()
	main.clear_bag()
	assert_eq(main.results.size(), 0, "no decision before the bag arrives")
	await _wait_phase(main, main.Phase.SCAN)
	main.flag_bag()
	main.clear_bag()
	assert_eq(main.results.size(), 1, "one decision per bag")
	assert_true(main.results[0].flag, "the flag stuck")


func test_progress_resumes():
	var main = await _fresh()
	main.start_shift()
	await _wait_phase(main, main.Phase.SCAN)
	main.flag_bag()
	main.load_day(DAY)
	assert_eq(main.results.size(), 1, "flag saved")
	main.start_shift()
	assert_eq(main.phase, main.Phase.OPEN, "resumes with the bag open")


func test_dev_controls():
	var main = await _fresh()
	main.dev_set_day("2026-11-01")
	assert_eq(main.date, "2026-11-01", "set day")
	main.dev_shift(-1)
	assert_eq(main.date, "2026-10-31", "previous day")
	main.dev_set_day(DAY)
	main.dev_win()
	assert_eq(main.screen, main.Screen.END, "instant win ends the shift")
	assert_eq(main.found_total(), main.contraband_total(), "instant win finds everything")
	assert_true(main._save_path().begins_with("user://dev_"), "dev progress is kept apart")
	main.dev_reset()
	assert_eq(main.screen, main.Screen.MENU, "reset back to the menu")
	assert_eq(main.results.size(), 0, "reset clears progress")
	main.dev_lose()
	assert_eq(main.found_total(), 0, "instant lose finds nothing")
	assert_eq(main.bag_mark(0), 2, "instant lose gets bags wrong")
	main.dev_reset()


func test_legend_toggle():
	var main = await _fresh()
	assert_false(main.legend_open, "closed at start")
	press_key(KEY_L)
	await wait_frames(2)
	assert_true(main.legend_open, "L opens the legend")
	press_key(KEY_ESCAPE)
	await wait_frames(2)
	assert_false(main.legend_open, "Esc closes it")


func test_keyboard_loop():
	var main = await _fresh()
	press_key(KEY_SPACE)
	await wait_frames(2)
	assert_eq(main.screen, main.Screen.PLAY, "space starts")
	await _wait_phase(main, main.Phase.SCAN)
	press_key(KEY_F)
	await wait_frames(2)
	assert_true(main.phase == main.Phase.OPENING or main.phase == main.Phase.OPEN, "F flags")
	await _wait_phase(main, main.Phase.OPEN)
	press_key(KEY_ENTER)
	await wait_frames(2)
	assert_true(main.results[0].done, "Enter closes the bag")


## Dates spread from next year out to 2100, plus leap days and the 2038 rollover.
func _far_future_days() -> Array:
	var out: Array = ["2028-02-29", "2038-01-19", "2038-01-20", "2096-02-29", "2100-03-01"]
	var t := Time.get_unix_time_from_datetime_string("2027-01-01T00:00:00")
	var end := Time.get_unix_time_from_datetime_string("2100-12-31T00:00:00")
	while t <= end:
		out.append(Time.get_date_string_from_unix_time(t))
		t += 449 * 86400   # an odd stride so the samples land on every weekday and month
	return out


func test_far_future_days_are_fair():
	var main = await _fresh()
	for d in _far_future_days():
		assert_true(main.bags_valid(main.generate(d)), d + ": valid shift")


func test_past_shifts_picker():
	var main = await _fresh()
	main.load_day(main.today)
	main.open_archive()
	await wait_frames(2)
	assert_true(main.archive_open, "picker opens from the menu")
	var first: Array = main.archive_page_days(0)
	assert_eq(String(first[0]), main.today, "newest day first")
	assert_true(first.size() <= main.ARCHIVE_ROWS, "one page of rows")
	var ids: Array = []
	for b in main.buttons:
		ids.append(String(b.id))
	assert_true(ids.has("day_" + main.today), "today is a row")
	assert_true(ids.has("arch_close"), "picker has a close button")
	main._do("day_" + main.EPOCH)
	assert_false(main.archive_open, "picking closes the picker")
	assert_eq(main.date, main.EPOCH, "picked day loads")
	main.pick_day("2099-01-01")
	assert_eq(main.date, main.EPOCH, "future days can't be picked")
	main.dev_win()
	await wait_frames(2)
	ids.clear()
	for b in main.buttons:
		ids.append(String(b.id))
	assert_true(ids.has("today") and ids.has("share"), "past shift end screen offers today's shift")
	main._do("today")
	assert_eq(main.date, main.today, "back to today")
	main.start_shift()
	main.open_archive()
	assert_false(main.archive_open, "no picker mid-shift")


func test_results_listed_in_picker():
	var main = await _fresh()
	var p: String = main._results_path()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main._record_result(DAY, "900 pts")
	assert_eq(String(main._load_results().get(DAY, "")), "900 pts", "result remembered for the picker")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
