extends GameTest
## Generator determinism, the exactly-one-answer guarantee, minimality and quality checks.

const DAY := "2030-03-15"


func test_same_date_same_puzzle():
	var a := PTGen.generate(DAY)
	var b := PTGen.generate(DAY)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same date, identical puzzle")


func test_different_dates_differ():
	var seen := {}
	for i in 30:
		var p := PTGen.generate(PTDaily.date_add(DAY, i))
		seen[PTSave.signature(p)] = true
	assert_eq(seen.size(), 30, "30 days, 30 different puzzles")


func test_exactly_one_plan_works():
	for i in 60:
		var d := PTDaily.date_add(DAY, i)
		var p := PTGen.generate(d)
		var sols := PTValidate.solutions(p)
		assert_eq(sols.size(), 1, "%s has exactly one answer" % d)
		assert_eq(sols[0], int(p.target), "%s answer is the target" % d)


func test_every_clue_matters():
	for i in 60:
		var p := PTGen.generate(PTDaily.date_add(DAY, i))
		assert_eq(PTValidate.redundant(p).size(), 0, "no removable clues")
		for e in PTValidate.all_rules(p):
			assert_true(PTValidate.necessary(p, e[0], e[1]), "clue is needed: %s" % PTRules.text(e[2]))


func test_no_clue_gives_it_away():
	for i in 60:
		var p := PTGen.generate(PTDaily.date_add(DAY, i))
		var n := PTValidate.decoys(p).size()
		for e in PTValidate.all_rules(p):
			assert_lt(PTValidate.elim(p, e[2]).size(), n, "one clue can't rule out every other plan")


func test_cadence_and_sizes():
	# 2030-03-11 is a Monday.
	var expect := {1: "Easy", 2: "Easy", 3: "Medium", 4: "Medium", 5: "Hard", 6: "Hard", 0: "Medium"}
	for i in 14:
		var d := PTDaily.date_add("2030-03-11", i)
		var p := PTGen.generate(d)
		var wd := PTDaily.weekday(d)
		assert_eq(p.difficulty.label, expect[wd], "%s difficulty" % d)
		assert_eq(p.plans.size(), int(PTDaily.CADENCE[wd].plans), "%s plan count" % d)
		assert_true(p.friends.size() >= 3 and p.friends.size() <= 6, "3–6 friends")
		assert_eq(p.theme, "birthday" if wd == 6 else "night", "Saturday is a birthday")


func test_plans_are_sane():
	for i in 40:
		var p := PTGen.generate(PTDaily.date_add(DAY, i))
		for plan in p.plans:
			assert_true(int(plan.end) > int(plan.start), "ends after it starts")
			assert_true(int(plan.end) <= 24 * 60, "over by midnight")
			assert_true(int(plan.start) >= 17 * 60, "evening start")
			assert_ne(int(plan.price) % 5, 0, "price never sits on a $5 threshold")
			assert_true(ResourceLoader.exists("res://icons/%s.svg" % plan.icon), "icon ships: %s" % plan.icon)
		for f in p.friends:
			assert_true(ResourceLoader.exists("res://icons/%s.svg" % f.avatar), "avatar ships")
			assert_false(String(f.flavor).is_empty(), "has a personality line")


func test_validator_catches_two_answers():
	var p := PTGen.generate(DAY)
	# Drop a needed clue: a second plan now works.
	var e: Array = PTValidate.all_rules(p)[0]
	var q := p.duplicate(true)
	q.friends[e[0]].rules.remove_at(e[1])
	if q.friends[e[0]].rules.is_empty():
		q.friends[e[0]].rules.append({"type": "max_price", "v": 1000})
	var probs := PTValidate.problems(q)
	assert_true(probs.any(func(x): return String(x).contains("plans work")), "flags multiple answers: %s" % str(probs))


func test_validator_catches_no_answer_and_contradiction():
	var p := PTGen.generate(DAY)
	var q := p.duplicate(true)
	q.friends[0].rules.append({"type": "setting", "v": "indoor"})
	q.friends[1].rules.append({"type": "setting", "v": "outdoor"})
	assert_eq(PTValidate.contradictions(q).size() >= 1, true, "detects indoor vs outdoor")
	var probs := PTValidate.problems(q)
	assert_true(probs.has("no plan works"), "flags no answer")
	assert_true(probs.has("contradictory clues"), "flags the contradiction")


func test_validator_catches_redundant_clue():
	var p := PTGen.generate(DAY)
	var q := p.duplicate(true)
	# A rule every plan passes is pure noise.
	q.friends[0].rules.append({"type": "max_price", "v": 999})
	assert_eq(PTValidate.redundant(q).size(), 1, "finds exactly the one redundant clue")
	assert_true(PTValidate.problems(q).any(func(x): return String(x).contains("redundant")))


func test_validator_catches_giveaway_clue():
	var p := PTGen.generate(DAY)
	var q := p.duplicate(true)
	var target: Dictionary = q.plans[int(q.target)]
	q.friends[0].rules = [{"type": "max_price", "v": int(target.price)}]
	for plan in q.plans:
		if int(plan.id) != int(q.target):
			plan.price = int(target.price) + 7
	assert_true(PTValidate.problems(q).any(func(x): return String(x).contains("gives it away")))


func test_candidate_rules_all_pass_target():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var plans := PTGen.make_plans(rng, 6)
	assert_eq(plans.size(), 6)
	var cands := PTGen.candidates(rng, plans, 2, PTDaily.HARD_TYPES)
	assert_gt(cands.size(), 3, "plenty of candidate clues")
	for c in cands:
		assert_true(PTRules.does(plans[2], c), "target passes %s" % PTRules.text(c))
		for id in c.elim:
			assert_false(PTRules.does(plans[id], c), "eliminated plan fails it")
