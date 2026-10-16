extends GameTest
## Level generation and validation: determinism, invariants, solvability, the attempt table.

const Gen = preload("res://core/generator.gd")
const Levels = preload("res://core/levels.gd")
const V = preload("res://core/validator.gd")
const L = preload("res://core/level.gd")
const P = preload("res://core/physics.gd")
const Daily = preload("res://core/daily.gd")


func _strip(lv: Dictionary) -> Dictionary:
	var c := lv.duplicate(true)
	c.erase("stats")
	c.erase("solution")
	return c


func test_same_date_same_level_and_dates_differ():
	var a := Levels.make_attempt("2026-10-23", 0)
	var b := Levels.make_attempt("2026-10-23", 0)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same date, same attempt, same level")
	var c := Levels.make_attempt("2026-10-30", 0)
	assert_ne(JSON.stringify(a.solids), JSON.stringify(c.solids), "a week later (same archetype) differs")
	assert_eq(a.archetype, c.archetype, "same weekday, same venue type")


func test_levels_are_plain_serializable_data():
	var lv := Levels.for_date("2026-10-24")
	var round_trip := L.from_json(L.to_json(lv))
	assert_eq(JSON.stringify(round_trip), JSON.stringify(lv), "JSON round trip")
	var sol: Dictionary = lv.solution
	var a := P.throw(lv, int(sol.a), int(sol.p), 1)
	var b := P.throw(round_trip, int(sol.a), int(sol.p), 1)
	assert_true(a.path == b.path, "a reloaded level plays identically")
	for s in lv.solids:
		for key in ["x", "y", "w", "h", "r"]:
			if s.has(key):
				assert_eq(typeof(s[key]), TYPE_INT, "geometry is whole numbers")


func test_generator_invariants_over_many_attempts():
	# Every raw attempt (accepted or not) must have legal geometry; only fairness may fail.
	var n := 0
	for i in 140:
		var arche: String = Daily.ARCHETYPES[i % 7]
		var d := Daily.add_days(Daily.EPOCH, i)
		var lv := Gen.make(d, 1, Daily.seed_for(d, 77 + i), i, arche)
		var errs := L.geometry_errors(lv)
		assert_true(errs.is_empty(), "%s %s: %s" % [d, arche, ", ".join(errs)])
		assert_true(lv.has("target") and lv.has("thrower") and lv.has("release"), "has people")
		assert_eq(lv.theme == "garden", lv.ceiling < 0, "only the garden is open to the sky")
		if arche != "garden":
			assert_eq(int(lv.wind), 0, "no wind indoors")
		n += 1
	assert_eq(n, 140, "checked them all")


func test_mirroring_mirrors_the_physics():
	var lv := Gen.make("2026-11-02", 1, 4242, 0, "open")
	var m := lv.duplicate(true)
	L.mirror(m)
	assert_true(L.geometry_errors(m).is_empty(), "mirrored geometry is legal")
	for pair in [[40, 50], [60, 70], [25, 85], [80, 40]]:
		var a := P.throw(lv, pair[0], pair[1])
		var b := P.throw(m, 180 - pair[0], pair[1])
		assert_eq(a.outcome, b.outcome, "mirrored throw ends the same way %s" % str(pair))
		assert_near(float(lv.w) - a.end_x, b.end_x, 0.5, "mirrored landing spot")


func test_next_30_days_are_fair():
	var d := Daily.today_local()
	if d < Daily.EPOCH:
		d = Daily.EPOCH
	for i in 30:
		var lv := Levels.for_date(d)
		assert_true(L.geometry_errors(lv).is_empty(), d + " geometry")
		var st := V.evaluate(lv)
		assert_true(st.ok, "%s (%s) accepted: %s" % [d, lv.archetype, ", ".join(st.reasons)])
		assert_gt(st.robust, 0, d + " has a forgiving solution")
		var sol: Dictionary = lv.solution
		var r := P.throw(lv, int(sol.a), int(sol.p))
		assert_eq(r.outcome, "catch", d + " reference throw catches")
		assert_true(int(lv.attempt) < 1000, d + " didn't need the fallback")
		d = Daily.add_days(d, 1)


func test_attempt_table_matches_fresh_search():
	var t := Levels.attempt_table()
	assert_gt(t.size(), 300, "table covers about a year")
	assert_true(t.has(Daily.EPOCH), "starts at puzzle #1")
	for d in ["2026-10-16", "2026-12-25", "2027-03-14"]:
		if not t.has(d):
			continue
		var fresh := Levels.search(d)
		var e: Array = t[d]
		assert_eq(int(e[0]), int(fresh.attempt), d + " attempt")
		assert_eq([int(e[1]), int(e[2])], [int(fresh.solution.a), int(fresh.solution.p)], d + " reference throw")
		assert_eq(JSON.stringify(_strip(Levels.from_table(d))), JSON.stringify(_strip(fresh)), d + " same level either way")


func test_validator_rejects_broken_levels():
	var lv := Levels.for_date("2026-10-19")
	var blocked := lv.duplicate(true)
	# Only the target, plus a wall from floor to ceiling halfway to them: impossible.
	var keep: Array = []
	for s in blocked.solids:
		if String(s.get("role", "")) == "target":
			keep.append(s)
	var mid := (int(blocked.release[0]) + int(blocked.target.x)) / 2
	keep.append(L.rect(mid - 10, int(blocked.ceiling), 20, int(blocked.floor) - int(blocked.ceiling), "pillar", 999))
	blocked.solids = keep
	assert_true(L.geometry_errors(blocked).is_empty(), "the walled room is legal geometry")
	var st := V.evaluate(blocked)
	assert_false(st.ok, "walled-off target is rejected")
	assert_true(st.reasons.has("unsolvable") or st.robust == 0, "because nothing reaches it")
	var overlap := lv.duplicate(true)
	overlap.solids.append(L.rect(int(overlap.release[0]) - 10, int(overlap.release[1]) - 10, 20, 20, "table"))
	assert_false(L.geometry_errors(overlap).is_empty(), "a table in the throwing hand is illegal geometry")
	var floating := lv.duplicate(true)
	floating.target.feet = 500
	assert_false(L.geometry_errors(floating).is_empty(), "a floating target is illegal")


func test_difficulty_rises_through_the_week():
	# Average solve rate over a few weeks: Monday's open room beats Sunday's divider.
	var mon := 0.0
	var sun := 0.0
	var d := "2026-10-19"     # a Monday
	for w in 3:
		mon += float(V.evaluate(Levels.for_date(Daily.add_days(d, w * 7))).rate)
		sun += float(V.evaluate(Levels.for_date(Daily.add_days(d, w * 7 + 6))).rate)
	assert_gt(mon, sun, "Monday is easier than Sunday")
