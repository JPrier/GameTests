extends GameTest
## Daily seeds, generation, uniqueness, difficulty tiers and serialization.

const Model = preload("res://core/model.gd")
const C = preload("res://core/constraints.gd")
const S = preload("res://core/solver.gd")
const L = preload("res://core/logic.gd")
const G = preload("res://core/generator.gd")
const D = preload("res://core/difficulty.gd")
const Daily = preload("res://core/daily.gd")
const Names = preload("res://core/names.gd")
const Sweep = preload("res://tools/sweep.gd")

const DAY := "2026-10-19"      # a Monday


func test_same_date_same_puzzle():
	var a = G.for_date(DAY)
	var b = G.for_date(DAY)
	assert_eq(a.to_dict(), b.to_dict(), "same date gives an identical puzzle")
	var c = G.for_date(Daily.add_days(DAY, 1))
	assert_ne(a.to_dict().clues, c.to_dict().clues, "the next day is different")
	assert_eq(a.number, Daily.day_number(DAY), "puzzle number")
	assert_eq(a.date, DAY, "date recorded")


func test_dates_and_rollover():
	assert_eq(Daily.day_number(Daily.EPOCH), 1, "epoch is #1")
	assert_eq(Daily.day_number(Daily.add_days(Daily.EPOCH, 1)), 2, "next day #2")
	assert_eq(Daily.add_days("2026-12-31", 1), "2027-01-01", "year rollover")
	assert_eq(Daily.add_days("2028-02-28", 1), "2028-02-29", "leap day")
	assert_eq(Daily.add_days("2026-11-01", 1), "2026-11-02", "across the US clock change")
	assert_eq(Daily.add_days("2026-03-01", -1), "2026-02-28", "month rollback")
	assert_eq(Daily.day_number("2027-10-16") - Daily.day_number("2026-10-16"), 365, "a year of numbers")
	assert_true(Daily.valid_date("2026-02-28"), "valid date")
	assert_false(Daily.valid_date("2026-02-30"), "impossible date rejected")
	assert_false(Daily.valid_date("16/10/2026"), "wrong format rejected")
	assert_eq(Daily.tier_for("2026-10-19"), 0, "Monday easy")
	assert_eq(Daily.tier_for("2026-10-20"), 1, "Tuesday medium")
	assert_eq(Daily.tier_for("2026-10-21"), 1, "Wednesday medium")
	assert_eq(Daily.tier_for("2026-10-22"), 2, "Thursday tricky")
	assert_eq(Daily.tier_for("2026-10-23"), 2, "Friday tricky")
	assert_eq(Daily.tier_for("2026-10-24"), 3, "Saturday hard")
	assert_eq(Daily.tier_for("2026-10-25"), 3, "Sunday hard")
	assert_ne(Daily.seed_for(DAY, 0), Daily.seed_for(DAY, 1), "re-rolls use new seeds")


func test_next_two_weeks_are_valid():
	# every day: unique, deducible within its tier, no redundant clue, rating fits the tier
	var start := Daily.today_local()
	for i in 14:
		var d := Daily.add_days(start, i)
		var m = G.for_date(d)
		assert_not_null(m, "puzzle for " + d)
		if m == null:
			continue
		assert_eq(m.tier, Daily.tier_for(d), "tier follows the weekday for " + d)
		assert_eq(Sweep.audit(m), "", "audit passes for " + d)
		assert_eq(m.guest_count(), 10, "10 guests")
		assert_eq(m.tables, 2, "2 tables")


func test_harder_tiers_need_harder_reasoning():
	var by_tier := {}
	for i in 21:
		var d := Daily.add_days("2026-10-19", i)
		var m = G.for_date(d)
		by_tier[m.tier] = by_tier.get(m.tier, []) + [m.rating]
	for r in by_tier[0]:
		assert_true(int(r.max_level) <= 2, "Monday never needs indirect reasoning")
	for t in [1, 2]:
		for r in by_tier[t]:
			assert_eq(int(r.max_level), 3, "%s needs indirect reasoning but no what-ifs" % D.tier_name(t))
			assert_false(r.falls_to_lower, "and can't be done with less")
	for r in by_tier[3]:
		assert_eq(int(r.max_level), 4, "weekends need a what-if")
		assert_true(int(r.at_table) <= 1, "weekends have at most one direct placement")


func test_bulk_generation_sample():
	# A slice of the sweep (tools/sweep.gd runs thousands): every accepted puzzle is audited, and
	# every rejection has a reason from the known list.
	var gen = G.new()
	var known := ["not logically solvable", "trivial: too few clues", "too many clues", "too hard for tier",
		"too many direct placements", "trivial: nothing to deduce", "too easy for tier",
		"wrong amount of indirect reasoning", "not enough overlapping reasoning",
		"wrong amount of what-if reasoning", "can't make it deducible"]
	var accepted := 0
	for i in 32:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + i
		var m = gen.attempt_puzzle(rng, i % 4)
		if m == null:
			assert_true(known.has(gen.last_reject), "rejection reason is known: " + gen.last_reject)
			continue
		accepted += 1
		assert_eq(Sweep.audit(m), "", "accepted puzzle passes audit (seed %d)" % (5000 + i))
	assert_gt(accepted, 10, "most attempts produce a puzzle")


func test_audit_catches_bad_puzzles():
	var m = G.for_date(DAY)
	var weak = Model.from_dict(m.to_dict())
	weak.clues = weak.clues.slice(0, 2)
	assert_ne(Sweep.audit(weak), "", "too few clues: multiple solutions caught")
	var wrong = Model.from_dict(m.to_dict())
	var c: Dictionary = wrong.clues[0].duplicate()
	var flip := {"adjacent": "not_adjacent", "not_adjacent": "adjacent", "same_table": "different_table",
		"different_table": "same_table"}
	if flip.has(String(c.type)):
		c.type = flip[String(c.type)]
	else:
		c.t = 1 - int(c.t)
	wrong.clues[0] = c
	assert_ne(Sweep.audit(wrong), "", "a false clue is caught")
	var extra = Model.from_dict(m.to_dict())
	for cand in G.new().true_clues(extra):
		if not extra.clues.any(func(x): return C.key(x) == C.key(cand)):
			extra.clues.append(cand)
			break
	assert_ne(Sweep.audit(extra), "", "a redundant clue is caught")
	var broken = Model.from_dict(m.to_dict())
	broken.clues.append({"type": "adjacent", "a": 3, "b": 3})
	assert_ne(Sweep.audit(broken), "", "a broken clue is caught")


func test_serialization_round_trip():
	var m = G.for_date(DAY)
	var json := JSON.stringify(m.to_dict())
	var back = Model.from_dict(JSON.parse_string(json))
	assert_eq(back.to_dict(), m.to_dict(), "puzzle survives JSON")
	assert_eq(S.count(back, back.clues, 2), 1, "and is still unique")
	assert_eq(C.text(back.clues[0], back), C.text(m.clues[0], m), "same clue text")


func test_descriptions_never_name_guests_and_fit():
	for desc in Names.DESCS:
		for nm in Names.NAMES:
			assert_false((" " + String(desc) + " ").contains(" " + String(nm) + " "), "'%s' doesn't name a guest" % desc)
	for nm in Names.NAMES:
		assert_true(String(nm).length() <= 6, "%s is short enough for a seat card" % nm)
	var font: Font = ThemeDB.fallback_font
	for desc in Names.DESCS:
		var w := 0.0
		var lines := 1
		var cur := ""
		for word in String(desc).split(" "):
			var test := word if cur == "" else cur + " " + word
			if cur != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x > 104:
				lines += 1
				cur = word
			else:
				cur = test
		assert_true(lines <= 4, "'%s' wraps to at most four lines on the smallest card" % desc)


func test_attempt_table_matches_full_search():
	# core/attempts.json only skips rejected attempts; it must never change a puzzle.
	var start := Daily.today_local()
	var checked := 0
	for i in 5:
		var d := Daily.add_days(start, i * 3)
		var k := G.known_attempt(d)
		if k == 0:
			continue
		checked += 1
		var full = G.new().generate_full(d, Daily.tier_for(d))
		assert_eq(full.attempts, k, "table attempt for %s (rerun tools/precompute.gd after generator changes)" % d)
		assert_eq(G.for_date(d).to_dict(), full.to_dict(), "fast path gives the same puzzle for " + d)
	assert_gt(checked, 0, "the table covers upcoming days (rerun tools/precompute.gd)")
