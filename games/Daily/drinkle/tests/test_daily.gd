extends GameTest
## Daily selection, the pinned schedule, difficulty and puzzle analysis over the whole database.

const DB = preload("res://core/db.gd")
const Daily = preload("res://core/daily.gd")
const Analysis = preload("res://core/analysis.gd")
const Cands = preload("res://core/candidates.gd")
const Game = preload("res://core/game.gd")

const SCHEDULE := "res://data/schedule.json"


func _schedule_doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SCHEDULE))


func test_same_date_same_drink():
	Daily.reset_cache()
	for i in 20:
		var d := Daily.add_days("2026-10-16", i * 3)
		assert_eq(Daily.target_id(d), Daily.target_id(d), "deterministic " + d)
		assert_eq(Daily.computed_target(d), Daily.computed_target(d), "rule deterministic " + d)


func test_puzzle_numbers():
	assert_eq(Daily.day_number("2026-10-16"), 1, "puzzle #1")
	assert_eq(Daily.day_number("2026-10-17"), 2, "next day")
	assert_eq(Daily.day_number("2027-10-16"), 366, "a year later")
	assert_eq(Daily.add_days("2026-12-31", 1), "2027-01-01", "year rollover")
	assert_eq(Daily.add_days("2028-02-28", 1), "2028-02-29", "leap day")
	assert_false(Daily.valid_date("2026-02-30"), "invalid date")
	assert_true(Daily.valid_date("2028-02-29"), "leap date")


func test_different_days_vary():
	var seen := {}
	for i in 30:
		seen[Daily.target_id(Daily.add_days("2026-10-16", i))] = true
	assert_gt(seen.size(), 25, "a month uses many different drinks")


func test_no_repeats_within_two_weeks():
	var last := {}
	for i in 1100:
		var d := Daily.add_days("2026-10-16", i)
		var id := Daily.target_id(d)
		if last.has(id):
			assert_true(i - int(last[id]) >= 14, "%s repeats after %d days (%s)" % [id, i - int(last[id]), d])
		last[id] = i


func test_upcoming_days_are_valid_answers():
	var start := Daily.today_local()
	for i in 60:
		var d := Daily.add_days(start, i)
		var t := Daily.target(d)
		assert_false(t.is_empty(), "a drink for " + d)
		assert_true(t.target, "%s: %s is allowed as an answer" % [d, t.id])
		assert_true(int(t.fame) <= Analysis.MAX_FAME, "not obscure")
		if d >= Daily.pinned_before():
			assert_eq(int(Daily.difficulty_of(t.id).tier), Daily.tier_for(d), "%s gets a %s from its weekday tier" % [d, t.id])


func test_weekday_tiers():
	assert_eq(Daily.tier_for("2026-10-19"), 0, "Monday easy")
	assert_eq(Daily.tier_for("2026-10-21"), 1, "Wednesday medium")
	assert_eq(Daily.tier_for("2026-10-17"), 2, "Saturday hard")


func test_schedule_matches_database():
	var doc := _schedule_doc()
	assert_eq(int(doc.fingerprint), DB.fingerprint(),
		"drinks.json/schema.json changed: rerun tools/schedule.gd (past dates stay pinned)")
	for d in doc.days:
		assert_true(DB.has(String(doc.days[d])), "pinned answer exists: " + d)
		assert_true(DB.get_drink(String(doc.days[d])).target, "pinned answer is allowed: " + d)


func test_schedule_agrees_with_the_rule():
	# with the database unchanged, the pinned days equal what the rule computes
	Daily.reset_cache()
	var doc := _schedule_doc()
	var n := 0
	for d in doc.days:
		n += 1
		if n % 7 != 0 or String(d) < String(doc.pinned_before):
			continue
		assert_eq(Daily.computed_target(String(d)), String(doc.days[d]), "pinned = computed for " + String(d))


func test_already_played_days_never_change():
	# answers published before the database grew to 90 drinks
	var doc := _schedule_doc()
	assert_true(String(doc.pinned_before) >= "2026-10-19", "the first days stay pinned")
	assert_eq(String(doc.days["2026-10-16"]), "mint_julep", "puzzle #1")
	assert_eq(String(doc.days["2026-10-17"]), "tom_collins", "puzzle #2")
	assert_eq(String(doc.days["2026-10-18"]), "margarita", "puzzle #3")
	Daily.reset_cache()
	assert_eq(Daily.target_id("2026-10-17"), "tom_collins", "the game reads the pinned answer")


func test_pinned_pools_are_the_analysers_pools():
	var doc := _schedule_doc()
	Analysis.clear_cache()
	assert_eq(Analysis.tier_pools(), doc.pools, "tier pools recomputed match the pinned ones")


func test_no_indistinguishable_drinks():
	assert_eq(Analysis.duplicates(), [], "every drink has a unique profile")


func test_eligibility_rules():
	assert_false(Analysis.eligibility(DB.get_drink("gin_tonic")).ok, "disputed drinks are never answers")
	assert_false(Analysis.eligibility(DB.get_drink("french_75")).ok, "trivially identifiable drinks are never answers")
	assert_true(Analysis.eligibility(DB.get_drink("margarita")).ok, "the margarita is fine")
	var n := 0
	for d in DB.all():
		if Analysis.eligibility(d).ok:
			n += 1
	assert_gt(n, 40, "plenty of answers")


func test_difficulty_scores():
	var easy: Dictionary = Analysis.difficulty(DB.get_drink("root_beer_float"))
	var hard: Dictionary = Analysis.difficulty(DB.get_drink("sidecar"))
	assert_lt(easy.score, hard.score, "a lone soda float is easier than one of many sours")
	for d in DB.all():
		var df: Dictionary = Analysis.difficulty(d)
		assert_true(df.score >= 0 and df.score <= 100, "score in range")
		assert_true(df.steps <= 5, "%s: a perfect player always solves within 5 (took %d)" % [d.id, df.steps])
	var pools := Analysis.tier_pools()
	for p in pools:
		assert_gt(p.size(), 8, "each tier has enough drinks for a varied rotation")


func test_every_answer_is_solvable_in_six():
	# a perfect-information greedy player beats every answer comfortably within the six guesses
	for d in DB.targets():
		var path := Analysis.solve_path(d)
		assert_eq(path[-1], d.id, "path ends on the answer")
		assert_true(path.size() <= Game.MAX_GUESSES, "%s solvable in six" % d.id)


func test_any_first_guess_still_leaves_a_solvable_game():
	# whatever a player opens with, the feedback always pins the answer down within 6 total
	for t in DB.targets():
		var worst := 0
		for g in DB.all():
			var path := Analysis.solve_path(t, g)
			worst = maxi(worst, path.size())
		assert_true(worst <= Game.MAX_GUESSES, "%s: worst opening still solvable (%d)" % [t.id, worst])
