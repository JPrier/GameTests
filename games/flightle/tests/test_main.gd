extends GameTest

const DAY := "2026-10-03"


func _fresh(d := DAY) -> Node:
	var main = await load_scene("res://main.tscn")
	main.dev_mode = true
	main.dev_open = false
	main.load_day(d)
	main.wipe_save()
	main.load_day(d)
	return main


func _days(from: String, n: int) -> Array:
	var out: Array = []
	var t0 := Time.get_unix_time_from_datetime_string(from + "T00:00:00")
	for i in n:
		out.append(Time.get_date_string_from_unix_time(t0 + i * 86400))
	return out


func _decoy(main, avoid: Array) -> String:
	for a in main.airports:
		if not String(a.c) in avoid:
			return String(a.c)
	return ""


func test_data_loaded():
	var main = await _fresh()
	assert_gt(main.routes.size(), 100, "route list loaded")
	assert_gt(main.airports.size(), 300, "airport pool loaded")
	assert_gt(main.land.size(), 50, "coastlines loaded")
	assert_true(main.ap_index.has("JFK") and main.ap_index.has("LHR"), "major airports present")
	assert_near(main.km_codes("JFK", "LHR"), 5540.0, 30.0, "JFK-LHR great-circle distance")
	assert_near(main.bearing("JFK", "LHR"), 51.0, 3.0, "JFK-LHR initial bearing")


func test_every_route_is_valid():
	var main = await _fresh()
	for r in main.routes:
		assert_true(main.route_valid(r), "route %s-%s valid" % [r.f, r.t])
		var prof: Array = main.altitude_profile(r)
		assert_eq(prof[0], Vector2.ZERO, "profile starts on the ground")
		assert_eq(prof[prof.size() - 1].y, 0.0, "profile ends on the ground")
		assert_near(prof[prof.size() - 1].x, float(r.min), 0.01, "profile spans the flight time")


func test_same_date_same_flight():
	var main = await _fresh()
	var a: int = main.route_index_for(DAY)
	var b: int = main.route_index_for(DAY)
	assert_eq(a, b, "same date gives the same flight")
	assert_ne(main.route_index_for(DAY), main.route_index_for("2026-10-04"), "next day differs")


func test_no_repeats_within_a_cycle():
	var main = await _fresh()
	var seen := {}
	var n: int = main.routes.size()
	for d in _days(main.EPOCH, n):
		seen[main.route_index_for(d)] = true
	assert_eq(seen.size(), n, "every route appears once per cycle")
	# no back-to-back repeats across days (including cycle boundaries)
	var prev := -1
	for d in _days(main.EPOCH, n * 3 + 5):
		var i: int = main.route_index_for(d)
		assert_ne(i, prev, "no repeat on %s" % d)
		prev = i


func test_next_30_days_are_playable():
	var main = await _fresh()
	for d in _days(DAY, 30):
		main.load_day(d)
		assert_true(main.route_valid(main.route), "%s has a valid route" % d)
		assert_eq(main.phase, main.Phase.PLAYING, "%s starts in play" % d)
		assert_eq(main.path_pts.size(), 65, "%s path sampled" % d)
		assert_true(main.suggestions(String(main.route.f)).has(String(main.route.f)), "departure is guessable")
		assert_true(main.suggestions(String(main.route.t)).has(String(main.route.t)), "arrival is guessable")


func test_suggestions():
	var main = await _fresh()
	assert_eq(main.suggestions("jfk")[0], "JFK", "exact code first")
	assert_true(main.suggestions("london").has("LHR"), "city search finds Heathrow")
	assert_true(main.suggestions("NEWYORK").has("JFK"), "spaces ignored")
	assert_eq(main.suggestions("").size(), 0, "empty query, no suggestions")


func test_core_loop_by_scripted_typing():
	var main = await _fresh()
	var f := String(main.route.f)
	var t := String(main.route.t)
	var d1 := _decoy(main, [f, t])
	var d2 := _decoy(main, [f, t, d1])
	# miss: type decoys on the keyboard path (type -> Enter picks the top match -> Enter submits)
	main.type_text(d1)
	main.confirm()
	assert_eq(main.picks[0], d1, "Enter picks the top suggestion")
	assert_eq(main.slot, 1, "cursor moves to the arrival slot")
	main.type_text(d2)
	main.confirm()
	assert_eq(main.guesses.size(), 1, "guess submitted")
	assert_eq(main.clues_revealed(), 1, "a miss unlocks the first clue")
	var fb: Dictionary = main.feedback(main.guesses[0], 0)
	assert_eq(fb.kind, "miss", "decoy is a miss")
	assert_gt(float(fb.km), 0.0, "miss reports a distance")
	# lock the departure, then win
	main.guess(f, d2)
	assert_true(main.solved(0), "departure locked in")
	assert_eq(main.slot, 1, "only arrival left to type")
	main.type_text(t)
	main.confirm()
	assert_eq(main.phase, main.Phase.WON, "won after 3 guesses")
	assert_eq(main.result_label(), "3/6")
	await wait_frames(2)


func test_swap_and_duplicates():
	var main = await _fresh()
	var f := String(main.route.f)
	var t := String(main.route.t)
	assert_true(main.guess(t, f), "reversed guess accepted")
	assert_eq(main.feedback(main.guesses[0], 0).kind, "swap", "reversed end flagged")
	assert_eq(main.phase, main.Phase.PLAYING, "reversed pair does not win")
	assert_false(main.guess(t, f), "duplicate pair rejected")
	assert_eq(main.guesses.size(), 1, "duplicate not counted")


func test_lose_and_share_text():
	var main = await _fresh()
	main.base_url = "https://jprier.github.io/GameTests/flightle/"
	main.dev_lose()
	assert_eq(main.phase, main.Phase.LOST, "six misses lose")
	assert_eq(main.guesses.size(), 6)
	assert_eq(main.clues_revealed(), 5, "all clues shown at the end")
	var s: String = main.share_text()
	assert_true(s.contains("Flightle #1"), "share has game and number")
	assert_true(s.contains("X/6"), "share has result")
	assert_true(s.contains("https://jprier.github.io/GameTests/flightle/?day=2026-10-03"), "share has day link")
	assert_false(s.contains("dev=1"), "no dev flag in share")
	assert_false(s.contains(String(main.route.f)) or s.contains(String(main.route.t)), "no spoilers")
	await wait_frames(2)


func test_win_share_and_end_screen():
	var main = await _fresh()
	main.dev_win()
	assert_eq(main.phase, main.Phase.WON)
	assert_true(main.share_text().contains("1/6"), "won in one")
	await wait_frames(3)
	var ids: Array = []
	for b in main.buttons:
		ids.append(String(b.id))
	assert_true(ids.has("share"), "end screen shows Share")


func test_dev_controls_keep_real_save_apart():
	var main = await _fresh()
	main.dev_win()
	assert_true(main._save_path().contains("dev_"), "dev progress uses a dev save")
	var real := "user://flightle_%s.json" % DAY
	assert_false(FileAccess.file_exists(real), "no real save written by dev actions")
	main.dev_reset()
	assert_eq(main.guesses.size(), 0, "reset clears the day")
	main.dev_set_day("2026-12-25")
	assert_eq(main.date, "2026-12-25", "jump to any day")
	main.dev_shift(-1)
	assert_eq(main.date, "2026-12-24", "previous day")


func test_progress_persists():
	var main = await _fresh()
	var f := String(main.route.f)
	main.guess(f, _decoy(main, [f, String(main.route.t)]))
	main.load_day("2026-10-04")
	main.load_day(DAY)
	assert_eq(main.guesses.size(), 1, "guess restored")
	assert_true(main.solved(0), "locked end restored")
	main.wipe_save()


func test_five_title_taps_enable_dev_mode():
	var main = await _fresh()
	main.dev_mode = false
	main.dev_open = false
	await wait_frames(2)
	var p: Vector2 = main.title_rect.get_center()
	for i in 4:
		main._on_press(p)
	assert_false(main.dev_mode, "four taps do nothing")
	main._on_press(p)
	assert_true(main.dev_mode, "fifth tap turns dev mode on")
	assert_true(main.dev_open, "panel opens")
	assert_true(main._save_path().contains("dev_"), "dev progress kept apart")
	main.dev_open = false
	for i in 5:
		main._on_press(p)
	assert_true(main.dev_open, "five more taps reopen the panel")
