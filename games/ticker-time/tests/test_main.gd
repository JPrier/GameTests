extends GameTest

const DAY := "2026-10-02"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.dev_mode = true
	main.dev_open = false
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


func test_data_loaded():
	var main = await _fresh()
	assert_gt(main.stocks.size(), 150, "stock list loaded")
	assert_gt(main.nweeks, 1600, "weekly history loaded")
	var aapl := -1
	for i in main.stocks.size():
		if main.stocks[i].t == "AAPL":
			aapl = i
	assert_true(aapl >= 0, "Apple is in the data")
	# split-adjusted close in the last week of 2008 was about $3.07
	var g: int = main.first_week_of(2009) - 1
	assert_near(main.price(aapl, g), 3.07, 0.1, "AAPL end of 2008")


func test_same_date_same_puzzle():
	var main = await _fresh()
	var y1: Array = main.generate_year_rounds(DAY)
	var u1: Array = main.generate_ud_rounds(DAY)
	assert_eq(main.generate_year_rounds(DAY), y1, "year rounds deterministic")
	assert_eq(main.generate_ud_rounds(DAY), u1, "up/down rounds deterministic")
	assert_ne(main.generate_year_rounds("2026-10-03"), y1, "next day differs (year)")
	assert_ne(main.generate_ud_rounds("2026-10-03"), u1, "next day differs (up/down)")
	assert_eq(main.day_number(DAY), 1, "puzzle #1 is the epoch")
	assert_eq(main.day_number("2026-10-12"), 11, "puzzle numbering")


func test_next_60_days_are_valid():
	var main = await _fresh()
	for d in _days(60):
		var yr: Array = main.generate_year_rounds(d)
		assert_eq(yr.size(), 5, d + ": five year rounds")
		var tick := {}
		var bins := {}
		for r in yr:
			assert_true(main.has_full_year(int(r.stock), int(r.year)), d + ": full year of data")
			assert_true(int(r.year) >= main.YEAR_MIN and int(r.year) <= main.YEAR_MAX, d + ": year in range")
			tick[int(r.stock)] = true
			bins[(int(r.year) - 1995) / 6 if int(r.year) < 2019 else 4] = true
		assert_eq(tick.size(), 5, d + ": distinct tickers")
		assert_eq(bins.size(), 5, d + ": years spread across eras")
		var ud: Array = main.generate_ud_rounds(d)
		assert_eq(ud.size(), 5, d + ": five up/down rounds")
		var ups := 0
		for r in ud:
			var e := int(r.end)
			assert_true(e - main.LOOKBACK + 1 >= main.stock_first(int(r.stock)), d + ": a full year of history")
			assert_true(e + main.AHEAD <= main.stock_last(int(r.stock)), d + ": the month after exists")
			if main.ud_return(r) > 0:
				ups += 1
		assert_true(ups > 0 and ups < 5, d + ": mix of ups and downs")


func test_year_mode_scripted_play():
	var main = await _fresh()
	main.open_mode(main.Screen.YEAR)
	for i in 5:
		var actual := int(main.year_rounds[i].year)
		main.set_guess(actual + (0 if i % 2 == 0 else 3))
		main.lock_guess()
		assert_true(main.revealed, "guess reveals the answer")
		main.next_round()
	assert_eq(main.screen, main.Screen.YEAR_END, "reaches the end screen")
	assert_eq(main.year_score(), 100 * 3 + 45 * 2, "points by distance")
	var s: String = main.share_text()
	assert_true(s.contains("?day=" + DAY), "share has the day link")
	assert_false(s.contains("dev=1"), "share never has dev")
	assert_true(s.contains("390/500"), "share has the score")
	assert_false(s.contains(main.stocks[int(main.year_rounds[0].stock)].t), "share doesn't spoil tickers")


func test_keyboard_drives_year_mode():
	var main = await _fresh()
	main.open_mode(main.Screen.YEAR)
	var g: int = main.cur_guess
	await press_key(KEY_RIGHT)
	await press_key(KEY_RIGHT)
	assert_eq(main.cur_guess, g + 2, "arrow keys move the guess")
	await press_key(KEY_ENTER)
	assert_eq(main.year_guesses.size(), 1, "enter locks in")
	await press_key(KEY_ENTER)
	assert_eq(main.year_i, 1, "enter goes to the next chart")


func test_up_down_money():
	var main = await _fresh()
	main.open_mode(main.Screen.UD)
	var expect := 1000.0
	for i in 5:
		var ret: float = main.ud_return(main.ud_rounds[i])
		var dir := 1 if i % 2 == 0 else -1
		var frac: float = [0.05, 0.35, 1.0, 0.6, 0.25][i]
		main.set_stake(frac)
		assert_near(main.stake, frac, 0.001, "slider stake set")
		var amt := snappedf(expect * frac, 0.01)
		expect = snappedf(expect + snappedf(maxf(-amt, amt * ret * dir), 0.01), 0.01)
		main.place_bet(dir)
		main.next_round()
	assert_eq(main.screen, main.Screen.UD_END, "reaches the end screen")
	assert_near(main.cash(), expect, 0.02, "cash follows the bets")
	assert_true(main.cash() >= 0.0, "never negative")
	assert_true(main.best_possible_cash() >= main.cash(), "perfect play is the ceiling")
	assert_true(main.share_text().contains("Up or Down"), "share mentions the mode")


func test_progress_resumes():
	var main = await _fresh()
	main.open_mode(main.Screen.YEAR)
	main.set_guess(2001)
	main.lock_guess()
	main.open_mode(main.Screen.UD)
	main.place_bet(-1)
	main.load_day(DAY)
	assert_eq(main.year_guesses, [2001], "year guess saved")
	assert_eq(main.ud_bets.size(), 1, "bet saved")


func test_dev_controls():
	var main = await _fresh()
	main.dev_set_day("2026-11-05")
	assert_eq(main.date, "2026-11-05", "dev can jump to a future day")
	main.dev_reset()
	main.dev_win()
	assert_eq(main.year_score(), 500, "instant win, year")
	assert_near(main.cash(), main.best_possible_cash(), 0.02, "instant win, up/down")
	main.dev_reset()
	assert_eq(main.year_guesses.size(), 0, "reset clears the day")
	main.open_mode(main.Screen.UD)
	main.dev_lose()
	assert_eq(main.screen, main.Screen.UD_END, "instant lose goes to the end")
	assert_lt(main.cash(), 1000.0, "losing loses money")
	assert_true(String(main._save_path()).contains("dev_"), "dev saves are separate")
	main.wipe_save()
	main.dev_mode = false
	assert_false(String(main._save_path()).contains("dev_"), "real saves untouched by dev")


func test_stake_slider_and_legacy_saves():
	var main = await _fresh()
	main.set_stake(0.0)
	assert_near(main.stake, 0.05, 0.001, "stake has a 5% floor")
	main.set_stake(0.42)
	assert_near(main.stake, 0.40, 0.001, "stake snaps to 5% steps")
	main.set_stake(3.0)
	assert_near(main.stake, 1.0, 0.001, "stake caps at all in")
	main.open_mode(main.Screen.UD)
	main.set_stake(0.5)
	await press_key(KEY_RIGHT)
	assert_near(main.stake, 0.55, 0.001, "right arrow raises the bet")
	# an old save stored an index into [25%, 50%, all in]
	var f := FileAccess.open(main._save_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"year": [], "ud": [{"dir": 1, "stake": 2}]}))
	f.close()
	main.load_day(main.date)
	assert_near(float(main.ud_bets[0].frac), 1.0, 0.001, "legacy stake index maps to a fraction")
	main.wipe_save()


func test_five_title_taps_enable_dev():
	var main = await _fresh()
	main.dev_mode = false
	main.dev_open = false
	for i in 5:
		main._dev_tap()
	assert_true(main.dev_mode, "5 quick taps turn dev mode on")
	assert_true(main.dev_open, "and open the panel")
	assert_true(String(main._save_path()).contains("dev_"), "dev progress is separate")
	for i in 5:
		main._dev_tap()
	assert_false(main.dev_open, "5 more taps close it")


## Dates spread from next year out to 2100, plus leap days and the 2038 rollover.
func _far_future_days() -> Array:
	var out: Array = ["2028-02-29", "2038-01-19", "2038-01-20", "2096-02-29", "2100-03-01"]
	var t := Time.get_unix_time_from_datetime_string("2027-01-01T00:00:00")
	var end := Time.get_unix_time_from_datetime_string("2100-12-31T00:00:00")
	while t <= end:
		out.append(Time.get_date_string_from_unix_time(t))
		t += 449 * 86400   # an odd stride so the samples land on every weekday and month
	return out


func test_far_future_days_are_valid():
	var main = await _fresh()
	for d in _far_future_days():
		assert_eq(main.generate_year_rounds(d).size(), 5, d + ": five year rounds")
		assert_eq(main.generate_ud_rounds(d).size(), 5, d + ": five up/down rounds")
