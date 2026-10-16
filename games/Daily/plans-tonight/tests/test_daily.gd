extends GameTest
## Dates, puzzle numbers, seeds and day rollover.


func test_puzzle_numbers():
	assert_eq(PTDaily.day_number(PTDaily.EPOCH), 1)
	assert_eq(PTDaily.day_number(PTDaily.date_add(PTDaily.EPOCH, 1)), 2)
	assert_eq(PTDaily.day_number(PTDaily.date_add(PTDaily.EPOCH, 365)), 366)


func test_date_rollover_math():
	assert_eq(PTDaily.date_add("2026-12-31", 1), "2027-01-01", "year rollover")
	assert_eq(PTDaily.date_add("2028-02-28", 1), "2028-02-29", "leap day")
	assert_eq(PTDaily.date_add("2028-02-29", 1), "2028-03-01")
	assert_eq(PTDaily.date_add("2026-11-01", 1), "2026-11-02", "no DST surprises (UTC)")
	assert_eq(PTDaily.date_for_unix(PTDaily.unix("2026-10-16") + 86399), "2026-10-16", "last second of the day")
	assert_eq(PTDaily.date_for_unix(PTDaily.unix("2026-10-16") + 86400), "2026-10-17", "midnight UTC is the next day")


func test_weekdays():
	assert_eq(PTDaily.weekday("2026-10-16"), 5, "Friday")
	assert_eq(PTDaily.weekday("2026-10-18"), 0, "Sunday")
	assert_eq(PTDaily.pretty("2026-10-16"), "Fri, Oct 16")


func test_is_date():
	assert_true(PTDaily.is_date("2026-10-16"))
	assert_false(PTDaily.is_date("2026-02-31"), "not a real day")
	assert_false(PTDaily.is_date("16/10/2026"))
	assert_false(PTDaily.is_date(""))


func test_seeds_differ_by_day():
	assert_ne(PTDaily.seed_for("2026-10-16"), PTDaily.seed_for("2026-10-17"))
	assert_eq(PTDaily.seed_for("2026-10-16"), PTDaily.seed_for("2026-10-16"))


func test_ui_rolls_over_at_midnight():
	var main = await load_scene("res://main.tscn")
	main.dev_mode = false
	var d := "2031-05-05"
	main.today = d
	main.load_day(d)
	main.wipe_save()
	main.load_day(d)
	# Untouched board: the new day loads straight away.
	main.check_rollover("2031-05-06")
	assert_eq(main.date, "2031-05-06", "fresh board moves to the new day")
	assert_eq(main.puzzle_no, PTDaily.day_number("2031-05-06"))
	# Mid-game: keep the player's board, just say new plans are ready.
	main.wipe_save()
	var wrong: int = PTValidate.decoys(main.puzzle)[0]
	main.guess_plan(wrong)
	main.close_modal()
	main.check_rollover("2031-05-07")
	assert_eq(main.date, "2031-05-06", "doesn't yank an in-progress board")
	assert_true(main.new_day_ready, "flags that new plans are ready")
	assert_eq(main.today, "2031-05-07")
	main.wipe_save()
	main.dev_mode = true
	for x in ["2031-05-05", "2031-05-06", "2031-05-07"]:
		main.date = x
		main.wipe_save()
