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
	var a := Levels.make_attempt("2026-10-23", 2, 0)
	var b := Levels.make_attempt("2026-10-23", 2, 0)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same date, throw and attempt: same level")
	var c := Levels.make_attempt("2026-10-30", 2, 0)
	assert_ne(JSON.stringify(a.solids), JSON.stringify(c.solids), "another day differs")
	var kinds := {}
	for h in Daily.HOLES:
		var lv := Levels.make_attempt("2026-10-23", h, 0)
		assert_eq(int(lv.hole), h, "knows which throw it is")
		kinds[String(lv.archetype)] = true
	assert_eq(kinds.size(), Daily.HOLES, "five different venues in a day")


func test_levels_are_plain_serializable_data():
	var lv := Levels.for_date("2026-10-24", 3)
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
		var lv := Gen.make(d, 1, Daily.seed_for(d, 0, 77 + i), i, arche)
		var errs := L.geometry_errors(lv)
		var tx := int(lv.thrower.x)
		assert_true(tx >= 170 and tx <= int(lv.w) - 170, "thrower stands well in from the edge (x=%d)" % tx)
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


func test_next_week_is_fair():
	var d := Daily.today_local()
	if d < Daily.EPOCH:
		d = Daily.EPOCH
	for i in 7:
		for h in Daily.HOLES:
			var lv := Levels.for_date(d, h)
			var tag := "%s throw %d" % [d, h + 1]
			assert_true(L.geometry_errors(lv).is_empty(), tag + " geometry")
			var st := V.evaluate(lv)
			assert_true(st.ok, "%s (%s) accepted: %s" % [tag, lv.archetype, ", ".join(st.reasons)])
			assert_gt(st.robust, 0, tag + " has a forgiving solution")
			var sol: Dictionary = lv.solution
			assert_eq(P.throw(lv, int(sol.a), int(sol.p)).outcome, "catch", tag + " reference throw catches")
			assert_true(int(lv.attempt) < 1000, tag + " didn't need the fallback")
		d = Daily.add_days(d, 1)


func test_attempt_table_matches_fresh_search():
	var t := Levels.attempt_table()
	assert_gt(t.size(), 300, "table covers about a year")
	assert_true(t.has(Daily.EPOCH), "starts at puzzle #1")
	for pair in [["2026-10-16", 0], ["2026-12-25", 4], ["2027-03-14", 2]]:
		var d: String = pair[0]
		var h: int = pair[1]
		if not t.has(d):
			continue
		assert_eq((t[d] as Array).size(), Daily.HOLES, d + " has all five throws")
		var fresh := Levels.search(d, h)
		var e: Array = t[d][h]
		assert_eq(int(e[0]), int(fresh.attempt), d + " attempt")
		assert_eq([int(e[1]), int(e[2])], [int(fresh.solution.a), int(fresh.solution.p)], d + " reference throw")
		assert_eq(JSON.stringify(_strip(Levels.from_table(d, h))), JSON.stringify(_strip(fresh)), d + " same level either way")


func test_validator_rejects_broken_levels():
	var lv := Levels.for_date("2026-10-19", 0)
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


func test_difficulty_rises_through_the_day():
	# Averaged over two weeks, the first throw of the day is easier than the last.
	var first := 0.0
	var last := 0.0
	var d := "2026-10-19"
	for i in 14:
		first += float(V.evaluate(Levels.for_date(d, 0)).rate)
		last += float(V.evaluate(Levels.for_date(d, Daily.HOLES - 1)).rate)
		d = Daily.add_days(d, 1)
	assert_gt(first, last, "throw 1 is gentler than throw 5")
